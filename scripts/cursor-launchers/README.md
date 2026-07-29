# Cursor launchers

This directory is the source of truth for the Finder and Stream Deck launchers
installed in `~/Applications/Cursor Launchers`. The app bundles are generated,
not committed: `osacompile` creates complete macOS AppleScript app bundles from
the manifest on the machine where they will run.

## Inventory

`launchers.tsv` contains all current launchers and their `cursor-go` targets:

| Launcher | Target | Behavior |
|----------|--------|----------|
| Cursor Agent Invoz | `agent-invoz` | Opens Cursor Agent in the local `invoz` workspace |
| Cursor Agents | `agents` | Opens Cursor chat |
| Cursor Fleet | `fleet` | Opens remote `fleet-system` |
| Cursor Firstmate | `firstmate` | Opens remote `firstmate` |
| Cursor Genpeli | `genpeli` | Opens remote `genpeli` |
| Cursor Holus | `holus` | Opens remote `holus` |
| Cursor Invoz | `invoz` | Opens local `invoz` |
| Cursor Job Tracker | `job-tracker` | Opens local `job-tracker` in a new classic IDE window |
| Cursor Pilaster | `pilaster` | Opens remote `pilaster` |
| Cursor Portfolio | `portfolio` | Opens remote `camilomartinez-portfolio` |
| Cursor Pythia | `pythia` | Opens remote `pythia` |
| Cursor Vault | `vault` | Opens the configured local Obsidian vault |

The generated AppleScript resolves the invoking user's home directory at run
time and calls `~/bin/cursor-go-bg <target>`. It deliberately does not retain
the old hard-coded username path.

## Configuration

`cursor-go` reads the following variables. Copy the tracked example to the
default config path for persistent machine-local values, or supply variables
from the calling environment.

| Variable | Default | Purpose |
|----------|---------|---------|
| `CURSOR_LAUNCHER_CONFIG` | `~/.config/cursor-launchers/config.sh` | Selects the sourced config file |
| `CURSOR_BIN` | `/Applications/Cursor.app/Contents/Resources/app/bin/cursor` | Selects the Cursor CLI |
| `CURSOR_LAUNCHER_LOCAL_GITHUB` | `~/github` | Base directory for local repositories |
| `CURSOR_LAUNCHER_VAULT` | `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/My Vault` | Local vault path |
| `CURSOR_LAUNCHER_REMOTE_HOST` | empty | SSH host required by remote routes |
| `CURSOR_LAUNCHER_REMOTE_ROOT` | empty | Remote directory containing the routed repositories |
| `CURSOR_LAUNCHER_SSH_TIMEOUT_SECONDS` | `5` | Positive-integer SSH preflight timeout |

Remote routes fail before opening Cursor when the host or root is missing, the
timeout is invalid, `ssh` is unavailable, or the host cannot be reached in
batch mode.

## Restore

1. Apply the dotfiles Home Manager configuration. It links `cursor-go` and
   `cursor-go-bg` into `~/bin` and installs the configuration example.
2. Copy `~/.config/cursor-launchers/config.sh.example` to
   `~/.config/cursor-launchers/config.sh`, then set the remote SSH host and
   remote workspace root for this machine. This is required for the remote
   routes: Fleet, Firstmate, Pilaster, Pythia, Genpeli, Holus, and Portfolio.
   Invoz, Agent Invoz, and Job Tracker open from the local `~/github`
   directory. Job Tracker explicitly opens a new classic IDE window instead of
   the Agents window. For the established Mini flow, use
   `CURSOR_LAUNCHER_REMOTE_HOST="mac-mini"` and
   `CURSOR_LAUNCHER_REMOTE_ROOT="/Users/mini/github"`; Firstmate then resolves
   to `/Users/mini/github/firstmate`.
3. If Home Manager is not being used, install the two portable commands:

   ```bash
   mkdir -p "$HOME/bin"
   install -m 755 scripts/cursor-launchers/cursor-go "$HOME/bin/cursor-go"
   install -m 755 scripts/cursor-launchers/cursor-go-bg "$HOME/bin/cursor-go-bg"
   ```

4. Generate and verify the Finder-launchable bundles:

   ```bash
   scripts/cursor-launchers/make-launchers.sh
   scripts/cursor-launchers/verify-launchers.sh
   ```

Both commands accept an optional destination directory, making a dry restore
safe to test outside `~/Applications`. The helper preserves the repaired
behavior: it returns immediately, activates Cursor only when it is already
running, and dispatches `cursor-go` in the background. A failed background
launch attempts to display the captured error in a macOS dialog.
