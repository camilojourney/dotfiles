#!/usr/bin/env python3
"""Exact top-level pins: validation, effective Pi settings and read-only selection.

Network is confined to public package registries (including GitHub Releases)
and OSV. Unknown metadata, missing digests or OSV failures abort selection.
"""
import argparse
import copy
import json
import os
import re
import subprocess
import tempfile
import time
from datetime import UTC, datetime, timedelta
from email.utils import parsedate_to_datetime
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
VERSION = re.compile(r"\d+(?:\.\d+)+\Z")


def version_key(value):
    if not isinstance(value, str) or not VERSION.fullmatch(value):
        raise ValueError(f"not an exact stable version: {value!r}")
    return tuple(int(part) for part in value.split("."))


def validate(manifest):
    for lane in ("npm", "uv", "python"):
        for entry in manifest[lane]:
            version_key(entry["version"])
    for version in manifest["piPackages"].values():
        version_key(version)
    for entry in manifest["external"].values():
        version_key(entry["version"])
        if "selfUpdateCommand" in entry or "bootstrapVersion" in entry:
            raise ValueError("external pins must not self-update")
        for platform in ("darwin-arm64", "darwin-amd64"):
            if not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"][platform]):
                raise ValueError("missing external checksum")


def render_settings(settings, pins):
    result = copy.deepcopy(settings)
    packages = []
    for package in result.get("packages", []):
        source = package if isinstance(package, str) else package["source"]
        if source.startswith("npm:"):
            name = source[4:].rsplit("@", 1)[0] if "@" in source[5:] else source[4:]
            if name not in pins:
                raise ValueError(f"Pi npm package has no managed pin: {name}")
            source = f"npm:{name}@{pins[name]}"
        elif source.startswith(("git:", "https://", "http://")):
            if not re.search(r"@[0-9a-f]{40}$", source):
                raise ValueError(f"Pi git package needs an immutable commit: {source}")
        if isinstance(package, str):
            packages.append(source)
        else:
            package["source"] = source
            packages.append(package)
    result["packages"] = packages
    return result


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=".pins-")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def choose(current, releases, now, blocked, security_fixes=frozenset()):
    """No downgrades/prereleases. Seven days inclusive; verified fixes may bypass age."""
    eligible = []
    for version, published in releases:
        if not VERSION.fullmatch(version) or version_key(version) <= version_key(current):
            continue
        age = now - datetime.fromisoformat(published)
        if age < timedelta(0) or (age < timedelta(days=7) and version not in security_fixes):
            continue
        if version not in blocked:
            eligible.append(version)
    if not eligible:
        return current, "keep: no newer age-qualified, non-vulnerable stable release"
    selected = max(eligible, key=version_key)
    reason = "OSV-known security fix" if selected in security_fixes else "public at least 7 days"
    return selected, reason


class Registry:
    def json(self, url, payload=None):
        body = None if payload is None else json.dumps(payload).encode()
        request = Request(url, data=body, headers={"Content-Type": "application/json", "User-Agent": "dotfiles-pins/1"})
        for attempt in range(3):
            delay = 2 ** attempt
            try:
                with urlopen(request, timeout=30) as response:
                    return json.load(response)
            except HTTPError as error:
                if error.code != 429 and not 500 <= error.code <= 599:
                    raise
                retry_after = error.headers.get("Retry-After")
                if retry_after:
                    try:
                        requested = float(retry_after)
                    except ValueError:
                        requested = (parsedate_to_datetime(retry_after) - datetime.now(UTC)).total_seconds()
                    # Fail closed rather than retry sooner than requested or
                    # hold a nightly job for an unbounded server delay.
                    if requested > 60:
                        raise
                    delay = max(delay, requested)
                if attempt == 2:
                    raise
            except URLError as error:
                if not isinstance(error.reason, TimeoutError) or attempt == 2:
                    raise
            except TimeoutError:
                if attempt == 2:
                    raise
            time.sleep(delay)
        raise AssertionError("unreachable retry state")

    def vulnerabilities(self, ecosystem, name, version):
        response = self.json("https://api.osv.dev/v1/query", {"package": {"ecosystem": ecosystem, "name": name}, "version": version})
        return [v for v in response.get("vulns", []) if not v.get("withdrawn")]

    def releases(self, lane, name, entry):
        if lane in ("npm", "piPackages"):
            data = self.json("https://registry.npmjs.org/" + quote(name, safe=""))
            return [(v, date) for v, date in data["time"].items() if v in data["versions"] and not data["versions"][v].get("deprecated")], {}
        if lane in ("uv", "python"):
            data = self.json("https://pypi.org/pypi/" + quote(name, safe="") + "/json")
            releases = []
            for version, files in data["releases"].items():
                # All files must have aged, not just an earlier sdist; ignore yanked versions.
                if files and not any(f.get("yanked") for f in files):
                    releases.append((version, max(f["upload_time_iso_8601"] for f in files)))
            return releases, {}
        template = r'{{range .}}{{if not .draft}}{{if not .prerelease}}{{.tag_name}}{{"\t"}}{{.published_at}}{{range .assets}}{{"\t"}}{{.name}}={{.digest}}{{end}}{{"\n"}}{{end}}{{end}}{{end}}'
        output = subprocess.run(["gh-axi", "api", f"repos/{entry['repo']}/releases?per_page=100", "--template", template], check=True, text=True, capture_output=True, timeout=60).stdout
        releases, checksums = [], {}
        for line in output.splitlines():
            parts = line.split("\t")
            version = parts[0].removeprefix("v")
            releases.append((version, parts[1]))
            assets = dict(p.split("=", 1) for p in parts[2:])
            checksums[version] = {}
            for platform in ("darwin-arm64", "darwin-amd64"):
                system, arch = platform.split("-")
                archive = entry["archivePattern"].format(version=version, os=system, arch=arch)
                digest = assets.get(archive, "").removeprefix("sha256:")
                if re.fullmatch(r"[0-9a-f]{64}", digest):
                    checksums[version][platform] = digest
        return releases, checksums


