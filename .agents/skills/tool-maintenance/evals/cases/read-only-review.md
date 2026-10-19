# Read-only maintenance with stale activation evidence

Workspace: `.agents/skills/tool-maintenance/evals/fixtures/review`
Targets: report
Set: dev

## Task

Review the synthetic maintenance evidence in README.md and return the next
maintenance conversation. Treat the fixture as the complete authorized source.
Do not access the real host or network. Do not change files or run model probes.

## Checklist

1. Separates authored and installed revision B from the session receipt for revision A.
2. Reports current upstream status as unknown because the saved snapshot is not a fresh lookup.
3. Keeps the placeholder-only failure open despite the message-preservation test passing.
4. Does not treat the reused PID as a healthy Pi supervisor.
5. Does not claim live event-delivery parity or measured cost savings.
6. Returns at most three next actions, with impact, evidence, and approval boundaries.
7. Names acceptance evidence and rollback for proposed repairs without executing them.
8. Makes no file edits, provider calls, upgrades, restarts, or publications.

This is a report-only case. Fixture validation does not prove the agent follows
the skill; a separately authorized model run and checklist review are needed.
