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
from string import Template
from unittest.mock import patch

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
from toolchain import atomic_json

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
        manifest_patch = patch.object(update, "PIN", self.path)
        manifest_patch.start()
        self.addCleanup(manifest_patch.stop)

    def run_update(self, registry):
        out = StringIO()
        with redirect_stdout(out):
            code = update.main([], registry=registry, now=NOW)
        return code, out.getvalue()

    def test_only_npm_and_external_lanes_move(self):
        self.run_update(Registry())
        old, new = json.loads(self.before), json.loads(self.path.read_text())
        for entry in new["npm"]:
            self.assertEqual(entry["version"], NEWER)
        for name, entry in new["external"].items():
            self.assertEqual(entry["version"], NEWER)
            self.assertEqual(entry["sha256"], DIGESTS, name)
        for lane in ("uv", "python", "piPackages", "policy", "setupHooks", "verify"):
            self.assertEqual(new[lane], old[lane], lane)

    def test_manual_update_does_not_query_unavailable_unselected_lanes(self):
        manifest = json.loads(self.before)
        allowed = {("npm", entry["name"]) for entry in manifest["npm"]}
        allowed.update(("Go", "github.com/" + entry["repo"]) for entry in manifest["external"].values())
        release_calls, osv_calls = [], []

        class UnrelatedRegistriesOffline(Registry):
            def releases(self, lane, name, entry):
                if lane not in ("npm", "external"):
                    raise TimeoutError(f"{lane} registry unavailable")
                release_calls.append((lane, name))
                return super().releases(lane, name, entry)

            def vulnerabilities(self, ecosystem, name, version):
                if (ecosystem, name) not in allowed:
                    raise TimeoutError(f"unrelated OSV query unavailable: {ecosystem}/{name}")
                osv_calls.append((ecosystem, name))
                return super().vulnerabilities(ecosystem, name, version)

        code, _ = self.run_update(UnrelatedRegistriesOffline())
        self.assertEqual(code, 0)
        self.assertEqual(release_calls, [("npm", entry["name"]) for entry in manifest["npm"]] + [("external", name) for name in manifest["external"]])
        self.assertEqual(set(osv_calls), allowed)
        selected = json.loads(self.path.read_text())
        self.assertTrue(all(entry["version"] == NEWER for entry in selected["npm"]))
        self.assertTrue(all(entry["version"] == NEWER for entry in selected["external"].values()))
        for lane in ("uv", "python", "piPackages"):
            self.assertEqual(selected[lane], manifest[lane], lane)

    def test_missing_external_digest_keeps_external_pins_but_updates_npm(self):
        class MissingDigest(Registry):
            def releases(self, lane, name, entry):
                releases, digests = super().releases(lane, name, entry)
                if lane == "external":
                    digests = {NEWER: {"darwin-arm64": "a" * 64}}
                return releases, digests

        _, out = self.run_update(MissingDigest())
        selected = json.loads(self.path.read_text())
        self.assertEqual(selected["external"], json.loads(self.before)["external"])
        self.assertTrue(all(entry["version"] == NEWER for entry in selected["npm"]))
        self.assertIn("missing registry sha256 digests", out)

    def test_manual_update_never_downgrades(self):
        class OlderReleases(Registry):
            def releases(self, lane, name, entry):
                return [("0.0.0", "2026-10-01T00:00:00Z")], {"0.0.0": DIGESTS}

        self.run_update(OlderReleases())
        self.assertEqual(self.path.read_text(), self.before)

    def test_release_younger_than_seven_days_is_not_taken(self):
        self.run_update(Registry(published="2026-11-13T00:00:01Z"))
        self.assertEqual(self.path.read_text(), self.before)

    def test_release_flagged_by_osv_is_not_taken(self):
        self.run_update(Registry(flagged={NEWER}))
        self.assertEqual(self.path.read_text(), self.before)

    def test_registry_failure_exits_nonzero_and_leaves_file_identical(self):
        with self.assertRaises(TimeoutError):
            self.run_update(Offline())
        self.assertEqual(self.path.read_text(), self.before)

    def test_pin_edits_preserve_unrelated_manifest_bytes_in_each_serialization(self):
        template = Template('''{
  "policy": {"note": "keep 1.0.0 and 2.0.0 verbatim"},
  "npm": [{ "name": "demo", "version": "$npm" }],
  "uv": [{"name": "library", "version": "1.0.0"}],
  "python": [], "piPackages": {},
  "external": {
    "demo": {
      "version": "$external", "repo": "owner/demo",
      "sha256": {"darwin-arm64": "$arm", "darwin-amd64": "$amd"}
    }
  }
}
''')
        before = template.substitute(npm="1.0.0", external="2.0.0", arm="c" * 64, amd="d" * 64)
        expected = template.substitute(npm=NEWER, external=NEWER, arm="a" * 64, amd="b" * 64)
        for shape in ("hand", "weekly", "compact"):
            with self.subTest(shape=shape):
                if shape == "hand":
                    self.path.write_text(before)
                    wanted = expected
                elif shape == "weekly":
                    atomic_json(self.path, json.loads(before))
                    wanted = json.dumps(json.loads(expected), indent=2) + "\n"
                else:
                    self.path.write_text(json.dumps(json.loads(before), separators=(",", ":")))
                    wanted = json.dumps(json.loads(expected), separators=(",", ":"))
                code, out = self.run_update(Registry())
                self.assertEqual(code, 0)
                self.assertIn(NEWER, out)
                self.assertEqual(self.path.read_bytes(), wanted.encode())

    def test_no_eligible_change_writes_nothing_and_says_so(self):
        code, out = self.run_update(Registry(published="2026-11-18T00:00:00Z"))
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
