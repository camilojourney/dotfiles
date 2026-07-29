# Cursor launchers

This directory is the source of truth for the Finder and Stream Deck launchers
installed in `~/Applications/Cursor Launchers`. The app bundles are generated,
not committed: `osacompile` creates complete macOS AppleScript app bundles from
the manifest on the machine where they will run.

## Inventory

`launchers.tsv` contains all current launchers and their `cursor-go` targets:

- Cursor Agent Invoz - `agent-invoz`
- Cursor Agents - `agents`
- Cursor Fleet - `fleet`
- Cursor Firstmate - `firstmate`
- Cursor Genpeli - `genpeli`
- Cursor Holus - `holus`
- Cursor Invoz - `invoz`
- Cursor Job Tracker - `job-tracker`
- Cursor Pilaster - `pilaster`
- Cursor Portfolio - `portfolio`
- Cursor Pythia - `pythia`
- Cursor Vault - `vault`

The generated AppleScript resolves the invoking user's home directory at run
time and calls `~/bin/cursor-go-bg <target>`. It deliberately does not retain
the old hard-coded username path.

## Restore

1. Apply the dotfiles Home Manager configuration. It links `cursor-go` and
   `cursor-go-bg` into `~/bin` and installs the configuration example.
2. Copy `~/.config/cursor-launchers/config.sh.example` to
   `~/.config/cursor-launchers/config.sh`, then set the remote SSH host and
   remote workspace root for this machine. This is required for the remote
   routes: Fleet, Firstmate, Pilaster, Pythia, Genpeli, Holus, and Portfolio.
   Invoz and Job Tracker open from the local `~/github` directory. Job Tracker
   explicitly opens a new classic IDE window instead of the Agents window. For
   the established Mini flow, use `CURSOR_LAUNCHER_REMOTE_HOST="mac-mini"`
   and `CURSOR_LAUNCHER_REMOTE_ROOT="/Users/mini/github"`; Firstmate then resolves
   to `/Users/mini/github/firstmate`.
3. If Home Manager is not being used, install the two portable commands:

   ```bash
   install -Dm755 scripts/cursor-launchers/cursor-go "$HOME/bin/cursor-go"
   install -Dm755 scripts/cursor-launchers/cursor-go-bg "$HOME/bin/cursor-go-bg"
   ```

4. Generate and verify the Finder-launchable bundles:

   ```bash
   scripts/cursor-launchers/make-launchers.sh
   scripts/cursor-launchers/verify-launchers.sh
   ```

Both commands accept an optional destination directory, making a dry restore
safe to test outside `~/Applications`. The helper preserves the repaired
behavior: it returns immediately, activates Cursor only when it is already
running, and dispatches `cursor-go` in the background.
