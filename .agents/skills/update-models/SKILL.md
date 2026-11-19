---
name: update-models
version: 1.4.0
description: Updates fleet models across crew dispatch, active Secondmates, every backup and no-mistakes for intelligence, coding value and subscription-quota use. Verifies routes and picks; keeps reasons concise.
---

# update-models

The goal is useful work from every available subscription pool:

1. **Capable and runnable**: each candidate meets its task's quality bar and runs tools through its configured route.
2. **Use the quota**: cover every usable pool so earned allowance is spent on real work before reset, not left idle.
3. **Right role**: distinguish frontier intelligence, good-value coding and quick utility work; prefer newer models within each class.

Models, scores, efforts and quota pools change all the time. Every rule below is a method; concrete model examples are dated evidence, not defaults to impose. Explicit task selections and approved trades take precedence: preserve them, unrelated defaults and account pins during a scoped refresh. A discovery fix does not authorize a tier sweep.

Quota coverage is a placement concern. Jev classifies the brief using `when`; Firstmate then ranks that rule's eligible candidates by `quota-axi`'s `spendPriority`, which accounts for runway and reset, not just percent remaining. Array order is not a quota preference. Never remove a capable model because its pool is exhausted today, or reserve a pool so narrowly that its allowance routinely expires unused.

Use all current, distinct, capable models across appropriate roles, not every obsolete version or every model in every tier. Separate routes to one model count as extra allowance only when quota evidence proves distinct pools. Within a quality-qualified tier, favor spending included quota over minimizing nominal API price. Cheap, good models still earn high-volume work through quality, speed and useful work per allowance. Never lower the quality bar, invent busywork, enable paid overages, or change billing/authentication/privacy settings to burn quota. Preserve explicit task selections and scoped account pins.

Run this skill only deliberately; keep the current placement as the last known safe version until then. Nothing runs this skill automatically. The daily auto-update (`docs/AUTO-UPDATE.md`) upgrades tools but never changes which models the fleet uses and does not refresh Pi's model catalog. A change pushed to `main` reaches both machines at the next 05:00 run.

This skill lives in `.agents/skills/`; `.claude/skills` is a symlink to that directory, so edit it there only.

## Where models are set

| File | Controls | Takes effect |
|---|---|---|
| `home/.firstmate/crew-dispatch.json` | Model per crewmate task, by rule | Immediately (symlinked into `~/github/firstmate/config/`) |
| `home/.firstmate/secondmate-harness` | Active Secondmate runtime: `<harness> <model> <effort>` | Next Secondmate launch |
| `home/.firstmate/secondmate-harness.backup` | Saved alternative in the same format, not automatic failover | Only when explicitly selected |
| `home/.pi/agent/settings.json` | Pi `defaultModel` | Immediately |
| `home/.pi/agent/settings.json` `compaction.modelOverrides` | Per-model compaction trigger; a new 1M Claude or resized GPT window needs a line ([docs/PI-COMPACTION.md](../../../docs/PI-COMPACTION.md)) | Immediately |
| `home/.no-mistakes/config.yaml` | no-mistakes pipeline `agent` / `agent_config` (one agent for every step) | Immediately (symlinked) |
| `tests/pi_settings_test.sh` | Pins Pi `defaultModel`; must match settings.json | Run `bash tests/pi_settings_test.sh` |
| `home/.claude/settings.json` | Claude Code's interactive default `model` | Next Claude Code session |

## Required coverage for a fleet refresh

A fleet-wide model update includes every role below unless the user explicitly narrows scope. Reading a file or listing its current model is not a completed model decision.

- **Crew dispatch**: assess all rules and the default for quality, capability and quota coverage.
- **Active Secondmates**: select the route, model and effort for sustained supervision and judgment, not just coding throughput.
- **Every backup entry**: assess each saved route, model and effort independently for role quality and alternative quota coverage. Firstmate reads `secondmate-harness` for active launches; the backup is manual, not automatic failover.
- **no-mistakes**: select its pipeline-wide `agent` and model/effort in `agent_config` for coding, independent review and long validation runs. Inspect effective argument overrides too; do not invent per-step model routing.

