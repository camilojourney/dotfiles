# Automations

Every job these dotfiles schedule, on both machines unless noted. A rebuild
installs each one from `nix/configuration.nix`; removing its block there and
rebuilding removes it.

| Job | When | Runs as | What it does | Log |
| --- | --- | --- | --- | --- |
| `org.dotfiles.auto-rebuild` | 05:00 daily, or at the next wake | root | Pulls this repository and Firstmate, then rebuilds | `/var/log/auto-rebuild.log` |
| newsyslog rotation | When the rebuild log passes 1 MB | root | Keeps 8 old copies of the rebuild log | - |
| `org.dotfiles.fleet-skill-usage` | Every 15 minutes | you | Adds skill usage and flushes task outcome evidence to Langfuse | `~/Library/Logs/fleet-skill-usage.log` |

The agent platform's launchd templates in `services/agent-platform/` are not
scheduled by a rebuild. Each is installed by hand, as
[agent platform](AGENT-PLATFORM.md) describes.

## Daily rebuild

[Auto-update](AUTO-UPDATE.md) explains the daemon, its failure notification and
how to turn it off.

## Fleet skill usage and task outcomes

Shows whether crew agents use the Fleet skills (`/code`, `/specs`, `/diagnose`)
and which parts of them. Pi already sends every tool call to Langfuse
live; this job adds what Langfuse cannot work out alone.

Each run calls `skill_usage.py update` from the Fleet checkout at `~/github/fleet-system/system/skills/meta/skill-creator-fleet/scripts/` and flushes Firstmate's pending task evidence.
Both collectors run independently, and either failure makes the scheduled job fail visibly.
The login shell supplies the existing native OTLP endpoint and authentication from the managed shell environment.
No additional daemon or credentials are introduced.
For every Pi session under `~/.pi/agent/sessions` that has been quiet for 10 minutes, the skill collector records:

- which skills the agent loaded, and whether before its first edit;
- which skill references and scripts it read or ran;
- which checks from each skill's Verify section it ran, and whether each was
  rerun after the last edit and before each commit.

It writes one record per native attempt (per session for legacy logs) under
`~/.local/share/fleet/telemetry/skill-usage/records/` and adds the result to
that session's Langfuse trace as a `fleet.skill_usage` span and `skill_usage.*`
scores. A record is exported again only when its log changes or its schema changes;
a trace Langfuse does not have yet is retried for two days. Quiet time is not
successful completion. Recorded native identities separate resumes and machines;
legacy lookup follows result-page cursors and refuses ambiguous matches. Records and traces hold names,
versions, skill-relative paths, check kinds and counts, never command text, file
content or tool output.

Read the results:

```bash
S=~/github/fleet-system/system/skills/meta/skill-creator-fleet/scripts/skill_usage.py
python3 "$S" report            # load rate, check coverage, verified commits per skill version
python3 "$S" report --parts    # how often agents use each reference, script and asset
```

In Langfuse, filter traces by the `skill_usage.*` scores, for example
`skill_usage.code.verified_commits`. Fleet's `system/skills/TRACING.md` owns the
full description.

Check the job: `launchctl print gui/$(id -u)/org.dotfiles.fleet-skill-usage`
shows its run count and last exit code. Each run logs one line of counts, such
as `{"exported": 1, "trace-not-found": 15}`, followed by the outcome connector's counts.
A missing checkout skips only its own collector.
`tests/fleet_telemetry_test.py` executes both hosts' evaluated job commands with isolated fixtures, including independent failure cases.

## Reproduce native agents on another Mac

This is the native Pi/Fleet setup, not the separate retained Durable trial.
Do not change the [trial destination](AGENT-PLATFORM-QUICKSTART.md), restore its
Langfuse store, or start stopped services to reproduce native agents.

Copy committed source, not a running home. Keep `dotfiles`, `fleet-system`,
`firstmate` and the telemetry extension at the tested commits. The active extension
pin is owned by `home/.pi/agent/settings.json` and its regression in
`tests/pi_settings_test.sh`. Keep that default at the published revision until a
reviewed upgrade is available from its fetch origin. The reproduction kit's
manifest records the tested candidate separately; copying the kit does not activate
it. The daily rebuild uses local commits too, even without a push.

For a published upgrade, preserve any managed-cache edits first, update the authored
pin and its regression together, run `bash tests/pi_settings_test.sh`, then run
`pi update <exact-package-source>` with that pin. New Pi sessions load the upgrade;
already-running sessions retain their loaded exporter until reloaded or resumed.
No machine rebuild or credential change is needed for this package switch.

