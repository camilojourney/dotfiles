#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mas-cleanup-test.XXXXXX")
MAS_BIN="$ROOT/mas"
MAS_LOG="$ROOT/mas.log"

cleanup() {
  rm -rf "$ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

cat >"$MAS_BIN" <<EOF
#!/usr/bin/env bash
set -euo pipefail

case "\$1" in
  list)
    printf '%s\n' 'Xcode (497799835)' 'Example App (123456789)'
    ;;
  uninstall)
    printf '%s\n' "\$2" >>"$MAS_LOG"
    ;;
esac
EOF
chmod +x "$MAS_BIN"

bash "$REPO_ROOT/scripts/mas-cleanup.sh" "$MAS_BIN" "$(/usr/bin/id -un)" 497799835

[ -f "$MAS_LOG" ] || fail "undeclared App Store app was not uninstalled"
[ "$(cat "$MAS_LOG")" = "123456789" ] || fail "cleanup did not uninstall only the undeclared numeric ID"

echo "PASS: MAS cleanup uninstalls undeclared numeric IDs"
