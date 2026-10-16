# Private agent platform

## Scope

Kind: technical
Capability: agent-platform
Owns: Opt-in storage prerequisites, the restricted Durable terminal and fresh Langfuse trial.

This capability gates startup and hosts an isolated public-fixture Pi Durable
terminal plus a fresh synthetic Langfuse stack on macOS. It does not migrate
native agents or monitor a running mount.
Host identity and evidence belong in private storage, not dotfiles.

## Requirements

### Verify storage before executing

`req~agent-platform.storage-gate~2`

WHEN invoked, the gate SHALL refuse execution unless the configured APFS volume
UUID and mountpoint match, that volume is encrypted and unlocked, ownership is
enabled, and storage is writable.

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

### Own the central terminal

`req~agent-platform.central-terminal~1`

The central host SHALL admit keyed instructions through the same upstream
submission and payload-identity boundary, expose only public-fixture read/search,
and keep execution alive independently of the attaching SSH terminal.

Startup SHALL require an existing compatible store on the verified encrypted
volume; it SHALL NOT initialize a replacement store on restart.

Needs: impl, utest

### Scope the macOS privacy identity

`req~agent-platform.central-privacy-identity~1`

The central LaunchAgent SHALL start through a dedicated task-owned binary rather
than a shared interpreter as its responsible program. The installation SHALL
record the final binary hash and source identity before requesting approval.

The launcher SHALL exec an absolute argument vector without a shell or fork,
preserve the process identity and propagate the executed program's exit status.
Removable Volumes permission SHALL require explicit operator approval; the
installation SHALL NOT change privacy settings or store an unlock secret.

Needs: impl, utest

### Isolate and bound fresh tracing

`req~agent-platform.langfuse-isolation~1`

The fresh Langfuse trial SHALL publish only web access on mini loopback port 3000,
with digest-pinned images, container memory limits totaling at most 5 GiB and bounded logs.

The trial SHALL NOT migrate existing data, switch producers, expose database ports
or enable its vendor telemetry.

Needs: impl, utest

### Keep service credentials out of process arguments

`req~agent-platform.langfuse-credentials~1`

The fresh stack SHALL supply secrets through private files or container environment,
not expanded process arguments; Redis SHALL read its password from an owner-only
configuration file.

Needs: impl, utest

### Preserve query worker progress

`req~agent-platform.langfuse-query-pool~1`

The trial SHALL retain ClickHouse's vendor global-thread-pool default, bounding
server/container memory and concurrent-query admission separately rather than
constraining query workers beneath reserved background workers.

Needs: impl, utest

### Isolate the container engine

`req~agent-platform.langfuse-engine~1`

The trial VM SHALL use task-local SSD state and cache, a pinned base image,
4 CPUs, 6 GiB memory, no host-directory mounts and no additional network interfaces.

The VM SHALL forward only TCP port 3000 to host loopback and ignore other guest ports.

Needs: impl, utest

### Verify synthetic OTLP without content

`req~agent-platform.synthetic-otlp~1`

The probe SHALL send complete private metadata-only OTLP observations once over
loopback HTTP using internally read owner-only credentials and the v4 header,
without proxies or redirects.

The probe SHALL verify identities, hierarchy, source and absent input/output through
loopback v2 API readback, refusing responses above 2,000,000 bytes and never retrying
POST.

Needs: impl, utest

## Fresh Langfuse interface

`services/agent-platform/langfuse/compose.json` is a fresh, synthetic-only stack;
native Compose `extends` in adjacent `common.json` owns shared logging and app
connection settings. Its adjacent XML bounds ClickHouse beneath its container limit. Required secrets
are supplied through an owner-only untracked `.env`, never command arguments.
Docker Compose interprets this JSON as its native configuration format.
Application web/worker are 4.56.0, PostgreSQL 17.11, ClickHouse 25.12.11.4,
Redis 7 and MinIO, pinned to immutable image digests. Media upload through the
browser is not qualified: object storage remains internal to the container network.

