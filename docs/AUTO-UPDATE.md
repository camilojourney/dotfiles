# Daily system updates and weekly agent pins

Both Macs run `org.dotfiles.auto-rebuild` at **05:00 local time daily** (or
next wake). The system lane stays daily; agent tools do not follow `latest`.

| | Laptop (`camiloslaptop`) | Mac mini (`camilo_mini`) |
|---|---|---|
| Pulls daily | `~/github/dotfiles`, `~/github/firstmate` | same |
| Target | last applied: `camilo` or `camilo-total` | last applied: `camilo-remote` or `camilo-remote-total` |
| Agent pin promotion | consumes passed pins with normal daily pull, normally Monday after Sunday's mini run | Sunday, after the daily system rebuild |

`rebuild.sh` and **`rebuild-total.sh` are in the repository root**. On the mini
these select `camilo-remote` and `camilo-remote-total`; on the laptop they select
`camilo` and `camilo-total`. Run the variant you want to keep using nightly.

## Owners and daily behavior

- `nix/configuration.nix`: root launchd daemon, fixed script path and 05:00 schedule.
- [`scripts/auto-rebuild.sh`](../scripts/auto-rebuild.sh): recovers interrupted
  pin transactions as the user, then fast-forwards both repos as the user,
  upgrades App Store apps with root-owned `mas`, and runs `darwin-rebuild switch`.
- `nix/agent-tools.manifest.lock.json`: exact top-level npm, uv, global Python,
  external release versions/checksums and Pi npm package pins.
- [`scripts/agent-tools/reconcile.sh`](../scripts/agent-tools/reconcile.sh):
  installs the declared versions on every rebuild. No npm `@latest`, uv
  upgrade, pip upgrade, or external self-updater. Undeclared Homebrew Python
  libraries still get removed; projects use their own environments.
- `nix/agent-toolchain.nix`: pin overlay and activation overrides, imported
  alongside `nix/home.nix` without changing it. It disables the former local
  quota-axi reinstall and the independent extension update activation.

Homebrew formulae/casks (`homebrew.onActivation.upgrade = true`) and App Store
apps still update daily. Chrome remains self-updating. Nix packages stay pinned
by `flake.lock`; update that deliberately with `nix flake update`.
**Firstmate's own daily pull is unchanged.** Moving it to a separate tested
weekly lane remains an open option, not part of this implementation.

### Pi settings without editing the authored file

`home/.pi/agent/settings.json` remains the authored preferences and package list,
including any uncommitted edits. The pin overlay reads that file and substitutes
exact npm versions from `piPackages` in the manifest, preserving other fields and
package resource filters. Git packages require immutable 40-character commit
refs; local checkouts remain local (not silently downloaded or upgraded).
Unrecognized npm packages fail closed until added to the manifest.

Home Manager links `~/.pi/agent/settings.json` to the writable effective file
`~/.local/state/agent-tools/pi-settings.json`. Neither rendering nor Pi writes
modify the authored git file. Put durable preference changes in the authored
file: the effective copy is regenerated on rebuild. Reconciliation checks that
this link is active, snapshots validated authored sources, and explicitly runs
`pi install <exact-source> --no-approve` for each remote package. This both
installs changed pins (Pi 1.4's broad updater skips pinned npm packages) and
ignores unpinned project declarations or concurrent session settings writes.
It then restores authored resource filters. No broad `pi update --extensions`
runs in activation; running it manually retains explicitly pinned versions.
`PI_SKIP_VERSION_CHECK=1` is in the managed user environment and update/smoke
processes, silencing Pi's latest-version notice.

Local package paths are not made portable by pinning. In particular, the
laptop-only telemetry path and maintained compaction checkout remain subject to
[the reproduction runbook](AUTOMATIONS.md#reproduce-native-agents-on-another-mac).
A pin build does not establish that those packages load on the mini.

## Sunday promotion, unattended

The mini's existing daily daemon invokes
[`weekly.py --scheduled`](../scripts/agent-tools/weekly.py) **as `camilo_mini`**
after the Sunday rebuild. It shares the daemon's serialization instead of racing
a separate 05:00 launch agent. The laptop does not propose pins: its daily
fast-forward pull receives the mini's passed commit, normally Monday 05:00.
No agent, reviewer, model request or captain approval runs in this path.

1. Require a clean `main`, matching the daily pull's `origin/main` tracking ref,
   the expected fetch and push origin URLs, and a successful `git push --dry-run`
   authorization/fast-forward check. Missing credentials,
   a dirty tree or a branch from another task means notify and keep current pins.
2. Read public npm/PyPI publication dates and GitHub Releases (the external tools'
   package registry). Stable releases must be public at least **7 x 24 hours**;
   all PyPI files must have aged. No prereleases, yanked/deprecated releases or
   downgrades. MLX compatibility pins stay unchanged.
3. Query **OSV** for the current and proposed exact versions. A non-withdrawn
   advisory rejects the candidate. A fixed version explicitly identified by OSV
   for a current vulnerability may bypass the age wait, but must itself pass OSV.
   Registry/OSV errors fail closed. External candidates need GitHub's sha256
   digests for both Darwin platforms. Only the latest 100 external releases are
   considered; missing old metadata means no bump, not an unverified download.
4. Journal the previous commit and pin digest, write and commit **only the
   manifest**, then run the existing reconciler in strict mode. Installs occur
   in the existing user-owned locations; nothing installs as root in this lane.
5. Smoke-check Pi, quota-axi, tasks-axi and gh-axi `--version` and `--help`, each
   with a timeout. Pi is offline; no worker or billable inference is launched.
6. Only after successful installation and smoke checks, push the pin-only commit
   to `origin main`. The laptop never receives an untested candidate from this job.

The job's only new network dependencies are package registries (including
GitHub Releases and pinned Pi Git sources), OSV and Git transport. The existing
daily system lane retains its existing network behavior. Registry traffic and
subprocesses are bounded by timeouts. These are **top-level pins**, not a
vendored lock of every transitive dependency or a guarantee that OSV knows every
vulnerability. A smoke pass establishes startup, not worker task quality.

### Credentials and repository safety

Use the mini user's existing Git credentials and commit identity. No credential
is stored in dotfiles or created/copied by the job. Git is noninteractive, SSH is
batch-only, and authorization is checked **before changing pins or installs**.
If it is absent, sign in to GitHub as the mini user using your normal credential
setup and enable that account's HTTPS Git credential helper (or authorized SSH
key) for `camilojourney/dotfiles`. Do not put a token in a remote URL or this repo.
`gh-axi api repos/camilojourney/dotfiles --jq '.permissions.push'` can confirm the
account's permission, but permission alone is not proof that Git's helper works.

