#!/usr/bin/env bash
# Regression tests for Baby Menu configuration-link recovery.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
SCRIPT="$ROOT/scripts/reconcile-baby-menu-config.sh"
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/baby-menu-config-test.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT
SOURCE="$SANDBOX/source"
TARGET="$SANDBOX/home/.baby-menu"
mkdir -p "$SOURCE/extensions" "$TARGET/extensions"
printf 'saved widget\n' > "$SOURCE/extensions/widget.tsx"
printf '[{"name":"agy"}]\n' > "$SOURCE/agents.json"
printf '{"openAtLogin":true}\n' > "$SOURCE/preferences.json"
printf 'starter widget\n' > "$TARGET/extensions/starter.tsx"
printf 'runtime database\n' > "$TARGET/baby-menu.db"
printf 'starter agents\n' > "$TARGET/agents.json"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

"$SCRIPT" "$SOURCE" "$TARGET"

[ -L "$TARGET/extensions" ] || fail "extensions was not linked"
[ -L "$TARGET/agents.json" ] || fail "agents.json was not linked"
[ -L "$TARGET/preferences.json" ] || fail "preferences.json was not linked"
[ "$(readlink "$TARGET/extensions")" = "$SOURCE/extensions" ] || fail "extensions link target is wrong"
[ "$(readlink "$TARGET/agents.json")" = "$SOURCE/agents.json" ] || fail "agents link target is wrong"
[ "$(readlink "$TARGET/preferences.json")" = "$SOURCE/preferences.json" ] || fail "preferences link target is wrong"
[ "$(<"$TARGET/baby-menu.db")" = "runtime database" ] || fail "runtime database changed"

extension_backup=$(find "$TARGET" -maxdepth 1 -name 'extensions.pre-dotfiles-*' -type d -print)
agents_backup=$(find "$TARGET" -maxdepth 1 -name 'agents.json.pre-dotfiles-*' -type f -print)
[ -n "$extension_backup" ] || fail "starter extensions were not preserved"
[ -n "$agents_backup" ] || fail "starter agents were not preserved"
[ "$(<"$extension_backup/starter.tsx")" = "starter widget" ] || fail "starter extension backup changed"
[ "$(<"$agents_backup")" = "starter agents" ] || fail "starter agents backup changed"

backup_count_before=$(find "$TARGET" -maxdepth 1 -name '*.pre-dotfiles-*' | wc -l | tr -d ' ')
"$SCRIPT" "$SOURCE" "$TARGET"
backup_count_after=$(find "$TARGET" -maxdepth 1 -name '*.pre-dotfiles-*' | wc -l | tr -d ' ')
[ "$backup_count_before" = "$backup_count_after" ] || fail "idempotent run created another backup"

BROKEN_SOURCE="$SANDBOX/broken-source"
BROKEN_TARGET="$SANDBOX/broken-target"
mkdir -p "$BROKEN_SOURCE/extensions" "$BROKEN_TARGET/extensions"
printf 'keep me\n' > "$BROKEN_TARGET/extensions/starter.tsx"
printf '[]\n' > "$BROKEN_SOURCE/agents.json"
if "$SCRIPT" "$BROKEN_SOURCE" "$BROKEN_TARGET" >/dev/null 2>&1; then
  fail "missing preferences source was accepted"
fi
[ -f "$BROKEN_TARGET/extensions/starter.tsx" ] || fail "failed validation mutated the target"
[ ! -L "$BROKEN_TARGET/extensions" ] || fail "failed validation linked the target"

printf 'PASS: Baby Menu config conflicts are preserved and authored links are restored\n'
