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

run_helper() {
  env -u BASH_ENV -u ENV HOME="$SANDBOX/home" PATH="$SANDBOX/bin" \
    STUB_LOG="$SANDBOX/log" DARWIN_REBUILD_BIN="$SANDBOX/darwin-rebuild" \
    REBUILD_ACCOUNT="$ACCOUNT" "$@" \
    /bin/bash "$SANDBOX/rebuild.sh"
}

# One script, both accounts: rebuild.sh must pick the right flake attr from
# REBUILD_ACCOUNT alone, with no per-host script or flag.
for ACCOUNT in camiloslaptop camilo_mini; do
PROFILE=camilo
[ "$ACCOUNT" != camilo_mini ] || PROFILE=camilo-remote
rm -f "$SANDBOX/darwin-rebuild"

# Not yet bootstrapped: fail loudly and point at setup/mac.sh instead of
# trying to install Nix itself.
status=0
run_helper || status=$?
test "$status" -eq 1
[ ! -f "$SANDBOX/log" ]

# Installed nix-darwin uses the normal activation path.
cp "$SANDBOX/bin/sudo" "$SANDBOX/darwin-rebuild"
run_helper
printf '%s\n' "$SANDBOX/darwin-rebuild" switch --flake \
  "$SANDBOX#$PROFILE" > "$SANDBOX/expected"
diff -u "$SANDBOX/expected" "$SANDBOX/log"
rm -f "$SANDBOX/log"

echo "PASS: rebuild.sh ($ACCOUNT -> $PROFILE) requires bootstrap first, then activates"
done

# An unrecognized account must fail loudly instead of silently picking a host.
ACCOUNT=someone-else
status=0
run_helper || status=$?
test "$status" -eq 1
echo "PASS: rebuild.sh rejects an unrecognized account"
