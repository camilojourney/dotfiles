# Tool maintenance

Use this page to resume the maintenance conversation without reconstructing a chat.
It is a review queue and decision record, not an installer or another inventory.
Last reviewed: **2026-10-19, laptop only**. Older observations need fresh checks.
Nothing here claims that the Mac mini received local changes.

## Start a review

Open Pi in this repository and run:

```text
/skill:tool-maintenance
/skill:tool-maintenance Pi and Firstmate only
```

Claude Code discovers the same repository skill through the existing local
`.claude/skills` link. The skill is project-scoped, not globally loaded into
workers. New sessions discover it; existing Pi sessions need `/reload`.
The default is a read-only review. Approve repairs, upgrades, restarts, paid
probes, publication, and tracker edits separately.

Review this page after a relevant release, a recurring failure, or before a
planned maintenance session. There is no new daemon, scheduled model call,
or automatic model-selection policy.

## Configuration owners

| Concern | Authoritative owner |
| --- | --- |
| CLI inventory and reconciliation | [Auto-update](AUTO-UPDATE.md), `nix/agent-tools.manifest.lock.json` |
| Pi packages, defaults and tools | [Pi tools](PI-TOOLS.md), `home/.pi/agent/settings.json` |
| Compaction mechanism and thresholds | [Pi compaction](PI-COMPACTION.md) |
| Model placement | [Existing update-models skill](../.agents/skills/update-models/SKILL.md) |
| Global skill loading | Fleet's `system/skills/ACTIVE` and `system/skills/link-skills.sh` |
| Tracing and host reproduction | [Automations](AUTOMATIONS.md) |

Inspect commands before running them. For example, the upstream configuration
checker refreshes files, and `pi update` reconciles installations. Neither is a
read-only status query.

## Latest operating change

Decision date: **2026-10-19**. Keep OpenAI native compaction, adopt the existing
public message-preservation fix, and reduce tool overhead without replacing
Firstmate's orchestration. See the owning runbooks for exact settings.

