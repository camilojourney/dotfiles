---
name: update-models
description: Use when changing or re-checking which AI models the agent fleet uses - a new model release, a retired model, a new provider or harness (e.g. Antigravity via Pi), or a periodic "are we on the newest, best-placed models?" review. Covers finding every model each harness can actually run, checking for newer releases, placing each model in the right Firstmate dispatch tier from coding benchmarks (and the right special-purpose rule for web research and images), verifying each one really works with tools, and editing every file that names a model.
---

# update-models

The goal is three things, in this order:

1. **Newest**: no tier uses a model when a newer, better one is runnable.
2. **Available**: every model in the config actually runs on this account, with tools, through the harness the config names.
3. **Right place**: each model sits in the tier its quality (or capability) earns.

Models, scores, efforts and quota pools change all the time. Every rule below is a method; concrete model examples are dated evidence, not defaults to impose. Explicit task selections and approved trades take precedence: preserve them, unrelated defaults and account pins during a scoped refresh. A discovery fix does not authorize a tier sweep.

Quota is not this skill's concern. At dispatch time Jev picks, within a tier, the candidate with the most spare quota (`spendPriority` from `quota-axi`) and skips an exhausted provider until its reset. So never drop a model for being low on quota today. One consequence matters: a candidate with spare quota wins most of its tier's tasks. So every candidate in a tier must be good enough for that tier's work.

Nothing runs this skill automatically. The daily auto-update (`docs/AUTO-UPDATE.md`) upgrades tools but never changes which models the fleet uses and does not refresh Pi's model catalog. A change pushed to `main` reaches both machines at the next 05:00 run.

This skill lives in `.agents/skills/`; `.claude/skills` is a symlink to that directory, so edit it there only.

## Where models are set

| File | Controls | Takes effect |
|---|---|---|
| `home/.firstmate/crew-dispatch.json` | Model per crewmate task, by rule | Immediately (symlinked into `~/github/firstmate/config/`) |
| `home/.firstmate/secondmate-harness` | Secondmate runtime, one line: `<harness> <model> <effort>` | Next secondmate launch |
| `home/.pi/agent/settings.json` | Pi `defaultModel` | Immediately |
| `home/.pi/agent/settings.json` `compaction.modelOverrides` | Per-model compaction trigger; a new 1M Claude or resized GPT window needs a line ([docs/PI-COMPACTION.md](../../../docs/PI-COMPACTION.md)) | Immediately |
| `home/.no-mistakes/config.yaml` | no-mistakes pipeline `agent` / `agent_config` (one agent for every step) | Immediately (symlinked) |
| `tests/pi_settings_test.sh` | Pins Pi `defaultModel`; must match settings.json | Run `bash tests/pi_settings_test.sh` |
| `home/.claude/settings.json` | Claude Code's interactive default `model` | Next Claude Code session |

Keep the family alias (e.g. `opus`) in `home/.claude/settings.json`: it follows each new release. Exact ids belong in dispatch config, where runs must be reproducible.

All are symlinked by `nix/home.nix`; a new model-bearing file belongs there too. Find stragglers with `grep -rnE 'gpt-|grok-|gemini-|opus|sonnet|haiku' home/ tests/`.

## 1. Inventory: what can each harness run right now?

For a fleet-wide review, run every catalog. For a scoped model/provider refresh, inventory the affected provider and configured route without changing unrelated selections. The vendor's own catalog is the authority; never infer a model name from a version pattern.

| Harness | Catalog command | Notes |
|---|---|---|
| Pi | `pi update --models`, then `pi --list-models <provider>` | A provider extension's list is not proof a model is served. It can keep retired models and miss new ones. Confirm each id in the vendor's own catalog (for Antigravity, `agy models`). An id only Pi lists is not a candidate. Pi also accepts an unlisted `provider/id` with a "Using custom model id" warning; confirm those the same way. |
| Antigravity | `agy models` | The authority for Antigravity. Lists Gemini and the other vendors' models Antigravity serves, each with effort suffixes. Every listed model is a candidate for every tier, placed by the same rules as the same model elsewhere. Dispatch through Pi only: strip the suffix (`<model>-high` is `antigravity/<model>`) and set effort with Pi's `--thinking`. The highest suffix listed is Antigravity's effort ceiling for that model. Judge it by the index row at that effort, not a higher one it cannot run. |
| Codex via Pi | `pi --list-models openai-codex` | |
| Claude via Pi | `pi --list-models claude-bridge` | The `pi-claude-bridge` extension runs Claude models in Pi through Claude Code's Agent SDK, on the Claude subscription pool. Dispatch through Pi only as `claude-bridge/<id>` with `provider` `claude`, never the `claude` harness. Use exact model ids, never the `opus`/`sonnet`/`haiku` aliases, which silently move. A prior `fable` probe stalled on a usage-credit prompt; retain an explicitly selected candidate and report its current tool-test result rather than removing it from dated prose. |
| Grok TUI | `grok models` | |
| Cursor via Pi | `pi --list-models cursor` | Re-test each run. As of 2026-10-04 only `cursor/auto` was accepted and it stalled on any tool call, so Cursor was not dispatchable. |

