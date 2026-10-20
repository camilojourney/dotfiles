#!/usr/bin/env bash
# Read-only storage report includes major agent and browser data roots.
# [utest->req~storage-audit.inventory~1]
# Run: bash tests/storage_report_test.sh
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
HOME="$TMP_ROOT/home"
mkdir -p \
  "$HOME/.firstmate-homes" \
  "$HOME/.treehouse" \
  "$HOME/.chrome-profiles" \
  "$HOME/Library/Application Support/Google/Chrome" \
  "$HOME/Library/Application Support/Google/Chrome Canary"
printf 'preserve\n' > "$HOME/.firstmate-homes/marker"

report=$(HOME="$HOME" bash "$REPO_ROOT/scripts/storage-report.sh")
for path in \
  "$HOME/.firstmate-homes" \
  "$HOME/.treehouse" \
  "$HOME/.chrome-profiles" \
  "$HOME/Library/Application Support/Google/Chrome" \
  "$HOME/Library/Application Support/Google/Chrome Canary"; do
  grep -F -- "$path" <<<"$report" >/dev/null || {
    printf 'FAIL: report omitted %s\n' "$path" >&2
    exit 1
  }
done
[[ $(<"$HOME/.firstmate-homes/marker") == preserve ]]
printf 'PASS: report measures the major agent/browser roots and leaves data untouched\n'
