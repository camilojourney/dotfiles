# Fresh private Langfuse trial

This is **not** a migration of the laptop's tracing data or producers. It creates
an isolated synthetic project with fresh local credentials. Keep the laptop
instance, deferred key rotation and exporter-content decisions unchanged.
See the [quickstart](AGENT-PLATFORM-QUICKSTART.md) for everyday use and the
[storage/backup guide](AGENT-PLATFORM.md) for the encrypted-volume prerequisites.

## Runtime and storage

[`runtime.json`](../services/agent-platform/langfuse/runtime.json) owns the exact
Lima arm64 archive URL/hash. Download that official release with `gh-axi release
download`, verify SHA256 before extraction, and install it into a **new** private
`$ROOT/langfuse/engine/runtime` directory. Do not install a global engine, move
OrbStack's shared disk or change a global Docker context.

[`lima.yaml`](../services/agent-platform/langfuse/lima.yaml) owns the pinned Ubuntu
image, Docker engine/package versions and VM limits: native Apple Virtualization,
4 CPUs, 6 GiB RAM, 48 GiB sparse virtual disk, no host mounts or extra network.
It follows Lima's supported Docker-rootful provisioning inside the new guest.
The official Docker install script is fetched at provisioning time; its resulting
core engine/Compose/containerd/buildx versions are pinned, not a bit-for-bit OS build.

Set these variables for **every** invocation, substituting the verified root:

```sh
ROOT=/Volumes/AgentPlatform/agent-platform
ENGINE="$ROOT/langfuse/engine"
export LIMA_HOME="$ENGINE/lima" HOME="$ENGINE/home" TMPDIR="$ENGINE/cache"
LIMA="$ENGINE/runtime/bin/limactl"
```

Create these private directories only after the mounted UUID/encryption/ownership
checks. Confirm they are canonical, invoking-user-owned and on the same device;
never make an internal fallback path. Process HOME keeps Go's `Library/Caches/lima`
on the SSD. The VM instance directory, key material, engine logs, download cache
and VM disk must all remain there. Do not put secrets into the source YAML.

Validate before the one-time create:

```sh
"$LIMA" validate "$ENGINE/lima.yaml"
python3 "$CODE/require-ssd.py" "$CONFIG" -- \
  "$LIMA" --log-level warn start --name lf --tty=false --mount-none "$ENGINE/lima.yaml"
```

`CODE` and `CONFIG` are the private installed storage gate and UUID configuration,
not repository defaults. Restart the **existing** VM with `start lf`, never recreate
or initialize it. A missing/locked SSD fails the gate. No VM autostart job or host
reboot acceptance is configured; containers restart inside a running guest.

All Linux named database volumes live **inside** `lima/lf/disk`. Verify with host
`stat`/`lsof`, guest DockerRootDir/mounts and container mounts, not empty host
folders named after databases. Guest root does not grant host root.

## Fresh stack

Copy [`compose.json`](../services/agent-platform/langfuse/compose.json), its
[`common.json`](../services/agent-platform/langfuse/common.json) shared native
Compose definitions and [`clickhouse-memory.xml`](../services/agent-platform/langfuse/clickhouse-memory.xml)
to a new owner-only project directory on the SSD and into the guest using
`limactl copy`. Select the private guest project directory explicitly for every
Compose command; do not use an ambient context or other stack.

Supply a new mode-0600 `.env` with the required variables named by Compose.
Generate random values internally; do not reuse old keys, quote values in the
file, print them, pass them through argv, or commit them. Headless initialization
creates only the fresh trial organization/project/operator. The browser uses
`NEXTAUTH_URL=http://127.0.0.1:3300` through its dedicated tunnel. Redis receives
its fresh secret in its container environment and writes a mode-0600 configuration
before dropping to its normal service user; the secret is never expanded into
process arguments.

With `PROJECT` set to that guest directory:

```sh
"$LIMA" shell lf sudo docker compose --project-directory "$PROJECT" -f "$PROJECT/compose.json" config --quiet
"$LIMA" shell lf sudo docker compose --project-directory "$PROJECT" -f "$PROJECT/compose.json" up -d --wait
```

Only web port `127.0.0.1:3000` is published. The engine forwards only that TCP port
to mini loopback, ignoring other TCP/UDP guest ports. Databases, Redis, MinIO and
the worker have no host port. Browser media upload is not qualified; MinIO is
internal. Never use Serve/Funnel or expose the Docker socket over TCP.

Images match web/worker 4.56.0, PostgreSQL 17.11, ClickHouse 25.12.11.4, Redis 7
and MinIO at immutable digests. Container caps total 4.81 GiB within the 6 GiB VM.
Docker logs rotate at 5 MiB x 3 per container; ClickHouse file logs at 5 MiB x 3.
The 48 GiB guest disk bounds container storage; it is not a retention SLA. Lima's
host-agent logs do not have an authored rotation policy; review their size before
long-term operation. The storage gate is a startup reserve, not a live quota.

Do not cap ClickHouse's **global** thread pool below its reserved background
workers. A trial cap of 128 allowed simple API reads but deadlocked concurrent
trace queries, eventually exhausting the separate query-admission limit of 8.
The configuration retains the vendor global-pool default while bounding server
memory and query admission independently. Do not fix this by raising timeouts or
query concurrency, removing memory caps, or repeatedly restarting a stuck service.

## Synthetic verification

Current primary contracts:
[Langfuse OTLP](https://langfuse.com/integrations/native/opentelemetry) and
[v4 migration](https://langfuse.com/integrations/native/opentelemetry/migration-to-v4).
Keep v4 `events_only`; legacy `trace-create` is not supported there.

The one-shot [probe](../scripts/agent-platform/synthetic-trace.py) reads fresh trial
keys internally, posts complete metadata-only root/child observations with
`x-langfuse-ingestion-version: 4`, then verifies exact private identities/hierarchy
through `/api/public/v2/observations`. It does not load an ambient exporter,
instrument an agent, record prompts/tool content or change global policy.

```sh
python3 synthetic-trace.py /absolute/private/fresh-trial.env http://127.0.0.1:3000 mini
```

On the laptop use the dedicated 3300 SSH tunnel and an explicitly authorized fresh
credential file. Never copy credentials to another task without authority. POST is
not retried: after accepted ingestion and a failed GET, reconcile that trace ID
using GET only. Re-exporting identical v4 spans may create duplicates.

Verify **both** API receipt and authenticated browser trace rendering. Health or
successful ingestion alone does not prove query/UI correctness. Observe host
pressure, swap, container/process RAM, latency and existing application health
under load. Stop the new workload on critical pressure or new application damage.

## Recovery and remaining work

Stop only this task's guest stack/VM for its maintenance; never existing apps or
the laptop source tracing service. Preserve named volumes: do not use `down -v`,
wipe/reinitialize a database or recreate the instance as a recovery shortcut.
The VM continues independently of the SSH client. After a host restart, account
login plus operator SSD unlock and explicit VM start are still required.

Fresh Langfuse full backup/restore, original tracing restoration/migration,
producer switch, VM automatic recovery, long-duration retention and coordinated
host reboot acceptance remain separate unproved stages. An SSD-local snapshot is
not an independent backup. No production capacity or full-fleet adoption follows
from the bounded synthetic trial.
