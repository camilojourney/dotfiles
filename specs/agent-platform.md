# Agent platform storage gate

## Scope

Kind: technical
Capability: agent-platform
Owns: Opt-in storage prerequisites and the isolated public-fixture Durable pilot.

This capability gates startup and hosts one isolated public-fixture Pi Durable
trial on macOS. It does not migrate native agents or monitor a running mount.
Host identity and evidence belong in private storage, not dotfiles.

## Requirements

### Verify storage before executing

`req~agent-platform.storage-gate~1`

WHEN invoked, the gate SHALL refuse execution unless the configured APFS volume
UUID and mountpoint match, ownership is enabled, and storage is writable.

The gate SHALL require owner-only, same-volume, non-symlinked state directories,
an owner-only configuration file, and the configured free-space reserve before
executing the supplied argument vector.

Needs: impl, utest

### Restrict the pilot boundary

`req~agent-platform.pilot-boundary~1`

WHEN reopening a pilot, the host SHALL refuse missing, non-private, incompatible,
or concurrently owned stores before scheduling work.

The host SHALL restrict read/search to the immutable public fixture allowlist and
reject changed payloads under an already reserved admission key.

Needs: impl, utest

### Recover committed execution

`req~agent-platform.pilot-recovery~1`

The pilot SHALL use upstream Durable submissions, entries, documents and views as
its sole execution authority, preserving admission identity across process recovery.

The acceptance procedure SHALL prove read-only crash recovery before enabling its
mutating acceptance controls.

Needs: impl, utest

### Reconcile the keyed artifact

`req~agent-platform.pilot-effects~1`

WHEN the same artifact key and payload recur, the target SHALL reconcile the
existing immutable artifact without overwriting it; conflicting bytes SHALL refuse.

The pilot SHALL leave unsafe interrupted calls for reconciliation rather than
silently replaying them.

Needs: impl, utest

### Back up without resuming effects

`req~agent-platform.pilot-backup~1`

The backup operation SHALL exclude another store owner and use SQLite's backup API
to include committed WAL state.

WHEN inspecting a restored store, the pilot SHALL verify its identity without
dispatching pending model or tool operations.

Needs: impl, utest

## Storage gate interface

```text
python3 scripts/agent-platform/require-ssd.py /absolute/private/volume.json
python3 scripts/agent-platform/require-ssd.py /absolute/private/volume.json -- command args...
```

The JSON object supplies `mountpoint`, `volume_uuid`, `root`, and
`minimum_free_bytes`. The root must be the mountpoint's direct `agent-platform`
child. Required directories are `state`, `state/pi`, `state/langfuse`, `artifacts`
and `logs`. Configuration and directory ownership must match the invoking UID;
no group/other mode bits are allowed. Missing identity fields fail closed.

The gate reads the mounted device with macOS `/usr/sbin/diskutil info -plist`.
It creates no paths and writes no logs. With no command it checks once. With a
command it replaces itself, preserving arguments without a shell. Exit 1 means
refused prerequisites; exit 2 means invalid invocation. Diagnostics omit raw
configuration and subprocess output. Failure to execute the command propagates.

The launchd storage-check template invokes check-only mode once at login. It is
not a worker service, automatic recovery mechanism, or proof of container storage.
No launchd output paths point at the SSD, preventing launchd from creating a
fallback log before the gate runs. Mount removal after startup and power-loss
recovery require separate runtime-specific acceptance.

## Pilot interface

`services/agent-platform/pilot/cli.mjs ROOT init|resume|inspect SCENARIO` hosts one
new conversation; `init` requires an unused directory and `resume` requires its
existing compatible store. `inspect` opens without starting the scheduler.
Opening normalizes running recovery records without dispatching; inspection is
not a byte-for-byte read-only SQLite connection. Scenario is persisted identity,
not a model-supplied capability selector.

The pinned package lock owns dependencies. `app.pilot` owns registry/package
identity, fixture hashes and admission digest reservations. The reservation
commit precedes admission; acknowledgment follows admission. A crash between
those commits can reserve an unused key, but retrying unchanged content can
complete admission. Native Durable request IDs alone do not reject changed bytes.

Darwin `shlock` owns process exclusion. Reopening polls the same native atomic
acquisition for at most two seconds to accommodate its current-second freshness
protection. A live owner is never unlinked by the adapter. PID reuse can
conservatively refuse; this is not a distributed lease.

The artifact tool exists only in explicit synthetic keyed/unsafe scenarios.
An exclusive link publishes a fully written receipt in the task-owned target;
the receipt binds key, relative destination, payload and digest. The target,
not Durable, supplies effect deduplication. All other writes, shell, browser,
forge and fleet operations remain unavailable. Do not import old native sessions.

Real-model mode uses the existing installed credential-store API and exact
OpenAI Codex GPT 6.1 model, without loading native extension resources. Its read
tool terminates the run after one result. Real-model replay requires separate
reconciliation and is refused by the one-shot CLI.

`backup.mjs SOURCE NEW_DESTINATION` holds the source lock, creates an offline
SQLite backup and copies bounded private fixture/artifact files. It refuses
existing destinations. Restored stores must be inspected before any deliberate
resume; pending effects must not be aimed at an original destination.
