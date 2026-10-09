# Daily auto-update

Both machines update themselves every day, so nothing here needs a manual
`./rebuild.sh` to stay current.

## What runs

| | Laptop (`camiloslaptop`) | Remote box (`camilo_mini`) |
|---|---|---|
| When | 05:00 daily, or at the next wake if asleep | same |
| Pulls | `~/github/dotfiles`, `~/github/firstmate` | same |
| Rebuilds | the target last applied by hand: `camilo` (`./rebuild.sh`) or `camilo-total` (`./rebuild-total.sh`) | same: `camilo-remote` or `camilo-remote-total` |

Pieces:

- `nix/configuration.nix` - the `org.dotfiles.auto-rebuild` launchd daemon
  (`launchd.daemons.auto-rebuild`), shared by every flake target. It passes the
  machine's user and the target's own flake attr (`flakeAttr` from `flake.nix`)
  to the script, so the daily run keeps applying whichever of `./rebuild.sh` or
  `./rebuild-total.sh` you ran last. Switching variants is just running the
  other script once.
- [`scripts/auto-rebuild.sh`](../scripts/auto-rebuild.sh) - the logic, run as
  root.

Each run:

1. Fast-forwards `~/github/dotfiles` and `~/github/firstmate` as the user
   (`git pull --ff-only`). A repo that cannot fast-forward (diverged, or local
   edits that conflict) is left untouched and you get a notification; the
   rebuild then uses what is already checked out. A repo that is not cloned is
   skipped.
2. Runs `darwin-rebuild switch` for the machine's flake attr.

A rebuild already updates everything else on every run:

| What | How |
|---|---|
| Homebrew formulae and casks | `homebrew.onActivation.upgrade = true` |
| Pi, quota-axi, gh-axi, tasks-axi, and the other npm CLIs | reinstalled at `@latest` from `nix/agent-tools.manifest.lock.json` |
| Pi extensions | `pi update --extensions` |
| no-mistakes, treehouse | their own self-updaters |

Not updated: Nix packages pinned in `flake.lock`. Bumping those is the change
most likely to break a rebuild, so do it deliberately with `nix flake update`
and a manual rebuild.

## Logs and failures

- Log: `/var/log/auto-rebuild.log` (`tail -50 /var/log/auto-rebuild.log`).
- A skipped pull, a failed rebuild, a failed quota-axi reinstall, or a
  Homebrew package that could not be installed or upgraded posts a macOS
  notification titled "Daily rebuild" to the logged-in user.
- One Homebrew package failing (say, a cask whose download the vendor pulled)
  does not fail the rebuild: everything else is still applied, the log gets a
  `homebrew: could not install or upgrade: <names>` line, and the next run
  retries it.
- Run it now instead of waiting:
  `sudo launchctl kickstart system/org.dotfiles.auto-rebuild`.
- Check it is loaded: `sudo launchctl print system/org.dotfiles.auto-rebuild`.

## Enabling it on a machine

Every target includes the daemon, so one manual `./rebuild.sh` (or
`./rebuild-total.sh`) on a machine installs everything and enables the daily
update for that same target. On a new machine, after `setup/mac.sh`:

    cd ~/github/dotfiles && ./rebuild.sh

## Trust trade-off

The daemon pulls this public repo's `main` and applies it as root with no
review step. Anything pushed to `main` - by you, an agent, or a compromised
GitHub account - reaches both machines by the next morning. That is the price
of not running rebuilds by hand. To stop it, remove
`launchd.daemons.auto-rebuild` from `nix/configuration.nix` and rebuild.

## Design notes

- **The plist points at the script by path, not through the Nix store.** A
  store path changes whenever the script changes, which changes the plist, and
  activation then reloads the daemon - killing the very rebuild that is running
  it. A fixed path keeps the plist stable. `AbandonProcessGroup` is a second
  guard if launchd does reload it mid-run.
- **Root, not a passwordless sudo rule.** A `NOPASSWD` rule for
  `darwin-rebuild` would let any process running as the user become root by
  pointing it at its own flake. A root daemon running one fixed command does
  not open that door.
- **The rebuild runs with `SUDO_USER`/`SUDO_UID` set to the machine's user**,
  the same environment `./rebuild.sh` gets from `sudo`. Without them, Nix
  running as root refuses the user-owned repo ("repository path ... is not
  owned by current user") and every daily rebuild fails.
- **App Store apps are upgraded by the daemon itself, before the rebuild.**
  `mas` needs root to install or upgrade, and during activation `brew bundle`
  runs it as the user, so any outdated App Store app would ask for a sudo
  password nobody can type and fail the rebuild. The script runs the
  root-owned Nix `mas upgrade` (`/run/current-system/sw/bin/mas`, from
  `environment.systemPackages`) inside the user's login session first. Never
  point it at Homebrew's `mas`: that binary is user-writable.
- **Homebrew failures warn instead of aborting activation.** nix-darwin runs
  `brew bundle` under `set -e`, so one failed download used to stop activation
  before Home Manager, the MAS cleanup, and linking the new generation
  (ChatGPT's cask 404, 2026-10-08/09). `nix/configuration.nix` replaces
  nix-darwin's Homebrew step with the same `brew bundle` command whose failure
  only warns; the script parses the `... has failed!` lines to report them.
  Re-check that override against nix-darwin's `modules/homebrew.nix` when
  bumping `flake.lock`.
- **`--ff-only` pulls.** The job never merges, rebases, or resets; anything
  that needs a decision is left for a human and reported.

## Temporary: quota-axi Antigravity fix

`quota-axi@latest` cannot score Antigravity quota, so Firstmate's Jev resolver
never picks Antigravity models (see `kunchenguid/quota-axi#308`). Until that
fix ships in an npm release, every rebuild - manual or daily - runs
[`scripts/agent-tools/quota-axi-agy-fix.sh`](../scripts/agent-tools/quota-axi-agy-fix.sh)
from the `quotaAxiAgyFix` activation in `nix/home.nix`, which rebuilds and
reinstalls the fix from `~/github/quota-axi` whenever the installed build lacks
it. Once a release contains the fix it does nothing; delete the script, the
activation entry, and this section then.