def select(manifest, now, registry):
    validate(manifest)
    result, decisions = copy.deepcopy(manifest), []
    for lane in ("npm", "uv", "python", "piPackages", "external"):
        entries = result[lane]
        if isinstance(entries, dict):
            entries = [{"name": name, "version": entry} if isinstance(entry, str) else dict(entry, name=name) for name, entry in entries.items()]
        for entry in entries:
            name, current = entry["name"], entry["version"]
            if lane == "uv" and name in ("mlx-lm", "mlx-optiq"):
                decisions.append(f"{lane}/{name}: keep {current}: MLX compatibility pin")
                continue
            ecosystem = "npm" if lane in ("npm", "piPackages") else "Go" if lane == "external" else "PyPI"
            osv_name = "github.com/" + entry["repo"] if lane == "external" else name
            osv_version = "v" + current if lane == "external" else current
            current_vulns = registry.vulnerabilities(ecosystem, osv_name, osv_version)
            fixes = set()
            for vulnerability in current_vulns:
                for affected in vulnerability.get("affected", []):
                    if affected.get("package", {}).get("name") != osv_name or affected.get("package", {}).get("ecosystem") != ecosystem:
                        continue
                    for affected_range in affected.get("ranges", []):
                        fixes.update(event["fixed"].removeprefix("v") for event in affected_range.get("events", []) if "fixed" in event)
            releases, checksums = registry.releases(lane, name, entry)
            blocked = set()
            while True:
                picked, reason = choose(current, releases, now, blocked, fixes)
                if picked == current:
                    break
                if lane == "external" and len(checksums.get(picked, {})) != 2:
                    blocked.add(picked)
                    decisions.append(f"{lane}/{name}: reject {picked}: missing registry sha256 digests")
                    continue
                if registry.vulnerabilities(ecosystem, osv_name, "v" + picked if lane == "external" else picked):
                    blocked.add(picked)
                    decisions.append(f"{lane}/{name}: reject {picked}: flagged by OSV")
                    continue
                break
            decisions.append(f"{lane}/{name}: {current} -> {picked}: {reason}; OSV checked" + ("; current pin vulnerable" if current_vulns else ""))
            if lane == "piPackages":
                result[lane][name] = picked
            elif lane == "external":
                result[lane][name]["version"] = picked
                if picked != current:
                    result[lane][name]["sha256"] = checksums[picked]
            else:
                entry["version"] = picked
    validate(result)
    return result, decisions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "select", "render", "sources"))
    parser.add_argument("--manifest", type=Path, default=ROOT / "nix/agent-tools.manifest.lock.json")
    parser.add_argument("--output", type=Path, help="select writes only when explicitly supplied")
    parser.add_argument("--settings", type=Path, default=ROOT / "home/.pi/agent/settings.json")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    validate(manifest)
    if args.command in ("render", "sources"):
        settings = render_settings(json.loads(args.settings.read_text()), manifest["piPackages"])
        if args.command == "render":
            if not args.output:
                parser.error("render requires --output")
            atomic_json(args.output, settings)
        else:
            for package in settings["packages"]:
                source = package if isinstance(package, str) else package["source"]
                if source.startswith(("npm:", "git:", "https://", "http://")):
                    print(source)
    elif args.command == "select":
        selected, decisions = select(manifest, datetime.now(UTC), Registry())
        print("\n".join(decisions))
        if args.output:
            atomic_json(args.output, selected)


if __name__ == "__main__":
    main()
