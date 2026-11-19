#!/usr/bin/env python3
"""Manual, on-demand update of the agent command-line tool pins.

Run by hand, never scheduled: `./rebuild.sh` calls it, or run it alone to update
the pins in place. It selects with toolchain.select, so every weekly safeguard
applies unchanged: stable releases only, public at least seven days (a fix for a
known vulnerability in the current pin may skip the wait), OSV-clean, registry
sha256 digests for external downloads, no downgrades, and a registry or OSV
error aborts without touching the manifest.

Only the npm and external lanes move. Python and uv libraries stay on the weekly
lane because a major-version jump there can break scripts that import them.
The manifest is hand-formatted, so only version and digest values are edited in
place. Nothing is committed or pushed.
"""
import argparse
import copy
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path

from toolchain import ROOT, Registry, select, validate

LANES = ("npm", "external")
PIN = ROOT / "nix/agent-tools.manifest.lock.json"


def changes(manifest, selected):
    found = []
    for entry in manifest["npm"]:
        new = next(item for item in selected["npm"] if item["name"] == entry["name"])
        if new["version"] != entry["version"]:
            found.append(("npm", entry["name"], entry["version"], new["version"]))
    for name, entry in manifest["external"].items():
        new = selected["external"][name]
        if new["version"] != entry["version"]:
            found.append(("external", name, entry["version"], new["version"]))
    return found


def _replace_once(text, pattern, replacement, what):
    result, count = re.subn(pattern, lambda match: match.group(1) + replacement + match.group(2), text)
    if count != 1:
        raise RuntimeError(f"expected exactly one {what} in the manifest, found {count}; nothing written")
    return result


def edit(text, manifest, selected):
    """Return the manifest text with only the changed versions and digests replaced."""
    for lane, name, old, new in changes(manifest, selected):
        if lane == "npm":
            pattern = rf'("name"\s*:\s*"{re.escape(name)}"\s*,\s*"version"\s*:\s*")' + re.escape(old) + '(")'
            text = _replace_once(text, pattern, new, f"npm entry {name}")
            continue
        lane_start = re.search(r'"external"\s*:\s*\{', text).end()
        start = re.search(rf'"{re.escape(name)}"\s*:\s*\{{', text[lane_start:]).end() + lane_start - 1
        _, length = json.JSONDecoder().raw_decode(text[start:])
        end = start + length
        block = text[start:end]
        block = _replace_once(block, r'("version"\s*:\s*")' + re.escape(old) + '(")', new, f"{name} version")
        for platform, digest in manifest["external"][name]["sha256"].items():
            pattern = rf'("{re.escape(platform)}"\s*:\s*")' + re.escape(digest) + '(")'
            block = _replace_once(block, pattern, selected["external"][name]["sha256"][platform], f"{name} {platform} digest")
        text = text[:start] + block + text[end:]
    return text


def write_atomic(path, text):
    mode = path.stat().st_mode
    handle, temp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".")
    try:
        with os.fdopen(handle, "w") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, mode)
        os.replace(temp, path)
    except BaseException:
        Path(temp).unlink(missing_ok=True)
        raise


class Installed:
    """What is really installed on this Mac, read-only."""

    def npm_versions(self):
        result = subprocess.run(["npm", "ls", "-g", "--depth=0", "--json"], capture_output=True, text=True, timeout=120, check=False)
        dependencies = json.loads(result.stdout or "{}").get("dependencies", {})
        return {name: info.get("version") for name, info in dependencies.items()}

    def external_output(self, name, entry):
        binary = Path.home() / entry["installSubdir"] / entry["binary"]
        try:
            # stdout only: some tools print "update available: A -> B" on stderr, which
            # would make an out-of-date install look current.
            return subprocess.run([str(binary), "--version"], capture_output=True, text=True, timeout=30, check=False).stdout
        except (OSError, subprocess.TimeoutExpired):
            return ""


def mismatches(manifest, probe):
    """Pinned tools whose installed version is not the pin: (name, pinned, what was found)."""
    found, installed = [], probe.npm_versions()
    for entry in manifest["npm"]:
        have = installed.get(entry["name"])
        if have != entry["version"]:
            found.append((entry["name"], entry["version"], f"installed {have or 'nothing'}"))
    for name, entry in manifest["external"].items():
        output = probe.external_output(name, entry)
        exact = r"(?<![\d.])" + re.escape(entry["version"]) + r"(?![\d.])"
        if not re.search(exact, output):
            found.append((name, entry["version"], f"installed output: {output.strip()[:60] or 'not found'}"))
    return found


def verify(manifest, probe):
    found = mismatches(manifest, probe)
    for name, pinned, seen in found:
        print(f"  {name}: pinned {pinned}, {seen}")
    print("agent tools: every npm and external tool is installed at its pin" if not found else "agent tools: installed versions do not match the pins")
    return 1 if found else 0


def lane_selection(manifest, now, registry):
    """The weekly selection, kept only for the lanes this manual update may move."""
    selected, decisions = select(manifest, now, registry)
    expected = copy.deepcopy(manifest)
    for lane in LANES:
        expected[lane] = selected[lane]
    return expected, [line for line in decisions if line.split("/", 1)[0] in LANES]


def report(found):
    if not found:
        print("\nagent tools: no eligible changes; every pin is current for the seven-day rule")
        return
    print("\nagent tools: updating")
    for _lane, name, old, new in found:
        print(f"  {name}: {old} -> {new}")


def apply(path, text, manifest, expected):
    new_text = edit(text, manifest, expected)
    if json.loads(new_text) != expected:
        raise RuntimeError("edited manifest differs from the selection; nothing written")
    validate(json.loads(new_text))
    write_atomic(path, new_text)
    print("agent tools: manifest updated; nothing committed or pushed")


def main(argv=None, registry=None, now=None, probe=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--verify", action="store_true", help="check that installed tools match the pins; changes nothing")
    args = parser.parse_args(argv)
    text = PIN.read_text()
    manifest = json.loads(text)
    validate(manifest)
    if args.verify:
        return verify(manifest, probe or Installed())
    expected, decisions = lane_selection(manifest, now or datetime.now(UTC), registry or Registry())
    print("\n".join(decisions))
    found = changes(manifest, expected)
    report(found)
    if found:
        apply(PIN, text, manifest, expected)
    return 0


if __name__ == "__main__":
    sys.exit(main())
