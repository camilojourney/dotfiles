#!/bin/bash
# All activation commands are stubs; no network or host changes.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
SANDBOX=$(mktemp -d)
SANDBOX=$(cd "$SANDBOX" && pwd -P)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin" "$SANDBOX/nix/bin" "$SANDBOX/home" "$SANDBOX/setup"
cp "$ROOT/rebuild-remote.sh" "$ROOT/rebuild.sh" "$SANDBOX/"
cat > "$SANDBOX/setup/mac.sh" <<'EOF'
#!/bin/bash
printf 'setup %s\n' "$DARWIN_FLAKE_ATTR" > "$STUB_LOG"
exit "${SETUP_EXIT:-0}"
EOF
for tool in dirname basename; do
  ln -s "$(command -v "$tool")" "$SANDBOX/bin/$tool"
done
cat > "$SANDBOX/bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$STUB_LOG"
EOF
chmod +x "$SANDBOX/bin/sudo"
printf '#!/bin/bash\nexit 99\n' > "$SANDBOX/nix/bin/nix"
chmod +x "$SANDBOX/nix/bin/nix"
printf 'export PATH="%s/nix/bin:$PATH"\n' "$SANDBOX" > "$SANDBOX/profile"

run_helper() {
  env -u BASH_ENV -u ENV HOME="$SANDBOX/home" PATH="$SANDBOX/bin" \
    STUB_LOG="$SANDBOX/log" DARWIN_REBUILD_BIN="$SANDBOX/darwin-rebuild" \
    NIX_DAEMON_PROFILE="$SANDBOX/profile" "$@" \
    /bin/bash "$SANDBOX/$HELPER"
}

for HELPER in rebuild.sh rebuild-remote.sh; do
PROFILE=camilo
[ "$HELPER" != rebuild-remote.sh ] || PROFILE=camilo-remote
rm -f "$SANDBOX/darwin-rebuild"

# A shell without Nix on PATH must source the profile and use absolute nix.
run_helper
printf '%s\n' "$SANDBOX/nix/bin/nix" --extra-experimental-features \
  'nix-command flakes' run 'nix-darwin/master#darwin-rebuild' -- switch \
  --flake "$SANDBOX#$PROFILE" > "$SANDBOX/expected"
diff -u "$SANDBOX/expected" "$SANDBOX/log"

# Already available Nix must not require a profile.
run_helper PATH="$SANDBOX/bin:$SANDBOX/nix/bin" NIX_DAEMON_PROFILE="$SANDBOX/missing"
diff -u "$SANDBOX/expected" "$SANDBOX/log"

# Fresh machines bootstrap the helper's profile, overriding inherited choices.
run_helper NIX_DAEMON_PROFILE="$SANDBOX/missing" DARWIN_FLAKE_ATTR=wrong
printf 'setup %s\n' "$PROFILE" > "$SANDBOX/expected"
diff -u "$SANDBOX/expected" "$SANDBOX/log"

# Setup failure must propagate without a second activation attempt.
status=0
run_helper NIX_DAEMON_PROFILE="$SANDBOX/missing" SETUP_EXIT=42 || status=$?
test "$status" -eq 42
diff -u "$SANDBOX/expected" "$SANDBOX/log"

# Installed nix-darwin must use the fast path even without Nix on PATH.
cp "$SANDBOX/nix/bin/nix" "$SANDBOX/darwin-rebuild"
run_helper NIX_DAEMON_PROFILE="$SANDBOX/missing"
printf '%s\n' "$SANDBOX/darwin-rebuild" switch --flake \
  "$SANDBOX#$PROFILE" > "$SANDBOX/expected"
diff -u "$SANDBOX/expected" "$SANDBOX/log"
echo "PASS: $HELPER first activation, installed fast path, and bootstrap delegation"
done