Compaction follow-up checked **2026-10-23, laptop only**: our fork's `main`
contains the validated Pi 1.4 repair, and `pi list` selects our local checkout.
See [fork maintenance](PI-COMPACTION.md#maintaining-our-compaction-fork) for
updating, testing, reloading and rollback. Upstream acceptance is not required.

| Area | Before | Selected state | Activation and evidence |
| --- | --- | --- | --- |
| Compaction connector | Earlier revisions lost messages or Pi 1.4 tool declarations | Our maintained fork, selected through a local checkout | Validated repair passed real-provider compaction/tool/resume testing; configured source checked on laptop. This documentation update did not reload running sessions. |
| Codemode | Not enabled | Alongside ordinary tools, not tools-only mode | Real CLI fixture preserved tested Firstmate denial hooks. New-session selection still needed. |
| Web tools | Older pinned package | Updated, unpinned, deferred schemas | Local CLI fixture verified hiding and discovery, not external search quality. |
| Waiting workers | No wait-no-turns flags | Presence flags in all eleven existing local homes | Applies to newly generated briefs; no polling-reduction measurement yet. |
| Codex fast-mode | Installed | Removed | Declaration and local package removed. |
| Defaults and thresholds | Existing model, trust and compaction policies | Unchanged | No claim that thresholds are optimal. |

Saved configuration, installed code, loaded sessions, and observed task success
are four separate states. A passing local fixture does not establish live fleet
reliability or task quality.

## Open maintenance queue

Keep IDs stable. Each entry names its exit condition so temporary fixes do not
become forgotten permanent forks. Priority reflects correctness and reliability
before optimization, not a predicted completion date.

### TM-001: maintain our compaction fork

- **Status:** our fork's `main` includes the repair; the laptop selects our local checkout. Running-session activation was not rechecked in this documentation update.
- **Owner:** [Pi compaction fork maintenance](PI-COMPACTION.md#maintaining-our-compaction-fork).
- **Evidence:** validated commit `4a471183` passed real-provider tool use after compaction and resume; [PR #28](https://github.com/algal/pi-openai-server-compaction/pull/28) remains open as of the follow-up check.
- **Next:** maintain and validate our fork independently; review upstream changes before merging them. Do not wait for upstream approval to use our version.
- **Done when:** a supported upstream revision includes our fixes, passes equivalent checks, and is deliberately adopted and loaded. Until then, retain our fork.
- **Rollback:** use the owning runbook's previous-validated-revision procedure; never rewrite historical session JSONL.

### TM-002: failed compaction can save a misleading placeholder

- **Status:** locally reproduced; not repaired by PR #18.
- **Owner:** `pi-openai-server-compaction`, portable-summary and native-failure handling.
- **Evidence:** when both requests failed in a local fixture, the hook returned success-sounding text without a native checkpoint or useful summary.
- **Next:** check existing upstream work, then contribute a regression-first fix if still needed. Preserve original context on total failure.
- **Done when:** failed requests cannot masquerade as successful context preservation; native success and useful text fallback still work.
- **Limits:** this reproduces a failure shape, not the original cause of every missing checkpoint. Do not restart a damaged session assuming it is repaired.

### TM-003: establish Pi supervision parity with the working baseline

- **Status:** historical stall not fully explained; no orchestrator switch authorized by these configuration edits.
- **Owner:** Firstmate's [Pi supervision contract](https://github.com/kunchenguid/firstmate/blob/main/docs/pi-supervision-branch.md).
- **Evidence:** isolated installed-SDK branch tests passed. The connector defect is real, but causality for the historical stall is unproven.
- **Watch:** [Firstmate issue #6714](https://github.com/kunchenguid/firstmate/issues/6714) describes leaked leases after branch failure. It was open at review; no matching live lease leak was established.
- **Next:** run the bounded comparison below after safely loading the selected revision.
- **Done when:** agreed tasks finish correctly, eligible events are processed, and compaction/recovery do not require manual nudges.

### TM-004: resolve residual npm dependency advisories

- **Status:** earlier local audit reported five advisories through an unconfigured legacy `pi-cursor-sdk` dependency; current counts require rechecking.
- **Owner:** Pi's managed npm root and [package-update policy](AUTO-UPDATE.md).
- **Next:** inspect the current dependency chain and whether the legacy root is still needed. Propose removal or a compatible upstream update.
- **Done when:** the relevant audit findings are resolved and configured packages still load.
- **Boundary:** do not run `npm audit fix --force` or remove a shared dependency blindly.

### TM-005: make tool reproduction and skill loading explicit

- **Status:** the telemetry package uses a laptop-only unpublished local path; the installed Arbiter skill is absent from Fleet's current ACTIVE list.
- **Owner:** [Native reproduction](AUTOMATIONS.md#reproduce-native-agents-on-another-mac) and Fleet's global skill registry.
- **Risk:** another host cannot reproduce the telemetry path; a skill-link reconciliation can remove an unlisted Arbiter link.
- **Next:** agree on published/installable sources and intended globally loaded skills before changing either owner.
- **Done when:** each intended host resolves its declared sources and a reconciliation preserves only the agreed skill set.
- **Boundary:** do not run global skill reconciliation as a harmless inspection or copy credentials, active sessions, or runtime state between hosts.

## Pi versus Claude Code trial

This is a proposed acceptance checklist, not a benchmark result or permission to
start jobs. Keep Claude Code available until the captain accepts the Pi result.

1. Use Firstmate's documented setup for an isolated home or a coordinated handover.
   Never let both harnesses own the same home. Do not clone live fleet state.
2. Record Pi, Firstmate and extension revisions, loaded tools, model and effort,
   supervision model and effort, and agreed task acceptance checks.
3. Use comparable bounded tasks with real tool work, a worker completion event,
   and a captain-relevant event. Exercise compaction and fresh-process resume.
4. Check event ownership and processing acknowledgement, not merely a visible
   branch note. Distinguish a quiet branch with no eligible work from a stall.
5. Record task correctness, tests, manual interventions, completion time, and
   available token/usage evidence across main and supervision conversations.
   Subscription usage is not automatically a dollar-cost measurement.
6. Compare Pi with codemode off versus on separately if attributing gains to
   codemode. Different models, effort levels, and tasks confound harness comparisons.
7. Accept or reject against the agreed outcomes. On failure, preserve bounded
   private evidence and hand ownership back through Firstmate's normal procedure.

Codemode can reduce tool round trips; it has not been shown here to improve
coding quality. It changes the main session's tools, not the isolated supervision
branch's default resource loading.

## Supervision is not a model toggle

On a Pi Firstmate or Pi Secondmate that owns its home's fleet lock, the in-process
supervision branch is **default-on**. `/supervision-model` chooses its model and
reasoning effort; it does not activate supervision or switch the main model.

Without pins, the branch follows main's model and effort. Pins are **per home**,
not inherited by Secondmates. Run the picker inside each intended home only when
a different branch model or effort is desired. Ordinary crewmate tasks do not
need another supervisor enabled simply because they use Pi.

Read-only observations at this review found five active Pi Secondmates with
supervision-extension markers matching their lock PIDs. The main home was still
Claude Code. This confirms loading in those sessions, not end-to-end delivery
health. Stale markers and reused PIDs are not proof of a healthy Pi process.

## Updating this page

Record review date and host scope, current evidence, proposed next action,
verification/rollback, and the condition that retires each workaround. Keep raw
transcripts, private task names, credentials and host process identifiers out of
this public repository. Replace stale summaries; Git preserves earlier versions.
