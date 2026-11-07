# Configuration belongs in dotfiles; app state does not

Keep authored settings, plugin lockfiles, source code, and required assets in
`home/`. Logs, sessions, snapshots, sockets, caches, generated helpers, and
application-created backup files belong in the app's host-local directories,
not in the checkout, even when Git would ignore them.

## Linked applications

The allowlists in `nix/home.nix` and `nix/camilo-extra.nix` use
[`nix/config-directory.nix`](../nix/config-directory.nix). Each app root remains
a real local directory; only its declared configuration and code/assets link
back to dotfiles. Add new shared configuration files to the owning allowlist;
unlisted files remain host-local.

| Application | What remains in the checkout | Host-local state |
| --- | --- | --- |
| Herdr | `home/.config/herdr/config.toml` only | Other files under `~/.config/herdr/`, including active sockets and saved sessions |
| WezTerm | `home/.config/wezterm/wezterm.lua` | Other files under `~/.config/wezterm/` |
| Neovim | Init, Lua configuration, plugin lockfile, preview CSS and documentation | Other files under `~/.config/nvim/`; plugins/cache/state retain Neovim's usual data paths |
| OBS, total targets only | The declared Streaming scene and profile settings | Other files under `~/Library/Application Support/obs-studio/basic/`, including `.bak` files, other profiles and private service settings |

Pi and Baby Menu already keep runtime data outside their authored settings and
code directories. Their extension/theme/widget source is required code, not a
cache. Dato and Stream Deck are explicit configuration backups, not live app-root
links; Stream Deck button images and its importable profile export are restore
assets. See their READMEs under `home/.config/`.

## Existing machines

Before Home Manager checks links, `scripts/separate-config-state.py` replaces old
directory-wide links and relocates unlisted entries from the checkout to the
local app directory. It uses the same Nix allowlist that declares the links.
Moves on the same filesystem retain file inodes, open log descriptors, and Unix
sockets; no sessions are deleted and no app is restarted.

The migration is idempotent. Unrelated directory links, missing configuration,
symlinked destination parents, cross-filesystem moves, or conflicting files stop
activation rather than overwrite either version. If interrupted, already moved
data stays local and remaining data stays in the checkout; resolve the reported
conflict before retrying. Apps that atomically replace a configuration symlink
can leave a changed local file; review and merge that change into its authored
owner before retrying. There is no automatic rollback into a directory-wide
link because that could hide local app state.

A rebuild applies the declarations on each machine. A local checkout edit does
not prove the other machine has migrated. Do not restore old whole-directory
links when rolling back application settings.

## Checks

```sh
python3 tests/config_state_test.py
```

The tests use temporary directories, a Home Manager-style symlink chain, a live
Unix socket, and an open log file. They check preservation, nested configuration,
repeat runs, and refusal to overwrite local data. They never touch real app
sessions.
