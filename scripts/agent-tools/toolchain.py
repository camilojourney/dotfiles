#!/usr/bin/env python3
"""Exact top-level pins: validation, effective Pi settings and read-only selection.

Network is confined to public package registries (including GitHub Releases)
and OSV. Unknown metadata, missing digests or OSV failures abort selection.
"""
# ruff: noqa: S310
# S310: HTTPS-only fixed registry/OSV hosts; every request has a 30-second timeout.
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
from urllib.parse import quote, urlsplit
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
VERSION = re.compile(r"\d+(?:\.\d+)+\Z")
REGISTRIES = {"registry.npmjs.org", "pypi.org", "api.osv.dev"}


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


def _pinned_source(source, pins):
    if source.startswith("npm:"):
        name = source[4:].rsplit("@", 1)[0] if "@" in source[5:] else source[4:]
        if name not in pins:
            raise ValueError(f"Pi npm package has no managed pin: {name}")
        return f"npm:{name}@{pins[name]}"
    if source.startswith(("git:", "https://", "http://")) and not re.search(r"@[0-9a-f]{40}$", source):
        raise ValueError(f"Pi git package needs an immutable commit: {source}")
    return source


def render_settings(settings, pins):
    result = copy.deepcopy(settings)
    packages = []
    for package in result.get("packages", []):
        source = package if isinstance(package, str) else package["source"]
        pinned = _pinned_source(source, pins)
        if isinstance(package, str):
            packages.append(pinned)
        else:
            package["source"] = pinned
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


def _retry_delay(error, attempt):
    if attempt == 2:
        raise error
    delay = 2 ** attempt
    if isinstance(error, HTTPError):
        if error.code != 429 and not 500 <= error.code <= 599:
            raise error
        return max(delay, _retry_after(error.headers.get("Retry-After")))
    if isinstance(error, URLError) and not isinstance(error.reason, TimeoutError):
        raise error
    return delay


def _retry_after(value):
    if not value:
        return 0
    try:
        requested = float(value)
    except ValueError:
        requested = (parsedate_to_datetime(value) - datetime.now(UTC)).total_seconds()
    # Fail closed rather than retry sooner than requested or wait indefinitely.
    if requested > 60:
        raise ValueError("registry Retry-After exceeds the 60-second retry budget")
    return requested


def _pypi_releases(data):
    releases = []
    for version, files in data["releases"].items():
        # All files must have aged, not just an earlier sdist; ignore yanked versions.
        if files and not any(f.get("yanked") for f in files):
            releases.append((version, max(f["upload_time_iso_8601"] for f in files)))
    return releases


def _release_digests(entry, version, assets):
    checksums = {}
    for platform in ("darwin-arm64", "darwin-amd64"):
        system, arch = platform.split("-")
        archive = entry["archivePattern"].format(version=version, os=system, arch=arch)
        digest = assets.get(archive, "").removeprefix("sha256:")
        if re.fullmatch(r"[0-9a-f]{64}", digest):
            checksums[platform] = digest
    return checksums


def _github_releases(entry):
    template = r'{{range .}}{{if not .draft}}{{if not .prerelease}}{{.tag_name}}{{"\t"}}{{.published_at}}{{range .assets}}{{"\t"}}{{.name}}={{.digest}}{{end}}{{"\n"}}{{end}}{{end}}{{end}}'
    output = subprocess.run(["gh-axi", "api", f"repos/{entry['repo']}/releases?per_page=100", "--template", template], check=True, text=True, capture_output=True, timeout=60).stdout
    releases, checksums = [], {}
    for line in output.splitlines():
        tag, published, *asset_fields = line.split("\t")
        # install-external.sh uses v-prefixed release tags, not arbitrary refs.
        if not tag.startswith("v"):
            continue
        version = tag[1:]
        releases.append((version, published))
        assets = dict(field.split("=", 1) for field in asset_fields)
        checksums[version] = _release_digests(entry, version, assets)
    return releases, checksums


class Registry:
    def json(self, url, payload=None):
        parsed = urlsplit(url)
        if parsed.scheme != "https" or parsed.netloc not in REGISTRIES:
            raise ValueError("only fixed HTTPS registry and OSV hosts are allowed")
        body = None if payload is None else json.dumps(payload).encode()
        # S310: scheme and exact host are checked above; callers supply no arbitrary URLs.
        request = Request(url, data=body, headers={"Content-Type": "application/json", "User-Agent": "dotfiles-pins/1"})
        for attempt in range(3):
            try:
                with urlopen(request, timeout=30) as response:
                    return json.load(response)
            except (HTTPError, URLError, TimeoutError) as error:
                if isinstance(error, HTTPError):
                    error.close()
                time.sleep(_retry_delay(error, attempt))
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
            return _pypi_releases(data), {}
        return _github_releases(entry)