For task-scoped linkage, create the presence flag
`~/github/firstmate/config/trace-context` in the intended operational home before
starting its next normal home session. Firstmate's `docs/trace-context.md` owns the
propagation contract. Existing homes keep their frozen decision until restarted;
coordinate their normal safe restart through Firstmate, preserving active work.
Never edit `state/.trace-context-effective` to force activation. A successful
exporter test alone does not prove that an existing Firstmate home enabled linking.

An unpublished SHA cannot be fetched from GitHub. A source-only git bundle carries
it without publishing or activating it. Merely seeding a managed cache is not enough:
Pi 1.3.0 still fetches the configured ref during `pi update <exact-package-source>`.

On an empty destination, clone the bundles into `~/github/<repository>` and check
out the recorded commits. For an existing repository, fetch the bundle and inspect
the diff before changing branches. Preserve local edits. Do not pull a moving branch
and call that the tested configuration. Firstmate's home setup and existing Mac
bootstrap remain the setup owners; this guide does not bypass their guards.

For an explicit unpublished-exporter trial, clone its verified bundle into Pi's
empty managed git path
`~/.pi/agent/git/github.com/camilojourney/pi-opentelemetry` at the manifest commit.
Retain the bundle as that clone's origin until publication: this lets online Pi
reconciliation fetch the exact candidate locally. Keep the bundle at a stable
absolute path. Install locked dependencies with
`npm ci --omit=dev --omit=peer --ignore-scripts`. In the receiving authored settings
and pin regression, select that manifest commit only when ready to activate it.
Then run the settings regression and `pi update <exact-package-source>` before
rebuilding. After publication, restore the declared GitHub origin and verify the
same update command before relying on unattended rebuilds.

Do not update an existing managed cache with local changes without preserving and
reviewing them first. Pi 1.3.0 reconciliation can reset tracked files and remove
untracked files when changing commits; it is not a guarded source-worktree update.
Do not copy `node_modules`, caches or an installed executable from the laptop.

Run the source checks on each Mac before activation:

```sh
(cd ~/github/pi-opentelemetry && npm ci --ignore-scripts && npm run release:check && npm audit)
(cd ~/github/fleet-system && uv run --with pytest --with pyyaml --with jsonschema pytest)
(cd ~/github/dotfiles && bash tests/pi_settings_test.sh)
(cd ~/github/firstmate && bash tests/fm-trace-evidence.test.sh)
```

The exporter suite includes a real pinned Pi CLI smoke test with no credentials,
no provider calls and a temporary local collector. It also tests redaction,
strict mode, sampling, task carriers and cloned-session identity separation.
Match the recorded Node, Python, Pi and no-mistakes versions on both hosts; the
normal tool inventory's self-update policy is not an exact runtime lock.
Matching source does not guarantee identical model responses or account quotas.

Use separate operational Firstmate homes on the two machines. Never copy active
`state/`, locks, task metadata, terminal sockets, telemetry records or sessions as
new work. Recovery of the *same* task is a separate guarded Firstmate procedure.
Authenticate model accounts locally. Provision telemetry secrets through the
existing protected secret-file procedure, never Git, chat or the source bundle.
Rotate any previously exposed telemetry credential before reuse.

The exporter creates a fresh run UUID on every start. Its default machine label
hashes the hostname; set a unique local `PI_OTEL_INSTANCE_ID` if the two hosts have
the same hostname. Do not commit a shared machine label. Keep private receipts
under each host's own XDG state/share directories.

The current native destination remains the laptop Langfuse. A `localhost:3000`
endpoint on the Mini is a different service, not a route to the laptop. Leave the
Mini's trial project untouched. To use the existing laptop project from the Mini,
configure an authenticated HTTPS route or a dedicated loopback SSH forward and
matching native-project credentials. A configured URL is not proof of delivery;
require an observed native trace and `fleet.skill_usage` span before claiming both
hosts collect evidence. Host sleep or a broken tunnel suspends collection.

The scheduled job also flushes Firstmate's automatic task snapshots, including outcomes without native session files.
Enable `config/fleet-ledger` separately in each intended Firstmate home, alongside normal trace propagation.
Lifecycle hooks save private identity and delivery evidence before cleanup; the scheduled connector retries failed exports without needing a live worker checkout.
Firstmate's `bin/fm-trace-evidence.py --help` owns the storage, attribution and retry contract.
It never starts validation or infers human acceptance, and it does not reconstruct dispatches missed before enablement.
This replays retained outcome snapshots, not missing native Pi spans.
Use Langfuse's existing feedback controls for corrections; keep regressions in
the application or skill that owns the failed behavior. No paid benchmark, judge
or automatic optimizer is part of this setup.
