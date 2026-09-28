# dotfiles

This repo is the public, reusable core of my Mac setup.

It is built with [Nix](https://nixos.org/), [`nix-darwin`](https://github.com/nix-darwin/nix-darwin), [Home Manager](https://github.com/nix-community/home-manager), and declarative [Homebrew](https://brew.sh/). The goal is to give macOS developers a reproducible base they can fork and adapt without inheriting someone else's entire private dotfiles repo.

If you want the longer explanation, see the [blog post](https://open.substack.com/pub/kunchenguid/p/how-i-built-a-reproducible-mac-setup?utm_campaign=post-expanded-share&utm_medium=web).

## What this repo does

It gives you a structured starting point for managing a Mac setup in code:

- bootstrap a fresh Mac with `setup/mac.sh`
- configure macOS defaults with `nix-darwin`
- manage user packages and shell behavior with Home Manager
- install GUI apps and macOS-native tools declaratively with Homebrew
- keep selected app config in the repo and link it into place

The repository includes selected editor, terminal, and agent configuration as concrete examples, while leaving credentials and host-local runtime state unmanaged.

## What is intentionally not included

This repo does **not** try to mirror my entire machine.

I left out things that are too personal or too workflow-specific to make a good public starter repo, including:

- custom shell systems
- personal scripts
- secrets and tokens
- host-local runtime state

The goal is to provide a reusable foundation that you can make your own.

## Repo structure

- `setup/mac.sh` - bootstrap a fresh Mac
- `setup/README.md` - bootstrap usage and testing notes
- `flake.nix` - top-level Nix wiring (`#camilo`, `#camilo-remote`, and their `#camilo-total` / `#camilo-remote-total` variants)
- `nix/configuration.nix` - system-level config (macOS defaults, Homebrew) identical on both machines
- `nix/home.nix` - user-level config (shell, packages, prompt, symlinks) identical on both machines
- `nix/camilo-extra.nix` - personal apps (Camo, OBS, WhatsApp, Dato, Notion, Obsidian, and more) - never installed by plain `rebuild.sh`, only by `rebuild-total.sh`
- `home/.config/` - live WezTerm / Neovim / herdr configs (symlinked by Home Manager)
- `home/.claude/`, `home/.grok/`, and `home/.firstmate/` - authored agent and crew-dispatch configuration (symlinked by Home Manager)
- `home/.pi/agent/` - authored Pi models, settings, themes, and extensions (symlinked by Home Manager)
- `upstream/kunchenguid/` - complete upstream mirror, selected config snapshot, and adoption decisions for [Kun's configs](https://github.com/kunchenguid/dotfiles)
- `scripts/check-upstream-configs.sh` - check / safely adopt his updates
- `rebuild.sh` - one nix-darwin rebuild helper for both machines, detects the account and picks the right flake attr
- `rebuild-total.sh` - same, plus `nix/camilo-extra.nix` (personal apps); typically only needed on the laptop
- `tests/` - safe shell regression tests for bootstrap and agent tools

## Tracking Kun's complete repository and config updates

We treat [kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles) as the expert baseline for terminal, editor, agent, and Pi configuration. The complete upstream repository is mirrored locally so root files and configurations outside the selected upstream paths are not lost. Selected upstream files are merged into our live `home/` tree while preserving our local additions and multi-host Nix layout.

### How it works

| Piece | Role |
|-------|------|
| `upstream/kunchenguid/repository/` | Complete local upstream mirror at the recorded commit (ignored, not versioned) |
| `upstream/kunchenguid/repository.commit` | Commit represented by the local mirror (ignored, not versioned) |
| `home/.config/` and `home/.pi/agent/` | What our machines actually use |
| `upstream/kunchenguid/snapshot/` | Selected config copy used by the adoption checker for diffs |
| `upstream/kunchenguid/decisions.json` | Per-file policy, adopted hashes, mirror metadata, and local additions |

Policies in `decisions.json`:

- **`track`** - stay with him. Auto-apply is safe when our file still matches the last adopted hash.
- **`extend`** - his base + our additions (list them in `our_additions`). Never auto-overwrite; review when he changes.
- **`fork`** - we own it; his diffs are inspiration only.
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
- `UPSTREAM_UPDATE` - he changed it; we did not customize → safe to adopt
- `EXTENDED` - we customized; upstream unchanged
- `CONFLICT` - both changed → open a diff and merge by hand

Adopt only the safe track updates:

```bash
bash scripts/check-upstream-configs.sh --apply
```

Inspect a file before applying:

```bash
diff -u home/.config/wezterm/wezterm.lua upstream/kunchenguid/snapshot/wezterm/wezterm.lua
```

### Adding our own changes

1. Edit `home/.config/...` as usual.
2. In `upstream/kunchenguid/decisions.json`, set that file's `policy` to `extend` (or `fork`).
3. Record what you added in `our_additions` (short bullets).
4. Re-run the check script so the next update surfaces as `EXTENDED` / `CONFLICT` instead of a blind overwrite.

Example: if you add WezTerm `Cmd+D` splits on top of his minimal config, mark `wezterm/wezterm.lua` as `extend` and put `"Cmd+D / Cmd+Shift+D pane splits"` in `our_additions`.


## How to use it

### 1. Clone the repo

```bash
git clone git@github.com:camilojourney/dotfiles.git ~/github/dotfiles
cd ~/github/dotfiles
```

### 2. Replace the placeholders

Update values like:

- `yourname`
- `/Users/yourname`
- `Your Name`
- `you@example.com`

If you are on an Intel Mac, change the system target in `flake.nix` from:

```nix
system = "aarch64-darwin";
```

to:

```nix
system = "x86_64-darwin";
```

### 3. Run the bootstrap script on a fresh Mac

This repo is primarily set up for Apple Silicon Macs. If you are on Intel, make the architecture change above before you run the bootstrap script.

```bash
bash setup/mac.sh
# on the remote Mac, select that host instead:
DARWIN_FLAKE_ATTR=camilo-remote bash setup/mac.sh
```

It installs Nix and Homebrew if missing, applies the `nix-darwin` + Home Manager config, and installs `nvm` - designed to complete in one run on a truly fresh Mac, no second shell needed. See [`setup/README.md`](setup/README.md) for what it does step by step and its environment variables.

## How I manage changes later

After the initial bootstrap, the usual workflow is:

1. edit the Nix config
2. run:

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

On the laptop, when you also want the personal apps in `nix/camilo-extra.nix`
(Camo, OBS, WhatsApp, Dato, etc.), run the total variant instead - it's the
same script, plus that one extra module:

```bash
./rebuild-total.sh
```

## Testing

Do not run `setup/mac.sh` or `rebuild.sh`/`rebuild-total.sh` against a real machine just to test them - they install Nix, Homebrew, and activate a real system. Run the sandboxed regression tests instead; see [`tests/README.md`](tests/README.md).

## Where to add new tools

My rough rule of thumb:

- use **Home Manager / Nix** for reproducible baseline CLI tools, fonts, shell utilities, and user environment packages
- use **Homebrew** for GUI apps and macOS-native tools that fit naturally there (declared in `nix/configuration.nix`, or `nix/camilo-extra.nix` for personal-only apps)
- use **`nix/agent-tools.manifest.lock.json`** for required agent/developer CLIs installed via npm, uv tool, or pinned external release archives

Agent npm globals, uv tool apps, and external tools (`no-mistakes`, `treehouse`) reconcile together on every `rebuild` via `scripts/agent-tools/reconcile.sh`. Add new entries to the manifest instead of ad hoc activation blocks. Run `bash scripts/agent-tools/audit.sh` to see unmanaged top-level tools without deleting anything.

A good setup does not force every tool through one package manager. It just makes the ownership of each layer clear.

## Why this setup looks like this

I wanted a setup that was:

- reproducible on a new Mac
- structured enough to maintain
- pragmatic about macOS
- publishable without oversharing the rest of my workflow

That is why this repo focuses on the reusable core.

## Related

- Long-form write-up: [blog post](https://open.substack.com/pub/kunchenguid/p/how-i-built-a-reproducible-mac-setup?utm_campaign=post-expanded-share&utm_medium=web)
- GitHub repo: <https://github.com/camilojourney/dotfiles>
- Forked from: <https://github.com/kunchenguid/dotfiles-mac-nix>
