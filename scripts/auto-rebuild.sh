#!/bin/bash
# Daily unattended update, run as root by the org.dotfiles.auto-rebuild
# launchd daemon (nix/configuration.nix) on both machines:
#   1. fast-forward ~/github/dotfiles and ~/github/firstmate (each skips,
#      never forces, when it cannot fast-forward cleanly)
#   2. the same rebuild as ./rebuild-total.sh (laptop) or ./rebuild.sh (remote)
# Usage: auto-rebuild.sh <macOS user> <flake attr>
# Output goes to /var/log/auto-rebuild.log; any failure posts a macOS
# notification to the logged-in user.
#
# The daemon runs this file by path instead of from the Nix store on purpose:
# a store path would change the daemon's plist whenever this script changes,
# and activation would then reload the daemon and kill the rebuild running it.
set -uo pipefail

USER_NAME=${1:?usage: auto-rebuild.sh <macOS user> <flake attr>}
FLAKE_ATTR=${2:?usage: auto-rebuild.sh <macOS user> <flake attr>}
USER_HOME=/Users/$USER_NAME
DOTFILES=$USER_HOME/github/dotfiles
FIRSTMATE=$USER_HOME/github/firstmate
export PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

as_user() { sudo -u "$USER_NAME" -H "$@"; }

notify() {
  local uid
  uid=$(id -u "$USER_NAME")
  launchctl asuser "$uid" sudo -u "$USER_NAME" osascript \
    -e "display notification \"$1\" with title \"Daily rebuild\"" >/dev/null 2>&1 || true
}

log "auto-rebuild: start ($FLAKE_ATTR)"

# A repo that cannot fast-forward (diverged, or local edits that conflict)
# is left untouched and the rebuild uses what is already checked out.
update_repo() {  # <name> <path>
  if [ ! -d "$2/.git" ]; then
    log "$1: not cloned on this machine; skipped"
  elif as_user git -C "$2" pull --ff-only --quiet origin main; then
    log "$1: up to date at $(as_user git -C "$2" rev-parse --short HEAD)"
  else
    log "$1: pull skipped (diverged or conflicting local edits); left untouched"
    notify "$1 pull skipped - see /var/log/auto-rebuild.log"
  fi
}

update_repo dotfiles "$DOTFILES"
update_repo firstmate "$FIRSTMATE"

if darwin-rebuild switch --flake "$DOTFILES#$FLAKE_ATTR"; then
  log "rebuild: ok"
else
  log "rebuild: FAILED"
  notify "Rebuild failed - see /var/log/auto-rebuild.log"
  exit 1
fi

log "auto-rebuild: done"
