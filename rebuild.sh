#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Agent CLI tools are updated as part of a manual rebuild: the same age-gated,
# OSV-checked selection as the weekly lane (scripts/agent-tools/update-now.py),
# then a check that the rebuild really installed the new versions. Never
# scheduled; --no-update-tools skips it. See docs/AUTO-UPDATE.md.
UPDATE_TOOLS=1
for arg in "$@"; do
  case "$arg" in
    --no-update-tools) UPDATE_TOOLS=0 ;;
    *)
      printf 'rebuild.sh: unknown option "%s". Usage: rebuild.sh [--no-update-tools]\n' "$arg" >&2
      exit 2
      ;;
  esac
done

# One script for both machines: pick the flake attr from the macOS account
# running it, so `./rebuild.sh` behaves correctly on either host with no
# flags. REBUILD_ACCOUNT is overridable so tests can simulate either account
# without depending on the real one running the test. REBUILD_SUFFIX lets
# rebuild-total.sh reuse this exact script to target the "-total" flake
# attrs (base config + nix/camilo-extra.nix) instead of duplicating it.
: "${REBUILD_ACCOUNT:=$(id -un)}"
: "${REBUILD_SUFFIX:=}"
case "$REBUILD_ACCOUNT" in
  camiloslaptop) FLAKE_ATTR="camilo$REBUILD_SUFFIX" ;;
  camilo_mini) FLAKE_ATTR="camilo-remote$REBUILD_SUFFIX" ;;
  *)
    printf 'rebuild.sh: unrecognized account "%s" - add it to the case statement in this script.\n' "$REBUILD_ACCOUNT" >&2
    exit 1
    ;;
esac

# Absolute path: sudo does not inherit interactive PATH.
: "${DARWIN_REBUILD_BIN:=/run/current-system/sw/bin/darwin-rebuild}"
if [ ! -x "$DARWIN_REBUILD_BIN" ]; then
  printf 'rebuild.sh: darwin-rebuild not found at %s.\n' "$DARWIN_REBUILD_BIN" >&2
  printf 'If this machine was already set up, follow %s/docs/RECOVERY.md first; /nix may be unavailable.\n' "$DIR" >&2
  printf 'Use setup/mac.sh only to bootstrap a machine that has not been set up.\n' >&2
  exit 1
fi

PIN_FILE="$DIR/nix/agent-tools.manifest.lock.json"
PIN_BACKUP=""
PINS_PENDING=0
UPDATE_TOOL="$DIR/scripts/agent-tools/update-now.py"
cleanup_pins() {
  if [ -n "$PIN_BACKUP" ]; then
    if [ "$PINS_PENDING" = 1 ]; then
      cp "$PIN_BACKUP" "$PIN_FILE"
    fi
    rm -f "$PIN_BACKUP"
    PIN_BACKUP=""
  fi
}
trap cleanup_pins EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$UPDATE_TOOLS" = 1 ]; then
  # Keep the old bytes: a failed rebuild, install check or smoke check puts them back.
  PIN_BACKUP=$(mktemp)
  cp "$PIN_FILE" "$PIN_BACKUP"
  PINS_PENDING=1
  if ! python3 "$UPDATE_TOOL"; then
    # Offline or a registry/OSV error: the pins stay as they are, which is the safe
    # state, so the rebuild itself must not be blocked by it.
    cleanup_pins
    UPDATE_TOOLS=0
    printf 'rebuild.sh: the tool update check failed; continuing with the current pins.\n' >&2
  fi
fi

status=0
sudo "$DARWIN_REBUILD_BIN" switch --flake "$DIR#$FLAKE_ATTR" || status=$?
if [ "$status" -ne 0 ]; then
  if [ "$UPDATE_TOOLS" = 1 ]; then
    cleanup_pins
    printf 'rebuild.sh: the rebuild failed; the previous tool pins were restored.\n' >&2
  fi
  exit "$status"
fi

if [ "$UPDATE_TOOLS" = 1 ]; then
  # A rebuild can stop early (for example a config conflict) and still return, leaving
  # the old tools installed. Never keep pins that were not installed.
  if ! python3 "$UPDATE_TOOL" --verify; then
    cleanup_pins
    printf 'rebuild.sh: the rebuild did not install the pinned tool versions (see above); the previous pins were restored.\n' >&2
    exit 1
  fi
  if ! python3 "$DIR/scripts/agent-tools/smoke.py"; then
    cleanup_pins
    printf 'rebuild.sh: the smoke check failed after the update; restoring the previous pins and rebuilding again.\n' >&2
    sudo "$DARWIN_REBUILD_BIN" switch --flake "$DIR#$FLAKE_ATTR" ||
      printf 'rebuild.sh: the rollback rebuild also failed; run ./rebuild.sh --no-update-tools by hand.\n' >&2
    exit 1
  fi
  PINS_PENDING=0
  cleanup_pins
  printf 'rebuild.sh: tool pins checked, installed and smoke-tested. Review: git -C %s diff nix/agent-tools.manifest.lock.json\n' "$DIR"
fi

# Laptop only: bring Baby Menu to the menu bar right away, so a rebuild that
# changed its widgets is visible now instead of at the next login.
if [ "$REBUILD_ACCOUNT" = camiloslaptop ]; then
  open -a "Baby Menu" || true
fi
