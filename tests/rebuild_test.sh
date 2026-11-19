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
echo rebuild >> "${STUB_ORDER:-/dev/null}"
if [ "${STUB_SIGNAL_PHASE:-}" = rebuild ]; then
  kill "-${STUB_SIGNAL:-TERM}" "$PPID"
fi
if [ "${STUB_REBUILD_FAIL_FIRST:-0}" = 1 ] && [ ! -f "$STUB_LOG.failed-once" ]; then
  : > "$STUB_LOG.failed-once"
  exit 1
fi
EOF
chmod +x "$SANDBOX/bin/sudo"
cat > "$SANDBOX/bin/open" <<'EOF'
#!/bin/bash
printf 'open %s\n' "$*" > "$STUB_OPEN_LOG"
if [ "${STUB_SIGNAL_PHASE:-}" = open ]; then
  kill "-${STUB_SIGNAL:-TERM}" "$PPID"
fi
EOF
chmod +x "$SANDBOX/bin/open"

run_helper() {
  env -u BASH_ENV -u ENV HOME="$SANDBOX/home" PATH="$SANDBOX/bin" \
    STUB_LOG="$SANDBOX/log" STUB_OPEN_LOG="$SANDBOX/open-log" \
    DARWIN_REBUILD_BIN="$SANDBOX/darwin-rebuild" \
    REBUILD_ACCOUNT="$ACCOUNT" \
    /bin/bash "$SANDBOX/rebuild.sh" --no-update-tools
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

# Tool updates run by default and are manual (never scheduled). The real selection
# and installed-version check are covered by agent_update_now_test.py; here python3
# is a stub, so only the ordering and the rollback guarantees of rebuild.sh are checked.
cp "$ROOT/rebuild-total.sh" "$SANDBOX/"
mkdir -p "$SANDBOX/nix" "$SANDBOX/scripts/agent-tools" "$SANDBOX/tmp"
REAL_MKTEMP=$(command -v mktemp)
cat > "$SANDBOX/bin/mktemp" <<EOF
#!/bin/bash
exec "$REAL_MKTEMP" "$SANDBOX/tmp/pins.XXXXXX"
EOF
chmod +x "$SANDBOX/bin/mktemp"
for tool in bash cp rm cmp cat; do
  ln -sf "$(command -v "$tool")" "$SANDBOX/bin/$tool"
done
: > "$SANDBOX/scripts/agent-tools/update-now.py"
: > "$SANDBOX/scripts/agent-tools/smoke.py"
cat > "$SANDBOX/bin/python3" <<'EOF'
#!/bin/bash
case "$1" in
  */update-now.py)
    if [ "$#" -eq 2 ] && [ "$2" = --verify ]; then
      phase=verify
      echo verify >> "$STUB_ORDER"
      [ "${STUB_VERIFY_FAIL:-0}" != 1 ] || exit 1
    elif [ "$#" -eq 1 ]; then
      phase=update
      echo update >> "$STUB_ORDER"
      [ "${STUB_UPDATE_FAIL:-0}" != 1 ] || exit 1
      echo UPDATED >> "$STUB_MANIFEST"
    else
      exit 2
    fi ;;
  */smoke.py)
    phase=smoke
    echo smoke >> "$STUB_ORDER"
    [ "${STUB_SMOKE_FAIL:-0}" != 1 ] || exit 1 ;;
esac
if [ "${STUB_SIGNAL_PHASE:-}" = "$phase" ]; then
  kill "-${STUB_SIGNAL:-TERM}" "$PPID"
fi
EOF
chmod +x "$SANDBOX/bin/python3"
printf 'original manifest\n' > "$SANDBOX/manifest.orig"

