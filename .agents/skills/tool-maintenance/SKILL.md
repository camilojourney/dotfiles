---
name: tool-maintenance
version: 1.0.0
description: Review tool maintenance, temporary pins, upstream fixes, and configuration drift in dotfiles. Use for periodic health reviews or deciding what to repair next.
---

# Tool maintenance

Review first. Return a short repair queue, not an automatic upgrade.

## Start

Read [the maintenance tracker](../../../docs/TOOL-MAINTENANCE.md), then the runbooks linked by relevant entries.
Resolve paths from this skill's repository, not the caller's working directory.
Use the requested tool scope. Without one, review open tracker entries and their configuration owners.
Keep the review local to this host unless another host is authorized.

## Review

1. Read repository instructions and `git status --short`. Preserve unrelated changes.
2. Compare authored declarations, installed revisions, and loaded-session evidence separately.
   Read manifests through their owning runbooks; never treat an installed version as proof of activation.
3. Check each open entry's upstream issue, pull request, release, and compatibility status.
   Use public URLs without private prompts or paths. Record the retrieval date.
   Without web access, report upstream status as unverified, not unchanged.
4. Run relevant documented read-only checks and isolated tests.
   Do not run a script merely because its name contains `check`; inspect its effects first.
   Upstream refresh scripts and `pi update` can change local state.
5. Distinguish reproduced defects, configuration drift, historical reports, hypotheses, and missing evidence.
   Correlate process identity with lock ownership and delivery evidence; a live PID or marker alone proves little.
6. Rank findings by correctness, reliability, security, then cost and prompt overhead.
   Compare keep, the smallest repair, and a named evidence gap before recommending change.
   Prefer verified upstream fixes over a permanent private fork.

## Boundaries

Never upgrade, reinstall, change pins, restart sessions, alter fleet state, or publish during a review: those actions need approval.
Never inspect credentials, private transcripts, or full runtime logs without a named diagnostic need and authorization.
Keep raw evidence outside Git; redact host identities and sensitive content from the public tracker.
Do not start Arbiter, research agents, paid probes, or a swarm during an ordinary review.
Use `/diagnose` for an approved investigation, `/code` for repairs, and `/arbiter` for an authorized consequential decision.
Use the existing `update-models` skill for model placement; do not duplicate its benchmarks or dispatcher policy here.

## Return

Start with three sections:

- **Act next:** at most three findings, each with impact, evidence, smallest next step, and approval needed.
- **Keep or watch:** temporary pins, upstream conditions, and what would justify removing each workaround.
- **Unknown:** failed checks, stale observations, untested behavior, and the next discriminating check.

State host scope, review date, tested revisions, and activation status.
Link the owning runbook instead of repeating configuration inventories.
For each proposed repair, name acceptance evidence and rollback before asking to proceed.

Update the tracker only when asked. Preserve stable item IDs and original decision dates.
For a resolved item, record the verifying revision and observation, not merely an upstream release announcement.
Keep the latest operating summary concise; Git owns the detailed editing history.
New sessions discover this repository-local skill. Existing sessions need `/reload`.
