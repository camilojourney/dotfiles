# Private Pi Durable installation and pilot

For current everyday use, start with the [quickstart](AGENT-PLATFORM-QUICKSTART.md).
The separate [fresh Langfuse runbook](AGENT-PLATFORM-LANGFUSE.md) covers its
SSD-backed container VM and synthetic-only tracing boundary.

This is an opt-in infrastructure trial, not a replacement for native Pi,
Firstmate, second mates, or their authority/delivery records. Do not import old
sessions or replay their tools. Existing services and global settings stay intact.

## Install and initialize

Use a fresh owner-only directory on an ownership-enabled local filesystem.
Keep runtime state, dependency caches and evidence outside this repository.
The pilot uses the exact dependencies/integrities in
[`package-lock.json`](../services/agent-platform/pilot/package-lock.json),
Node >=22.19.0 and macOS `/usr/bin/shlock`.

```sh
cd services/agent-platform/pilot
npm ci --ignore-scripts --no-audit --no-fund
npm test
node cli.mjs /absolute/private/new-store init read
node cli.mjs /absolute/private/new-store inspect read
node cli.mjs /absolute/private/new-store resume read
```

The parent of `new-store` must already be canonical and owner-only. Initialization
refuses collisions. Recovery refuses a missing store, wrong registry/scenario,
changed fixtures, unsafe paths, or another live owner. Do not delete an ownership
lock to bypass refusal. Native `shlock` may briefly refuse a newly dead owner's
lock; the adapter polls native acquisition for at most two seconds.

Only two fixed public text fixtures are readable/searchable. No shell, arbitrary
paths, native extensions, browser, research submission, worker launch or forge
operation is exposed. This is a capability boundary for these tools, not an OS
sandbox against trusted host code or another process using the same account.

## What the trial tests

`npm test` owns and SIGKILLs only its children at explicit committed boundaries:
model partial, queued follow-up/steer admission, before/after tool intent and
safe-read completion. It reopens the same store, reacquires the stored submission,
and checks committed views, compaction/instruction continuity, unchanged-key
admission and changed-payload refusal. A concurrent-live-owner negative control
must refuse. Test scratch is retained outside Git for inspection.

Mutating controls are skipped unless read-only recovery passes. Exactly one
mutation type exists: a harmless immutable keyed artifact under the trial's own
`artifacts/`. The target atomically publishes a receipt, reconciles identical
bytes and refuses conflicts rather than overwriting another writer. The
side-effect-before-result crash test distinguishes invocation count from logical
effect count. A separate unsafe-policy control must report interruption without
running again. This is not arbitrary-tool exactly-once I/O.

## Actual models and tracing

A separately authorized mini invocation may use `init real` once. It selects only
`openai-codex/gpt-6.1-sol`, using the installed Pi credential-store API. It neither
copies credentials into the store nor loads native provider/tool extensions.
Its public-fixture read terminates the run; automatic real-model replay is
refused. Catalog presence alone is not authentication. Keep credential files,
authorization headers and provider error bodies out of logs and Git.

Execution output is correlated synthetic metadata: identities, submission/entry
IDs, checkpoints, tool-error counts and outcome. This is not live Langfuse/API/UI
qualification. Global exporter/content and key-rotation policy remain unchanged.

## SSH connection loss and restart

SSH is the interface, not the owner. The mini must remain powered, awake and
online. Laptop-only apps/files still require the laptop. No new server API,
network database mount or Tailscale service is introduced.

[`pilot-job.plist.in`](../services/agent-platform/pilot-job.plist.in) is a temporary
native launchd acceptance job for an already admitted synthetic `delay` store.
Render its tokens to new private paths and an unused label only. It resumes that
store, restarts on failure, caps each output file at 1 MiB, and exits after success.
It is not a general production daemon. The private operational receipt records
its tested PID ownership, dedicated-client disconnection and native restart.

Connect a dedicated metadata viewer using SSH, disconnect only that client,
then reconnect and inspect the completed store after its owner exits. Never close
this machine's main session or kill an existing endpoint. Stop only the exact
new job using `launchctl bootout gui/UID/NEW_LABEL`; archive its new definition
outside LaunchAgents so it does not run on a future login. Preserve its stores.
Process restart proof does not establish host reboot or power-loss recovery.

## Backup, restore and rollback

After the pilot owner exits:

```sh
node backup.mjs /absolute/private/source /absolute/private/new-snapshot
```

This holds the same owner lock and uses Node's SQLite backup API, including
committed WAL state. The isolated backup regression keeps a synthetic writer
connection open with a nonempty committed WAL and verifies that the restored
snapshot contains that commit without scheduling effects. This is not permission
to run two Harness owners against one store.

Do not hot-copy a bare live SQLite file. Transfer only the
closed snapshot to a separate device over existing SSH. For example, with
private paths chosen on each host:

```sh
ssh mac-mini 'COPYFILE_DISABLE=1 tar -C "$SNAPSHOT_PARENT" -cf - snapshot' > backup.tar
```