`lima.yaml` is JSON-compatible YAML for task-local Lima 2.2.1, using native Apple
Virtualization and Docker 29.8.2 in a separate Linux guest. Set `LIMA_HOME`, `HOME`
and `TMPDIR` beneath the encrypted Langfuse engine directory for every invocation;
the Go download cache uses that process HOME. Linux named volumes reside inside
the SSD VM disk, not misleading empty host database directories. Guest root does
not authorize host root. Starting this trial is explicit, after the storage gate;
no shared OrbStack configuration or global Docker context is changed.

`scripts/agent-platform/synthetic-trace.py ENV_PATH BASE_URL mini|laptop` sends
one root plus two synthetic children to the fresh trial only. BASE_URL accepts
only `http://127.0.0.1:3000` or `http://127.0.0.1:3300`. It reads fresh keys from
an invoking-user-owned regular file with no group/other permissions, constructs
authentication internally and never prints it. No provider/model/tool payload is
instrumented. A successful POST followed by readback failure must be reconciled
with GET, not another POST: v4 does not supply arbitrary repeated-export deduplication.

Host memory pressure and existing application health are acceptance observations,
not an automatic runtime governor. A ten-minute synthetic test is not a production
sizing guarantee or evidence of native Firstmate integration.

## Storage gate interface

```text
python3 scripts/agent-platform/require-ssd.py /absolute/private/volume.json
python3 scripts/agent-platform/require-ssd.py /absolute/private/volume.json -- command args...
```

The JSON object supplies `mountpoint`, `volume_uuid`, `root`, and
`minimum_free_bytes`. The root must be the mountpoint's direct `agent-platform`
child. Required directories are `state`, `state/pi`, `state/langfuse`, `artifacts`
and `logs`, plus `state/pi/terminal` for the dedicated terminal socket.
Configuration and directory ownership must match the invoking UID;
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
reconciliation and is refused by the one-shot CLI. The central terminal is a
separate explicitly authorized read/search-only host for a fresh store; it
resumes its safe pending work with the existing model/registry. It never loads
historical sessions or enables the artifact tool.

`central.mjs ROOT init|serve` reuses the pilot's real-model public-fixture registry.
Initialization is an explicit separate operation and admits no work. Serve opens
an existing store and calls upstream `harness.resume()`. Input is `status` or a
1-64-character lowercase/digit/dash key, one space, and 1-4096 instruction
characters. Changed bytes under a key refuse; admission precedes acknowledgment.
The terminal processes commands serially. Unacknowledged input is not a durable
queue, and no arbitrary shell/paths/native tools are available.

The central launchd template first execs through the dedicated `launch.c` binary.
It runs the gate before foreground native screen, using an isolated SSD socket
directory and no user screen configuration. Scrollback is limited to 200 lines
in memory; stdout/stderr are not persisted. KeepAlive restarts any exit,
throttled to 30 seconds.

The launcher is a macOS responsibility identity, not an OS sandbox.
Trusted job arguments still own the command. Its installed binary is private, ad-hoc signed
with the dedicated identifier and hash-pinned in a private build receipt. The
operator approves the single Removable Volumes prompt for that installed binary,
not shared Homebrew Python or Node. Retaining screen supplies the SSH terminal;
no new API or durable execution queue is introduced.

The user agent loads at service-account login, not before login. It does not unlock encrypted volumes: after restart while locked it
refuses, retains the existing encrypted state and awaits an operator's interactive
UUID-targeted unlock before retrying. SSH attachment only views/types into this dedicated terminal. Stop only the new launchd label
before backup or unmounting; a locked/missing volume refuses rather than writing
elsewhere. No monitor, auto-backup, runtime quota or reboot guarantee is implied.

`backup.mjs SOURCE NEW_DESTINATION` holds the source lock, creates an offline
SQLite backup and copies bounded private fixture/artifact files. It refuses
existing destinations. Restored stores must be inspected before any deliberate
resume; pending effects must not be aimed at an original destination.
