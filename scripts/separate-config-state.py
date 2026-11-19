"""Replace a checkout-wide directory link with config-only links, preserving state.

Usage: separate-config-state.py [--adopt-app-changes] SOURCE TARGET CONFIG [CONFIG ...]
The Nix declaration supplies the allowlist. Unlisted entries move to TARGET,
including hidden files and live sockets. Nothing is deleted or overwritten.

Some apps (OBS) replace a config symlink with a real file whenever they save.
With --adopt-app-changes such a file is not a conflict: the newer of the two
versions becomes the repository file, both are first saved (privately, they can
hold stream keys) under ~/.local/state/config-adopt, and the path is linked again.
Conflicts in this app's plan stop it before adoption; other apps are checked by
Home Manager. A concurrent replacement save is left untouched and stops relinking.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time
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


def _check_destination(entry, destination, target, is_config, adopt=False):
    parent = destination.parent
    while parent != target:
        if parent.is_symlink() or (parent.exists() and not parent.is_dir()):
            raise ValueError(f"unsafe target parent: {parent}")
        parent = parent.parent
    if not os.path.lexists(destination):
        return
    if is_config and destination.is_symlink() and destination.resolve() == entry.resolve():
        return
    if is_config and adopt and destination.is_file() and not destination.is_symlink():
        return
    raise ValueError(f"target conflict; both versions preserved: {destination}")


def _private_copy(source, directory):
    previous = os.umask(0o077)  # every directory created on the way is owner-only too
    try:
        directory.mkdir(parents=True, exist_ok=True)
        copy = directory / source.name
        shutil.copy2(source, copy)
        copy.chmod(0o600)
    finally:
        os.umask(previous)


def _adopt(entry, destination):
    """Reconcile an app-written real file with its repository file, then relink."""
    previous = os.umask(0o077)
    try:
        root = Path.home() / ".local/state/config-adopt"
        root.mkdir(parents=True, exist_ok=True)
        backup = Path(tempfile.mkdtemp(prefix=time.strftime("%Y%m%d-%H%M%S-"), dir=root))
        _private_copy(entry, backup / "repo")
        _private_copy(destination, backup / "app")
    finally:
        os.umask(previous)
    saved = destination.rename(backup / "app" / (".claimed-" + destination.name))
    try:
        saved.chmod(0o600)
        if saved.stat().st_mtime_ns > entry.stat().st_mtime_ns:
            with tempfile.TemporaryDirectory(prefix=".config-adopt-", dir=entry.parent) as staging:
                replacement = Path(staging) / entry.name
                shutil.copy2(saved, replacement)
                os.replace(replacement, entry)
            outcome = "adopted the app's newer file into the repository"
        else:
            outcome = "kept the repo version (the app's file was not newer)"
        destination.symlink_to(entry)
    except OSError:
        try:
            os.link(saved, destination)
        except FileExistsError:
            print(f"separate-config-state: replacement preserved at {destination}; claimed version remains at {saved}", file=sys.stderr)
        raise
    return f"{destination}: {outcome}; both versions saved in {backup}"


def _apply(entries, adopt=False):
    moved = 0
    for entry, destination, is_config in entries:
        destination.parent.mkdir(parents=True, exist_ok=True)
        if is_config:
            if adopt and destination.is_file() and not destination.is_symlink():
                print(f"separate-config-state: {_adopt(entry, destination)}")
            elif not destination.is_symlink():
                destination.symlink_to(entry)
        else:
            # mv -n also protects against a live app creating the destination
            # after preflight. Same-filesystem moves retain open files/sockets.
            subprocess.run(["/bin/mv", "-n", str(entry), str(destination)], check=True, timeout=30)
            if os.path.lexists(entry):
                raise ValueError(f"runtime move conflicted; both versions preserved: {destination}")
            moved += 1
    return moved


def separate(source: Path, target: Path, configs: list[str], adopt: bool = False) -> int:
    source, target = _checked_directories(source, target)
    kept = _configuration_files(source, configs)
    old_link = _check_target(source, target)
    entries = list(_entries(source, target, kept))
    # Check the whole plan before detaching a managed parent or moving state.
    if not old_link:
        for entry, destination, is_config in entries:
            _check_destination(entry, destination, target, is_config, adopt)
    if old_link:
        target.unlink()
    target.mkdir(parents=True, exist_ok=True)
    return _apply(entries, adopt)


def main():
    args = sys.argv[1:]
    adopt = "--adopt-app-changes" in args
    args = [arg for arg in args if arg != "--adopt-app-changes"]
    if len(args) < 3:
        raise ValueError("usage: separate-config-state.py [--adopt-app-changes] SOURCE TARGET CONFIG [CONFIG ...]")
    source, target = map(Path, args[:2])
    moved = separate(source, target, args[2:], adopt)
    print(f"separate-config-state: {target}: {moved} runtime entries relocated; config-only links ready")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(f"separate-config-state: {error}", file=sys.stderr)
        sys.exit(1)
