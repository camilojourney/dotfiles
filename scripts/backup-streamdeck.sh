#!/usr/bin/env bash
# Copy live Stream Deck profiles + prefs into the repo backup.
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DEST="$REPO_ROOT/files/.config/streamdeck"
SUPPORT="$HOME/Library/Application Support/com.elgato.StreamDeck"

if [ ! -d "$SUPPORT/ProfilesV3" ]; then
  echo "No Stream Deck ProfilesV3 at: $SUPPORT/ProfilesV3" >&2
  exit 1
fi

mkdir -p "$DEST"
rsync -a --delete "$SUPPORT/ProfilesV3/" "$DEST/ProfilesV3/"

if compgen -G "$SUPPORT/BackupV3/"*.streamDeckProfilesBackup >/dev/null; then
  LATEST=$(ls -t "$SUPPORT/BackupV3/"*.streamDeckProfilesBackup | head -1)
  cp "$LATEST" "$DEST/profiles.streamDeckProfilesBackup"
fi

PREF="$HOME/Library/Preferences/com.elgato.StreamDeck.plist"
if [ -f "$PREF" ]; then
  plutil -convert xml1 -o "$DEST/com.elgato.StreamDeck.plist" "$PREF"
fi

echo "Backed up Stream Deck -> $DEST"
du -sh "$DEST" "$DEST/ProfilesV3" "$DEST/profiles.streamDeckProfilesBackup" 2>/dev/null || true
