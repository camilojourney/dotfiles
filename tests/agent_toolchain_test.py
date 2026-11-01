#!/usr/bin/env python3
"""Pin selector and transaction regressions. No network or real installs."""
import hashlib
import importlib.util
import json
import os
import pathlib
import signal
import stat
import subprocess
import sys
import tempfile
import unittest
from datetime import UTC, datetime
from unittest.mock import patch
from urllib.error import HTTPError

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("toolchain", ROOT / "scripts/agent-tools/toolchain.py")
toolchain = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(toolchain)
NOW = datetime(2026, 11, 1, tzinfo=UTC)
sys.path.insert(0, str(ROOT / "scripts/agent-tools"))
import weekly


class SelectionTest(unittest.TestCase):
    def test_seven_days_inclusive_and_newer_only(self):
        releases = [("1.0.1", "2026-10-25T00:00:00Z"), ("1.0.2", "2026-10-25T00:00:01Z")]
        self.assertEqual(toolchain.choose("1.0.0", releases, NOW, set())[0], "1.0.1")
        self.assertEqual(toolchain.choose("1.0.2", releases, NOW, set())[0], "1.0.2")

    def test_vulnerable_pre_release_and_empty_stay_put(self):
        releases = [("1.1.0", "2026-10-01T00:00:00Z"), ("2.0.0-rc.1", "2026-10-01T00:00:00Z")]
        self.assertEqual(toolchain.choose("1.0.0", releases, NOW, {"1.1.0"})[0], "1.0.0")
        self.assertEqual(toolchain.choose("1.0.0", [], NOW, set())[0], "1.0.0")

    def test_security_fix_can_skip_wait_but_not_vulnerability(self):
        releases = [("1.0.1", "2026-10-31T00:00:00Z")]
        self.assertEqual(toolchain.choose("1.0.0", releases, NOW, set(), {"1.0.1"})[0], "1.0.1")
        self.assertEqual(toolchain.choose("1.0.0", releases, NOW, {"1.0.1"}, {"1.0.1"})[0], "1.0.0")

    def test_calendar_versions_and_semver_numeric_order(self):
        self.assertEqual(toolchain.choose("2026.9.1", [("2026.10.26", "2026-10-01T00:00:00Z")], NOW, set())[0], "2026.10.26")
        self.assertEqual(toolchain.choose("1.9.0", [("1.10.0", "2026-10-01T00:00:00Z")], NOW, set())[0], "1.10.0")

    def test_render_preserves_preferences_filters_and_local_git_packages(self):
        original = {"theme": "mine", "packages": ["npm:pi-web-access", {"source": "npm:pi-claude-bridge@0.9.3", "extensions": []}, "git:github.com/a/b@deadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "../../local"]}
        pins = {"pi-web-access": "0.46.0", "pi-claude-bridge": "0.9.3"}
        rendered = toolchain.render_settings(original, pins)
        self.assertEqual(rendered["packages"], ["npm:pi-web-access@0.46.0", {"source": "npm:pi-claude-bridge@0.9.3", "extensions": []}, "git:github.com/a/b@deadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "../../local"])
        self.assertEqual(original["packages"][0], "npm:pi-web-access")
        self.assertEqual(rendered["theme"], "mine")
        with self.assertRaises(ValueError):
            toolchain.render_settings({"packages": ["npm:unknown"]}, pins)
        with self.assertRaises(ValueError):
            toolchain.render_settings({"packages": ["git:github.com/a/b"]}, pins)

    def test_atomic_pin_journal_syncs_file_then_directory(self):
        synced = []
        real_sync = os.fsync
        def sync(fd):
            synced.append(stat.S_ISDIR(os.fstat(fd).st_mode))
            real_sync(fd)
        with tempfile.TemporaryDirectory() as directory, patch.object(os, "fsync", side_effect=sync):
            path = pathlib.Path(directory) / "journal.json"
            toolchain.atomic_json(path, {"base": "previous"})
            self.assertEqual(json.loads(path.read_text()), {"base": "previous"})
        self.assertEqual(synced, [False, True])

    def test_manifest_has_only_exact_pins_and_no_self_updaters(self):
        manifest = json.loads((ROOT / "nix/agent-tools.manifest.lock.json").read_text())
        toolchain.validate(manifest)
        self.assertEqual(manifest["uv"][0]["version"], "0.31.3")
        self.assertEqual(manifest["uv"][1]["version"], "0.5.13")


class RegistryTest(unittest.TestCase):
    def test_transient_registry_failure_retries_but_client_failure_does_not(self):
        from io import BytesIO
        response = BytesIO(b'{"ok":true}')
        transient = HTTPError("https://api.osv.dev/v1/query", 429, "limited", {"Retry-After": "0"}, None)
        with patch.object(toolchain, "urlopen", side_effect=[transient, response]) as fetch, patch("time.sleep"):
            self.assertEqual(toolchain.Registry().json("https://api.osv.dev/v1/query"), {"ok": True})
            self.assertEqual(fetch.call_count, 2)
        denied = HTTPError("https://api.osv.dev/v1/query", 403, "denied", {}, None)
        with patch.object(toolchain, "urlopen", side_effect=denied) as fetch, self.assertRaises(HTTPError):
            toolchain.Registry().json("https://api.osv.dev/v1/query")
        self.assertEqual(fetch.call_count, 1)

    def test_osv_failure_aborts_without_mutating_manifest(self):
        manifest = json.loads((ROOT / "nix/agent-tools.manifest.lock.json").read_text())
        original = json.dumps(manifest)

        class Offline:
            def vulnerabilities(self, *args):
                raise TimeoutError("OSV unavailable")

        with self.assertRaises(TimeoutError):
            toolchain.select(manifest, NOW, Offline())
        self.assertEqual(json.dumps(manifest), original)

    def test_vulnerable_newest_falls_back_and_mlx_stays_fixed(self):
        manifest = json.loads((ROOT / "nix/agent-tools.manifest.lock.json").read_text())

        class PublicRegistry:
            def vulnerabilities(self, ecosystem, name, version):
                return [{"id": "test"}] if version.lstrip("v") == "99.0.0" else []

            def releases(self, lane, name, entry):
                return [("99.0.0", "2026-10-01T00:00:00Z"), ("98.0.0", "2026-10-01T00:00:00Z")], {"98.0.0": {"darwin-arm64": "a" * 64, "darwin-amd64": "b" * 64}}

        selected, reasons = toolchain.select(manifest, NOW, PublicRegistry())
        self.assertEqual(selected["npm"][0]["version"], "98.0.0")
        self.assertEqual(selected["uv"][0]["version"], "0.31.3")
        self.assertTrue(any("flagged by OSV" in reason for reason in reasons))
        self.assertEqual(manifest["npm"][0]["version"], "1.4.0")


class WeeklyTransactionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.state = self.root / "state"
        self.git("init", "-b", "main")
        self.git("config", "user.email", "test@example.com")
        self.git("config", "user.name", "Test")
        (self.repo / "nix").mkdir()
        self.manifest = json.loads((ROOT / "nix/agent-tools.manifest.lock.json").read_text())
        self.path = self.repo / "nix/agent-tools.manifest.lock.json"
        self.path.write_text(json.dumps(self.manifest))
        scripts = self.repo / "scripts/agent-tools"
        scripts.mkdir(parents=True)
        # Stateful boundary: fail only candidate installs or their smoke check.
        for command in ("reconcile.sh", "smoke.py"):
            path = scripts / command
            path.write_text('#!/bin/sh\necho "$0" >> "$HOME/calls"\nif grep -q 99.0.0 "$AGENT_TOOLS_MANIFEST" && [ -f "$HOME/fail-' + command + '" ]; then exit 42; fi\nif [ "${0##*/}" = reconcile.sh ] && [ -f "$HOME/concurrent" ]; then echo captain > "$AGENT_TOOLS_REPO_ROOT/captain.txt"; git -C "$AGENT_TOOLS_REPO_ROOT" add captain.txt; git -C "$AGENT_TOOLS_REPO_ROOT" commit -qm captain; fi\n')
            path.chmod(0o755)
        self.git("add", ".")
        self.git("commit", "-m", "fixture")
        self.base = self.git("rev-parse", "HEAD").strip()
        self.selected = json.loads(json.dumps(self.manifest))
        self.selected["npm"][0]["version"] = "99.0.0"
        self.old_home = os.environ.get("HOME")
        os.environ["HOME"] = str(self.root)
        real_run = subprocess.run
        def boundary(command, **kwargs):
            if command[0] == "/usr/bin/osascript":
                return subprocess.CompletedProcess(command, 0)
            return real_run(command, **kwargs)
        self.notification_boundary = patch.object(subprocess, "run", side_effect=boundary)
        self.notification_boundary.start()

    def tearDown(self):
        self.notification_boundary.stop()
        if self.old_home is None:
            del os.environ["HOME"]
        else:
            os.environ["HOME"] = self.old_home
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.repo), *args], capture_output=True, text=True, check=True).stdout

    def test_partial_install_failure_restores_pin_commit_and_installs(self):
        (self.root / "fail-reconcile.sh").touch()
        with self.assertRaises(subprocess.CalledProcessError):
            weekly.install_candidate(self.repo, self.state, self.selected, publish=lambda head: self.fail("must not publish"))
        self.assertEqual(self.git("rev-parse", "HEAD").strip(), self.base)
        self.assertEqual(json.loads(self.path.read_text()), self.manifest)
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertGreaterEqual(len((self.root / "calls").read_text().splitlines()), 2)
        self.assertFalse((self.state / "transaction.json").exists())

    def test_smoke_and_push_failures_restore_previous_install(self):
        for failure in ("smoke", "push"):
            with self.subTest(failure=failure):
                marker = self.root / "fail-smoke.py"
                if failure == "smoke":
                    marker.touch()
                def publish(head):
                    raise RuntimeError("push denied")
                with self.assertRaises((subprocess.CalledProcessError, RuntimeError)):
                    weekly.install_candidate(self.repo, self.state, self.selected, publish=publish)
                marker.unlink(missing_ok=True)
                self.assertEqual(self.git("rev-parse", "HEAD").strip(), self.base)
                self.assertEqual(self.git("status", "--porcelain"), "")
                self.assertEqual(json.loads(self.path.read_text()), self.manifest)

    def test_only_passing_pin_commit_is_published(self):
        published = []
        weekly.install_candidate(self.repo, self.state, self.selected, publish=published.append)
        self.assertEqual(published, [self.git("rev-parse", "HEAD").strip()])
        self.assertEqual(self.git("diff", "--name-only", self.base, "HEAD").strip(), "nix/agent-tools.manifest.lock.json")
        self.assertFalse((self.state / "transaction.json").exists())

    def test_missing_push_credentials_leave_pins_and_installs_untouched(self):
        self.git("remote", "add", "origin", "https://github.com/camilojourney/dotfiles.git")
        self.git("update-ref", "refs/remotes/origin/main", self.base)
        pushes = []
        real_run = subprocess.run
        def network(command, **kwargs):
            if "push" in command:
                pushes.append(command)
                raise subprocess.CalledProcessError(128, command, stderr="credential absent")
            return real_run(command, **kwargs)
        with patch.object(subprocess, "run", side_effect=network), self.assertRaises(subprocess.CalledProcessError):
            weekly.preflight(self.repo)
        self.assertEqual(len(pushes), 1)
        self.assertIn("--dry-run", pushes[0])
        self.assertEqual(self.git("rev-parse", "HEAD").strip(), self.base)
        self.assertFalse((self.root / "calls").exists())
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_interrupted_uncommitted_candidate_recovers_before_rebuild(self):
        self.state.mkdir()
        previous = self.path.read_bytes()
        toolchain.atomic_json(self.path, self.selected)
        toolchain.atomic_json(self.state / "transaction.json", {"base": self.base, "digest": hashlib.sha256(self.path.read_bytes()).hexdigest(), "previousDigest": hashlib.sha256(previous).hexdigest()})
        weekly.recover(self.repo, self.state)
        self.assertEqual(self.path.read_bytes(), previous)
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertFalse((self.state / "transaction.json").exists())

    def test_recovery_refuses_concurrent_edits(self):
        self.state.mkdir()
        previous = self.path.read_bytes()
        toolchain.atomic_json(self.path, self.selected)
        toolchain.atomic_json(self.state / "transaction.json", {"base": self.base, "digest": hashlib.sha256(self.path.read_bytes()).hexdigest(), "previousDigest": hashlib.sha256(previous).hexdigest()})
        (self.repo / "captain.txt").write_text("untouched")
        with self.assertRaises(RuntimeError):
            weekly.recover(self.repo, self.state)
        self.assertEqual((self.repo / "captain.txt").read_text(), "untouched")
        self.assertTrue((self.state / "transaction.json").exists())

    def test_install_timeout_kills_entire_group_before_rollback(self):
        real_killpg = os.killpg
        signals = []
        def killpg(pid, sig):
            signals.append(sig)
            return real_killpg(pid, sig)
        with patch.object(os, "killpg", side_effect=killpg), self.assertRaises(subprocess.TimeoutExpired):
            weekly.run_install([sys.executable, "-c", "import time; time.sleep(10)"], dict(os.environ), 0.05)
        self.assertIn(signal.SIGKILL, signals)

    def test_concurrent_commit_cannot_be_published_or_erased(self):
        (self.root / "concurrent").touch()
        published = []
        with self.assertRaises(RuntimeError):
            weekly.install_candidate(self.repo, self.state, self.selected, publish=published.append)
        self.assertEqual(published, [])
        self.assertEqual((self.repo / "captain.txt").read_text(), "captain\n")
        self.assertEqual(self.git("log", "-1", "--format=%s").strip(), "captain")
        self.assertTrue((self.state / "transaction.json").exists())

    def test_dirty_checkout_is_not_modified(self):
        self.path.write_text("captain edits")
        with self.assertRaises(RuntimeError):
            weekly.install_candidate(self.repo, self.state, self.selected, publish=lambda head: None)
        self.assertEqual(self.path.read_text(), "captain edits")
        self.assertEqual(self.git("rev-parse", "HEAD").strip(), self.base)


if __name__ == "__main__":

    unittest.main()
