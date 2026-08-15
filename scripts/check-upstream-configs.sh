#!/usr/bin/env bash
# Mirror the complete kunchenguid/dotfiles repository and compare our selected
# live configs against its home/.config/{wezterm,nvim,herdr} files. Uses
# upstream/kunchenguid/decisions.json so we can adopt updates without
# blind-overwriting intentional local changes.
#
# Usage:
#   bash scripts/check-upstream-configs.sh           # report only
#   bash scripts/check-upstream-configs.sh --apply   # safe-apply track files only
#   bash scripts/check-upstream-configs.sh --refresh-snapshot
#   bash scripts/check-upstream-configs.sh --refresh-repository
#
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DECISIONS="$REPO_ROOT/upstream/kunchenguid/decisions.json"
SNAP="$REPO_ROOT/upstream/kunchenguid/snapshot"
MIRROR="$REPO_ROOT/upstream/kunchenguid/repository"
MIRROR_COMMIT="$REPO_ROOT/upstream/kunchenguid/repository.commit"
OURS="$REPO_ROOT/files/.config"
PI_OURS="$REPO_ROOT/files/.pi/agent"
UPSTREAM_REPO="${UPSTREAM_REPO:-kunchenguid/dotfiles}"
UPSTREAM_REF="${UPSTREAM_REF:-main}"

APPLY=0
REFRESH_ONLY=0
REPOSITORY_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --refresh-snapshot) REFRESH_ONLY=1 ;;
    --refresh-repository) REPOSITORY_ONLY=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $arg" >&2
      exit 2
      ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "need $1" >&2; exit 1; }; }
need curl
need python3
need git

if [ ! -f "$DECISIONS" ]; then
  echo "Missing $DECISIONS" >&2
  exit 1
fi

sha256_file() {
  python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
}

fetch_commit() {
  if command -v gh >/dev/null 2>&1; then
    gh api "repos/${UPSTREAM_REPO}/commits/${UPSTREAM_REF}" --jq .sha
  else
    curl -fsSL "https://api.github.com/repos/${UPSTREAM_REPO}/commits/${UPSTREAM_REF}" \
      | python3 -c 'import sys,json; print(json.load(sys.stdin)["sha"])'
  fi
}

refresh_repository() {
  local commit="$1"
  local tmp repo staged mirror_commit

  tmp=$(mktemp -d)
  repo="$tmp/repository"
  staged="$tmp/staged"
  git init --quiet "$repo"
  git -C "$repo" remote add origin "https://github.com/${UPSTREAM_REPO}.git"
  git -C "$repo" fetch --quiet --depth 1 origin "$commit"
  mirror_commit=$(git -C "$repo" rev-parse FETCH_HEAD)
  if [ "$mirror_commit" != "$commit" ]; then
    echo "Fetched commit $mirror_commit does not match requested commit $commit" >&2
    rm -rf "$tmp"
    exit 1
  fi

  mkdir -p "$staged"
  git -C "$repo" archive --format=tar "$commit" | tar -xf - -C "$staged"
  rm -rf "$MIRROR"
  mv "$staged" "$MIRROR"
  printf '%s\n' "$mirror_commit" >"$MIRROR_COMMIT"

  python3 - "$DECISIONS" "$mirror_commit" <<'PY'
import json, pathlib, sys
dec_path, commit = sys.argv[1], sys.argv[2]
data = json.loads(pathlib.Path(dec_path).read_text())
data["upstream"]["mirror_commit"] = commit
pathlib.Path(dec_path).write_text(json.dumps(data, indent=2) + "\n")
PY

  rm -rf "$tmp"
}

import_missing_authored_configs() {
  local source rel dest

  # Import only files that do not exist locally. Existing files may contain
  # intentional additions and must go through the decisions workflow instead.
  if [ -d "$MIRROR/home/.pi/agent" ]; then
    while IFS= read -r -d '' source; do
      rel="${source#"$MIRROR/home/.pi/agent/"}"
      dest="$PI_OURS/$rel"
      if [ ! -e "$dest" ]; then
        mkdir -p "$(dirname "$dest")"
        cp -p "$source" "$dest"
        echo "Imported missing upstream Pi config: home/.pi/agent/$rel"
      fi
    done < <(find "$MIRROR/home/.pi/agent" -type f -print0)
  fi

  if [ ! -e "$REPO_ROOT/files/.claude/settings.json" ] && [ -f "$MIRROR/home/.claude/settings.json" ]; then
    mkdir -p "$REPO_ROOT/files/.claude"
    cp -p "$MIRROR/home/.claude/settings.json" "$REPO_ROOT/files/.claude/settings.json"
    echo "Imported missing upstream Claude config: home/.claude/settings.json"
  fi
}

