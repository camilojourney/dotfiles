# Review the fleet's models

## Task

Use the update-models skill to review which AI models this fleet uses: are we on the newest, best-placed, working models?

Constraints for this run:
- Do not edit, create, or delete files in this directory or in ~/github/firstmate. Do not commit or push.
- Everything else the skill's steps need is allowed and expected. That covers catalogs, benchmarks, quota-axi, and model probes through Pi and Claude Code, which keep their own state under ~/.pi and ~/.claude. It also covers Firstmate's validator and resolver, run from ~/github/firstmate; they write only temporary files.
- Stop before step 5's edits. Finish with the skill's step 6 report, written as if you were about to apply the changes you recommend.

## Checklist

1. Read every step 1 catalog, including `agy models` and `pi --list-models meta`.
2. Decided each newer release's availability from a tool-test probe, not from a warning or the release list.
3. Ran the releases list and the coding index.
4. Left trades recorded in `why` in place unless their gap moved more than about 2 points.
5. Tool-tested every model it proposes to add or move, or said why a probe could not run.
6. Ran Firstmate's validator and the Jev resolver, and reported any unranked candidate as a gap.
7. Sized only extra pools (a second route to a model) by probe drain, and kept main pools out of placement.
8. Left the `home/.claude/settings.json` family alias in place.
9. Started the answer with the step 6 table, followed only by the short lists step 6 names.
10. Stated no model, score or limit as current fact without having read it this run.
11. Treated a model id missing from the vendor catalog as no candidate, even when Pi lists it. Named the cause or listed it under Gaps.
12. Checked every rule's `why` against its `use` and flagged each claim the config no longer makes true.
13. Kept any proposed `when` text about the task alone: no model, harness, effort or cost.
14. Evaluated confirmed Meta/Muse candidates for crew-dispatch tiers without excluding Pi's route because native Muse Code lacked authentication.
15. Kept Muse Wonder and Wonder Full separate, and treated native Muse Code benchmark results as directional rather than measured Pi performance.
16. Established the selected Meta route's authentication, billing and quota mapping independently, reporting missing mapping without inventing a provider.
