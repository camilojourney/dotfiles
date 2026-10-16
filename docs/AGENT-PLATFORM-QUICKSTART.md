# Mini platform: how it works now

## What is running

- **Mini:** one restricted Pi Durable terminal and a fresh Langfuse trial.
- **Encrypted SSD:** Durable execution state and the entire Langfuse VM/data.
- **Laptop:** an SSH interface and separate manual Durable backups. Its original
  Langfuse remains the live destination for existing producers.
- **Not adopted:** native Pi sessions, Firstmate, second mates and existing workers.
  Their folders, sessions and authority records have not moved.

Durable remembers committed execution and resumes its safe pending work after
its worker restarts. SSH is only the interface: disconnecting it does not stop
that worker. The mini must stay powered, awake, online and able to use its SSD.
Laptop-only files and applications still need the laptop awake.

## Use the Durable terminal

From the laptop, including over the existing Tailscale connection:

```sh
ssh -t mac-mini 'env SCREENDIR=/Volumes/AgentPlatform/agent-platform/state/pi/terminal /usr/bin/screen -r agent-platform'
```

Type `status`, or `check-1 Read alpha.txt using read.` This worker can only read
and search its two public fixtures. It cannot edit a repository, run shell tools,
launch workers or carry out real fleet obligations. Use a new stable request key
for new work; reusing a key with changed instructions refuses.

Detach with **Ctrl-a, then d**. Do not start a second scheduler on its store.
Execution recovery is not an exactly-once guarantee for arbitrary external actions.

## Open mini Langfuse

In a separate laptop terminal, leave this forwarding command running:

```sh
ssh -N -T -o ControlPath=none -o ExitOnForwardFailure=yes -L 127.0.0.1:3300:127.0.0.1:3000 mac-mini
```

Open <http://127.0.0.1:3300>. Sign in with the fresh trial account. The operator
can obtain its password locally from the mini's private `langfuse/project/.env`;
do not paste keys/passwords into chat, commands or Git.
Port 3300 deliberately avoids the laptop's existing port 3000. `ControlPath=none`
keeps this tunnel separate from shared SSH connections; Ctrl-c closes its forward.

The mini project currently contains **synthetic metadata-only canaries**, not
an automatic feed of native agents or Durable model/tool activity. Durable's own
results are in its store/status interface. Do not switch existing producers or
reuse the fresh keys as a global exporter configuration.

## Where the data is

Under `/Volumes/AgentPlatform/agent-platform/`:

| Folder | Meaning |
| --- | --- |
| `state/pi/central/` | Existing Durable SQLite store, public fixtures and keyed artifacts |
| `state/pi/terminal/` | Dedicated terminal socket, not a database |
| `state/pi/snapshots/central/` | Closed staging snapshots, **not independent backups** |
| `langfuse/project/` | Private trial configuration and fresh secrets |
| `langfuse/engine/lima/lf/disk` | Linux VM disk containing named PostgreSQL, ClickHouse, MinIO and Redis volumes |
| `langfuse/engine/home/` | Isolated engine cache/home, also on the SSD |
| `plans/rollout.md` | Private plan, acceptance history and remaining conditions |

Do not mount a live SQLite file over the network. Do not move the Pythia/Trader
folders. The old SSD volume remains separate and unchanged.

## Restart and backup expectations

The Durable LaunchAgent restarts its worker and loads at account login. A mini
reboot was **not tested**: the operator must log in, interactively unlock the
recorded encrypted volume and verify storage before work can resume. No passphrase
is stored and unattended boot recovery is not promised.

Langfuse containers restart inside their VM; VM startup is currently manual after
unlock. See the [tracing runbook](AGENT-PLATFORM-LANGFUSE.md). Do not reboot or
restart existing applications to test this platform.

A closed Durable snapshot was copied to and restored on the separate laptop.
Backups are manual and require that laptop online. SSD staging snapshots are not
backups; fresh Langfuse full backup/restore and source-data migration remain pending.

The joint trial qualified one serial Durable execution with three outstanding
requests, not a fleet concurrency limit or a demonstrated productivity improvement.
See the private capacity report for measured RAM/latency and its limits.
