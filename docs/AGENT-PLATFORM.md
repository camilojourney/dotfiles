# Isolated Pi Durable pilot

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
committed WAL state. Do not hot-copy a bare live SQLite file. Transfer only the
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
Encrypted central storage is a separate, explicitly gated deployment phase.

The [technical contract](../specs/agent-platform.md) owns these interfaces.
Private host inventories, source hashes, actual test history and operational
receipts belong in the task delivery report, never in this public repository.
