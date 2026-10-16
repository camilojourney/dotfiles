#!/usr/bin/env python3
"""Fail closed before starting task-owned services on a private macOS SSD."""

import json
import os
import plistlib
import shutil
import stat
import subprocess
import sys
from pathlib import Path


class GateError(Exception):
    """A prerequisite is missing. No service should start."""


def disk_info(mountpoint):
    try:
        result = subprocess.run(
            ["/usr/sbin/diskutil", "info", "-plist", str(mountpoint)],
            check=True,
            capture_output=True,
            timeout=15,
        )
        return plistlib.loads(result.stdout)
    except (
        OSError,
        subprocess.SubprocessError,
        plistlib.InvalidFileException,
        ValueError,
    ) as error:
        raise GateError("cannot verify mounted device") from error


def private_path(path, directory=False):
    if path.is_symlink() or path.resolve() != path:
        raise GateError("symlinked storage or configuration path")
    info = path.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise GateError("storage or configuration is not owner-only")
    if directory and not stat.S_ISDIR(info.st_mode):
        raise GateError("storage path is not a directory")
    if not directory and not stat.S_ISREG(info.st_mode):
        raise GateError("configuration is not a regular file")
    return info


# [impl->req~agent-platform.storage-gate~1]
def check(config_path):
    private_path(config_path)
    config = json.loads(config_path.read_text())
    mountpoint, root = Path(config["mountpoint"]), Path(config["root"])
    uuid = config["volume_uuid"]
    minimum = config["minimum_free_bytes"]
    if (
        not mountpoint.is_absolute()
        or not root.is_absolute()
        or root.parent != mountpoint
        or root.name != "agent-platform"
        or mountpoint.resolve() != mountpoint
        or not isinstance(uuid, str)
        or not uuid
        or type(minimum) is not int
        or minimum < 0
    ):
        raise GateError("invalid volume configuration")
    info = disk_info(mountpoint)
    if (
        info.get("MountPoint") != str(mountpoint)
        or info.get("VolumeUUID") != uuid
        or info.get("FilesystemType") != "apfs"
    ):
        raise GateError("expected APFS volume is not mounted here")
    if info.get("GlobalPermissionsEnabled") is not True:
        raise GateError("SSD ownership is disabled; private service startup refused")
    if os.statvfs(mountpoint).f_flag & os.ST_RDONLY:
        raise GateError("SSD is read-only")
    device = mountpoint.stat().st_dev
    for relative in (".", "state", "state/pi", "state/langfuse", "artifacts", "logs"):
        if private_path(root / relative, directory=True).st_dev != device:
            raise GateError("storage crosses the verified volume")
    if shutil.disk_usage(mountpoint).free < minimum:
        raise GateError("SSD free space is below the configured reserve")


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if not args or (len(args) > 1 and (args[1] != "--" or len(args) < 3)):
        print(
            "usage: require-ssd.py /absolute/private/volume.json [-- command args...]",
            file=sys.stderr,
        )
        return 2
    try:
        config = Path(args[0])
        if not config.is_absolute():
            raise GateError("configuration path must be absolute")
        check(config)
    except (GateError, OSError, ValueError, KeyError, TypeError) as error:
        # Do not print configuration, subprocess output, or private paths.
        message = (
            str(error)
            if isinstance(error, GateError)
            else "invalid or unavailable storage configuration"
        )
        print(f"agent-platform: {message}", file=sys.stderr)
        return 1
    if len(args) > 1:
        os.execvp(args[2], args[2:])
    print("agent-platform: storage prerequisites verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
