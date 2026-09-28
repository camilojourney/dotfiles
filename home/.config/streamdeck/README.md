# Stream Deck configuration backup

Elgato Stream Deck does **not** read `~/.config/streamdeck`. Live data lives under:

```text
~/Library/Application Support/com.elgato.StreamDeck/
```

This folder is a **git backup**, same idea as Dato - not a live WezTerm-style symlink.

## What we store

| Path | Purpose |
|------|---------|
| `ProfilesV3/` | Live profile folders (layouts, actions, button images) |
| `profiles.streamDeckProfilesBackup` | Latest official Elgato backup file (importable in the app) |
| `com.elgato.StreamDeck.plist` | App preferences |

Plugins (`Plugins/`, ~50MB marketplace plugins) are **not** stored here - reinstall from Stream Deck Marketplace after restore if needed.

## Refresh backup from this Mac

```bash
bash scripts/backup-streamdeck.sh
```

## Restore onto this Mac

1. Quit Stream Deck.
2. Run:

```bash
bash scripts/restore-streamdeck.sh
```

3. Reopen Stream Deck (or: File → Profiles → Import the `.streamDeckProfilesBackup` if needed).

Stream Deck is laptop-only (`nix/camilo` cask). The Mini does not install it.
