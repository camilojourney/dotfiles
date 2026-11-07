"""Configuration/state separation with real directories, symlink chains and sockets."""
import os
import socket
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/separate-config-state.py"


class ConfigStateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="config-state-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / "repo/herdr"
        self.target = self.root / "home/.config/herdr"
        self.source.mkdir(parents=True)
        self.target.parent.mkdir(parents=True)
        (self.source / "config.toml").write_text("theme = 'dark'\n")

    def run_migration(self, *files, success=True):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(self.source), str(self.target), *(files or ["config.toml"])],
            check=False, capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0 if success else 1, result.stdout + result.stderr)
        return result

    def test_live_directory_link_becomes_config_link_and_preserves_runtime(self):
        # Home Manager links through a generation, not directly into the checkout.
        generation = self.root / "generation"
        generation.symlink_to(self.source, target_is_directory=True)
        self.target.symlink_to(generation, target_is_directory=True)
        (self.source / "session.json").write_text("saved session\n")
        (self.source / "session-snapshots").mkdir()
        (self.source / "session-snapshots/one.json").write_text("snapshot\n")
        (self.source / ".plugins.lock").write_text("lock\n")
        log = (self.source / "herdr.log").open("w")
        self.addCleanup(log.close)
        log.write("before\n")
        log.flush()
        inode = os.fstat(log.fileno()).st_ino
        sock = socket.socket(socket.AF_UNIX)
        self.addCleanup(sock.close)
        sock.bind(str(self.source / "herdr.sock"))
        sock.listen(1)
        sock.settimeout(2)

        self.run_migration()

        self.assertFalse(self.target.is_symlink())
        self.assertEqual((self.target / "config.toml").resolve(), self.source / "config.toml")
        self.assertEqual(sorted(p.name for p in self.source.iterdir()), ["config.toml"])
        self.assertEqual((self.target / "session.json").read_text(), "saved session\n")
        self.assertEqual((self.target / "session-snapshots/one.json").read_text(), "snapshot\n")
        self.assertEqual((self.target / ".plugins.lock").read_text(), "lock\n")
        log.write("after\n")
        log.flush()
        self.assertEqual((self.target / "herdr.log").stat().st_ino, inode)
        self.assertEqual((self.target / "herdr.log").read_text(), "before\nafter\n")
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(2)
            client.connect(str(self.target / "herdr.sock"))
            connection, _ = sock.accept()
            with connection:
                client.sendall(b"alive")
                self.assertEqual(connection.recv(5), b"alive")
        self.run_migration()
        self.assertEqual((self.target / "herdr.log").stat().st_ino, inode)

    def test_fresh_install_and_unmanaged_runtime_are_preserved(self):
        self.target.mkdir()
        (self.target / "local-session.json").write_text("local\n")
        self.run_migration()
        self.assertEqual((self.target / "local-session.json").read_text(), "local\n")
        (self.target / "config.toml").write_text("theme = 'light'\n")
        self.assertEqual((self.source / "config.toml").read_text(), "theme = 'light'\n")

    def test_nested_config_keeps_backups_outside_checkout(self):
        self.target.symlink_to(self.source, target_is_directory=True)
        (self.source / "profiles/Streaming").mkdir(parents=True)
        (self.source / "profiles/Streaming/basic.ini").write_text("settings\n")
        (self.source / "profiles/Streaming/basic.ini.bak").write_text("backup\n")
        self.run_migration("config.toml", "profiles/Streaming/basic.ini")
        self.assertTrue((self.target / "profiles/Streaming/basic.ini").is_symlink())
        self.assertEqual((self.target / "profiles/Streaming/basic.ini.bak").read_text(), "backup\n")
        self.assertFalse((self.source / "profiles/Streaming/basic.ini.bak").exists())

    def test_conflicts_fail_before_moving_any_data(self):
        self.target.mkdir()
        (self.source / "session.json").write_text("source\n")
        (self.target / "session.json").write_text("target\n")
        self.run_migration(success=False)
        self.assertEqual((self.source / "session.json").read_text(), "source\n")
        self.assertEqual((self.target / "session.json").read_text(), "target\n")
        self.assertFalse((self.target / "config.toml").exists())

    def test_local_configuration_is_never_overwritten(self):
        self.target.mkdir()
        (self.target / "config.toml").write_text("local config\n")
        self.run_migration(success=False)
        self.assertEqual((self.target / "config.toml").read_text(), "local config\n")

    def test_missing_config_does_not_detach_existing_directory(self):
        self.target.symlink_to(self.source, target_is_directory=True)
        self.run_migration("missing.toml", success=False)
        self.assertTrue(self.target.is_symlink())

    def test_unknown_directory_link_is_not_followed(self):
        elsewhere = self.root / "elsewhere"
        elsewhere.mkdir()
        self.target.symlink_to(elsewhere, target_is_directory=True)
        self.run_migration(success=False)
        self.assertEqual(self.target.resolve(), elsewhere)
        self.assertEqual(list(elsewhere.iterdir()), [])

    def test_unsafe_config_paths_are_rejected(self):
        for path in ("../outside", "/absolute", "profiles/../../outside", "."):
            with self.subTest(path=path):
                self.run_migration(path, success=False)
                self.assertFalse(self.target.exists())

    def test_symlinked_parent_cannot_redirect_runtime_moves(self):
        self.target.mkdir()
        (self.source / "profiles").mkdir()
        (self.source / "profiles/settings.ini").write_text("config\n")
        elsewhere = self.root / "elsewhere"
        elsewhere.mkdir()
        (self.target / "profiles").symlink_to(elsewhere, target_is_directory=True)
        self.run_migration("config.toml", "profiles/settings.ini", success=False)
        self.assertEqual(list(elsewhere.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
