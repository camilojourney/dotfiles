#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/scripts/safe-maintenance.sh"
FAILURES=0
pass(){ echo "PASS: $1"; }
fail(){ echo "FAIL: $1" >&2; FAILURES=$((FAILURES+1)); }
run(){ env -i HOME="$1" SAFE_MAINTENANCE_TEST_MODE=1 PATH="/usr/bin:/bin" "$SCRIPT" "${@:2}"; }
base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT
mkdir -p "$base/Users/mini" "$base/Users/camiloslaptop" "$base/outside" "$base/Users/mini/project"
printf keep > "$base/Users/mini/project/file"

out=$(run "$base/Users/mini" --profile camilo-remote --action cleanup)
[[ "$out" == *"no files changed"* && "$out" == *"Pythia, Trader, Pilaster"* ]] && pass preview || fail preview
[[ -f "$base/Users/mini/project/file" ]] && pass "preview did not mutate" || fail "preview mutated"

if run "$base/Users/mini" --profile camilo-remote --apply >/dev/null 2>&1; then fail "apply refused"; else pass "apply refused"; fi
if run "$base/Users/mini" --profile camilo --action setup >/dev/null 2>&1; then fail "wrong machine accepted"; else pass "wrong machine refused"; fi
ln -s "$base/outside" "$base/Users/mini/escape"
if run "$base/Users/mini" --profile camilo-remote --action cleanup --path "$base/Users/mini/escape" >/dev/null 2>&1; then fail "symlink accepted"; else pass "symlink refused"; fi
if run "$base/Users/mini" --profile camilo-remote --action cleanup --path "$base/Users/mini/project/missing" >/dev/null 2>&1; then fail "ambiguous accepted"; else pass "ambiguous path refused"; fi

if [ "$FAILURES" -gt 0 ]; then exit 1; fi
echo "All safe maintenance tests passed."
