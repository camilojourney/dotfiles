#!/bin/bash
# Daily unattended update for the laptop, run as root by the
# org.dotfiles.auto-rebuild launchd daemon (nix/camilo-extra.nix):
#   1. fast-forward ~/github/firstmate (skips, never forces, on conflict)
#   2. the same rebuild as ./rebuild-total.sh
# Output goes to /var/log/auto-rebuild.log; any failure posts a macOS
# notification to the logged-in user.
#
# The daemon runs this file by path instead of from the Nix store on purpose:
# a store path would change the daemon's plist whenever this script changes,
# and activation would then reload the daemon and kill the rebuild running it.
set -uo pipefail

USER_NAME=camiloslaptop
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

log "auto-rebuild: start"

if as_user git -C "$FIRSTMATE" pull --ff-only --quiet origin main; then
  log "firstmate: up to date at $(as_user git -C "$FIRSTMATE" rev-parse --short HEAD)"
else
  log "firstmate: pull skipped (diverged or conflicting local edits); left untouched"
  notify "Firstmate pull skipped - see /var/log/auto-rebuild.log"
fi

if darwin-rebuild switch --flake "$DOTFILES#camilo-total"; then
  log "rebuild: ok"
else
  log "rebuild: FAILED"
  notify "Rebuild failed - see /var/log/auto-rebuild.log"
  exit 1
fi

# TEMPORARY until kunchenguid/quota-axi#308 ships in an npm release: the
# rebuild reinstalls quota-axi@latest, which cannot score Antigravity quota,
# so Jev stops picking Antigravity models. Reinstall the local fix when the
# released build lacks it. Retires itself once the release has the fix;
# delete this block then.
QUOTA_AXI_SRC=$USER_HOME/github/quota-axi
installed_agy=$(npm root -g)/quota-axi/dist/src/providers/agy.js
if [ -f "$installed_agy" ] && ! grep -q windowSeconds "$installed_agy" && [ -d "$QUOTA_AXI_SRC" ]; then
  if as_user bash -c "cd '$QUOTA_AXI_SRC' && pnpm install --frozen-lockfile --silent && pnpm run build >/dev/null && tarball=\$(npm pack --silent) && npm install -g --ignore-scripts \"\$PWD/\$tarball\" >/dev/null && rm -f \"\$tarball\""; then
    log "quota-axi: reinstalled local Antigravity fix"
  else
    log "quota-axi: local fix reinstall FAILED"
    notify "quota-axi fix reinstall failed - see /var/log/auto-rebuild.log"
  fi
fi

log "auto-rebuild: done"
