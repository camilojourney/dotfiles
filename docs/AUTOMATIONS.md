# Automations

Every job these dotfiles schedule, on both machines unless noted. A rebuild
installs each one from `nix/configuration.nix`; removing its block there and
rebuilding removes it.

| Job | When | Runs as | What it does | Log |
| --- | --- | --- | --- | --- |
| `org.dotfiles.auto-rebuild` | 05:00 daily, or at the next wake | root | Pulls this repository and Firstmate, then rebuilds | `/var/log/auto-rebuild.log` |
| newsyslog rotation | When the rebuild log passes 1 MB | root | Keeps 8 old copies of the rebuild log | - |
| `org.dotfiles.fleet-skill-usage` | Every 15 minutes | you | Adds skill usage to finished agent sessions' Langfuse traces | `~/Library/Logs/fleet-skill-usage.log` |

The agent platform's launchd templates in `services/agent-platform/` are not
scheduled by a rebuild. Each is installed by hand, as
[agent platform](AGENT-PLATFORM.md) describes.

## Daily rebuild

[Auto-update](AUTO-UPDATE.md) explains the daemon, its failure notification and
how to turn it off.

## Fleet skill usage

Shows whether crew agents use the Fleet skills (`/code`, `/specs`, `/diagnose`)
and which parts of them. Pi already sends every tool call to Langfuse
live; this job adds what Langfuse cannot work out alone.

Each run calls `skill_usage.py update` from the Fleet checkout at
`~/github/fleet-system/system/skills/meta/skill-creator-fleet/scripts/`. For
every Pi session under `~/.pi/agent/sessions` that has been quiet for 10
minutes, it records:

- which skills the agent loaded, and whether before its first edit;
- which skill references and scripts it read or ran;
- which checks from each skill's Verify section it ran, and whether each was
  rerun after the last edit and before each commit.

It writes one record per session under
`~/.local/share/fleet/telemetry/skill-usage/records/` and adds the result to
that session's Langfuse trace as a `fleet.skill_usage` span and `skill_usage.*`
scores. A session is read again only when its log changes; a trace Langfuse
does not have yet is retried for two days. Records and traces hold names,
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
as `{"exported": 1, "trace-not-found": 15}`. On a machine without the Fleet
checkout the job exits at once and does nothing.
