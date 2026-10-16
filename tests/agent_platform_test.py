#!/usr/bin/env python3
"""Sandboxed tests: never mount, unmount, install, or start a host service."""

import importlib.util
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# Dynamic imports must not leave bytecode in the real checkout.
sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "scripts/agent-platform/require-ssd.py"


# [utest->req~agent-platform.storage-gate~2]
class StorageGateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.mount = Path(self.tmp.name).resolve()
        self.root = self.mount / "agent-platform"
        self.root.mkdir(mode=0o700)
        for name in (
            "state",
            "state/pi",
            "state/pi/terminal",
            "state/langfuse",
            "artifacts",
            "logs",
        ):
            (self.root / name).mkdir(mode=0o700)
        self.config = self.mount / "volume.json"
        self.config.write_text(
            json.dumps(
                {
                    "mountpoint": str(self.mount),
                    "volume_uuid": "fixture-uuid",
                    "root": str(self.root),
                    "minimum_free_bytes": 1024,
                }
            )
        )
        self.config.chmod(0o600)
        self.info = {
            "MountPoint": str(self.mount),
            "VolumeUUID": "fixture-uuid",
            "FilesystemType": "apfs",
            "GlobalPermissionsEnabled": True,
            "Encryption": True,
            "EncryptionThisVolumeProper": True,
            "Locked": False,
        }
        spec = importlib.util.spec_from_file_location("storage_gate", SCRIPT)
        self.gate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.gate)

    def invoke(self, *, info=None, command=()):
        with (
            patch.object(
                self.gate, "disk_info", return_value=self.info if info is None else info
            ),
            patch.object(self.gate.os, "execvp") as execute,
        ):
            result = self.gate.main(
                [str(self.config), *(["--", *command] if command else [])]
            )
            return result, execute

    def test_valid_mount_executes_exact_argv(self):
        result, execute = self.invoke(command=("/usr/bin/true", "literal argument"))
        self.assertEqual(result, 0)
        execute.assert_called_once_with(
            "/usr/bin/true", ["/usr/bin/true", "literal argument"]
        )

    def test_missing_wrong_or_unrestricted_mount_never_executes(self):
        for change in (
            {},
            {"MountPoint": "/"},
            {"VolumeUUID": "other"},
            {"FilesystemType": "exfat"},
            {"GlobalPermissionsEnabled": False},
        ):
            with self.subTest(change=change):
                info = {} if not change else {**self.info, **change}
                result, execute = self.invoke(info=info, command=("/usr/bin/true",))
                self.assertEqual(result, 1)
                execute.assert_not_called()

    def test_unencrypted_or_locked_volume_never_executes(self):
        for change in (
            {"Encryption": False},
            {"EncryptionThisVolumeProper": False},
            {"Locked": True},
            {"Locked": None},
        ):
            with self.subTest(change=change):
                result, execute = self.invoke(
                    info={**self.info, **change}, command=("/usr/bin/true",)
                )
                self.assertEqual(result, 1)
                execute.assert_not_called()

    def test_permission_and_path_fail_closed(self):
        private = self.root / "state/pi/terminal"
        private.chmod(0o750)
        self.assertEqual(self.invoke()[0], 1)
        private.chmod(0o700)
        private.rmdir()
        private.symlink_to(self.root / "artifacts", target_is_directory=True)
        self.assertEqual(self.invoke()[0], 1)
        private.unlink()
        self.assertEqual(self.invoke()[0], 1)

    def test_config_is_private_and_strict(self):
        self.config.chmod(0o644)
        self.assertEqual(self.invoke()[0], 1)
        self.config.chmod(0o600)
        self.config.write_text("not-json")
        self.assertEqual(self.invoke()[0], 1)
        self.config.write_text(json.dumps({"mountpoint": "/", "root": "/tmp"}))
        self.assertEqual(self.invoke()[0], 1)

    def test_missing_device_command_failure_does_not_dump_output(self):
        with (
            patch.object(
                self.gate.subprocess,
                "run",
                side_effect=subprocess.CalledProcessError(1, "diskutil"),
            ),
            self.assertRaises(self.gate.GateError),
        ):
            self.gate.disk_info(self.mount)

    def test_diskutil_plist_and_capacity_edges(self):
        completed = subprocess.CompletedProcess([], 0, plistlib.dumps(self.info), b"")
        with patch.object(self.gate.subprocess, "run", return_value=completed) as run:
            self.assertEqual(self.gate.disk_info(self.mount), self.info)
            self.assertEqual(
                run.call_args.args[0],
                ["/usr/sbin/diskutil", "info", "-plist", str(self.mount)],
            )
        for available, expected in ((1023, 1), (1024, 0), (1025, 0)):
            with (
                self.subTest(available=available),
                patch.object(
                    self.gate.shutil,
                    "disk_usage",
                    return_value=type("Usage", (), {"free": available})(),
                ),
            ):
                self.assertEqual(self.invoke()[0], expected)

    def test_bad_identity_readonly_and_root_escape(self):
        with patch.object(self.gate.os, "getuid", return_value=os.getuid() + 1):
            self.assertEqual(self.invoke()[0], 1)
        with patch.object(
            self.gate.os,
            "statvfs",
            return_value=type("FS", (), {"f_flag": os.ST_RDONLY})(),
        ):
            self.assertEqual(self.invoke()[0], 1)
        config = json.loads(self.config.read_text())
        config["root"] = str(self.mount.parent / "outside")
        self.config.write_text(json.dumps(config))
        self.assertEqual(self.invoke()[0], 1)

    def test_process_boundary_effect_only_after_success(self):
        # A separate process invokes the real entry point and execs a harmless
        # file effect. Only the OS mount query is faked; no real mount changes.
        effect = self.mount / "effect"
        for good in (False, True):
            info = self.info if good else {**self.info, "VolumeUUID": "wrong"}
            code = (
                "import sys; sys.dont_write_bytecode=True; import importlib.util; "
                f"s=importlib.util.spec_from_file_location('gate', {str(SCRIPT)!r}); "
                "m=importlib.util.module_from_spec(s); s.loader.exec_module(m); "
                f"m.disk_info=lambda _: {info!r}; "
                f"raise SystemExit(m.main([{str(self.config)!r}, '--', '/usr/bin/touch', {str(effect)!r}]))"
            )
            run = subprocess.run(
                [sys.executable, "-c", code],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(run.returncode, 0 if good else 1)
            self.assertEqual(effect.exists(), good)

    # [utest->req~agent-platform.central-terminal~1]
    def test_central_job_is_guarded_foreground_terminal_without_persistent_logs(self):
        text = (REPO / "services/agent-platform/central-job.plist.in").read_text()
        for token, value in {
            "PYTHON": "/python",
            "CODE": "/private/code",
            "CONFIG": str(self.config),
            "ROOT": str(self.root),
            "NODE": "/node",
        }.items():
            text = text.replace(f"@{token}@", value)
        job = plistlib.loads(text.encode())
        arguments = job["ProgramArguments"]
        self.assertEqual(
            arguments[:4],
            ["/python", "/private/code/require-ssd.py", str(self.config), "--"],
        )
        self.assertIn(f"SCREENDIR={self.root}/state/pi/terminal", arguments)
        self.assertEqual(
            arguments[arguments.index("/usr/bin/screen") + 1 :][:2], ["-D", "-m"]
        )
        self.assertEqual(
            arguments[-4:],
            [
                "/node",
                "/private/code/central.mjs",
                f"{self.root}/state/pi/central",
                "serve",
            ],
        )
        self.assertTrue(job["KeepAlive"])
        self.assertEqual(job["StandardOutPath"], "/dev/null")
        self.assertEqual(job["StandardErrorPath"], "/dev/null")
        self.assertNotIn(
            "HardResourceLimits", job
        )  # FileSize also limits SQLite, not just logs.

    def test_launch_definition_uses_guard_without_ssd_log_side_effects(self):
        template = REPO / "services/agent-platform/storage-check.plist.in"
        text = (
            template.read_text()
            .replace("@PYTHON@", "/python")
            .replace("@DOTFILES@", str(REPO))
            .replace("@CONFIG@", str(self.config))
        )
        job = plistlib.loads(text.encode())
        self.assertEqual(
            job["ProgramArguments"], ["/python", str(SCRIPT), str(self.config)]
        )
        self.assertTrue(job["RunAtLoad"])
        self.assertNotIn("KeepAlive", job)
        self.assertNotIn("StandardOutPath", job)
        self.assertNotIn("StandardErrorPath", job)


if __name__ == "__main__":
    unittest.main()