Disable macOS copyfile metadata so AppleDouble sidecars do not masquerade as
artifact files. Verify database hashes before inspection. Restore to a new
owner-only directory, run `inspect` first with the same pinned code/registry,
and compare messages, submissions, app documents and pending unsafe operations.
Inspection never resumes effects. Reconcile pending operations and destinations
before any later explicit resume; do not let a restore act on the original target.

A laptop backup is a separate device from the mini source, but requires the
laptop online. No successful backup is implied while it is offline. No automatic
retention, offline copy, deletion schedule or production backup SLA is configured.
Keep the original store and receipts for rollback. Rollback stops only the new
pilot owner and leaves native agents/services untouched; do not blindly resend
an uncertain mutating operation through native Pi.

## Storage deployment boundary

The original external SSD is not a private runtime merely because a new folder
has mode 0700. It must not receive private pilot state while ownership is ignored.
The authored [storage gate](../scripts/agent-platform/require-ssd.py) validates the
actual mounted UUID before executing any supplied command and creates no paths
or logs before checking. Its check-only launchd template is not an agent service.
The encrypted central installation below is a separate, explicitly gated phase.
The gate also requires that the volume itself is encrypted and unlocked; container
or sibling-volume encryption does not satisfy it.

## Central mini installation

The small central terminal uses the same pinned Durable package, model and
public-fixture read/search boundary. It is a useful infrastructure workbench,
not a general coding agent or a transparent replacement for native Pi. No
historical session or artifact-writing tool is loaded. It admits commands
straight into upstream submissions, not a second execution queue.

### Storage and initialization

Create a **new encrypted APFS volume** in the verified external container, not a
folder on the old noowners volume. Have the operator run `diskutil apfs addVolume
CONTAINER APFS AgentPlatform -passprompt` interactively with the required admin
authority, then `sudo diskutil enableOwnership /Volumes/AgentPlatform`. Reverify
the physical device/container immediately before creation. Do not change the old
volume, put a passphrase in argv, or store it in dotfiles/logs. Record the new
volume UUID, encryption/unlocked state and ownership by reading back `diskutil
info -plist /Volumes/AgentPlatform`. A locked volume requires operator unlock;
this installation does not store an unlock secret or promise unattended reboot.

Only after that readback, create a new owner-only `agent-platform` child and its
`state`, `state/pi`, `state/pi/terminal`, `state/langfuse`, `artifacts`, `logs` and
`plans` directories. All must be canonical, owned by the service account and on
the same verified device. The `state/langfuse` compatibility directory starts no tracing
service; fresh tracing storage belongs in `langfuse/engine` as described by the
separate runbook. Save the private plan under `plans/rollout.md` on this **new** volume,
not the original SSD volume.

Install the exact pilot package/lock into a new private mini code directory,
along with `require-ssd.py` and `launch.c`; do not modify the pilot installation
for this phase.
Keep code/config on private internal storage so missing-SSD refusal is executable.
Create a new mode-0600 private `volume.json` outside Git:

```json
{
  "mountpoint": "/Volumes/AgentPlatform",
  "volume_uuid": "REPLACE_WITH_READ_BACK_UUID",
  "root": "/Volumes/AgentPlatform/agent-platform",
  "minimum_free_bytes": 2147483648
}
```

Initialize explicitly once, with real paths substituted:

```sh
python3 "$CODE/require-ssd.py" "$CONFIG" -- \
  "$NODE" "$CODE/central.mjs" "$ROOT/state/pi/central" init
```

`init` admits no model request. Restart uses only `serve`, which refuses a missing
store and never silently initializes elsewhere. Read/search are replay-safe;
central recovery deliberately resumes only this fresh restricted store. The
one-shot pilot's automatic real-model resume restriction stays unchanged.

### Start, connect, stop

Build a dedicated launcher into a **new** private runtime directory inside this
installation. Do not make a shared Homebrew Python/Node executable the job's
responsible program or grant it broad access. With real private paths selected:

```sh
mkdir -m 700 "$INSTALL/runtime"
/usr/bin/clang -std=c17 -Wall -Wextra -Werror -pedantic \
  "$CODE/launch.c" -o "$INSTALL/runtime/agent-platform-durable"
/usr/bin/codesign --force --sign - --identifier local.agent-platform.durable \
  --timestamp=none "$INSTALL/runtime/agent-platform-durable"
chmod 500 "$INSTALL/runtime/agent-platform-durable"
/usr/bin/codesign --verify --strict "$INSTALL/runtime/agent-platform-durable"
shasum -a 256 "$CODE/launch.c" "$INSTALL/runtime/agent-platform-durable"
```

Record the source head/hash, compiler identity and final signed binary hash in a
private receipt; verify the installed hash before loading its job. This tiny
exec-only launcher preserves PID and arguments. It is a responsibility identity,
not an OS sandbox, agent API or durability engine. A dedicated identity keeps the
one-time macOS permission separate from shared interpreters and other services.

Render [`central-job.plist.in`](../services/agent-platform/central-job.plist.in)
with XML-escaped absolute `LAUNCHER`, `PYTHON`, `NODE`, `CODE`, `CONFIG` and `ROOT` paths into a
**new** owner-only `~/Library/LaunchAgents/dev.agent-platform.durable.plist`.
Never overwrite a pre-existing job. Validate with `plutil -lint` before loading.

