#!/usr/bin/env bash
# Exercise the actual daily entrypoint with stateful user/system boundaries.
# No real sudo, Git transport, mas, launchctl, switch or install is executed.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/auto-rebuild-test.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT
export TEST_TRACE="$SANDBOX/trace"
HOME_DIR="$SANDBOX/home"
mkdir -p "$HOME_DIR/github/dotfiles/.git" "$HOME_DIR/github/firstmate/.git" \
  "$HOME_DIR/github/dotfiles/scripts/agent-tools" "$SANDBOX/tmp"
export TMPDIR="$SANDBOX/tmp"
cat > "$HOME_DIR/github/dotfiles/scripts/agent-tools/weekly.py" <<'PY'
import os
import sys
with open(os.environ['TEST_TRACE'], 'a') as log:
    log.write('weekly ' + sys.argv[1] + '\n')
if '--recover' in sys.argv and os.environ.get('TEST_RECOVERY_FAIL'):
    sys.exit(42)
if '--scheduled' in sys.argv and os.environ.get('TEST_BUMP_FAIL'):
    sys.exit(42)
PY
# /Users/../<absolute sandbox> stays wholly inside temporary storage while
# exercising the real fixed /Users/<account>/github layout without changing it.
USER_ARG="../${HOME_DIR#/}"
sudo() {
  [ "$1" = -u ] || return 99
  shift 2
  [ "$1" = -H ] || return 99
  shift
  "$@"
}
id() { case "$1" in -u) echo 501 ;; -g) echo 20 ;; *) return 99 ;; esac; }
launchctl() { printf 'notification-or-mas %s\n' "$*" >> "$TEST_TRACE"; }
git() {
  [ "$1" = -C ] || return 99
  shift 2
  case "$1" in
    pull) echo 'git pull' >> "$TEST_TRACE" ;;
    rev-parse) echo fixture ;;
    *) return 99 ;;
  esac
}
darwin-rebuild() {
  echo 'system rebuild' >> "$TEST_TRACE"
  printf '%s\n' "${TEST_REBUILD_OUTPUT:-}"
  [ -z "${TEST_REBUILD_FAIL:-}" ]
}
export -f sudo id launchctl git darwin-rebuild
assert_absent() {
  if grep -q "$1" "$TEST_TRACE"; then
    echo "FAIL: unexpected call matching $1" >&2; exit 1
  fi
}

: > "$TEST_TRACE"
/bin/bash "$ROOT/scripts/auto-rebuild.sh" "$USER_ARG" camilo-remote > "$SANDBOX/output" 2>&1
python3 - "$TEST_TRACE" <<'PY'
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text().splitlines()
assert lines.index('weekly --recover') < lines.index('git pull') < lines.index('system rebuild') < lines.index('weekly --scheduled'), lines
PY

: > "$TEST_TRACE"
/bin/bash "$ROOT/scripts/auto-rebuild.sh" "$USER_ARG" camilo-total > "$SANDBOX/output" 2>&1
assert_absent 'weekly --scheduled'
grep -q 'system rebuild' "$TEST_TRACE"

: > "$TEST_TRACE"
if TEST_RECOVERY_FAIL=1 /bin/bash "$ROOT/scripts/auto-rebuild.sh" "$USER_ARG" camilo-remote > "$SANDBOX/output" 2>&1; then
  echo 'FAIL: recovery failure must stop the daily entrypoint' >&2; exit 1
fi
assert_absent 'git pull\|system rebuild\|weekly --scheduled'
grep -q 'notification-or-mas' "$TEST_TRACE"

: > "$TEST_TRACE"
if TEST_BUMP_FAIL=1 /bin/bash "$ROOT/scripts/auto-rebuild.sh" "$USER_ARG" camilo-remote-total > "$SANDBOX/output" 2>&1; then
  echo 'FAIL: weekly failure must be reported' >&2; exit 1
fi
grep -q 'weekly --scheduled' "$TEST_TRACE"
grep -q 'Weekly agent pins failed' "$TEST_TRACE"

: > "$TEST_TRACE"
if TEST_REBUILD_FAIL=1 /bin/bash "$ROOT/scripts/auto-rebuild.sh" "$USER_ARG" camilo-remote > "$SANDBOX/output" 2>&1; then
  echo 'FAIL: system failure must stop before promotion' >&2; exit 1
fi
assert_absent 'weekly --scheduled'
# Homebrew's activation is deliberately nonfatal. Pin failures must not be
# hidden by a successful switch: the existing daily log and notification own it.
for failure in 'Pinning google-chrome has failed!' 'Upgrading wezterm has failed!'; do
  : > "$TEST_TRACE"
  TEST_REBUILD_OUTPUT="$failure" /bin/bash "$ROOT/scripts/auto-rebuild.sh" "$USER_ARG" camilo-total > "$SANDBOX/output" 2>&1
  package=${failure#* }
  package=${package%% *}
  grep -q "homebrew: could not install, upgrade or pin: $package" "$SANDBOX/output"
  grep -q "Homebrew failures: $package" "$TEST_TRACE"
done
echo 'PASS: recovery precedes pull, mini-only promotion follows rebuild, and all lane/pin failures notify safely'
