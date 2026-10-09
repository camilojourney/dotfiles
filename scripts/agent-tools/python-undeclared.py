"""Print the pip-installed packages in this interpreter that nothing declared needs.

Usage: python3 python-undeclared.py [--path SITE_DIR] [DECLARED ...]

Run with the interpreter being reconciled (Homebrew's python3). A package is
kept when it is declared, was installed by something other than pip (Homebrew
ships pip and wheel itself), or is a runtime dependency of either
(transitively). Everything else is printed, one name per line, for
reconcile.sh to uninstall. --path scans a directory instead of the
interpreter's own site-packages (used by tests).
"""

import argparse
import importlib.metadata as md
import re

from pip._vendor.packaging.requirements import InvalidRequirement, Requirement


def canonical(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def installer(dist):
    return (dist.read_text("INSTALLER") or "").strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", action="append")
    parser.add_argument("declared", nargs="*")
    args = parser.parse_args()

    dists = {}
    for dist in md.distributions(path=args.path) if args.path else md.distributions():
        dists.setdefault(canonical(dist.metadata["Name"]), dist)

    keep = set()
    pending = [canonical(name) for name in args.declared]
    pending += [name for name, dist in dists.items() if installer(dist) != "pip"]
    while pending:
        name = pending.pop()
        if name in keep or name not in dists:
            continue
        keep.add(name)
        for spec in dists[name].requires or []:
            try:
                req = Requirement(spec)
            except InvalidRequirement:
                continue
            # Skip optional extras and requirements for other platforms.
            if req.marker and not req.marker.evaluate({"extra": ""}):
                continue
            pending.append(canonical(req.name))

    for name in sorted(set(dists) - keep):
        print(name)


if __name__ == "__main__":
    main()
