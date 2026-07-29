#!/bin/bash
#
# Sandboxed regression test for scripts/cursor-launchers.
#
# Run: bash tests/cursor_launcher_test.sh

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/cursor-launcher-test.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT

FAKE_BIN="$SANDBOX/bin"
FAKE_HOME="$SANDBOX/home"
SCRIPT_COPY="$SANDBOX/cursor-launchers"
DESTINATION="$SANDBOX/apps"
mkdir -p "$FAKE_BIN" "$FAKE_HOME" "$DESTINATION"
cp -R "$REPO_ROOT/scripts/cursor-launchers" "$SCRIPT_COPY"

cat > "$SANDBOX/cursor-stub" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
: "${CURSOR_ARGV_OUT:?}"
{
  printf '%s\0' "$0"
  for arg in "$@"; do
    printf '%s\0' "$arg"
  done
} > "$CURSOR_ARGV_OUT"
STUB
chmod +x "$SANDBOX/cursor-stub"

CURSOR_ARGV_OUT="$SANDBOX/cursor.argv" \
CURSOR_BIN="$SANDBOX/cursor-stub" \
CURSOR_LAUNCHER_LOCAL_GITHUB="$SANDBOX/github" \
HOME="$FAKE_HOME" \
  "$REPO_ROOT/scripts/cursor-launchers/cursor-go" job-tracker

python3 - "$SANDBOX/cursor.argv" "$SANDBOX/cursor-stub" "$SANDBOX/github/job-tracker" <<'PY'
import sys
from pathlib import Path

argv = Path(sys.argv[1]).read_bytes().split(b"\0")
if argv and argv[-1] == b"":
    argv.pop()
actual = [arg.decode("utf-8", "surrogateescape") for arg in argv]
expected = [sys.argv[2], "--classic", "--new-window", sys.argv[3]]
if actual != expected:
    print(f"FAIL: job-tracker argv mismatch: {actual!r}", file=sys.stderr)
    sys.exit(1)
PY
echo "PASS: job-tracker launcher uses exact Cursor argv"

while IFS=$'\t' read -r name target || [[ -n "$name" ]]; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  "$SCRIPT_COPY/cursor-go" --validate-target "$target"
done < "$SCRIPT_COPY/launchers.tsv"
echo "PASS: production launcher manifest uses supported cursor-go targets"

printf '# Display name<TAB>cursor-go target\nInvoz\tinvoz\nVault\tvault' > "$SCRIPT_COPY/launchers.tsv"

cat > "$FAKE_BIN/osacompile" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
out=""
source=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -e)
      source="$2"
      shift 2
      ;;
    *)
      echo "unexpected osacompile argument: $1" >&2
      exit 1
      ;;
  esac
done
[ -n "$out" ] || { echo "missing osacompile output" >&2; exit 1; }
mkdir -p "$out/Contents/Resources/Scripts"
bundle_name=$(basename "$out" .app)
printf '%s\n' "$bundle_name" > "$out/Contents/Info.plist"
printf '%s\n' "$source" > "$out/Contents/Resources/Scripts/main.scpt"
STUB

cat > "$FAKE_BIN/plistbuddy" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = "-c" ] && [ "$2" = "Print :CFBundleName" ] || {
  echo "unexpected PlistBuddy invocation" >&2
  exit 1
}
cat "$3"
STUB

cat > "$FAKE_BIN/osadecompile" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
cat "$1"
STUB

cat > "$FAKE_BIN/codesign" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = "--verify" ] && [ "$2" = "--deep" ] && [ "$3" = "--strict" ] && [ -d "$4" ]
STUB

chmod +x "$FAKE_BIN/osacompile" "$FAKE_BIN/plistbuddy" "$FAKE_BIN/osadecompile" "$FAKE_BIN/codesign"

PATH="$FAKE_BIN:$PATH" \
OSACOMPILE_BIN="$FAKE_BIN/osacompile" \
  "$SCRIPT_COPY/make-launchers.sh" "$DESTINATION" >/dev/null

[ -d "$DESTINATION/Cursor Invoz.app" ] || { echo "FAIL: missing generated Invoz launcher" >&2; exit 1; }
[ -d "$DESTINATION/Cursor Vault.app" ] || { echo "FAIL: final no-newline launcher was not generated" >&2; exit 1; }

PATH="$FAKE_BIN:$PATH" \
PLISTBUDDY_BIN="$FAKE_BIN/plistbuddy" \
OSADECOMPILE_BIN="$FAKE_BIN/osadecompile" \
CODESIGN_BIN="$FAKE_BIN/codesign" \
  "$SCRIPT_COPY/verify-launchers.sh" "$DESTINATION" >/dev/null

echo "PASS: launcher generation and verification process final manifest line without newline"

printf '# Display name<TAB>cursor-go target\nUnsupported\tunsupported' > "$SCRIPT_COPY/launchers.tsv"

set +e
unsupported_make_output=$(
  PATH="$FAKE_BIN:$PATH" \
  OSACOMPILE_BIN="$FAKE_BIN/osacompile" \
    "$SCRIPT_COPY/make-launchers.sh" "$DESTINATION" 2>&1
)
unsupported_make_status=$?
set -e

if [ "$unsupported_make_status" -eq 0 ]; then
  echo "FAIL: launcher generator accepted unsupported cursor-go target" >&2
  exit 1
fi
if ! grep -qF "Unsupported cursor-go target: unsupported" <<<"$unsupported_make_output"; then
  echo "FAIL: launcher generator did not identify unsupported target" >&2
  exit 1
fi
echo "PASS: launcher generator rejects unsupported cursor-go target"

rm -rf "${DESTINATION:?}"/*
mkdir -p "$DESTINATION/Cursor Unsupported.app/Contents/Resources/Scripts"
printf '%s\n' "Cursor Unsupported" > "$DESTINATION/Cursor Unsupported.app/Contents/Info.plist"
printf '%s\n' 'quoted form of "unsupported"' > "$DESTINATION/Cursor Unsupported.app/Contents/Resources/Scripts/main.scpt"

set +e
unsupported_verify_output=$(
  PATH="$FAKE_BIN:$PATH" \
  PLISTBUDDY_BIN="$FAKE_BIN/plistbuddy" \
  OSADECOMPILE_BIN="$FAKE_BIN/osadecompile" \
  CODESIGN_BIN="$FAKE_BIN/codesign" \
    "$SCRIPT_COPY/verify-launchers.sh" "$DESTINATION" 2>&1
)
unsupported_verify_status=$?
set -e

if [ "$unsupported_verify_status" -eq 0 ]; then
  echo "FAIL: launcher verifier accepted unsupported cursor-go target" >&2
  exit 1
fi
if ! grep -qF "Unsupported cursor-go target: unsupported" <<<"$unsupported_verify_output"; then
  echo "FAIL: launcher verifier did not identify unsupported target" >&2
  exit 1
fi
echo "PASS: launcher verifier rejects unsupported cursor-go target"

echo "ALL CURSOR LAUNCHER TESTS COMPLETED SUCCESSFULLY."
