#!/usr/bin/env bash
# Regression test for declarative Pi package configuration.
# Run: bash tests/pi_settings_test.sh

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
SETTINGS="$REPO_ROOT/files/.pi/agent/settings.json"
CURSOR_PROVIDER="git:github.com/camilojourney/pi-cursor-provider@73fd2d75c58bfe1757a124e407fbc72f89642826"

jq -e --arg cursor_provider "$CURSOR_PROVIDER" '
  .packages as $packages
  | ($packages | map(select(test("cursor"; "i"))) == [$cursor_provider])
  and ($packages | index("npm:pi-cursor-sdk") | not)
' "$SETTINGS" >/dev/null

echo "PASS: declarative Pi packages contain only the pinned Cursor provider"
