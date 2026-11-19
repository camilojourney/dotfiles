# Daily system updates and weekly agent pins

**No schedule runs this.** The former `org.dotfiles.auto-rebuild` launchd daemon
(05:00 daily) is removed from `nix/configuration.nix`; the update is run
**manually** with `scripts/auto-rebuild.sh` (or `./rebuild.sh` / `./rebuild-total.sh`).
Agent tools do not follow `latest`. Where this page says daily, nightly or
05:00, read it as the cadence of that manual run.

| | Laptop (`camiloslaptop`) | Mac mini (`camilo_mini`) |
| --- | --- | --- |
| Pulls daily | `~/github/dotfiles`, `~/github/firstmate` | same |
| Target | last applied laptop variant | last applied mini variant |
| Agent pins | daily pull, normally Monday | Sunday after system rebuild |

`rebuild.sh` and **`rebuild-total.sh` are in the repository root**. On the mini
these select `camilo-remote` and `camilo-remote-total`; on the laptop they select
`camilo` and `camilo-total`. Run the variant you want to keep using nightly.

## Owners and daily behavior

- `nix/configuration.nix`: no longer declares a daemon or schedule for this.
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

The weekly lane covers only the declared agent-tool pins, not Chrome or all
applications/dependencies.

| Lane | Update owner and cadence |
| --- | --- |
| Homebrew formulae and unpinned casks | Homebrew, daily activation |
| App Store apps | App Store via `mas`, daily |
| Regular Google Chrome | Google, native security-update cadence |
| Declared agent-tool pins | Weekly promotion below, OSV security exception |
| Nix packages | `flake.lock`, deliberate update |

`homebrew.onActivation.upgrade = true` still upgrades unpinned casks daily,
including Chrome Canary. Update Nix pins deliberately with `nix flake update`.
**Firstmate's own daily pull is unchanged.** Moving it to a separate tested
weekly lane remains an open option, not part of this implementation.

### Regular Chrome: one updater, coordinated relaunch

Keep `google-chrome` declared and `homebrew.onActivation.cleanup = "uninstall"`:
removing the declaration would uninstall Chrome, not hand it to Google. The
existing Homebrew activation installs Chrome only if missing, then applies and
verifies `brew pin --cask google-chrome` **as the Homebrew user before Bundle**.
The pin is reapplied on every activation, including first bootstrap and an
already-installed browser. It excludes regular Chrome from both Bundle upgrades
and ordinary `brew upgrade`, including explicitly named Chrome upgrades. It is
**not a browser-version freeze**: Google's native updater stays enabled and owns
regular Chrome security updates. `google-chrome@canary` is unchanged; do not pin
that channel without verifying its use and native updater health.

Google's updater can update files while Chrome runs, retaining in-use versions;
relaunch activates fixes in running processes. The browser/workflow owner must
coordinate an orderly relaunch **within 48 hours of an update**. When Google
marks a security fix as **exploited in the wild, relaunch the same day** rather
than waiting for that deadline or the weekly agent lane. Keep Google's default
update checks and relaunch prompts enabled. Preserve unsaved work and active
research receipts first, coordinate all profiles/processes using that app, then
verify the affected workflows after relaunch. There is no forced restart,
managed Chrome policy, new scheduler or new service enforcing this deadline.

A Homebrew pin does not protect against explicit unpin/reinstall, a vendor
DMG/pkg replacement, restore, another management tool or a channel change. Those
are owner-authorized maintenance only: identify and quiesce all processes using
the app before replacement. Do not bypass the native updater with a fallback
installer while Chrome runs, or downgrade a browser against a newer profile.
If native updating is unavailable, arrange prompt owner-authorized repair rather
than leaving the browser indefinitely pinned and unpatched.

If the Chrome install/pin/verification fails, activation **skips the entire
Homebrew Bundle step** to avoid unsafe replacement, logs
`Pinning google-chrome has failed!`, and continues other activation steps. The
daily job posts its existing Homebrew failure notification and retries next run;
a successful system rebuild alone does not establish a successful pin or update.
Check `/var/log/auto-rebuild.log` for the underlying error. Manual activation
shows the same warning in its output.