def _fixed_versions(ranges):
    versions = set()
    for affected_range in ranges:
        for event in affected_range.get("events", []):
            if "fixed" in event:
                versions.add(event["fixed"].removeprefix("v"))
    return versions


def _security_fixes(vulns, package):
    fixes = set()
    for vulnerability in vulns:
        for affected in vulnerability.get("affected", []):
            declared = affected.get("package", {})
            if (declared.get("name"), declared.get("ecosystem")) == (package["name"], package["ecosystem"]):
                fixes.update(_fixed_versions(affected.get("ranges", [])))
    return fixes


def _candidate_rejection(version, checksums, check_version):
    if checksums is not None and len(checksums.get(version, {})) != 2:
        return "missing registry sha256 digests"
    if check_version(version):
        return "flagged by OSV"
    return None


def _pick_release(current, catalog, now, fixes, check_version):
    releases, checksums = catalog
    blocked, rejections = set(), []
    while True:
        picked, reason = choose(current, releases, now, blocked, fixes)
        if picked == current:
            return picked, reason, rejections
        rejection = _candidate_rejection(picked, checksums, check_version)
        if not rejection:
            return picked, reason, rejections
        blocked.add(picked)
        rejections.append(f"reject {picked}: {rejection}")


def _select_entry(lane, name, entry, now, registry):
    current = entry["version"]
    if lane == "uv" and name in ("mlx-lm", "mlx-optiq"):
        return current, None, [f"keep {current}: MLX compatibility pin"]
    ecosystem = "npm" if lane in ("npm", "piPackages") else "Go" if lane == "external" else "PyPI"
    osv_name = "github.com/" + entry["repo"] if lane == "external" else name
    def check_version(version):
        return registry.vulnerabilities(ecosystem, osv_name, "v" + version if lane == "external" else version)
    current_vulns = check_version(current)
    fixes = _security_fixes(current_vulns, {"ecosystem": ecosystem, "name": osv_name})
    releases, checksums = registry.releases(lane, name, entry)
    digests = checksums if lane == "external" else None
    picked, reason, decisions = _pick_release(current, (releases, digests), now, fixes, check_version)
    decisions.append(f"{current} -> {picked}: {reason}; OSV checked" + ("; current pin vulnerable" if current_vulns else ""))
    new_digests = checksums[picked] if lane == "external" and picked != current else None
    return picked, new_digests, decisions


def _entries(manifest, lane):
    entries = manifest[lane]
    if isinstance(entries, list):
        return [(entry["name"], entry) for entry in entries]
    return [(name, {"version": entry} if isinstance(entry, str) else entry) for name, entry in entries.items()]


def select(manifest, now, registry):
    validate(manifest)
    result, decisions = copy.deepcopy(manifest), []
    for lane in ("npm", "uv", "python", "piPackages", "external"):
        for name, entry in _entries(result, lane):
            picked, checksums, notes = _select_entry(lane, name, entry, now, registry)
            entry["version"] = picked
            if checksums:
                entry["sha256"] = checksums
            if lane == "piPackages":
                result[lane][name] = picked
            decisions.extend(f"{lane}/{name}: {note}" for note in notes)
    validate(result)
    return result, decisions


def _settings_command(args, manifest):
    settings = render_settings(json.loads(args.settings.read_text()), manifest["piPackages"])
    if args.command == "render":
        atomic_json(args.output, settings)
        return
    for package in settings["packages"]:
        source = package if isinstance(package, str) else package["source"]
        if source.startswith(("npm:", "git:", "https://", "http://")):
            print(source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "select", "render", "sources"))
    parser.add_argument("--manifest", type=Path, default=ROOT / "nix/agent-tools.manifest.lock.json")
    parser.add_argument("--output", type=Path, help="select writes only when explicitly supplied")
    parser.add_argument("--settings", type=Path, default=ROOT / "home/.pi/agent/settings.json")
    args = parser.parse_args()
    if args.command == "render" and not args.output:
        parser.error("render requires --output")
    manifest = json.loads(args.manifest.read_text())
    validate(manifest)
    if args.command in ("render", "sources"):
        _settings_command(args, manifest)
    elif args.command == "select":
        selected, decisions = select(manifest, datetime.now(UTC), Registry())
        print("\n".join(decisions))
        if args.output:
            atomic_json(args.output, selected)


if __name__ == "__main__":
    main()
