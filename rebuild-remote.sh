#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
: "${DARWIN_REBUILD_BIN:=/run/current-system/sw/bin/darwin-rebuild}"
if [ -x "$DARWIN_REBUILD_BIN" ]; then
  # Absolute path: sudo does not inherit interactive PATH.
  exec sudo "$DARWIN_REBUILD_BIN" switch --flake "$DIR#camilo-remote"
fi

# Nix may be installed without being available in this shell yet.
if ! command -v nix >/dev/null 2>&1; then
  : "${NIX_DAEMON_PROFILE:=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh}"
  if [ -f "$NIX_DAEMON_PROFILE" ]; then
    set +u
    # shellcheck disable=SC1090
    . "$NIX_DAEMON_PROFILE"
    set -u
  fi
fi

NIX_BIN=$(command -v nix || true)
if [ -z "$NIX_BIN" ]; then
  # Fresh Macs have no Nix yet. Previously this stopped with instructions to
  # run setup manually, making repeated rebuild attempts fail the same way.
  # Delegate to setup so one command installs prerequisites and activates the
  # correct host; exec avoids activating a second time after setup succeeds.
  printf 'Nix is unavailable; running first-time setup for camilo-remote.\n' >&2
  export DARWIN_FLAKE_ATTR=camilo-remote
  exec /bin/bash "$DIR/setup/mac.sh"
fi
# Resolve even a relative PATH entry before passing the executable to sudo.
NIX_BIN="$(cd "$(dirname "$NIX_BIN")" && pwd -P)/$(basename "$NIX_BIN")"
exec sudo "$NIX_BIN" --extra-experimental-features "nix-command flakes" \
  run nix-darwin/master#darwin-rebuild -- switch --flake "$DIR#camilo-remote"