For each role, apply a supported improvement or explicitly mark **kept**, **blocked** or **out of scope**, with a short reason and verification result. Existing configuration is not an instruction to keep an obsolete model. Preserve explicit user pins, but still assess and report their verification or gaps. Do not call a fleet refresh complete while any role is silently skipped.

Keep the family alias (e.g. `opus`) in `home/.claude/settings.json`: it follows each new release. Exact ids belong in dispatch config, where runs must be reproducible.

All are symlinked by `nix/home.nix`; a new model-bearing file belongs there too. Find stragglers with `grep -rnE 'gpt-|grok-|gemini-|opus|sonnet|haiku' home/ tests/`.

## 0. Check and safely update each route's actual source

Before refreshing catalogs, read [the provider log](references/provider-log.md) for each provider's last checked route/pin, active workarounds, and cleanup conditions. Check each route against the software that actually supplies it:

| Pi route | Real source & pin owner | What does NOT update it |
|---|---|---|
| `openai-codex/`, `xai/`, `meta/`, and the `anthropic` catalog that `claude-bridge/` lists | `@earendil-works/pi-coding-agent` in `nix/agent-tools.manifest.lock.json`, plus `pi update --models` | `pi update --models` refreshes catalog data only, not Pi itself |
| `claude-bridge/` | `piPackages["pi-claude-bridge"]` in `nix/agent-tools.manifest.lock.json` (bundles its own Claude Code SDK/binary; shares login only with Homebrew `claude`) | Homebrew `claude` |
| `antigravity/` | Immutable 40-char commit pin in `home/.pi/agent/settings.json` (`git:github.com/Rahularya01/pi-antigravity@...`) | Homebrew `agy` (reference catalog only) |
| `pi-web-access` | `piPackages["pi-web-access"]` in `nix/agent-tools.manifest.lock.json` | - |

Keep one route per vendor in the picker: Pi's built-in `openai` and `anthropic` providers stay signed out. If `pi --offline --list-models` lists them, run `pi auth logout openai` / `pi auth logout anthropic`.

Apply these safety gates before adopting any package or extension update:

1. **Age and advisories:** run read-only `python3 scripts/agent-tools/toolchain.py select` for npm packages (requires >= 7 days public age and OSV clear). For git-pinned extensions (`pi-antigravity`), manually verify >= 7 days since tag/commit and check open issues and account-risk reports.
2. **Code review:** read release notes and diffs for extensions handling credentials (`pi-claude-bridge`, `pi-antigravity`) covering auth/tokens, subprocesses, network destinations, telemetry, and new dependencies.
3. **Isolated probe:** test candidate pins in a throwaway `PI_CODING_AGENT_DIR` with synthetic fixtures and `PI_TELEMETRY=0` on exact routes (checking JSON `tool_execution_end` and `stopReason`, not shell exit 0 alone) before changing live pins.
4. **Approval and cleanup:** never run `weekly.py` on a dirty worktree or push pin changes without approval (pushes reach both machines on next rebuild). After an approved adoption, update `references/provider-log.md` with the date and delete any retired workaround whose exit condition now passes.

## 1. Inventory: what can each harness run right now?

For a fleet-wide review, run every catalog. For a scoped model/provider refresh, inventory the affected provider and configured route without changing unrelated selections. The vendor's own catalog is the authority; never infer a model name from a version pattern.

