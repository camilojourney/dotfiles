#!/usr/bin/env bash
# Restore Dato prefs from the repo backup into the App Store sandbox path.
# Quit Dato before running.
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$REPO_ROOT/files/.config/dato/com.sindresorhus.Dato.plist"
DEST_DIR="$HOME/Library/Containers/com.sindresorhus.Dato/Data/Library/Preferences"
DEST="$DEST_DIR/com.sindresorhus.Dato.plist"

if [ ! -f "$SRC" ]; then
  echo "Missing backup: $SRC" >&2
  exit 1
fi

if pgrep -xq Dato; then
  echo "Quit Dato first (it can overwrite prefs on exit)." >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
# Convert to binary plist (what the app normally writes) and install.
plutil -convert binary1 -o "$DEST" "$SRC"
# Nudge cfprefsd
killall cfprefsd 2>/dev/null || true
echo "Restored Dato prefs -> $DEST"
echo "Open Dato and confirm calendars / notifications."