A provider error like `X is no longer available. Please switch to Y` is a retirement notice: replace X everywhere and check Y.

When a catalog lists a model the vendor no longer serves, find the cause before working around it. Read the extension's catalog code and compare it with the vendor's raw list. Fix it upstream or in our fork, and record it under Gaps until the fix ships. Example (2026-10-11): pi-antigravity 0.10.0 appends its built-in model list to the server's. So Pi listed `claude-sonnet-4-6` after the server dropped it.

The reverse gap also happens: a model the vendor serves that the extension cannot reach. The server answers `429 ResourceExhausted` with `matched=none` even with quota to spare. So a 429 on a custom id, while the vendor's own CLI runs the model (`agy --model <id>-high -p ...`), is an extension gap, not quota. Search the extension's open issues and pull requests before debugging, and record it under Gaps until a fix ships. Example (2026-10-16): pi-antigravity 0.9.0 and npm 0.10.0 announced an old Antigravity client version, so the backend hid Gemini 4 Argon ([issue 93](https://github.com/Rahularya01/pi-antigravity/issues/93), [issue 94](https://github.com/Rahularya01/pi-antigravity/issues/94)). Reuse that evidence before investigating the same failure again; check current releases and fixes before reinstalling npm latest.

For Argon, `agy models` currently advertises `gemini-4-argon-{low,medium,high}`. Pi's logical id is `antigravity/gemini-4-argon`; `--thinking high` must route to the exact `gemini-4-argon-high` runtime, not Flash or another provider. The configured Git extension pin contains the discovery fix while npm latest remains 0.10.0. Refresh with `pi update --models` after the fixed source is installed; headless inference alone is not a catalog refresh. Compare the refreshed Pi list with `agy models`, not the extension's built-in fallback list. Never edit `models-store.json` or add a static Argon override to conceal a discovery failure. Catalog presence and offline routing tests are not live tool verification.

## 2. Newer models: is anything better released?

1. `scripts/aa-coding-agents.py --releases` lists recent releases from the vendors the fleet can run, newest first. Also check vendor release notes or news for releases the page has not added.
2. Within the same cost and latency class (e.g. a new Flash vs an older Flash, or a new frontier model vs an older frontier model), the newest runnable version replaces the older one unless benchmarks or cost-to-run show it worse. Never blindly replace a cheap, fast model (e.g. Gemini Flash) with a slow, expensive frontier reasoning model (e.g. Gemini Argon) on low-effort or special-purpose rules: place each by task effort, cost, and pool size in step 3.
3. A release in no catalog yet goes on the watch list for the report.

## 3. Placement: weigh task effort, cost-to-run, and quota bounds

Every tier is placed by matching the **task's effort and volume** against **measured quality, cost-to-run, wall-clock time, token pricing, and account quota bounds**. Research and cite current figures with dates from all three authoritative sources on every run:

1. **Benchmark score, $/task, minutes/task, and tokens/task**: run `scripts/aa-coding-agents.py` (`--json` for tokens/steps) for the [Artificial Analysis Coding Agent Index](https://artificialanalysis.ai/agents/coding-agents), and cross-check any tier change with one independent source (SWE-Bench Pro, DeepSWE, or the vendor's release model card). One benchmark alone misleads: on 2026-10-04 a Flash model reported a strong SWE-Bench Pro score but sat about 20 points under the index leaders. When no independent source is reachable, keep the tier and list the change under Gaps.
2. **Official provider token pricing**: check current $/1M input, output, and cached-input rates on the vendors' pricing pages (OpenAI, Anthropic, Google Gemini, xAI) to catch introductory-rate expirations, long-context multipliers, and cost differences between model classes.
3. **Account subscription and quota bounds**: run `quota-axi --full` before and after the step 4 probes. Note which windows bound each provider scope (e.g. 5-hour session vs 7-day weekly vs model-specific weekly windows), how much a handful of probes drains each window, and whether supervisor roles (Firstmate, second mates) already draw from that pool.
4. Placement rules:
   - **Match task effort and volume to cost and pool size**:
     - *Trivial or non-coding rules* (`recon`, `web research`, `images`): high volume, low reasoning effort. Use fast, low-cost models on large quota pools (e.g. Luna, Gemini Flash) so workhorse and frontier pools are not burned on lookups or asset calls.
     - *Workhorse coding* (`everyday`, `default`): high volume, moderate effort. Lead with the model that delivers strong coding quality at the lowest $/task and minutes/task (e.g. Sol medium at $0.70/task and 10.9 min rather than a $5-$14/task, 35-87 min frontier model).
     - *High-effort, low-volume tiers* (`large`, `review`, `hardest`): complex multi-file refactors, cross-family review, and root-cause/architecture work justify higher $/task, longer runtimes, and small weekly quota pools (e.g. Claude max models, Sol xhigh, Gemini Argon high, Antigravity Opus high).
   - **Effort per model**, from that model's own index rows, never "higher is better". The same step up can help one model a lot, another not at all, and some it hurts. In cost-sensitive tiers (`everyday`, `default`), use the cheapest effort within about 2 points of the model's best. In `large` and `hardest`, use its best-scoring effort. Never use an effort that scores below a cheaper one (e.g. Sol high below Sol medium). An effort with no index row keeps its current setting; say so in the report.
   - **Newer and as good replaces older** within the same cost/effort class, especially when cheaper.
   - **Below the tier's best by more than about 2 points** needs a justified cost/speed or fallback trade recorded concisely in the rule's `why`. Spare quota will make an eligible candidate win when higher-priority pools drain.
   - **Small quota windows stay in low-volume tiers**: if `quota-axi --full` shows a model or route has a small weekly/session window (a few probes move it by several percent, such as Antigravity's `claude_gpt` pool or Argon's separate weekly window) or shares a heavily loaded supervisor pool, restrict it to low-volume tiers (`review`, `large`, `hardest`).
   - Scores come from each vendor's own agent; the fleet runs models through Pi. Treat them as directional.
   - **Our own evidence for judgment tiers** (hardest, review, secondmate): the index ranks reasoning, but to move a model in or out of these tiers on our own runs, use Fleet's principle cases. Grade every model's runs with the same two judges from different families (`skill-creator-fleet/scripts/cross_judge.py`; its `evaluation-workflow.md` section 8). Never compare models that different judges graded: on 2026-10-15 a per-model judge reversed a GPT-versus-Opus reading. Our result overrides the index only when it wins under both judges at sign-test p < 0.05.

Special-purpose rules are placed by capability, not the coding index. Re-check which harnesses have each capability:

| Rule | Needs | How to find who has it |
|---|---|---|
| Live web facts | A web search tool | Pi models via the `pi-web-access` extension, Grok native search |
| Images | An image generation tool | Pi with the `pi-antigravity` extension (`generate_image`) |

For these, a fast model with a weak coding score is fine.

Show the user the benchmark rows and the proposed placement before editing, unless they already named the change.

## 4. Verify each new model really works

For every model you add or move, through the exact configured extension source, harness and effort:

- **Pi**: `pi --model <provider/id> --thinking <effort> --no-session --no-context-files --no-skills --no-prompt-templates --no-mcp --no-approve --mode json -p "Use your bash tool to run: ls | head -2. Then reply DONE" </dev/null`

Run bounded probes from a fresh throwaway directory containing only invented synthetic fixtures, with no project/private files, no historical session replay and no private input. For this synthetic-only probe, the existing local Pi tracer (`PI_OTEL_EXPORTER_OTLP_ENDPOINT`, currently `http://localhost:3000/api/public/otel` on the laptop) may capture the fixed synthetic prompt/tool content and ordinary runtime metadata; do not label that capture metadata-only, do not expose or copy credentials/headers, and keep ordinary private-data protections and exporter settings unchanged for all other work. Pass means the probe ran the tool, printed `DONE`, exited within seconds, confirmed the actual provider/model/effort in the run output, and read back that exact run's trace (`attributes.pi.session.id` and `attributes.pi.tool.call_id`, not an unrelated canary) from the existing local tracing destination. If trace readback fails, report the concrete backend failure under Gaps without blocking independent dispatcher/config validation. A plain "reply OK" is not enough: some models answer that and still hang on the first tool call. For special-purpose rules also exercise the capability (a checkable `web_search`, a `generate_image`) when in scope. Without `</dev/null`, `pi -p` waits on stdin forever. If Pi replies but never exits, an extension is holding it open: bisect with `pi --no-extensions -e <path> ...`.

## 5. Edit, validate, and confirm Jev can pick it

Dispatch profile shape:

- `pi` profiles declare `provider` as `quota-axi` names it, not the Pi model prefix (`openai-codex/` is `codex`, `claude-bridge/` is `claude`, `xai/` is `grok`, `antigravity/` is `agy`, `cursor/` is `cursor`).
- Only `pi` and `grok` harnesses; Claude (`claude-bridge/`) and Antigravity (`antigravity/`) models go through Pi, never the `claude` or `agy` harnesses.
- `when` is the only rule text the dispatch classifier sees. It reads the brief's intent and spec and picks one `when` as a Choice option; it never sees `use`, `why` or quota. Write `when` so a reader of the brief alone can pick the right rule:
  - Describe the task, never the model, harness, effort or cost.
  - Start with the kind of work, then concrete examples in the words briefs use.
  - Separate neighbouring tiers with an observable trait (size, ambiguity, prior failure) or an explicit "Not for ..." clause.
  - Keep it to one or two short sentences.
- `why` states **only the decisive reason for that tier's candidate choice and order** (capability requirement, effort/cost boundary, cross-family rule, quota-window bound, or non-monotonic effort). Firstmate reads it when the classifier does not decide, and people read it when editing.
  - Omit anything that does not change a routing decision: no dates, history ("added on ...", "replaces ..."), benchmark numbers (put those in the step 6 report), or filler.
  - Write present-tense claims about this rule's `use` only ("Sol runs at xhigh because Sol high scores below Sol medium").
  - Re-read each `why` after every edit to confirm every claim matches its rule's `use`.

Then:

1. Edit all files consistently. Edit JSON with `jq` or exact full-line matches, and keep the file's one-line-per-profile style.
2. Validate `crew-dispatch.json` with Firstmate's own checker (do not run the whole `fm-bootstrap.sh`):
   ```sh
   cd ~/github/firstmate
   S=$(mktemp -d); mkdir "$S/cfg"; cp ~/github/dotfiles/home/.firstmate/crew-dispatch.json "$S/cfg/"
   sed -n '/^crew_dispatch_validate() {/,/^}/p' bin/fm-bootstrap.sh > "$S/v.sh"
   bash -c ". bin/fm-control-lib.sh; . bin/fm-quota-axi-lib.sh; install_cmd(){ :; }; fmx_env_get(){ :; }
     FM_HOME=$PWD CONFIG=$S/cfg; . $S/v.sh; crew_dispatch_validate"
   ```
   No output means valid.
3. Confirm Jev can rank each new candidate: write a brief whose `## Captain's intent` and `## Firstmate spec` fit the tier, then run `bin/fm-dispatch-resolve.sh <brief> --project <name>` from `~/github/firstmate`. Every candidate must show `-> eligible` with a `scope=` and a numeric `spendPriority`; which one wins today does not matter. `eligible, unranked: no applicable quota row` means the resolver cannot bind the model to a quota row, so it never wins. That is a resolver or config gap to fix or flag, not a quota state. (As of 2026-10-10, Antigravity models rank only with firstmate PR #6569, which binds `antigravity/<id>` to quota-axi's `gemini`/`claude_gpt` scopes; check whether it has merged.) Re-run once before trusting an `unknown` row.

## 6. Report

Start the answer with this table: no summary, verdict or other table before it. It covers every model that is new, moved, or removed. A model that stays put is not in the table.

| Model | Harness | Change | Used in (tier @ effort) | Score · $/task · min | Verified |
|---|---|---|---|---|---|
| `<model>` | Pi / Grok | 🆕 added · ⬆️ moved · 🔁 effort · ❌ removed | e.g. hardest @ high | index row + token rate + quota bound, with cited sources/dates | ✅ tools · ✅ Jev ranks, or ⚠️ with the gap |

Then only these short lists. Add no other sections: placement reasoning belongs in the table's score column.

- **Watch list**: released but not runnable on this account yet.
- **Kept out on purpose**: model and reason.
- **Gaps**: anything that blocks a candidate from being picked (e.g. unranked in Jev), or a catalog that lists models the vendor does not serve.
- **Rule text**: each `when` or `why` edit, with the claim it fixes.
- Reminder: secondmate homes only receive `crew-dispatch.json` when their sync is not skipped, and remote (Mac mini) homes refuse it while it is a symlink.
