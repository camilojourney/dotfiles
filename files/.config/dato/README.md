# Dato preferences

Dato is an App Store / sandboxed app. It does **not** read `~/.config/dato`.

Live settings path:

```text
~/Library/Containers/com.sindresorhus.Dato/Data/Library/Preferences/com.sindresorhus.Dato.plist
```

This folder is a **backup / source of truth in git**, not a live WezTerm-style symlink target.

## Why not symlink like WezTerm?

1. Dato never looks under `~/.config/`.
2. Pointing the container plist at the repo via symlink often breaks App Sandbox (or Dato rewrites a real file on quit).
3. Calendar / reminder IDs inside the plist are machine-specific UUIDs - restoring on another Mac may need re-selecting calendars.

## Refresh the backup from this Mac

```bash
plutil -convert xml1 -o files/.config/dato/com.sindresorhus.Dato.plist \
  "$HOME/Library/Containers/com.sindresorhus.Dato/Data/Library/Preferences/com.sindresorhus.Dato.plist"
```

## Restore onto this Mac (quit Dato first)

```bash
bash scripts/restore-dato-prefs.sh
```
