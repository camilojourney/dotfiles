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

I include [WezTerm](https://wezfurlong.org/wezterm/) as the one concrete app-config example because it is real enough to demonstrate the pattern without dragging in the more personal parts of my workflow.

## What is intentionally not included

This repo does **not** try to mirror my entire machine.

I left out things that are too personal or too workflow-specific to make a good public starter repo, including:

- editor config
- custom shell systems
- personal scripts
- AI tooling
- secrets and tokens
- private automation

The goal is to provide a reusable foundation that you can make your own.

## Repo structure

- `setup/mac.sh` - bootstrap a fresh Mac
- `setup/README.md` - bootstrap usage and testing notes
- `flake.nix` - top-level Nix wiring (`#camilo` and `#camilo-mini`)
- `nix/shared/` - foundation host + user config shared by both machines
- `nix/camilo/` - main laptop extras (Camo, Logi Options+, Stream Deck, OBS, Wispr) + `rebuild` alias
- `nix/camilo-mini/` - Mini overlay (foundation only + `rebuild` alias)
- `files/.config/` - live WezTerm / Neovim / herdr configs (symlinked by Home Manager)
- `upstream/kunchenguid/` - decisions + snapshot for tracking [Kun's configs](https://github.com/kunchenguid/dotfiles)
- `scripts/check-upstream-configs.sh` - check / safely adopt his updates
- `tests/` - regression tests for the bootstrap script
- `blog.md` - local copy of the [blog post](https://open.substack.com/pub/kunchenguid/p/how-i-built-a-reproducible-mac-setup?utm_campaign=post-expanded-share&utm_medium=web)

## Tracking Kun's config updates (wezterm / nvim / herdr)

We treat [kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles) as the expert baseline for terminal, editor, and agent multiplexer configs. Our live copies live under `files/.config/`. We keep the freedom to add our own changes without losing the ability to pull his next improvements.

### How it works

| Piece | Role |
|-------|------|
| `files/.config/{wezterm,nvim,herdr}` | What the machine actually uses |
| `upstream/kunchenguid/snapshot/` | Last fetched copy of his files (for diffs) |
| `upstream/kunchenguid/decisions.json` | Per-file policy + hash of the upstream version we last adopted + notes about our additions |

Policies in `decisions.json`:

- **`track`** - stay with him. Auto-apply is safe when our file still matches the last adopted hash.
- **`extend`** - his base + our additions (list them in `our_additions`). Never auto-overwrite; review when he changes.
- **`fork`** - we own it; his diffs are inspiration only.
- **`ignore`** - stop watching.

### Routine (do this when he updates, or monthly)

```bash
bash scripts/check-upstream-configs.sh
```

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
diff -u files/.config/wezterm/wezterm.lua upstream/kunchenguid/snapshot/wezterm/wezterm.lua
```

### Adding our own changes

1. Edit `files/.config/...` as usual.
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
```

On the Mac Mini, select that host instead:

```bash
DARWIN_FLAKE_ATTR=camilo-mini bash setup/mac.sh
```

The script will:

- install [Determinate Nix Installer](https://determinate.systems/nix-installer/) if needed
- install [Homebrew](https://brew.sh/) if needed
- apply the `nix-darwin` + Home Manager config
- install [`nvm`](https://github.com/nvm-sh/nvm) and a default Node.js version if needed

On a fresh machine, the bootstrap is designed to complete in one run.
After the Determinate installer runs, the script sources the Nix daemon profile into the current shell and uses an absolute `nix` path for the first `nix-darwin` activation, so you should not need a second shell or a second setup run.

The `NIX_DAEMON_PROFILE` and `DARWIN_REBUILD_BIN` environment variables are only there so the regression test can point the script at sandboxed paths.
`DARWIN_FLAKE_ATTR` selects which flake output to apply (`camilo` by default, or `camilo-mini`).
Normal use should leave the first two unset.

## How I manage changes later

After the initial bootstrap, the usual workflow is:

1. edit the Nix config
2. run:

```bash
rebuild
```

This alias is included in the shell config and expands to the host-specific flake attr (`#camilo` on the laptop, `#camilo-mini` on the Mini):

```bash
/run/current-system/sw/bin/darwin-rebuild switch --flake ~/github/dotfiles#camilo
```

## Testing

Do not run `setup/mac.sh` against a development or CI machine just to test it.
Run the sandboxed regression test instead:

```bash
bash tests/mac_setup_test.sh
```

It runs the real script logic with stub executables for `curl`, `sh`, `nix`, `darwin-rebuild`, `sudo`, and `bash`, covering both a fresh-machine single-pass bootstrap and the already-bootstrapped fast path.
The harness also guards every harness/stub write against sandbox escapes, re-homes `NVM_DIR` under the sandboxed `HOME`, and unsets inherited `BASH_ENV`/`ENV` hooks before invoking the script under test.

## Where to add new tools

My rough rule of thumb:

- use **Home Manager / Nix** for reproducible baseline CLI tools, fonts, shell utilities, and user environment packages
- use **Homebrew** for GUI apps and macOS-native tools that fit naturally there
- use **ecosystem-specific package managers** like `npm` when that is the right abstraction for the tool

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
