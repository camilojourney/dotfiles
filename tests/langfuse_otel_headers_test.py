#!/usr/bin/env python3
"""Synthetic-only shell authentication regression tests."""
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts/agent-tools/langfuse-otel-headers.sh"


class HeaderTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.secrets = self.home / ".config/secrets/langfuse.env"
        self.secrets.parent.mkdir(parents=True)
        self.env = {"PATH": os.environ["PATH"], "HOME": str(self.home)}
        self.rotate()

    def rotate(self, suffix=""):
        self.secrets.write_text(
            f"LANGFUSE_INIT_PROJECT_PUBLIC_KEY=fixture-public{suffix}\n"
            f"LANGFUSE_INIT_PROJECT_SECRET_KEY=fixture-private{suffix}\n"
        )

    def helper(self, *args):
        return subprocess.run([str(HELPER), *args], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def shell(self, command):
        # Execute the actual managed zsh environment block with an isolated home.
        block = (ROOT / "nix/home.nix").read_text().split("envExtra = ''", 1)[1].split("'';", 1)[0]
        block = block.replace("${dotfilesDir}", str(ROOT))
        return subprocess.run(["zsh", "-c", block + "\n" + command],
                              env=self.env, capture_output=True, text=True, timeout=30)

    # [utest->req~native-tracing.private-header-file~1]
    def test_private_atomic_rotation(self):
        first = self.helper("--file")
        self.assertEqual(first.returncode, 0)
        path = Path(first.stdout.strip())
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(path.stat().st_uid, os.getuid())
        with path.open() as old:
            self.rotate("-rotated")
            second = self.helper("--file")
            self.assertEqual(second.returncode, 0)
            self.assertEqual(second.stdout, first.stdout)
            self.assertNotEqual(old.read(), path.read_text())
        expected = base64.b64encode(b"fixture-public-rotated:fixture-private-rotated").decode()
        self.assertTrue(path.read_text() == f"Authorization=Basic%20{expected},x-langfuse-ingestion-version=4\n")
        self.assertEqual(sorted(p.name for p in path.parent.iterdir()), ["headers"])

    def test_legacy_json_and_env(self):
        expected = base64.b64encode(b"fixture-public:fixture-private").decode()
        self.assertTrue(json.loads(self.helper().stdout) == {
            "Authorization": f"Basic {expected}", "x-langfuse-ingestion-version": "4"})
        self.assertTrue(self.helper("--env").stdout ==
                        f"Authorization=Basic%20{expected},x-langfuse-ingestion-version=4\n")
        self.secrets.unlink()
        self.assertEqual(self.helper().stdout, "{}\n")
        self.assertEqual(self.helper("--env").stdout, "")

    # [utest->req~native-tracing.shell-authentication~1]
    def test_shell_removes_inline_and_exports_only_path(self):
        self.env.update(PI_OTEL_EXPORTER_OTLP_HEADERS="fixture-inline",
                        OTEL_EXPORTER_OTLP_HEADERS="fixture-inline-standard",
                        PI_OTEL_EXPORTER_OTLP_HEADERS_FILE="/fixture/stale",
                        OTEL_EXPORTER_OTLP_HEADERS_FILE="/fixture/stale-standard")
        result = self.shell("""python3 - <<'PY'
import os, pathlib
assert 'PI_OTEL_EXPORTER_OTLP_HEADERS' not in os.environ
assert 'OTEL_EXPORTER_OTLP_HEADERS' not in os.environ
assert 'OTEL_EXPORTER_OTLP_HEADERS_FILE' not in os.environ
assert pathlib.Path(os.environ['PI_OTEL_EXPORTER_OTLP_HEADERS_FILE']).is_file()
assert not any('Basic' in v or 'fixture-' in v for v in os.environ.values())
PY""")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    # [utest->req~native-tracing.private-header-file~1]
    # [utest->req~native-tracing.shell-authentication~1]
    def test_failed_refresh_does_not_export_stale_file(self):
        self.assertEqual(self.helper("--file").returncode, 0)
        for contents in ("", "LANGFUSE_INIT_PROJECT_PUBLIC_KEY=fixture-only\n", None):
            if contents is None:
                self.secrets.unlink()
            else:
                self.secrets.write_text(contents)
            failed = self.helper("--file")
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual(failed.stdout, "")
            self.env["PI_OTEL_EXPORTER_OTLP_HEADERS_FILE"] = "/fixture/stale"
            result = self.shell("test -z \"${PI_OTEL_EXPORTER_OTLP_HEADERS_FILE+x}\"")
            self.assertEqual(result.returncode, 0)

    def test_failed_publish_retains_previous_file_and_cleans_temporary(self):
        path = Path(self.helper("--file").stdout.strip())
        original = path.read_text()
        self.rotate("-rotated")
        bin_dir = self.home / "bin"
        bin_dir.mkdir()
        failing_mv = bin_dir / "mv"
        failing_mv.write_text("#!/bin/sh\nexit 1\n")
        failing_mv.chmod(0o700)
        self.env["PATH"] = str(bin_dir) + os.pathsep + self.env["PATH"]
        failed = self.helper("--file")
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(failed.stdout, "")
        self.assertTrue(path.read_text() == original)
        self.assertEqual(list(path.parent.iterdir()), [path])
        self.env["PATH"] = os.environ["PATH"]
        self.assertEqual(self.helper("--file").returncode, 0)
        self.assertTrue(path.read_text() != original)

    def test_refuses_symlink_directory_and_destination(self):
        directory = self.secrets.parent / "pi-otel"
        directory.symlink_to(self.home, target_is_directory=True)
        self.assertNotEqual(self.helper("--file").returncode, 0)
        directory.unlink()
        directory.mkdir(mode=0o700)
        target = self.home / "untouched"
        target.write_text("fixture")
        (directory / "headers").symlink_to(target)
        self.assertNotEqual(self.helper("--file").returncode, 0)
        self.assertEqual(target.read_text(), "fixture")


if __name__ == "__main__":
    unittest.main()