Installed app version, Homebrew's cask receipt, Google's updater record and the
already-running browser version can differ. A pull is not an activation; an
installed security update is not proof the running browser has relaunched onto
it. Read-only checks include `brew list --cask --pinned google-chrome`, the
GoogleUpdater launch-agent/log state on each host, and the installed Chrome
bundle version. Check runtime version only through an owned browser/profile;
notifications and startup smoke tests do not prove real-workflow acceptance.

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
processes, silencing Pi's latest-version notice. Install and smoke processes also
set `PI_TELEMETRY=0`, so this update lane sends no Pi install/update telemetry;
this does not change the user's interactive telemetry preferences.

Local package paths are not made portable by pinning. The home-relative
telemetry installation and maintained compaction checkout must exist on each host,
per
[the reproduction runbook](AUTOMATIONS.md#reproduce-native-agents-on-another-mac).
A pin build does not establish that those packages load on the mini.

## Manual tool update, on every rebuild

`./rebuild.sh` and `./rebuild-total.sh` update the agent command-line tool pins
as part of the rebuild, on either machine, on any day. It only happens when you
run a rebuild: nothing is scheduled. `--no-update-tools` skips it. The selection
is the Sunday lane's (`toolchain.select`), so every safeguard still applies:
stable releases only, public at least seven days (a fix for a known vulnerability
in the current pin may skip the wait), clean in OSV, registry sha256 digests for
external downloads, no downgrades.

- Only the npm and external lanes move (the agent CLIs and pnpm, no-mistakes,
  treehouse). Python and uv libraries stay on the Sunday lane, because a major
  jump there can break scripts that import them.
- Order: select and edit the manifest in place
  ([`update-now.py`](../scripts/agent-tools/update-now.py); run it alone with no
  flag to preview), rebuild, check with `update-now.py --verify` that every npm and
  external tool is installed at its pin, then run the same
  [`smoke.py`](../scripts/agent-tools/smoke.py) check as the Sunday lane.
- Offline or a registry/OSV error: the rebuild warns and continues with the
  current pins. The manifest is never touched.
- A failed rebuild, or installed versions that miss the pins (a rebuild can stop
  early and still return), restore the previous manifest. A failed smoke check
  restores it and rebuilds again to reinstall the previous versions.
- Nothing is committed or pushed. The manifest shows as modified for you to review
  and commit. If the mini's Sunday lane has pushed a different manifest, restore the
  file with `git checkout nix/agent-tools.manifest.lock.json` before pulling.

## Sunday promotion, unattended

On the mini, `scripts/auto-rebuild.sh` (run by hand on a Sunday) invokes
[`weekly.py --scheduled`](../scripts/agent-tools/weekly.py) **as `camilo_mini`**
after the Sunday rebuild. It runs inside that one manual run instead of a separate launch agent. The laptop does not propose pins: its
fast-forward pull receives the mini's passed commit when run.
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
bash tests/chrome_update_test.sh  # effective activation, fake OS boundaries
bash tests/auto_rebuild_test.sh   # daily failure notifications, no live switch
nix build .#darwinConfigurations.camilo-total.system \
  .#darwinConfigurations.camilo-remote.system --no-link
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
extra-app target. The variant you rebuild last is the one to pass to `scripts/auto-rebuild.sh`.

## Logs and trust

- Output of `scripts/auto-rebuild.sh`: `/var/log/auto-rebuild.log` (no longer rotated automatically).
- Run an update now, as root: `sudo bash ~/github/dotfiles/scripts/auto-rebuild.sh <macOS user> <flake attr>`.
  On Sunday on the mini this also attempts promotion; it is not read-only.
- A skipped pull, failed rebuild/promotion/recovery, Homebrew package failure or
  Chrome pin failure posts a macOS notification. Homebrew install failures still
  warn rather than stopping the other system activation steps. A failed Chrome
  pin skips Bundle entirely, not just Chrome; both are retried on the next run.

The script pulls this public repo's main and applies it as root without a review
step. Local commits and edits can also activate when a pull is skipped. The mini
is still trusted to publish manifest-only commits after its checks.

The script sets `SUDO_USER`/`SUDO_UID` for the user-owned repository and
App Store account. It upgrades App Store apps with root-owned Nix `mas` inside
the user's login session; never substitute a user-writable `mas` for that step.