run_update_case() { # run_update_case SCRIPT [ENV=VAL ...] -- ARGS...
  local script=$1; shift
  local envs=()
  while [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  cp "$SANDBOX/manifest.orig" "$SANDBOX/nix/agent-tools.manifest.lock.json"
  rm -f "$SANDBOX/order" "$SANDBOX/log" "$SANDBOX/log.failed-once"
  CASE_STATUS=0
  env -u BASH_ENV -u ENV HOME="$SANDBOX/home" PATH="$SANDBOX/bin" \
    STUB_LOG="$SANDBOX/log" STUB_OPEN_LOG="$SANDBOX/open-log" STUB_ORDER="$SANDBOX/order" \
    STUB_MANIFEST="$SANDBOX/nix/agent-tools.manifest.lock.json" \
    DARWIN_REBUILD_BIN="$SANDBOX/darwin-rebuild" REBUILD_ACCOUNT=camiloslaptop \
    ${envs[@]+"${envs[@]}"} /bin/bash "$SANDBOX/$script" "$@" >"$SANDBOX/case-out" 2>&1 || CASE_STATUS=$?
  if compgen -G "$SANDBOX/tmp/*" >/dev/null; then
    echo "FAIL: temporary pin backup was not cleaned up" >&2
    exit 1
  fi
}
manifest_is_original() { cmp -s "$SANDBOX/manifest.orig" "$SANDBOX/nix/agent-tools.manifest.lock.json"; }
order() { if [ -f "$SANDBOX/order" ]; then tr '\n' ' ' < "$SANDBOX/order"; fi; }
expect_order() { [ "$(order)" = "$1" ] || { echo "FAIL: expected '$1' but ran '$(order)'" >&2; cat "$SANDBOX/case-out" >&2; exit 1; }; }

# A plain run updates by default: gated update, rebuild installs it, installed versions
# are verified against the pins, then the smoke check; the update stays.
run_update_case rebuild.sh --
test "$CASE_STATUS" -eq 0
expect_order "update rebuild verify smoke "
manifest_is_original && { echo "FAIL: verified pins were not kept" >&2; exit 1; }
echo "PASS: rebuild.sh updates the tools by default, verifies and smoke-checks them"

# --no-update-tools is the explicit opt-out: nothing about the tools runs.
run_update_case rebuild.sh -- --no-update-tools
test "$CASE_STATUS" -eq 0
expect_order "rebuild "
manifest_is_original
echo "PASS: --no-update-tools skips every tool step"

# rebuild-total.sh forwards its arguments and still targets the -total flake.
run_update_case rebuild-total.sh --
test "$CASE_STATUS" -eq 0
expect_order "update rebuild verify smoke "
grep -qxF "$SANDBOX#camilo-total" "$SANDBOX/log"
run_update_case rebuild-total.sh -- --no-update-tools
expect_order "rebuild "
echo "PASS: rebuild-total.sh updates by default and forwards --no-update-tools"

# An unreachable registry must not block the rebuild: warn, keep the current pins, go on.
run_update_case rebuild.sh STUB_UPDATE_FAIL=1 --
test "$CASE_STATUS" -eq 0
expect_order "update rebuild "
manifest_is_original
grep -qi "continuing with the current pins" "$SANDBOX/case-out"
echo "PASS: a failed update check warns and rebuilds with the current pins"

# A failed rebuild restores the previous pins file and runs no further tool step.
run_update_case rebuild.sh STUB_REBUILD_FAIL_FIRST=1 --
test "$CASE_STATUS" -ne 0
expect_order "update rebuild "
manifest_is_original
echo "PASS: a failed rebuild restores the previous pins"

# A rebuild that did not install the new versions (for example activation stopped early)
# restores the pins instead of claiming an update; it does not rebuild again.
run_update_case rebuild.sh STUB_VERIFY_FAIL=1 --
test "$CASE_STATUS" -ne 0
expect_order "update rebuild verify "
manifest_is_original
grep -qi "did not install" "$SANDBOX/case-out"
echo "PASS: installed versions that miss the pins restore the previous pins"

# A failed smoke check restores the previous pins and rebuilds again to reinstall them.
run_update_case rebuild.sh STUB_SMOKE_FAIL=1 --
test "$CASE_STATUS" -ne 0
expect_order "update rebuild verify smoke rebuild "
manifest_is_original
echo "PASS: a failed smoke check rolls the pins back and reinstalls them"

for signal in INT TERM; do
  expected_status=130
  [ "$signal" != TERM ] || expected_status=143
  for phase in update rebuild verify smoke; do
    run_update_case rebuild.sh "STUB_SIGNAL=$signal" "STUB_SIGNAL_PHASE=$phase" --
    test "$CASE_STATUS" -eq "$expected_status"
    manifest_is_original
    case "$phase" in
      update) expect_order "update " ;;
      rebuild) expect_order "update rebuild " ;;
      verify) expect_order "update rebuild verify " ;;
      smoke) expect_order "update rebuild verify smoke " ;;
    esac
  done
  run_update_case rebuild.sh "STUB_SIGNAL=$signal" STUB_SIGNAL_PHASE=open --
  test "$CASE_STATUS" -eq "$expected_status"
  expect_order "update rebuild verify smoke "
  manifest_is_original && { echo "FAIL: verified pins were not kept" >&2; exit 1; }
  echo "PASS: $signal restores pending pins and keeps successfully verified pins"
done

# A mistyped option must fail loudly instead of silently doing a plain rebuild.
run_update_case rebuild.sh -- --update-tool
test "$CASE_STATUS" -eq 2
[ -z "$(order)" ] || { echo "FAIL: ran something for an unknown option" >&2; exit 1; }
grep -qF -- "--no-update-tools" "$SANDBOX/case-out"
echo "PASS: rebuild.sh rejects an unknown option"
