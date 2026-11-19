#!/usr/bin/env python3
"""Manual pin update: lane limits, inherited safeguards and in-place edits. No network or installs."""
import importlib.util
import json
import pathlib
import shutil
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import UTC, datetime
from io import StringIO

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "nix/agent-tools.manifest.lock.json"
NOW = datetime(2026, 11, 19, tzinfo=UTC)
NEWER = "999.0.0"
DIGESTS = {"darwin-arm64": "a" * 64, "darwin-amd64": "b" * 64}


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


import sys

sys.path.insert(0, str(ROOT / "scripts/agent-tools"))
update = load("update_now", ROOT / "scripts/agent-tools/update-now.py")


class Registry:
    """Offers one newer release for every package; the knobs model age and OSV."""

    def __init__(self, published="2026-10-01T00:00:00Z", flagged=()):
        self.published, self.flagged = published, set(flagged)

    def vulnerabilities(self, ecosystem, name, version):
        return [{"id": "TEST"}] if version.lstrip("v") in self.flagged else []

    def releases(self, lane, name, entry):
        return [(NEWER, self.published)], {NEWER: DIGESTS}


class Offline:
    def vulnerabilities(self, *args):
        raise TimeoutError("OSV unavailable")


class UpdateNowTest(unittest.TestCase):
    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.path = self.dir / "manifest.json"
        shutil.copy(MANIFEST, self.path)
        self.before = self.path.read_text()

    def run_update(self, registry, *flags):
        out = StringIO()
        with redirect_stdout(out):
            code = update.main(["--manifest", str(self.path), *flags], registry=registry, now=NOW)
        return code, out.getvalue()

    def test_preview_changes_nothing(self):
        code, out = self.run_update(Registry())
        self.assertEqual(code, 0)
        self.assertEqual(self.path.read_text(), self.before)
        self.assertIn(NEWER, out)

    def test_only_npm_and_external_lanes_move(self):
        self.run_update(Registry(), "--write")
        old, new = json.loads(self.before), json.loads(self.path.read_text())
        for entry in new["npm"]:
            self.assertEqual(entry["version"], NEWER)
        for name, entry in new["external"].items():
            self.assertEqual(entry["version"], NEWER)
            self.assertEqual(entry["sha256"], DIGESTS, name)
        for lane in ("uv", "python", "piPackages", "policy", "setupHooks", "verify"):
            self.assertEqual(new[lane], old[lane], lane)

    def test_release_younger_than_seven_days_is_not_taken(self):
        self.run_update(Registry(published="2026-11-13T00:00:01Z"), "--write")
        self.assertEqual(self.path.read_text(), self.before)

    def test_release_flagged_by_osv_is_not_taken(self):
        self.run_update(Registry(flagged={NEWER}), "--write")
        self.assertEqual(self.path.read_text(), self.before)

    def test_registry_failure_exits_nonzero_and_leaves_file_identical(self):
        with self.assertRaises(TimeoutError):
            self.run_update(Offline(), "--write")
        self.assertEqual(self.path.read_text(), self.before)

    def test_edit_keeps_hand_formatting_and_touches_only_versions_and_digests(self):
        self.run_update(Registry(), "--write")
        old, new = self.before.splitlines(), self.path.read_text().splitlines()
        self.assertEqual(len(old), len(new))
        for a, b in zip(old, new):
            if a != b:
                self.assertTrue('"version"' in a or '"darwin-' in a, a)

    def test_no_eligible_change_writes_nothing_and_says_so(self):
        code, out = self.run_update(Registry(published="2026-11-18T00:00:00Z"), "--write")
        self.assertEqual(code, 0)
        self.assertIn("no eligible changes", out)
        self.assertEqual(self.path.read_text(), self.before)


class Probe:
    """Stands in for what is installed on the machine."""

    def __init__(self, npm=None, external=None):
        self.npm, self.external = npm or {}, external or {}

    def npm_versions(self):
        return self.npm

    def external_output(self, name, entry):
        return self.external.get(name, "")


class VerifyTest(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads(MANIFEST.read_text())
        self.npm = {e["name"]: e["version"] for e in self.manifest["npm"]}
        self.external = {n: f"{n} version v{e['version']} (abc 2026-01-01)" for n, e in self.manifest["external"].items()}

    def test_everything_installed_at_its_pin_is_clean(self):
        self.assertEqual(update.mismatches(self.manifest, Probe(self.npm, self.external)), [])

    def test_stale_npm_tool_is_reported_with_both_versions(self):
        name = self.manifest["npm"][0]["name"]
        self.npm[name] = "0.0.1"
        found = update.mismatches(self.manifest, Probe(self.npm, self.external))
        self.assertEqual([item[0] for item in found], [name])
        self.assertIn("0.0.1", found[0][2])

    def test_missing_npm_tool_is_reported(self):
        name = self.manifest["npm"][0]["name"]
        del self.npm[name]
        self.assertEqual([i[0] for i in update.mismatches(self.manifest, Probe(self.npm, self.external))], [name])

    def test_external_version_must_match_exactly_not_as_a_prefix(self):
        name, entry = next(iter(self.manifest["external"].items()))
        self.external[name] = f"{name} version v{entry['version']}0 (abc)"
        self.assertEqual([i[0] for i in update.mismatches(self.manifest, Probe(self.npm, self.external))], [name])

    def test_verify_flag_exit_codes(self):
        out = StringIO()
        with redirect_stdout(out):
            ok = update.main(["--verify"], probe=Probe(self.npm, self.external))
            self.npm[self.manifest["npm"][0]["name"]] = "0.0.1"
            bad = update.main(["--verify"], probe=Probe(self.npm, self.external))
        self.assertEqual((ok, bad), (0, 1))
        self.assertIn("0.0.1", out.getvalue())


if __name__ == "__main__":
    unittest.main()
