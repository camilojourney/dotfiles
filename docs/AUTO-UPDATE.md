# Daily auto-update

Both machines update themselves every day, so nothing here needs a manual
`./rebuild.sh` to stay current.

## What runs

| | Laptop (`camiloslaptop`) | Remote box (`camilo_mini`) |
|---|---|---|
| When | 05:00 daily, or at the next wake if asleep | same |
| Pulls | `~/github/dotfiles`, `~/github/firstmate` | same |
| Rebuilds | `camilo-total` (same as `./rebuild-total.sh`) | `camilo-remote` (same as `./rebuild.sh`) |

Pieces:

- `nix/configuration.nix` - the `org.dotfiles.auto-rebuild` launchd daemon
  (`launchd.daemons.auto-rebuild`), shared by every flake target. It passes the
  machine's user and flake attr to the script.
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
- A skipped pull, a failed rebuild, or a failed quota-axi reinstall posts a
  macOS notification titled "Daily rebuild" to the logged-in user.
- Run it now instead of waiting:
  `sudo launchctl kickstart system/org.dotfiles.auto-rebuild`.
- Check it is loaded: `sudo launchctl print system/org.dotfiles.auto-rebuild`.

## Enabling it on a machine

The daemon only exists after one manual rebuild that includes it. Run once on
each machine:

- Laptop: `cd ~/github/dotfiles && ./rebuild-total.sh`
- Remote box: `cd ~/github/dotfiles && git pull && ./rebuild.sh`

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