No force push, merge, rebase or hard reset is used. Ordinary pulls remain
`--ff-only`; divergence and conflicting edits are left untouched. A concurrent
user edit/commit during promotion stops automatic recovery rather than erasing
it. Do not hand-edit the checkout during a scheduled pin transaction.

## Failure and rollback

Any selection, authorization, install, smoke or push failure notifies macOS.
After a candidate install begins, rollback restores the previous manifest and
removes only the job's own pin-only local commit using compare-and-swap ref
update, then reinstalls and smoke-checks the previous pinned set. A rollback
failure retains `~/.local/state/agent-tools/transaction.json` for retry and
reports recovery required. Daily rebuilds recover **before pulling or switching**;
they stop if recovery cannot finish, rather than activating a partial candidate.
Power loss is handled by that same journal. A crash or lost Git response just
after a successful push can roll back locally first; the subsequent fast-forward
pull reapplies the already-passed remote pins. No remote history is rewritten.

To retry an interrupted transaction as the normal user:

```sh
python3 ~/github/dotfiles/scripts/agent-tools/weekly.py --recover
```

If recovery reports concurrent edits or a different branch, preserve those edits
and inspect the journal's `base` before intervening. Do not delete the journal
or reset the checkout blindly. For an already published bad pin commit, make a
normal manifest-only revert on main, validate and push it, then run the usual
rebuild on each host. This preserves the auditable history and daily fast-forward
path; do not roll the entire repository backward.

## Inspection and proof

Read-only checks (no package installs, switches or model calls):

```sh
bash scripts/agent-tools/check-pins.sh  # real registries + OSV, writes no pins
python3 scripts/agent-tools/smoke.py
python3 tests/agent_toolchain_test.py
bash tests/agent_tools_test.sh
nix build .#darwinConfigurations.camilo-total.system .#darwinConfigurations.camilo-remote.system --no-link
```

A build is **not** an applied rebuild. Activation and the first Sunday promotion
are only proven after running on the mini. The existing local-package portability
constraints also need the normal host acceptance checks.

After pulling the delivered change on the mini (currently `main`, plain remote
target):

```sh
git -C ~/github/dotfiles pull --ff-only origin main
( cd ~/github/dotfiles && ./rebuild.sh )
```

Use `./rebuild-total.sh` in that same directory only if deliberately adopting the
extra-app target. A manual rebuild enables the daemon for the variant you chose.

## Logs and trust

- Daily and weekly output: `/var/log/auto-rebuild.log`.
- Check daemon: `sudo launchctl print system/org.dotfiles.auto-rebuild`.
- Run a daily cycle now: `sudo launchctl kickstart system/org.dotfiles.auto-rebuild`.
  On Sunday on the mini this also attempts promotion; it is not read-only.
- A skipped pull, failed rebuild/promotion/recovery, or Homebrew package failure
  posts a macOS notification. Homebrew install failures still warn rather than
  stopping the other system activation steps and are retried next day.

The daemon pulls this public repo's main and applies it as root without a review
step. Anything pushed to main reaches both machines unattended; local commits
and edits can also activate when a pull is skipped. Keep unservable package pins
out of that checkout. The mini is now also trusted to publish manifest-only
commits after its checks. To disable all unattended system updates, remove the
`launchd.daemons.auto-rebuild` declaration and rebuild.

The plist intentionally points to the script by a fixed checkout path, not a
changing Nix store path, so activation does not reload launchd and kill its own
rebuild. The daemon sets `SUDO_USER`/`SUDO_UID` for the user-owned repository and
App Store account. It upgrades App Store apps with root-owned Nix `mas` inside
the user's login session; never substitute a user-writable `mas` for that step.
