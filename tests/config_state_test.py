"""Configuration/state separation with real directories, symlink chains and sockets."""
import importlib.util
import os
import socket
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/separate-config-state.py"
spec = importlib.util.spec_from_file_location("separate_config_state", SCRIPT)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


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


class AdoptAppChangesTest(unittest.TestCase):
    """Apps such as OBS replace a config symlink with a real file when they save."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="config-adopt-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / "repo/obs"
        self.target = self.root / "home/obs"
        self.backups = self.root / "home/.local/state/config-adopt"
        (self.source / "scenes").mkdir(parents=True)
        self.target.joinpath("scenes").mkdir(parents=True)
        self.repo_file = self.source / "scenes/Streaming.json"
        self.live_file = self.target / "scenes/Streaming.json"
        self.repo_file.write_text("repo\n")
        self.repo_mtime_ns = 1_700_000_000_000_000_000
        os.utime(self.repo_file, ns=(self.repo_mtime_ns, self.repo_mtime_ns))

    def run_adopt(self, *extra, success=True, files=("scenes/Streaming.json",)):
        env = dict(os.environ, HOME=str(self.root / "home"))
        result = subprocess.run(
            [sys.executable, str(SCRIPT), *extra, str(self.source), str(self.target), *files],
            check=False, capture_output=True, text=True, timeout=10, env=env,
        )
        self.assertEqual(result.returncode, 0 if success else 1, result.stdout + result.stderr)
        return result

    def app_saved(self, text, newer=True):
        self.live_file.write_text(text)
        base = self.repo_file.stat().st_mtime
        os.utime(self.live_file, (base + 100, base + 100) if newer else (base - 100, base - 100))

    def backed_up_texts(self):
        return sorted(path.read_text() for path in self.backups.rglob("*") if path.is_file())

    def test_without_the_flag_an_app_written_file_is_still_a_conflict(self):
        self.app_saved("live\n")
        self.run_adopt(success=False)
        self.assertEqual(self.live_file.read_text(), "live\n")
        self.assertEqual(self.repo_file.read_text(), "repo\n")

    def test_newer_app_file_is_adopted_into_the_repo_and_linked_with_both_versions_kept(self):
        self.app_saved("live\n", newer=True)
        result = self.run_adopt("--adopt-app-changes")
        self.assertEqual(self.repo_file.read_text(), "live\n")
        self.assertTrue(self.live_file.is_symlink())
        self.assertEqual(self.live_file.resolve(), self.repo_file.resolve())
        self.assertEqual(self.backed_up_texts(), ["live\n", "repo\n"])
        self.assertIn("adopted", result.stdout)
        self.assertIn(str(self.backups), result.stdout)

    def test_newer_repo_file_wins_and_the_app_copy_is_kept(self):
        self.app_saved("live\n", newer=False)
        result = self.run_adopt("--adopt-app-changes")
        self.assertEqual(self.repo_file.read_text(), "repo\n")
        self.assertTrue(self.live_file.is_symlink())
        self.assertEqual(self.backed_up_texts(), ["live\n", "repo\n"])
        self.assertIn("kept the repo version", result.stdout)

    def test_identical_app_file_is_claimed_and_backed_up_before_relinking(self):
        self.app_saved("repo\n")
        self.run_adopt("--adopt-app-changes")
        self.assertTrue(self.live_file.is_symlink())
        self.assertEqual(self.repo_file.read_text(), "repo\n")
        self.assertEqual(self.backed_up_texts(), ["repo\n", "repo\n"])

    def test_save_after_claim_is_adopted_on_retry_in_every_reconciliation_case(self):
        rename = os.rename
        replacement_mtime_ns = self.repo_mtime_ns + 200_000_000_000
        for original in ("repo\n", "live\n"):
            for delta_ns in (-100_000_000_000, 0, 100_000_000_000):
                with self.subTest(original=original, delta_ns=delta_ns):
                    self.live_file.unlink(missing_ok=True)
                    self.repo_file.write_text("repo\n")
                    os.utime(self.repo_file, ns=(self.repo_mtime_ns, self.repo_mtime_ns))
                    self.live_file.write_text(original)
                    app_mtime_ns = self.repo_mtime_ns + delta_ns
                    os.utime(self.live_file, ns=(app_mtime_ns, app_mtime_ns))
                    before = self.backed_up_texts()
                    adopted = original if delta_ns > 0 else "repo\n"

                    def save_after_claim(source, destination, *args, **kwargs):
                        result = rename(source, destination, *args, **kwargs)
                        if Path(source) == self.live_file:
                            replacement = self.live_file.with_suffix(".new")
                            replacement.write_text("concurrent save\n")
                            os.utime(replacement, ns=(replacement_mtime_ns, replacement_mtime_ns))
                            os.replace(replacement, self.live_file)
                        return result

                    with patch.dict(os.environ, HOME=str(self.root / "home")), patch.object(os, "rename", save_after_claim), self.assertRaises(FileExistsError):
                        migration.separate(self.source, self.target, ["scenes/Streaming.json"], adopt=True)
                    self.assertFalse(self.live_file.is_symlink())
                    self.assertEqual(self.live_file.read_text(), "concurrent save\n")
                    self.assertEqual(self.repo_file.read_text(), adopted)
                    self.assertEqual(self.repo_file.stat().st_mtime_ns, max(app_mtime_ns, self.repo_mtime_ns))
                    self.assertEqual(self.backed_up_texts(), sorted([*before, original, "repo\n"]))

                    self.run_adopt("--adopt-app-changes")
                    self.assertTrue(self.live_file.is_symlink())
                    self.assertEqual(self.live_file.resolve(), self.repo_file)
                    self.assertEqual(self.repo_file.read_text(), "concurrent save\n")
                    self.assertEqual(self.repo_file.stat().st_mtime_ns, replacement_mtime_ns)
                    self.assertEqual(self.backed_up_texts(), sorted([*before, original, "repo\n", adopted, "concurrent save\n"]))

    def test_repeated_adoptions_keep_every_snapshot_even_in_the_same_second(self):
        with patch.dict(os.environ, HOME=str(self.root / "home")), patch.object(migration.time, "strftime", return_value="fixed-second-"):
            for text in ("first save\n", "second save\n"):
                self.live_file.unlink(missing_ok=True)
                self.app_saved(text)
                migration.separate(self.source, self.target, ["scenes/Streaming.json"], adopt=True)
        self.assertEqual(self.repo_file.read_text(), "second save\n")
        self.assertTrue(self.live_file.is_symlink())
        self.assertEqual(self.backed_up_texts(), ["first save\n", "first save\n", "repo\n", "second save\n"])

    def test_backups_are_private_because_they_can_hold_stream_keys(self):
        self.app_saved("live\n")
        self.run_adopt("--adopt-app-changes")
        self.assertEqual(self.backups.stat().st_mode & 0o077, 0)
        for path in self.backups.rglob("*"):
            self.assertEqual(path.stat().st_mode & 0o077, 0, path)

    def test_unlisted_runtime_conflict_still_fails_before_adopting_anything(self):
        self.app_saved("live\n")
        (self.source / "session.json").write_text("source\n")
        self.target.joinpath("session.json").write_text("target\n")
        self.run_adopt("--adopt-app-changes", success=False)
        self.assertEqual(self.repo_file.read_text(), "repo\n")
        self.assertEqual(self.live_file.read_text(), "live\n")
        self.assertFalse(self.backups.exists())

    def test_existing_correct_link_is_left_alone(self):
        self.live_file.symlink_to(self.repo_file)
        self.run_adopt("--adopt-app-changes")
        self.assertEqual(self.repo_file.read_text(), "repo\n")
        self.assertFalse(self.backups.exists())

    def test_a_foreign_symlink_is_never_adopted(self):
        other = self.root / "elsewhere.json"
        other.write_text("other\n")
        self.live_file.symlink_to(other)
        self.run_adopt("--adopt-app-changes", success=False)
        self.assertEqual(self.repo_file.read_text(), "repo\n")


if __name__ == "__main__":
    unittest.main()
