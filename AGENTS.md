# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.

## setup/mac.sh: never run it for real

`setup/mac.sh` installs Nix (via the Determinate installer) and runs a real `nix-darwin` system activation (`darwin-rebuild switch` / `sudo nix run ... switch`). Never execute it, the real Determinate installer, `darwin-rebuild switch`, `sudo nix run ...`, the Homebrew installer, or the nvm installer against a dev machine or CI host - these mutate the host permanently. All validation of this script must go through `tests/mac_setup_test.sh`, which runs the actual script with PATH masked to stub executables so nothing real is ever installed or activated.

## Fresh-machine single-pass contract

`setup/mac.sh` must bootstrap a brand-new Mac in one run, with no "run it again in a new shell" step. After the Determinate installer runs, the script sources the Nix daemon profile (`NIX_DAEMON_PROFILE`, defaults to `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`) into the current shell so `nix` is usable immediately, then activates nix-darwin for the first time via `sudo <absolute nix path> --extra-experimental-features "nix-command flakes" run nix-darwin/master#darwin-rebuild -- switch --flake ...` (absolute path because `sudo` doesn't inherit the newly-sourced PATH). `NIX_DAEMON_PROFILE` and `DARWIN_REBUILD_BIN` are both overridable via environment variables (defaulting to the real canonical paths) specifically so tests can point them at a sandbox instead of the real filesystem. Any future edit to this bootstrap logic must preserve: single-pass success on a fresh machine, and the existing already-installed fast path (`$DARWIN_REBUILD_BIN switch`) staying untouched.

## Testing setup/mac.sh

Run `bash tests/mac_setup_test.sh`. It simulates a fresh Mac by copying the repo into a scratch fixture (placeholders pre-replaced), building stub `curl`/`sh`/`nix`/`darwin-rebuild`/`sudo`/`bash` executables that record invocations and fake just enough side effects (a profile script, a `nix` binary) for the script to progress, then running the real `setup/mac.sh` against that PATH-masked sandbox. It covers both the fresh-machine path (single-pass activation) and the already-installed fast path. It never touches the real network, Nix store, Homebrew, sudo, or system state. Set `DEBUG_KEEP_SANDBOX=1` to keep the scratch sandbox around for inspection after a failing run.

Each scenario sandboxes `HOME`, re-homes `NVM_DIR` under that temp root, and unsets inherited `BASH_ENV`/`ENV` before invoking `setup/mac.sh` (an inherited absolute `NVM_DIR` from hm-session-vars would otherwise leak stub writes).
Harness and stub writes call `assert_path_under_sandbox` / `guard_write_path` so a future leak through parent traversal, symlink escape, or another absolute write path fails the test instead of mutating the host.

## Adopting upstream expert patterns (kunchenguid/dotfiles)

This repo tracks https://github.com/kunchenguid/dotfiles as the reference for WezTerm, Neovim, herdr, and Pi agent config.

**Do not blind-copy.** Use the check script and decisions file:

1. `bash scripts/check-upstream-configs.sh` - fetch his latest complete repository into `upstream/kunchenguid/repository/`, refresh the selected comparison snapshot, and report status vs `files/.config/`.
2. Read `upstream/kunchenguid/decisions.json` - each file has policy `track` | `extend` | `fork` | `ignore`, plus `our_additions`, the last adopted upstream hash, and complete-mirror metadata.
3. Explain why a delta exists before adopting.
4. `bash scripts/check-upstream-configs.sh --apply` only auto-updates clean `track` files (ours still matches last adopted hash). `extend` / `fork` / conflicts stay manual.
5. Keep our multi-host Nix layout (`#camilo` / `#camilo-remote`); the check script tracker is for `files/.config/{wezterm,nvim,herdr}`. Pi lives under `files/.pi/agent/` (see below).

### Upstream review protocol

Never run `--apply` as the first update command.
Before refreshing, copy `upstream/kunchenguid/snapshot/` to a temporary directory, then run `bash scripts/check-upstream-configs.sh` to fetch and classify the latest upstream state without applying it. The full repository mirror is reference material and includes files outside the selected snapshot.
Review the old and refreshed snapshots, plus the complete mirror when needed, to understand the upstream change. Then compare our file with the refreshed snapshot to identify our retained additions.
For every changed file, record an explicit adopt, retain, merge, or reject decision and its short rationale in `upstream/kunchenguid/decisions.json` before changing the file.
Only clean `track` files may be auto-applied after that review; merge `extend` and `fork` files manually.
After a manual merge, update that file's `adopted_upstream_sha256` to the refreshed upstream file hash and retain every local difference in `our_additions` so the next review has an honest baseline.

### Repeatable upstream update workflow

Use this workflow whenever Kun publishes changes. The goal is to refresh first, inspect the complete diff, record decisions, and only then change live configuration.

1. **Check local state before starting.**
   ```bash
   git status --short
   git diff -- files/.config files/.pi/agent upstream/kunchenguid/decisions.json
   ```
   Do not mix unrelated local work into an upstream adoption.

2. **Preserve the old reference.**
   ```bash
   REVIEW_DIR=$(mktemp -d)
   cp -R upstream/kunchenguid/snapshot "$REVIEW_DIR/snapshot-before"
   cp -R upstream/kunchenguid/repository "$REVIEW_DIR/repository-before"
   ```

3. **Refresh without applying anything.**
   ```bash
   bash scripts/check-upstream-configs.sh
   ```
   This refreshes the complete repository mirror and the selected comparison snapshot. If only the complete mirror is needed, use:
   ```bash
   bash scripts/check-upstream-configs.sh --refresh-repository
   ```
   Never start with `--apply`.

4. **Inspect the changes.**
   ```bash
   diff -ru "$REVIEW_DIR/snapshot-before" upstream/kunchenguid/snapshot || true
   diff -ru "$REVIEW_DIR/repository-before" upstream/kunchenguid/repository || true
   bash scripts/check-upstream-configs.sh
   ```
   Review both the checker status and the full mirror. Then compare each changed upstream file with its mapped live file under `files/`.

5. **Make and record one decision per changed file before editing live files.**
   Record the decision in `upstream/kunchenguid/decisions.json`:
   - **adopt**: upstream is better and replaces our version.
   - **retain**: our version is intentional; keep the upstream change only in the mirror.
   - **merge**: combine upstream improvements with our local additions.
   - **reject**: do not use the upstream change, with a short reason.

6. **Apply only the recorded decisions.**
   - Clean `track` files with an adopt decision may use `bash scripts/check-upstream-configs.sh --apply`.
   - `extend`, `fork`, and conflict files must be merged manually.
   - New authored Pi or Claude files may be imported when they do not already exist locally. Never overwrite an existing local file automatically.
   - Keep Kun's root Nix/bootstrap files as reference only. Preserve the repository's declared multi-host Nix layout.

7. **Update the adoption baseline.**
   After adopting or merging, set `adopted_upstream_sha256` to the refreshed upstream file hash and list every retained local difference in `our_additions`. Do not claim `IN_SYNC` when our file intentionally differs.

8. **Verify and review the final diff.**
   ```bash
   bash -n scripts/check-upstream-configs.sh
   jq empty upstream/kunchenguid/decisions.json
   git diff --check
   bash tests/mac_setup_test.sh
   graphify update .
   git diff --stat
   git status --short
   ```
   Leave the temporary review directory available until the adoption is reviewed, then remove it.

Path mapping: his `home/.config/X` → our `files/.config/X`; his `home/.pi/agent/X` → our `files/.pi/agent/X`. His root Nix/bootstrap files remain in the complete mirror for reference because our repository has a deliberate multi-host Nix layout.

## Pi (kunchenguid-aligned)

- CLI: declared in `nix/shared/agent-tools/manifest.lock.json` and reconciled by `scripts/agent-tools/reconcile.sh` on rebuild (Home Manager `installAgentTools` activation; needs brew `node`).
- Authored config only: `files/.pi/agent/{themes,extensions,models.json,settings.json}` symlinked into `~/.pi/agent/`.
- Third-party Pi packages are pinned in `settings.json` `"packages"` (not vendored into the repo).
- Do not manage `~/.pi/agent` wholesale; leave auth, sessions, `npm/`, and `git/` unmanaged.

## Agent/developer CLI inventory

Required agent CLIs (npm globals, pipx apps, external release binaries) are owned by `nix/shared/agent-tools/manifest.lock.json`.

- **Add or bump a tool:** edit the manifest, then rebuild. Do not add one-off `home.activation` blocks.
- **npm globals:** reconciled together via `scripts/agent-tools/reconcile.sh` using brew node `npm install -g --ignore-scripts <pkg>@<pin>`. Never declare a global `npm` package.
- **pipx:** shared packages apply to both hosts; laptop-only MLX tooling lives under `pipx.camilo`.
- **External** (`no-mistakes`, `treehouse`): pinned GitHub release archives with sha256 in the manifest; installed by `scripts/agent-tools/install-external.sh`.
- **Update policy:** ordinary `rebuild` reconciles to manifest pins (not floating latest). Bump pins explicitly.
- **Audit unmanaged tools:** `bash scripts/agent-tools/audit.sh [camilo|camilo-remote]` (reports only; never deletes).
- **Tests:** `bash tests/agent_tools_test.sh` (stubbed package managers; no network or host mutation).

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
