# global agent instructions

- Never use the em dash. Use plain dash "-" instead
- When writing commit messages, NEVER auto-add your agent name as co-author
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated
- When making technical decisions, do not give much weight to development cost.
  Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- For one-off or infrequent operational work, use the simplest direct end-to-end path. Avoid wrappers or automation unless a concrete blocker or repeated need justifies them.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it as possible.
  This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection.
  If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness.
  If you see one, even if it is not caused by what you are working on right now, still get it fixed.
- Before using a workflow that immediately spawns many subagents, explain the tradeoffs and ask the user for approval.
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.
# holusight
- **holusight** (`~/.claude/skills/holusight/SKILL.md`) - hybrid BM25 + vector + structural search over any project's code/docs, with provenance/freshness attached. Self-installs the `holus` CLI on first use. Trigger: `/holusight`
When the user types `/holusight`, use the installed holusight skill or instructions before doing anything else.

## Maintaining this file

Keep guidance useful across most agent sessions. Point to authoritative files instead of repeating project details. Prefer updating or pruning notes over appending, and keep changes concise.