```sh
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/dev.agent-platform.durable.plist"
launchctl print "gui/$(id -u)/dev.agent-platform.durable"
```

On the first launchd start, macOS can ask on the mini's display whether
`agent-platform-durable` may access files on a removable volume. An operator must
approve that single **Removable Volumes** prompt for the dedicated installed
binary, using Screen Sharing if necessary. Do not change privacy settings or the
TCC database automatically, grant shared Python/Node Full Disk Access, or assume
SSH access grants launchd the same permission. Until approval the native process
can wait without creating a worker/socket; this is not evidence of Durable
corruption. Verify the responsible binary in scoped TCC logs before asking for
approval; no secret or encryption passphrase is needed for this permission.

The guard runs before native `/usr/bin/screen -D -m` creates its terminal. Screen
stays in the foreground of launchd; the dedicated socket directory is on the
verified volume. No network listener, server API, shared screen namespace or
network SQLite mount is introduced. KeepAlive restarts the new job, throttled to
30 seconds. Missing/locked/wrong/noowners storage refuses every start without
creating fallback paths. Mount removal **after** startup is not monitored; stop
the service before unmounting. Filesystem free-space checks are startup reserves,
not a runtime storage quota.

Connect from the laptop, including over the existing Tailscale SSH route:

```sh
ssh -t mac-mini 'env SCREENDIR=/Volumes/AgentPlatform/agent-platform/state/pi/terminal /usr/bin/screen -r agent-platform'
```

Enter `status` for correlated metadata, or a stable request key and public-fixture
instruction, such as `check-1 Read alpha.txt using read.` Repeating an identical
key and payload reuses its upstream submission; changing bytes refuses. Only
public-fixture instructions belong in this terminal. Output suppresses model
responses and raw provider errors. Detach with `Ctrl-a d`, or disconnect SSH;
neither is the owner. The mini must remain powered, awake, online and mounted.
Laptop-only applications/files still need the laptop awake.

Persistent stdout/stderr are discarded (zero disk-log growth); screen scrollback
is bounded to 200 lines in memory. Status and the Durable store are the results
interface. A per-process file-size limit would also cap SQLite and is deliberately
not used as log rotation. This is not Langfuse qualification.

Stop **only** the new service before maintenance:

```sh
launchctl bootout "gui/$(id -u)/dev.agent-platform.durable"
```

Archive its task-owned definition outside LaunchAgents if disabling future login
startup. Do not stop screen globally, alter other agents, delete the volume, or
remove a lock to bypass ownership. Starting again uses the same rendered job and
existing store. Reboot acceptance needs separate coordination.

### After a mini restart with the volume locked

This is a user LaunchAgent: it loads when the service account logs in, not before
login. If the encrypted volume is still locked or absent, the guard refuses and
launchd retries at most once per 30 seconds. No empty store or terminal socket is
created on internal storage. Existing committed work stays on the encrypted
volume, but cannot resume while that volume is locked. SSH detachment during
normal mounted operation does not have this limitation.

An operator holding the passphrase must unlock the **recorded volume UUID**, not
a possibly renumbered `diskNsM`, using an interactive command. Never supply
`-passphrase`, pipe a secret through this agent, or add an unlock secret to Git:

```sh
ssh -t mac-mini 'sudo diskutil apfs unlockVolume RECORDED_VOLUME_UUID'
```

Then read back mountpoint, UUID, encryption and ownership; run the storage check
with the installed private config. If the job is already loaded, its next retry
opens the same existing store; `launchctl kickstart gui/UID/dev.agent-platform.durable`
can request an immediate retry. If it was not loaded after login, use the normal
bootstrap command instead. This is not unattended boot recovery, automatic
unlock, or a tested host-reboot guarantee. Laptop-offline periods also mean no
laptop backup, even if the mini continues executing normally.

### Central backup and rollback

Stop the new service, use `backup.mjs` to create an unused snapshot directory on
the verified volume, and transfer that closed snapshot to a new mode-0700 laptop
backup directory using the SSH/COPYFILE_DISABLE procedure above. Compare hashes
and restore into another new owner-only laptop directory; use the same pinned
`cli.mjs RESTORED inspect real` with no effects dispatched. Verify identities,
requests, entries, fixture hashes, pending tasks and SQLite integrity before any
resume. A backup command refuses while another owner holds the source.

Bootstrap the service again after backup. This manual procedure requires the
laptop online; no scheduled/offline backup or automatic retention is claimed.
Keep original central stores and receipts intact. A synthetic pilot may be retired
only with explicit authority, no remaining references and independently verified
archival of its stores/evidence. Keep the archived pilot source and laptop backups.
Rollback unloads only the
new job and preserves its definition/state for reconciliation; native agents,
original SSD data and existing tracing remain unaffected.

The [technical contract](../specs/agent-platform.md) owns these interfaces.
Private host inventories, source hashes, actual test history and operational
receipts belong in the task delivery report, never in this public repository.