| Harness | Catalog command | Notes |
|---|---|---|
| Pi | `pi update --models`, then `pi --list-models <provider>` | A provider extension's list is not proof a model is served. It can keep retired models and miss new ones. Confirm each id in the vendor's own catalog (for Antigravity, `agy models`). An id only Pi lists is not a candidate. Pi also accepts an unlisted `provider/id` with a "Using custom model id" warning; confirm those the same way. |
| Antigravity | `agy models` | The authority for Antigravity. Lists Gemini and the other vendors' models Antigravity serves, each with effort suffixes. Every listed model is a candidate for every tier, placed by the same rules as the same model elsewhere. Dispatch through Pi only: strip the suffix (`<model>-high` is `antigravity/<model>`) and set effort with Pi's `--thinking`. The highest suffix listed is Antigravity's effort ceiling for that model. Judge it by role-specific evidence at that effort, not a higher one it cannot run. |
| Codex via Pi | `pi --list-models openai-codex` | |
| Meta/Muse via Pi | `pi --list-models meta` | Confirm IDs against the [Meta Model API catalog](https://dev.meta.ai/docs/api-reference). Native Muse Code and Cursor routes are separate candidates. |
| Claude via Pi | `pi --list-models claude-bridge` | The `pi-claude-bridge` extension runs Claude models in Pi through Claude Code's Agent SDK, on the Claude subscription pool. Dispatch through Pi only as `claude-bridge/<id>` with `provider` `claude`, never the `claude` harness. Use exact model ids, never the `opus`/`sonnet`/`haiku` aliases, which silently move. A prior `fable` probe stalled on a usage-credit prompt; retain an explicitly selected candidate and report its current tool-test result rather than removing it from dated prose. |
| Grok TUI | `grok models` | |
| Cursor via Pi | `pi --list-models cursor` | Re-test each run. As of 2026-10-04 only `cursor/auto` was accepted and it stalled on any tool call, so Cursor was not dispatchable. |

Include Meta/Muse in every fleet-wide inventory, not only when native Muse Code works. Pi's `meta` provider is a separate route. For example, `meta/muse-wonder-1.0` appeared in Pi's catalog on 2026-10-17. Discover its current ID and supported effort again during each review.

Evaluate catalog-confirmed Meta candidates for each crew-dispatch tier under step 3, then tool-test proposed placements under step 4. A native Muse login failure does not disqualify Pi's Meta route. Establish authentication, billing and quota mapping for the selected route; do not infer them from the `meta` prefix or another route's diagnostics. Report missing quota mapping as uncertainty, not proof that the model cannot run.

Keep Muse Wonder and Wonder Full distinct. Never transfer Full's scores or assume its availability from a standard Wonder catalog entry. Native Muse Code benchmarks are directional evidence, not measured Pi performance. Inventory inclusion alone never authorizes changing dispatcher defaults.

A provider error like `X is no longer available. Please switch to Y` is a retirement notice: replace X everywhere and check Y.

When a catalog lists a model the vendor no longer serves, find the cause before working around it. Read the extension's catalog code and compare it with the vendor's raw list. Fix it upstream or in our fork, and record it under Gaps until the fix ships. Example (2026-10-11): pi-antigravity 0.10.0 appends its built-in model list to the server's. So Pi listed `claude-sonnet-4-6` after the server dropped it.

The reverse gap also happens: a model the vendor serves that the extension cannot reach. The server answers `429 ResourceExhausted` with `matched=none` even with quota to spare. So a 429 on a custom id, while the vendor's own CLI runs the model (`agy --model <id>-high -p ...`), is an extension gap, not quota. Search the extension's open issues and pull requests before debugging, and record it under Gaps until a fix ships. Example (2026-10-16): pi-antigravity 0.9.0 and npm 0.10.0 announced an old Antigravity client version, so the backend hid Gemini 4 Argon ([issue 93](https://github.com/Rahularya01/pi-antigravity/issues/93), [issue 94](https://github.com/Rahularya01/pi-antigravity/issues/94)). Reuse that evidence before investigating the same failure again; check current releases and fixes before reinstalling npm latest.

Argon discovery example, checked 2026-10-16:

- `agy models` advertises `gemini-4-argon-{low,medium,high}`.
- Pi's logical id is `antigravity/gemini-4-argon`. Its `--thinking high` must select `gemini-4-argon-high`, not Flash or another provider.
- The configured Git extension pin contains the discovery fix; npm latest was 0.10.0.
- Run `pi update --models` after installing the fixed source. Headless inference alone is not a catalog refresh.
- Compare the refreshed Pi list with `agy models`, not the extension's built-in fallback list.
- Never edit `models-store.json` or add a static Argon override to conceal a discovery failure.
- Catalog presence and offline routing tests are not live tool verification.

## 2. Newer models: is anything better released?

1. `scripts/aa-coding-agents.py --releases` lists recent releases from the vendors the fleet can run, newest first. Also check vendor release notes or news for releases the page has not added.
2. Within the same cost and latency class, prefer the newest runnable version when step 3's role-specific evidence requirements support the change. Compare Flash with Flash or frontier with frontier, not across classes. Never blindly replace a cheap, fast model with a slow, expensive frontier reasoning model on low-effort or special-purpose rules. Place each by task effort, cost, and pool size in step 3.
3. A release in no catalog yet goes on the watch list for the report.

## 3. Placement: intelligence, coding value, and quota coverage

Match the **task's effort and volume** to **measured quality, coding ability, wall-clock time and useful work per quota unit**. Token prices and benchmark $/task describe efficiency, not the marginal bill for included subscription usage. Research and cite current figures with dates from all three evidence categories on every run:

1. **Role-specific benchmark quality, $/task, minutes/task, and tokens/task**: research current results and dated primary methodology for the role, not one overall coding score.
   - **Everyday feature implementation**: use SWE-rebench's latest qualifying task window, DeepSWE and FrontierCode.
   - **Hard multi-file changes**: use DeepSWE and FrontierCode. Add BOBA-Bench only when current comparable results establish chained-feature reliability, or Terminal-Bench for environment-heavy work.
   - **Independent code review**: consult CR-Bench and c-CRAB. Use Martian's online Code Review Bench for review products, not raw-model rankings. Review evidence is thinner: implementation scores never qualify a reviewer by themselves. Treat these as candidate evidence sets, not permanently trusted boards.
   - Compare exact model, effort, benchmark version, task window, harness and budget. Use fixed-harness results for model comparisons; label native-agent results as model-plus-harness evidence, not measured Pi performance. Keep uncertainty-overlapping candidates tied. Require corroboration from independently built, role-relevant evaluations before changing a placement; a vendor model card is not independent corroboration.
   - Run `scripts/aa-coding-agents.py` (`--json` for structured rows; token/step fields may be unavailable) for [Artificial Analysis Coding Agent Index](https://artificialanalysis.ai/agents/coding-agents) stack-quality and efficiency context. Inspect the index's current components; never count an aggregate and its components as separate confirming votes. Do not average incompatible scores or transfer an effort margin across benchmarks.
   - **Stale-benchmark rule**: reassess saturation, contamination, grading validity and maintenance on every refresh. Require documented held-out/original tasks or a verified post-training task window. Unknown cutoff or exposure remains a gap, not proof of freshness. Exclude affected versions or subsets when material test defects, solution leakage, ceiling clustering, obsolete tasks or missing current candidate coverage defeats this role's comparison. Re-admit only with documented repairs and current comparable results. Retain old versions for history, not current placement authority. SWE-bench Verified, unrepaired Pro public splits and frozen SWE-Lancer do not establish autonomous repository-feature or review quality. Neither do algorithm-only LiveCodeBench or UI-preference arenas. New versions earn admission under the same criteria.
   - When current independent role-specific evidence is missing, conflicting or unreachable, keep the placement and list the exact gap. Do not invent a model ranking or launch a local evaluation without separate authorization.
2. **Official provider token pricing**: check current $/1M input, output, and cached-input rates on the vendors' pricing pages (OpenAI, Anthropic, Google Gemini, xAI) to catch introductory-rate expirations, long-context multipliers, and cost differences between model classes.
3. **Account subscription and quota bounds**: run `quota-axi --full` before and after the step 4 probes. Record limiting windows, reset, pace, `spendPriority`, probe drain and shared supervisor load. Map every usable pool to suitable rules; explain any uncovered pool. A small pool is not an exclusion: find enough quality-appropriate work to use it before reset. API credit balances are money, not expiring subscription allowance; do not treat them as a spending target.
4. Placement rules:
   - **Match task effort and volume to cost and pool size**:
     - *Quick utility* (`recon`, `web research`, `images`, judging): fast, capable models with the required tools. Do not infer coding or judgment quality from low price alone.
     - *Good-value coding* (`everyday`, `default`): reliable implementation, bug fixes and tests. Include qualified candidates across subscription pools, not just the nominally cheapest vendor. Favor useful work per allowance and latency; let Firstmate spend available quota.
     - *Frontier intelligence* (`large`, `review`, `hardest`): sustained reasoning, risky changes and independent review. Include every verified frontier candidate that clears the role's quality bar; distinguish implementation from judgment evidence. Do not mistake a coding score for general intelligence or assume a small pool must sit idle.
   - **Effort per model**, from comparable role-specific results for that exact model, never "higher is better". In cost-sensitive tiers (`everyday`, `default`), use the cheapest effort whose quality is indistinguishable within the evaluation's uncertainty. In `large` and `hardest`, use the best-supported effort for the role. Never use an effort reliably worse than a cheaper one under comparable conditions. Missing, conflicting or inconclusive effort evidence keeps the current setting; name the gap in the report.
   - **Newer and as good replaces older** within the same cost/effort class, especially when cheaper.
   - **Reliably below the tier's best on comparable role-specific evidence** needs a justified cost/speed or fallback trade recorded concisely in the rule's `why`. Spare quota will make an eligible candidate win when higher-priority pools drain.
   - **Spend all usable allowance on suitable work**: quota size informs capacity, not a blanket tier ban. Expand a candidate into another tier only when quality evidence supports it. Keep exhausted candidates configured for reset; flag missing scope mappings and unused pools instead of hiding them. Do not bypass explicit supervisor reservations or account pins.
   - Native-agent scores measure model-plus-harness stacks; the fleet runs models through Pi. Treat transfer to Pi as directional, not measured.
   - **Our own evidence for judgment tiers** (hardest, review, secondmate): local evaluations require separate authorization; external evidence remains role-specific. When authorized to use our own runs for placement, use Fleet's principle cases. Grade every model's runs with the same two judges from different families. Use `skill-creator-fleet/scripts/cross_judge.py` and its `evaluation-workflow.md` section 8. Never compare models that different judges graded. On 2026-10-15, a per-model judge reversed a GPT-versus-Opus reading. Our runs need wins under both judges to support a placement change. Require sign-test p < 0.05 under each judge. Do not treat implementation cases as review qualification.

Special-purpose rules are placed by capability, not implementation benchmarks. Re-check which harnesses have each capability:

| Rule | Needs | How to find who has it |
|---|---|---|
| Live web facts | A web search tool | Pi models via the `pi-web-access` extension, Grok native search |
| Images | An image generation tool | Pi with the `pi-antigravity` extension (`generate_image`) |

For these, a fast model with a weak coding score is fine.

Show the user the role-specific evidence and the proposed placement before editing, unless they already named the change.

## 4. Verify each new model really works

Tool-test every model you add or move through the exact configured extension source, harness and effort. During a fleet-wide refresh, also test every selected active Secondmate, every backup entry and the no-mistakes selection, including kept selections. Reuse a current-run probe only for an identical route, model and effort. A working crew candidate does not verify another role's different route or effort; a saved backup is not proof its route works. Report a blocked probe rather than claiming verification.

- **Pi**: run this probe, substituting the selected model and effort:

  ```sh
  pi --model <provider/id> --thinking <effort> --no-session --no-context-files \
    --no-skills --no-prompt-templates --no-mcp --no-approve --mode json \
    -p 'Use your bash tool to run exactly `ls | head -2`. Reply DONE only after the command exits 0.' </dev/null
  ```

Check the tool's exit status; `DONE` alone is not a pass.

Run bounded probes from a fresh throwaway directory containing only invented synthetic fixtures. Never use project files, private files, historical session replay or other private input. Global Pi/Claude session export is retired; Langfuse is for Phrona's explicit native tracing only. Do not enable an exporter or provision tracing credentials for this probe. A passing probe runs the tool, prints `DONE` and exits within seconds. Its output confirms the actual provider, model and effort. Retain only synthetic local session/tool evidence and report that agent trace readback is intentionally unavailable, not a backend failure. A plain "reply OK" is not enough: some models answer that and still hang on the first tool call. For special-purpose rules also exercise the capability (a checkable `web_search`, a `generate_image`) when in scope. Without `</dev/null`, `pi -p` waits on stdin forever. If Pi replies but never exits, an extension is holding it open: bisect with `pi --no-extensions -e <path> ...`.

## 5. Edit, validate, and confirm Jev can pick it

Dispatch profile shape:

- `pi` profiles declare `provider` as `quota-axi` names it, not the Pi model prefix (`openai-codex/` is `codex`, `claude-bridge/` is `claude`, `xai/` is `grok`, `antigravity/` is `agy`, `cursor/` is `cursor`).
- Only `pi` and `grok` harnesses; Claude (`claude-bridge/`) and Antigravity (`antigravity/`) models go through Pi, never the `claude` or `agy` harnesses.
- Never set the top-level `preferred_provider`. Each rule lists the best qualified candidates for its tier, one per quota pool; Jev picks the rule and Firstmate picks among its candidates by quota. A preference for one vendor shows only in which candidates a rule lists.
- Meta/Muse profiles use `harness: pi` and the catalog-confirmed `meta/<id>`. Resolve their quota provider from the selected authentication route, not its name. Report an unbound Jev candidate under Gaps; never relabel it as native Muse to obtain a quota match.
- `when` is the only rule text the dispatch classifier sees. It reads the brief's intent and spec and picks one `when` as a Choice option; it never sees `use`, `why` or quota. Write `when` so a reader of the brief alone can pick the right rule:
  - Describe the task, never the model, harness, effort or cost.
  - Start with the kind of work, then concrete examples in the words briefs use.
  - Separate neighbouring tiers with an observable trait (size, ambiguity, prior failure) or an explicit "Not for ..." clause.
  - Maximum 30 words and two short sentences; usually one. Keep only examples that separate neighbouring rules.
- `why` states **only the decisive reason for that tier's candidate eligibility and fallback trade** (capability requirement, effort/cost boundary, cross-family rule, quota-window bound, or non-monotonic effort). Firstmate reads it when the classifier does not decide, and people read it when editing.
  - Omit anything that does not change a routing decision: no dates, history ("added on ...", "replaces ..."), benchmark numbers (put those in the step 6 report), or filler.
  - Write present-tense claims about this rule's `use` only ("Sol runs at xhigh because Sol high scores below Sol medium").
  - Maximum 35 words and two short sentences; usually one. State the trade, not the research behind it.
  - Re-read each `why` after every edit to confirm every claim matches its rule's `use`. Never describe array order as overriding quota ranking.

Run `bash tests/model_routing_test.sh` after edits. Its word limits guard every rule, not just the changed ones.

Then:

1. Edit all files consistently. Edit JSON with `jq` or exact full-line matches, and keep the file's one-line-per-profile style.
   Update each in-scope role's selected harness, model and effort, matching assertions and documentation. Keep Secondmate selections and their assertions in `tests/pi_settings_test.sh` consistent. For no-mistakes, check `agent`, the matching `agent_config` block and any winning argument overrides together. Confirm effective files resolve to the authored selections. A scoped primary-only change leaves the backup unchanged; a fleet-wide refresh requires a separate decision for every backup entry.
2. Validate `crew-dispatch.json` with Firstmate's own checker (do not run the whole `fm-bootstrap.sh`):
   ```sh
   cd ~/github/firstmate
   S=$(mktemp -d); mkdir "$S/cfg"; cp ~/github/dotfiles/home/.firstmate/crew-dispatch.json "$S/cfg/"
   sed -n '/^crew_dispatch_validate() {/,/^}/p' bin/fm-bootstrap.sh > "$S/v.sh"
   bash -c ". bin/fm-control-lib.sh; . bin/fm-quota-axi-lib.sh; install_cmd(){ :; }; fmx_env_get(){ :; }
     FM_HOME=$PWD CONFIG=$S/cfg; . $S/v.sh; crew_dispatch_validate"
   ```
   No output means valid.
3. **Quick live pick check**: run the actual resolver on a short synthetic brief per changed rule (all rules after a fleet-wide text rewrite). Jev chooses `when`; Firstmate, not Jev, binds quota and ranks candidates. Run from `~/github/firstmate`:
   ```sh
   B=$(mktemp)
   printf "## Captain's intent\nFix a bounded parser bug.\n\n## Firstmate spec\nChange one function and add focused tests; the implementation path is clear.\n" > "$B"
   bin/fm-dispatch-resolve.sh "$B" --project model-routing-smoke
   rm "$B"
   ```
   Confirm the expected rule, `status: clear`, and a `profile:` naming one of that rule's candidates at its configured effort. Check every candidate has `scope=` and numeric `spendPriority`. An available candidate must show `-> eligible`; an exhausted pool may be ineligible until reset and is not a mapping failure. A genuine tie/approval escalation is not a clear pick: report it. An off resolver, low-confidence match, API error or zero exit alone is not a pass.

   This resolver check covers crew dispatch only. It does not select or verify Secondmates, backups or no-mistakes: check their effective selections and exact-route tool probes separately, without launching a full validation pipeline merely to test a model.

   `eligible, unranked: no applicable quota row` is a resolver/config gap, not exhaustion; fix or flag it. Rerun an `unknown` row once, unless the quota endpoint is rate-limited: respect its retry-after and stop additional live checks rather than hammering it. Check neighboring rules with contrasting briefs so shortening `when` does not merge their meanings. Keep this a direct check, not a new harness or swarm. Run Firstmate's existing offline resolver tests if changing resolver code; a mocked pass is not live Jev verification.

## 6. Report

Start the answer with this table: no summary, verdict or other table before it. It covers every model that is new, moved, or removed. A model that stays put is not in the table.

| Model | Harness | Change | Used in (tier @ effort) | Role-specific sources · quality · $/task · min | Verified |
|---|---|---|---|---|---|
| `<model>` | Pi / Grok | 🆕 added · ⬆️ moved · 🔁 effort · ❌ removed | e.g. hardest @ high | named role-specific sources/results + token rate + quota bound, with citations/dates | ✅ tools · ✅ Firstmate ranks, or ⚠️ with the gap |

Name benchmark versions, task windows and harnesses in each evidence cell. Then only these short lists. Add no other sections: placement reasoning belongs in the table's evidence column.

- **Role coverage**: one line each for crew dispatch, active Secondmates, every backup entry and no-mistakes. Name the selected model(s)/effort, changed/kept/blocked/out-of-scope decision, short reason and verification. A fleet-wide refresh must account for all four roles, even when unchanged; a narrower run must mark excluded roles out of scope.
- **Watch list**: released but not runnable on this account yet.
- **Kept out on purpose**: model and reason.
- **Gaps**: blocked/unranked candidates, unused quota pools, catalog drift, and quick-pick results (expected rule, actual profile, or concrete failure). Include validation commands/results here; do not call an unrun check passed.
- **Rule text**: each `when` or `why` edit, with the claim it fixes.

Keep the report compact: one brief reason per table row or list item, no research narrative. State whether edits are committed/pushed; never ship a known routing regression.

- Reminder: secondmate homes only receive `crew-dispatch.json` when their sync is not skipped, and remote (Mac mini) homes refuse it while it is a symlink.
