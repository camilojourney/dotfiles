#!/bin/bash
# All activation commands are stubs; no network or host changes.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
SANDBOX=$(mktemp -d)
SANDBOX=$(cd "$SANDBOX" && pwd -P)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin" "$SANDBOX/home"
cp "$ROOT/rebuild.sh" "$SANDBOX/"
for tool in dirname basename; do
  ln -s "$(command -v "$tool")" "$SANDBOX/bin/$tool"
done
cat > "$SANDBOX/bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$STUB_LOG"
EOF
chmod +x "$SANDBOX/bin/sudo"
cat > "$SANDBOX/bin/open" <<'EOF'
#!/bin/bash
printf 'open %s\n' "$*" > "$STUB_OPEN_LOG"
EOF
chmod +x "$SANDBOX/bin/open"

run_helper() {
  env -u BASH_ENV -u ENV HOME="$SANDBOX/home" PATH="$SANDBOX/bin" \
    STUB_LOG="$SANDBOX/log" STUB_OPEN_LOG="$SANDBOX/open-log" \
    DARWIN_REBUILD_BIN="$SANDBOX/darwin-rebuild" \
    REBUILD_ACCOUNT="$ACCOUNT" "$@" \
    /bin/bash "$SANDBOX/rebuild.sh"
}

# One script, both accounts: rebuild.sh must pick the right flake attr from
# REBUILD_ACCOUNT alone, with no per-host script or flag.
for ACCOUNT in camiloslaptop camilo_mini; do
PROFILE=camilo
[ "$ACCOUNT" != camilo_mini ] || PROFILE=camilo-remote
rm -f "$SANDBOX/darwin-rebuild"

# A missing binary may mean /nix is unavailable: point to recovery as well as
# fresh-machine setup without trying to install or activate anything.
status=0
out=$(run_helper 2>&1) || status=$?
test "$status" -eq 1
printf '%s\n' "$out" | grep -qF "docs/RECOVERY.md"
printf '%s\n' "$out" | grep -qF "setup/mac.sh"
[ ! -f "$SANDBOX/log" ]

# Installed nix-darwin uses the normal activation path.
cp "$SANDBOX/bin/sudo" "$SANDBOX/darwin-rebuild"
rm -f "$SANDBOX/open-log"
run_helper
printf '%s\n' "$SANDBOX/darwin-rebuild" switch --flake \
  "$SANDBOX#$PROFILE" > "$SANDBOX/expected"
diff -u "$SANDBOX/expected" "$SANDBOX/log"
rm -f "$SANDBOX/log"

# Baby Menu is brought forward on the laptop only, after activation succeeds.
if [ "$ACCOUNT" = camiloslaptop ]; then
  [ "$(cat "$SANDBOX/open-log")" = "open -a Baby Menu" ] || { echo "FAIL: Baby Menu was not opened on the laptop" >&2; exit 1; }
else
  [ ! -f "$SANDBOX/open-log" ] || { echo "FAIL: Baby Menu was opened on the remote account" >&2; exit 1; }
fi

echo "PASS: rebuild.sh ($ACCOUNT -> $PROFILE) requires bootstrap first, then activates"
done

# An unrecognized account must fail loudly instead of silently picking a host.
ACCOUNT=someone-else
status=0
run_helper || status=$?
test "$status" -eq 1
echo "PASS: rebuild.sh rejects an unrecognized account"