refresh_snapshot() {
  local commit="$1"
  local base="https://raw.githubusercontent.com/${UPSTREAM_REPO}/${commit}/home/.config"
  local rel path dest

  mkdir -p "$SNAP"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("\n".join(d["files"].keys()))' "$DECISIONS" \
    | while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        dest="$SNAP/$rel"
        mkdir -p "$(dirname "$dest")"
        curl -fsSL "$base/$rel" -o "$dest"
      done

  # Also pick up any new upstream files under the three roots (informational).
  # Tree listing via GitHub API (best-effort).
  if command -v gh >/dev/null 2>&1; then
    gh api "repos/${UPSTREAM_REPO}/git/trees/${commit}?recursive=1" --jq '
      .tree[] | select(.type=="blob") | .path
      | select(startswith("home/.config/wezterm/")
            or startswith("home/.config/nvim/")
            or startswith("home/.config/herdr/"))
      | sub("^home/.config/"; "")
    ' >"$SNAP/.upstream_file_list" || true
  fi

  python3 - "$DECISIONS" "$commit" <<'PY'
import json, pathlib, sys, datetime
dec_path, commit = sys.argv[1], sys.argv[2]
data = json.loads(pathlib.Path(dec_path).read_text())
data["upstream"]["last_checked_commit"] = commit
data["upstream"]["last_checked_at"] = datetime.date.today().isoformat()
pathlib.Path(dec_path).write_text(json.dumps(data, indent=2) + "\n")
PY
}

COMMIT=$(fetch_commit)
echo "Upstream ${UPSTREAM_REPO}@${UPSTREAM_REF} -> ${COMMIT}"
refresh_repository "$COMMIT"
import_missing_authored_configs

if [ "$REPOSITORY_ONLY" -eq 1 ]; then
  echo "Complete repository mirrored at $MIRROR"
  exit 0
fi

refresh_snapshot "$COMMIT"

if [ "$REFRESH_ONLY" -eq 1 ]; then
  echo "Snapshot refreshed at $SNAP"
  exit 0
fi

python3 - "$DECISIONS" "$SNAP" "$OURS" "$APPLY" <<'PY'
import json, hashlib, pathlib, shutil, sys

dec_path = pathlib.Path(sys.argv[1])
snap_root = pathlib.Path(sys.argv[2])
ours_root = pathlib.Path(sys.argv[3])
apply = sys.argv[4] == "1"
data = json.loads(dec_path.read_text())

def sha(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()

tracked = data["files"]
statuses = []
applied = []
blocked = []
new_upstream = []

list_path = snap_root / ".upstream_file_list"
if list_path.exists():
    for rel in list_path.read_text().splitlines():
        if rel and rel not in tracked:
            new_upstream.append(rel)

print()
print(f"{'FILE':<42} {'POLICY':<8} STATUS")
print("-" * 78)

for rel, meta in sorted(tracked.items()):
    policy = meta.get("policy", "track")
    adopted = meta.get("adopted_upstream_sha256", "")
    snap = snap_root / rel
    ours = ours_root / rel
    note = ""

    if not snap.exists():
        status = "MISSING_UPSTREAM"
        note = "could not fetch"
    elif not ours.exists():
        status = "MISSING_OURS"
        note = "not in files/.config"
        up = sha(snap)
        if apply and policy == "track":
            ours.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(snap, ours)
            meta["adopted_upstream_sha256"] = up
            applied.append(rel)
            status = "APPLIED_NEW"
            note = "copied from upstream"
    else:
        up = sha(snap)
        our = sha(ours)
        clean = our == adopted
        upstream_moved = up != adopted
        if our == up:
            status = "IN_SYNC"
            note = "ours == upstream"
            if upstream_moved and apply:
                meta["adopted_upstream_sha256"] = up
                applied.append(rel)
                status = "BUMPED"
                note = "already matched new upstream; recorded"
        elif not upstream_moved and not clean:
            status = "EXTENDED"
            note = "our local changes on top of last adopt"
            if meta.get("our_additions"):
                note += " | additions: " + ", ".join(meta["our_additions"])
        elif upstream_moved and clean:
            status = "UPSTREAM_UPDATE"
            note = "safe to adopt (ours still == last adopted)"
            if apply and policy == "track":
                shutil.copy2(snap, ours)
                meta["adopted_upstream_sha256"] = up
                applied.append(rel)
                status = "APPLIED"
                note = "adopted new upstream"
            elif apply:
                blocked.append((rel, policy))
                status = "BLOCKED"
                note = f"policy={policy}; review manually"
        elif upstream_moved and not clean:
            status = "CONFLICT"
            note = "upstream moved AND we customized"
            if apply:
                blocked.append((rel, policy))
        else:
            status = "IN_SYNC"
            note = "upstream unchanged"

    print(f"{rel:<42} {policy:<8} {status}  ({note})")
    statuses.append(status)

print()
if new_upstream:
    print("New upstream files not in decisions.json yet:")
    for rel in new_upstream:
        print(f"  + {rel}")
    print("Add them to decisions.json with a policy when you decide.")
    print()

if apply:
    dec_path.write_text(json.dumps(data, indent=2) + "\n")
    if applied:
        print(f"Applied {len(applied)} file(s).")
    if blocked:
        print("Blocked (need manual review):")
        for rel, pol in blocked:
            print(f"  ! {rel} (policy={pol})")
            print(f"      diff -u {ours_root / rel} {snap_root / rel}")
    if not applied and not blocked:
        print("Nothing to apply.")
else:
    actionable = sum(1 for s in statuses if s in ("UPSTREAM_UPDATE", "MISSING_OURS", "CONFLICT"))
    print(f"Check complete. {actionable} file(s) need attention.")
    print("Safe auto-adopt for clean track files: bash scripts/check-upstream-configs.sh --apply")
    print("Review diffs: diff -u files/.config/<path> upstream/kunchenguid/snapshot/<path>")
PY
