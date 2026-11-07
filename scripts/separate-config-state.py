"""Replace a checkout-wide directory link with config-only links, preserving state.

Usage: separate-config-state.py SOURCE TARGET CONFIG [CONFIG ...]
The Nix declaration supplies the allowlist. Unlisted entries move to TARGET,
including hidden files and live sockets. Nothing is deleted or overwritten.
"""
import os
import subprocess
import sys
from pathlib import Path


def _checked_directories(source, target):
    if not source.is_absolute() or not target.is_absolute():
        raise ValueError("source and target must be absolute paths")
    if source.is_symlink() or not source.is_dir():
        raise ValueError(f"source must be a real directory: {source}")
    source = source.resolve()
    # Resolve the parent only: TARGET may be the old link into SOURCE.
    target = target.parent.resolve() / target.name
    if source == target or source.is_relative_to(target) or target.is_relative_to(source):
        raise ValueError("source and target must not overlap")
    return source, target


def _configuration_files(source, names):
    kept = set()
    for name in names:
        path = Path(name)
        if path.is_absolute() or ".." in path.parts or not path.parts:
            raise ValueError(f"unsafe configuration path: {name}")
        entry = source / path
        if not entry.is_file():
            raise ValueError(f"declared configuration file is missing: {entry}")
        if not entry.resolve().is_relative_to(source):
            raise ValueError(f"configuration escapes the source directory: {name}")
        kept.add(entry)
    if not kept:
        raise ValueError("at least one configuration path is required")
    return kept


def _check_target(source, target):
    old_link = target.is_symlink()
    if old_link:
        if target.resolve() != source:
            raise ValueError(f"refusing an unrelated directory link: {target}")
    elif target.exists() and not target.is_dir():
        raise ValueError(f"target must be a directory: {target}")
    filesystem = target if not old_link and target.exists() else target.parent
    while not filesystem.exists():
        filesystem = filesystem.parent
    if source.stat().st_dev != filesystem.stat().st_dev:
        raise ValueError("runtime relocation requires the same filesystem (including sockets)")
    return old_link


def _entries(source, target, kept):
    for entry in sorted(source.iterdir()):
        destination = target / entry.name
        if entry in kept:
            yield entry, destination, True
        elif any(path.is_relative_to(entry) for path in kept):
            if entry.is_symlink() or not entry.is_dir():
                raise ValueError(f"configuration parent must be a real directory: {entry}")
            yield from _entries(entry, destination, kept)
        else:
            yield entry, destination, False


def _check_destination(entry, destination, target, is_config):
    parent = destination.parent
    while parent != target:
        if parent.is_symlink() or (parent.exists() and not parent.is_dir()):
            raise ValueError(f"unsafe target parent: {parent}")
        parent = parent.parent
    if not os.path.lexists(destination):
        return
    if is_config and destination.is_symlink() and destination.resolve() == entry.resolve():
        return
    raise ValueError(f"target conflict; both versions preserved: {destination}")


def _apply(entries):
    moved = 0
    for entry, destination, is_config in entries:
        destination.parent.mkdir(parents=True, exist_ok=True)
        if is_config:
            if not destination.is_symlink():
                destination.symlink_to(entry)
        else:
            # mv -n also protects against a live app creating the destination
            # after preflight. Same-filesystem moves retain open files/sockets.
            subprocess.run(["/bin/mv", "-n", str(entry), str(destination)], check=True, timeout=30)
            if os.path.lexists(entry):
                raise ValueError(f"runtime move conflicted; both versions preserved: {destination}")
            moved += 1
    return moved


def separate(source: Path, target: Path, configs: list[str]) -> int:
    source, target = _checked_directories(source, target)
    kept = _configuration_files(source, configs)
    old_link = _check_target(source, target)
    entries = list(_entries(source, target, kept))
    # Check the whole plan before detaching a managed parent or moving state.
    if not old_link:
        for entry, destination, is_config in entries:
            _check_destination(entry, destination, target, is_config)
    if old_link:
        target.unlink()
    target.mkdir(parents=True, exist_ok=True)
    return _apply(entries)


def main():
    if len(sys.argv) < 4:
        raise ValueError("usage: separate-config-state.py SOURCE TARGET CONFIG [CONFIG ...]")
    source, target = map(Path, sys.argv[1:3])
    moved = separate(source, target, sys.argv[3:])
    print(f"separate-config-state: {target}: {moved} runtime entries relocated; config-only links ready")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(f"separate-config-state: {error}", file=sys.stderr)
        sys.exit(1)
