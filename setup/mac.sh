#!/bin/bash

set -euo pipefail

DOTFILES_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && cd .. && pwd )

# Fail early if placeholder values have not been customized yet
if grep -R -n -E 'yourname|/Users/yourname|Your Name|you@example.com' \
  "$DOTFILES_DIR/flake.nix" \
  "$DOTFILES_DIR/nix" >/dev/null 2>&1; then
  echo "Placeholder values are still present in the repo."
  echo "Please replace values like 'yourname', '/Users/yourname', 'Your Name', and 'you@example.com' before running setup/mac.sh."
  exit 1
fi

# These paths are overridable so tests never inspect the host installation.
: "${NIX_DAEMON_PROFILE:=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh}"
: "${NIX_LAUNCH_DAEMONS_DIR:=/Library/LaunchDaemons}"

nix_recovery_required() {
  printf 'setup/mac.sh: %s\n' "$1" >&2
  printf 'See %s/docs/RECOVERY.md before retrying setup.\n' "$DOTFILES_DIR" >&2
  exit 1
}

load_nix_profile() {
  if [ -r "$NIX_DAEMON_PROFILE" ]; then
    # A shell started while /nix was unavailable can inherit this stale guard.
    # The installed profile also needs nounset disabled while it is sourced.
    unset __ETC_PROFILE_NIX_SOURCED
    set +u
    # shellcheck disable=SC1090
    . "$NIX_DAEMON_PROFILE"
    set -u
  fi
}

if ! command -v nix &> /dev/null; then
  load_nix_profile
fi

# A missing PATH entry or unmounted store does not mean Nix is uninstalled.
if ! command -v nix &> /dev/null; then
  for marker in \
    "$NIX_DAEMON_PROFILE" \
    "$NIX_LAUNCH_DAEMONS_DIR/systems.determinate.nix-store.plist" \
    "$NIX_LAUNCH_DAEMONS_DIR/systems.determinate.nix-daemon.plist" \
    "$NIX_LAUNCH_DAEMONS_DIR/org.nixos.darwin-store.plist" \
    "$NIX_LAUNCH_DAEMONS_DIR/org.nixos.nix-daemon.plist"; do
    if [ -e "$marker" ] || [ -L "$marker" ]; then
      nix_recovery_required "An existing Nix installation is unavailable ($marker); refusing to reinstall it."
    fi
  done

  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
  load_nix_profile
fi

if ! NIX_BIN=$(command -v nix); then
  nix_recovery_required "Nix is still unavailable after installation."
fi

# A working client binary does not establish that the daemon is available.
# Check its exit status: even a failed connection can print partial output.
if ! NIX_STORE_STATUS=$("$NIX_BIN" --extra-experimental-features nix-command store info --store daemon 2>&1); then
  printf '%s\n' "$NIX_STORE_STATUS" >&2
  nix_recovery_required "The Nix daemon is unavailable; check /nix and Determinate background permissions."
fi

# Install Homebrew if missing
if ! command -v brew &> /dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Apply the Nix configuration. (DARWIN_REBUILD_BIN is overridable so tests
# can point at a sandboxed binary instead of the real one.)
# DARWIN_FLAKE_ATTR selects which darwinConfigurations.* to build
# (default: camilo; use camilo-remote on the remote Mac).
: "${DARWIN_REBUILD_BIN:=/run/current-system/sw/bin/darwin-rebuild}"
: "${DARWIN_FLAKE_ATTR:=camilo}"
if [ -x "$DARWIN_REBUILD_BIN" ]; then
  sudo "$DARWIN_REBUILD_BIN" switch --flake "$DOTFILES_DIR#$DARWIN_FLAKE_ATTR"
else
  # First activation: nix-darwin has never run, so darwin-rebuild doesn't
  # exist yet and has to be fetched via `nix run`. Resolve nix by absolute
  # path since sudo won't inherit the PATH this script just sourced, and
  # enable the experimental features it needs in case nix.conf doesn't
  # already have them.
  sudo "$NIX_BIN" --extra-experimental-features "nix-command flakes" \
    run nix-darwin/master#darwin-rebuild -- switch --flake "$DOTFILES_DIR#$DARWIN_FLAKE_ATTR"
fi

# Install nvm and a default Node.js if missing
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
  PROFILE=/dev/null bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install --lts
fi

echo "Bootstrap complete. Restart your shell if needed, then use 'rebuild' or darwin-rebuild for future config changes."
