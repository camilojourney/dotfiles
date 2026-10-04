# dotfiles

My personal Mac setup as code, built with [Nix](https://nixos.org/), [`nix-darwin`](https://github.com/nix-darwin/nix-darwin), [Home Manager](https://github.com/nix-community/home-manager), and declarative [Homebrew](https://brew.sh/).

I run this on two Macs: my laptop, and a Mac mini I use as a remote work computer. `rebuild.sh` detects which one it's running on and applies the matching config automatically, so the same command works on either.

## What's here

- bootstrap a fresh Mac with `setup/mac.sh`
- configure macOS defaults with `nix-darwin`
- manage user packages and shell behavior with Home Manager
- install GUI apps and macOS-native tools declaratively with Homebrew
- keep selected app config in the repo and link it into place

Editor, terminal, and agent configuration live here as real, current files - not stripped-down examples. Credentials, session state, and other host-local runtime data are never committed.

## If you're only running this on one Mac

Everything here works fine on a single machine - you just won't need all of it:

- `flake.nix`, `nix/configuration.nix`, `nix/home.nix` are the whole setup. `nix/camilo-extra.nix` is optional, for apps you only want on some machines.
- `./rebuild.sh` is the one command you run, always. It reads the macOS account it's running under to pick the right config - with one machine there's nothing to disambiguate, it just works.
- Ignore `rebuild-total.sh` and the `-remote`/`-total` flake attrs entirely; those exist only because I have two machines with different optional extras.

## Repo structure

- `setup/mac.sh` - bootstrap a fresh Mac
- `setup/README.md` - bootstrap usage and testing notes
- `flake.nix` - top-level Nix wiring (`#camilo` for the laptop, `#camilo-remote` for the Mac mini, and their `#camilo-total` / `#camilo-remote-total` variants)
- `nix/configuration.nix` - system-level config (macOS defaults, Homebrew), identical on both machines
- `nix/home.nix` - user-level config (shell, packages, prompt, symlinks), identical on both machines
- `nix/camilo-extra.nix` - personal apps (Camo, OBS, WhatsApp, Dato, Notion, Obsidian, and more) - never installed by plain `rebuild.sh`, only by `rebuild-total.sh`
- `home/.config/` - live WezTerm / Neovim / herdr configs (symlinked by Home Manager)
- `home/.claude/` and `home/.firstmate/` - authored agent, crew-dispatch, and secondmate harness configuration (symlinked by Home Manager)
- `home/.pi/agent/` - authored Pi models, settings, themes, and extensions (symlinked by Home Manager)
- `upstream/kunchenguid/` - complete upstream mirror, selected config snapshot, and adoption decisions for [Kun's configs](https://github.com/kunchenguid/dotfiles)
- `scripts/check-upstream-configs.sh` - check / safely adopt his updates
- `rebuild.sh` - one nix-darwin rebuild helper for both machines, detects the account and picks the right flake attr
- `rebuild-total.sh` - same, plus `nix/camilo-extra.nix` (personal apps); typically only needed on the laptop
- `tests/` - safe shell regression tests for bootstrap and agent tools

## Tracking Kun's complete repository and config updates

I treat [kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles) as the expert baseline for terminal, editor, agent, and Pi configuration. The complete upstream repository is mirrored locally so root files and configurations outside the selected upstream paths are not lost. Selected upstream files are merged into my live `home/` tree while preserving my local additions and multi-host Nix layout.

### How it works

| Piece | Role |
|-------|------|
| `upstream/kunchenguid/repository/` | Complete local upstream mirror at the recorded commit (ignored, not versioned) |
| `upstream/kunchenguid/repository.commit` | Commit represented by the local mirror (ignored, not versioned) |
| `home/.config/` and `home/.pi/agent/` | What my machines actually use |
| `upstream/kunchenguid/snapshot/` | Selected config copy used by the adoption checker for diffs |
| `upstream/kunchenguid/decisions.json` | Per-file policy, adopted hashes, mirror metadata, and local additions |

Policies in `decisions.json`:

- **`track`** - stay with him. Auto-apply is safe when my file still matches the last adopted hash.
- **`extend`** - his base + my additions (list them in `our_additions`). Never auto-overwrite; review when he changes.
- **`fork`** - I own it; his diffs are inspiration only.
- **`ignore`** - stop watching.

### Routine (do this when he updates, or monthly)

```bash
bash scripts/check-upstream-configs.sh
```

This refreshes both the complete repository mirror and the selected comparison snapshot. To refresh those upstream artifacts without printing the status report, use:

```bash
bash scripts/check-upstream-configs.sh --refresh-repository
```

`--refresh-repository` remains available for compatibility, but it refreshes the snapshot too so the published upstream state always represents one commit.

Read the STATUS column:

- `IN_SYNC` - nothing to do
- `UPSTREAM_UPDATE` - he changed it; I did not customize → safe to adopt
- `EXTENDED` - I customized; upstream unchanged
- `CONFLICT` - both changed → open a diff and merge by hand

Adopt only the safe track updates:

```bash
bash scripts/check-upstream-configs.sh --apply
```

Inspect a file before applying:

```bash
diff -u home/.config/wezterm/wezterm.lua upstream/kunchenguid/snapshot/wezterm/wezterm.lua
```

### Adding my own changes

1. Edit `home/.config/...` as usual.
2. In `upstream/kunchenguid/decisions.json`, set that file's `policy` to `extend` (or `fork`).
3. Record what I added in `our_additions` (short bullets).
4. Re-run the check script so the next update surfaces as `EXTENDED` / `CONFLICT` instead of a blind overwrite.

Example: if I add WezTerm `Cmd+D` splits on top of his minimal config, mark `wezterm/wezterm.lua` as `extend` and put `"Cmd+D / Cmd+Shift+D pane splits"` in `our_additions`.

## Bootstrapping a Mac

```bash
bash setup/mac.sh
# on the Mac mini, select that host instead:
DARWIN_FLAKE_ATTR=camilo-remote bash setup/mac.sh
```

It installs Nix and Homebrew if missing, applies the `nix-darwin` + Home Manager config, and installs `nvm` - designed to complete in one run on a truly fresh Mac, no second shell needed. See [`setup/README.md`](setup/README.md) for what it does step by step and its environment variables.

## Making changes later

After the initial bootstrap, the usual workflow is: edit the Nix config, then run:

```bash
rebuild
```

One script and one alias for both machines - `rebuild.sh` reads the macOS
account it's running under and picks the matching flake attr (`camilo` or
`camilo-remote`) automatically, so the same command works everywhere:

```bash
./rebuild.sh
# or:
rebuild
```

On the laptop, when I also want the personal apps in `nix/camilo-extra.nix`
(Camo, OBS, WhatsApp, Dato, etc.), I run the total variant instead - it's the
same script, plus that one extra module:

```bash
./rebuild-total.sh
```

Both machines also update themselves every day at 05:00 (or at the next
wake): the `org.dotfiles.auto-rebuild` launchd daemon in
`nix/configuration.nix` runs [`scripts/auto-rebuild.sh`](scripts/auto-rebuild.sh)
as root, which fast-forwards `~/github/dotfiles` and `~/github/firstmate`,
then runs the same rebuild as `./rebuild-total.sh` on the laptop or
`./rebuild.sh` on the remote box. It logs to `/var/log/auto-rebuild.log` and
posts a notification on failure. Because it pulls this repo and applies it as
root, anything pushed to `main` reaches both machines unattended.
See [`docs/AUTO-UPDATE.md`](docs/AUTO-UPDATE.md) for logs, enabling it, and
the design notes.

## Testing

Do not run `setup/mac.sh` or `rebuild.sh`/`rebuild-total.sh` against a real machine just to test them - they install Nix, Homebrew, and activate a real system. Run the sandboxed regression tests instead; see [`tests/README.md`](tests/README.md).

## Where to add new tools

My rough rule of thumb:

- use **Home Manager / Nix** for reproducible baseline CLI tools, fonts, shell utilities, and user environment packages
- use **Homebrew** for GUI apps and macOS-native tools that fit naturally there (declared in `nix/configuration.nix`, or `nix/camilo-extra.nix` for personal-only apps)
- use **`nix/agent-tools.manifest.lock.json`** for required agent/developer CLIs installed via npm, uv tool, or pinned external release archives

Agent npm globals, uv tool apps, and external tools (`no-mistakes`, `treehouse`) reconcile together on every `rebuild` via `scripts/agent-tools/reconcile.sh`. Add new entries to the manifest instead of ad hoc activation blocks. Run `bash scripts/agent-tools/audit.sh` to see unmanaged top-level tools without deleting anything.

A good setup does not force every tool through one package manager. It just makes the ownership of each layer clear.

## Related

- GitHub repo: <https://github.com/camilojourney/dotfiles>
- Based on the structure of: <https://github.com/kunchenguid/dotfiles-mac-nix>
