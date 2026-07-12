#!/usr/bin/env bash
# Restore Stream Deck profiles + prefs from the repo backup.
# Quit Stream Deck before running.
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$REPO_ROOT/files/.config/streamdeck"
SUPPORT="$HOME/Library/Application Support/com.elgato.StreamDeck"

if [ ! -d "$SRC/ProfilesV3" ]; then
  echo "Missing backup: $SRC/ProfilesV3" >&2
  exit 1
fi

if pgrep -xq "Stream Deck" || pgrep -f "Elgato Stream Deck" >/dev/null 2>&1; then
  echo "Quit Stream Deck first (it can overwrite profiles on exit)." >&2
  exit 1
fi

mkdir -p "$SUPPORT/ProfilesV3" "$SUPPORT/BackupV3"
rsync -a --delete "$SRC/ProfilesV3/" "$SUPPORT/ProfilesV3/"

if [ -f "$SRC/profiles.streamDeckProfilesBackup" ]; then
  cp "$SRC/profiles.streamDeckProfilesBackup" \
    "$SUPPORT/BackupV3/Restored from dotfiles.streamDeckProfilesBackup"
fi

if [ -f "$SRC/com.elgato.StreamDeck.plist" ]; then
  plutil -convert binary1 -o "$HOME/Library/Preferences/com.elgato.StreamDeck.plist" \
    "$SRC/com.elgato.StreamDeck.plist"
  killall cfprefsd 2>/dev/null || true
fi

echo "Restored Stream Deck profiles -> $SUPPORT/ProfilesV3"
echo "Open Stream Deck and confirm your pages/buttons."
echo "If a plugin is missing, reinstall it from the Stream Deck Marketplace."
