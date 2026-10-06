#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

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
sudo "$DARWIN_REBUILD_BIN" switch --flake "$DIR#$FLAKE_ATTR"

# Laptop only: bring Baby Menu to the menu bar right away, so a rebuild that
# changed its widgets is visible now instead of at the next login.
if [ "$REBUILD_ACCOUNT" = camiloslaptop ]; then
  open -a "Baby Menu" || true
fi
