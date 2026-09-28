#!/usr/bin/env bash
# Reconcile Baby Menu's authored configuration links without deleting app state.
#
# Usage: reconcile-baby-menu-config.sh <source-config-dir> <target-config-dir>
#
# Baby Menu can recreate starter files after its managed links disappear.
# Existing non-symlink entries are moved to collision-safe dated backups before
# links are restored, while baby-menu.db and other runtime state stay untouched.
set -euo pipefail

SOURCE=${1:?usage: reconcile-baby-menu-config.sh <source-config-dir> <target-config-dir>}
TARGET=${2:?usage: reconcile-baby-menu-config.sh <source-config-dir> <target-config-dir>}

fail() {
  printf 'reconcile-baby-menu-config: %s\n' "$*" >&2
  exit 1
}

case "$SOURCE" in /*) ;; *) fail "source must be an absolute path" ;; esac
case "$TARGET" in /*) ;; *) fail "target must be an absolute path" ;; esac
[ -d "$SOURCE" ] && [ ! -L "$SOURCE" ] || fail "source is not a safe directory: $SOURCE"
[ -d "$SOURCE/extensions" ] && [ ! -L "$SOURCE/extensions" ] \
  || fail "source extensions directory is missing or unsafe"
for name in agents.json preferences.json; do
  [ -f "$SOURCE/$name" ] && [ ! -L "$SOURCE/$name" ] \
    || fail "source $name is missing or unsafe"
done

if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
  [ -d "$TARGET" ] && [ ! -L "$TARGET" ] || fail "target is not a safe directory: $TARGET"
else
  mkdir -p "$TARGET"
fi

backup_path() { # <destination> <stamp>
  local destination=$1 stamp=$2 candidate index=0
  candidate="${destination}.pre-dotfiles-${stamp}"
  while [ -e "$candidate" ] || [ -L "$candidate" ]; do
    index=$((index + 1))
    candidate="${destination}.pre-dotfiles-${stamp}.${index}"
  done
  printf '%s\n' "$candidate"
}

reconcile_link() { # <name> <stamp>
  local name=$1 stamp=$2 source destination backup
  source="$SOURCE/$name"
  destination="$TARGET/$name"

  if [ -L "$destination" ]; then
    return 0
  fi
  if [ -e "$destination" ]; then
    backup=$(backup_path "$destination" "$stamp")
    mv "$destination" "$backup"
    if ! ln -s "$source" "$destination"; then
      mv "$backup" "$destination"
      fail "could not link $destination"
    fi
    printf 'reconcile-baby-menu-config: preserved %s at %s\n' "$name" "$backup"
    return 0
  fi
  ln -s "$source" "$destination"
}

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
reconcile_link extensions "$STAMP"
reconcile_link agents.json "$STAMP"
reconcile_link preferences.json "$STAMP"
