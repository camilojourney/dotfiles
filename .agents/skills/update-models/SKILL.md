---
name: update-models
description: Use when changing or re-checking which AI models the agent fleet uses - a new model release, a retired model, a new provider or harness (e.g. Antigravity via Pi), or a periodic "are we on the newest, best-placed models?" review. Covers finding every model each harness can actually run, checking for newer releases, placing each model in the right Firstmate dispatch tier from coding benchmarks (and the right special-purpose rule for web research and images), verifying each one really works with tools, and editing every file that names a model.
---

# update-models

The goal is three things, in this order:

1. **Newest**: no tier uses a model when a newer, better one is runnable.
2. **Available**: every model in the config actually runs on this account, with tools, through the harness the config names.
3. **Right place**: each model sits in the tier its quality (or capability) earns.

Models, scores, efforts and quota pools change all the time. Every rule below is a method; any concrete model, score or number in this file is a dated example, never a value to keep. Re-derive everything from today's catalogs and benchmarks on each run.

Quota is not this skill's concern. At dispatch time Jev picks, within a tier, the candidate with the most spare quota (`spendPriority` from `quota-axi`) and skips an exhausted provider until its reset. So never drop a model for being low on quota today. One consequence matters: a candidate with spare quota wins most of its tier's tasks. So every candidate in a tier must be good enough for that tier's work.

Nothing runs this skill automatically. The daily auto-update (`docs/AUTO-UPDATE.md`) upgrades tools but never changes which models the fleet uses and does not refresh Pi's model catalog. A change pushed to `main` reaches both machines at the next 05:00 run.

This skill lives in `.agents/skills/`; `.claude/skills` is a symlink to that directory, so edit it there only.

## Where models are set

| File | Controls | Takes effect |
|---|---|---|
| `home/.firstmate/crew-dispatch.json` | Model per crewmate task, by rule | Immediately (symlinked into `~/github/firstmate/config/`) |
| `home/.firstmate/secondmate-harness` | Secondmate runtime, one line: `<harness> <model> <effort>` | Next secondmate launch |
| `home/.pi/agent/settings.json` | Pi `defaultModel` | Immediately |
| `home/.no-mistakes/config.yaml` | no-mistakes pipeline `agent` / `agent_config` (one agent for every step) | Immediately (symlinked) |
| `tests/pi_settings_test.sh` | Pins Pi `defaultModel`; must match settings.json | Run `bash tests/pi_settings_test.sh` |
| `home/.claude/settings.json` | Claude Code's interactive default `model` | Next Claude Code session |

Keep the family alias (e.g. `opus`) in `home/.claude/settings.json`: it follows each new release. Exact ids belong in dispatch config, where runs must be reproducible.

All are symlinked by `nix/home.nix`; a new model-bearing file belongs there too. Find stragglers with `grep -rnE 'gpt-|grok-|gemini-|opus|sonnet|haiku' home/ tests/`.

## 1. Inventory: what can each harness run right now?

Run every catalog, every time. The vendor's own catalog is the authority; never infer a model name from a version pattern.

| Harness | Catalog command | Notes |
|---|---|---|
| Pi | `pi update --models`, then `pi --list-models <provider>` | A provider extension's list is not proof a model is served. It can keep retired models and miss new ones. Confirm each id in the vendor's own catalog (for Antigravity, `agy models`). An id only Pi lists is not a candidate. Pi also accepts an unlisted `provider/id` with a "Using custom model id" warning; confirm those the same way. |
| Antigravity | `agy models` | The authority for Antigravity. Lists Gemini and the other vendors' models Antigravity serves, each with effort suffixes. Every listed model is a candidate for every tier, placed by the same rules as the same model elsewhere. Dispatch through Pi only: strip the suffix (`<model>-high` is `antigravity/<model>`) and set effort with Pi's `--thinking`. The highest suffix listed is Antigravity's effort ceiling for that model. Judge it by the index row at that effort, not a higher one it cannot run. |
| Claude Code | `claude --model <id> -p "Reply with exactly the model name you are" </dev/null` | Dispatch config uses exact model ids, never the `opus`/`sonnet`/`haiku` aliases, which silently move. An `unrecognized_model` warning proves nothing: the step 4 tool test decides whether the id runs. Never dispatch `fable`: it stalls unattended on a usage-credit prompt. |
| Codex via Pi | `pi --list-models openai-codex` | |
| Claude via Pi | `pi --list-models claude-bridge` | The `pi-claude-bridge` extension runs Claude models in Pi through Claude Code's Agent SDK, on the Claude subscription pool. Dispatch as `pi` with `claude-bridge/<id>`. It is another harness for the same model, so compare it to Claude Code before routing to it. |
| Grok TUI | `grok models` | |
| Cursor via Pi | `pi --list-models cursor` | Re-test each run. As of 2026-10-04 only `cursor/auto` was accepted and it stalled on any tool call, so Cursor was not dispatchable. |

A provider error like `X is no longer available. Please switch to Y` is a retirement notice: replace X everywhere and check Y.

When a catalog lists a model the vendor no longer serves, find the cause before working around it. Read the extension's catalog code and compare it with the vendor's raw list. Fix it upstream or in our fork, and record it under Gaps until the fix ships. Example (2026-10-11): pi-antigravity 0.10.0 appends its built-in model list to the server's. So Pi listed `claude-sonnet-4-6` after the server dropped it.

The reverse gap also happens: a model the vendor serves that the extension cannot route. pi-antigravity maps each id to an internal backend code, and sends an unmapped id as-is. The server then answers `429 ResourceExhausted` with `matched=none` even with quota to spare. So a 429 on a custom id, while the vendor's own CLI runs the model (`agy --model <id>-high -p ...`), is a missing mapping, not quota: record it under Gaps until the extension adds the model. Example (2026-10-16): Gemini 4 Argon ran in `agy` but not through pi-antigravity 0.9.0 or 0.10.0.

## 2. Newer models: is anything better released?

1. `scripts/aa-coding-agents.py --releases` lists recent releases from the vendors the fleet can run, newest first. Also check vendor release notes or news for releases the page has not added.
2. For each family the config uses, its newest runnable version replaces the older one unless benchmarks show it worse. This applies to every family on every run, Gemini included: rules that use a Gemini model use the newest Gemini in `agy models`.
3. A release in no catalog yet goes on the watch list for the report.

## 3. Placement: which tier earns which model?

Coding tiers (recon, everyday, large, hardest, review, default) are placed from benchmarks:

1. `scripts/aa-coding-agents.py` prints the [Artificial Analysis Coding Agent Index](https://artificialanalysis.ai/agents/coding-agents) with score, $/task and minutes/task per agent + model + effort. If it fails, read the page in a browser (a plain fetch shows "Not publicly available").
2. Cross-check any tier change with one independent source (SWE-Bench Pro, a vendor post). One benchmark alone misleads. On 2026-10-04 a Flash model reported a strong SWE-Bench Pro score but sat about 20 points under the index leaders. When no independent source is reachable, keep the tier and list the change under Gaps.
3. Rules:
   - **Quality first**: a tier's candidates are the highest-scoring runnable models. Cost breaks ties only within about 2 points.
   - **Effort per model**, from that model's own index rows, never "higher is better". The same step up can help one model a lot, another not at all, and some it hurts. In cost-sensitive tiers (everyday, default), use the cheapest effort within about 2 points of the model's best. In large and hardest, use its best-scoring effort. Never use an effort that scores below a cheaper one. An effort with no index row keeps its current setting; say so in the report.
   - **Newer and as good replaces older**, especially when cheaper.
   - **Below the tier's best by more than about 2 points** needs a user-approved trade (e.g. far cheaper or faster). Record it in the rule's `why`. Spare quota will make it win. A trade already recorded in `why` is approved. Reopen it only when new scores change the gap by more than about 2 points.
   - **Pool size decides only where a second route goes.** A model reached through another harness (e.g. Opus through Antigravity) has the same quality but may draw on a separate pool. Size that extra pool by how fast it drains: run `quota-axi --full` before and after the step 4 probes. A pool that a handful of probes visibly moves is small. A small extra pool goes only in low-volume tiers (review, hardest). A large one can also serve high-volume rules (recon, web research, images). A provider's main pool never decides placement: Jev balances it at dispatch.
   - Scores come from each vendor's own agent; the fleet often runs the model through Pi. Treat them as directional.
   - **Our own evidence for judgment tiers** (hardest, review, secondmate): the index ranks reasoning, but to move a model in or out of these tiers on our own runs, use Fleet's principle cases. Grade every model's runs with the same two judges from different families (`skill-creator-fleet/scripts/cross_judge.py`; its `evaluation-workflow.md` section 8). Never compare models that different judges graded: on 2026-10-15 a per-model judge reversed a GPT-versus-Opus reading. Our result overrides the index only when it wins under both judges at sign-test p < 0.05.
   - **Harness is a variable too**: the same model through Claude Code and through Pi (`claude-bridge/`) can differ. Compare them with the same cases and judges before choosing the harness for a tier.

Special-purpose rules are placed by capability, not the coding index. Re-check which harnesses have each capability:

| Rule | Needs | How to find who has it |
|---|---|---|
| Live web facts | A web search tool | Pi models via the `pi-web-access` extension, Claude Code built-in search, Grok native search |
| Images | An image generation tool | Pi with the `pi-antigravity` extension (`generate_image`) |

For these, a fast model with a weak coding score is fine.

Show the user the benchmark rows and the proposed placement before editing, unless they already named the change.

## 4. Verify each new model really works

For every model you add or move, through the exact harness and effort the config will use:

- **Pi**: `pi --model <provider/id> --thinking <effort> -p "Use your bash tool to run: ls | head -2. Then reply DONE" </dev/null`
- **Claude Code**: `claude --model <id> --effort <effort> --dangerously-skip-permissions -p "Use your Bash tool to run: ls | head -2. Then reply DONE" </dev/null`

Pass means it ran the tool, printed `DONE`, and exited within seconds. A plain "reply OK" is not enough: some models answer that and still hang on the first tool call. For special-purpose rules also exercise the capability (a checkable `web_search`, a `generate_image`). Without `</dev/null` both CLIs wait on stdin forever. If Pi replies but never exits, an extension is holding it open: bisect with `pi --no-extensions -e <path> ...`.

## 5. Edit, validate, and confirm Jev can pick it

Dispatch profile shape:

- `pi` profiles declare `provider` as `quota-axi` names it, not the Pi model prefix (`openai-codex/` is `codex`, `xai/` is `grok`, `antigravity/` is `agy`, `cursor/` is `cursor`).
- Only `pi`, `claude`, and `grok` harnesses; Antigravity models go through Pi.
- `when` is the only rule text the dispatch classifier sees. It reads the brief's intent and spec and picks one `when` as a Choice option; it never sees `use`, `why` or quota. Write `when` so a reader of the brief alone can pick the right rule:
  - Describe the task, never the model, harness, effort or cost.
  - Start with the kind of work, then concrete examples in the words briefs use.
  - Separate neighbouring tiers with an observable trait (size, ambiguity, prior failure) or an explicit "Not for ..." clause.
  - Keep it to one or two short sentences.
- `why` is optional. Firstmate reads it when the classifier does not decide, and people read it when editing. Use it only for a choice a future editor would otherwise undo. That means a capability limit, a deliberate restriction, a user-approved trade, or a surprising effort.
  - Write present-tense claims about this rule's `use` only ("X runs at xhigh: X high scores below X medium").
  - When a fact applies to several rules, use the same words in each.
  - Leave out benchmark numbers, history ("replaces ..."), quota mechanics, and anything `when`/`use` already says.
  - After every edit, re-read each `why` against its rule's `use`. A claim like "used only here" breaks as soon as the model joins another tier.

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
| `<model>` | Pi / Claude Code / Grok | 🆕 added · ⬆️ moved · 🔁 effort · ❌ removed | e.g. hardest @ high | index row, or the capability tested | ✅ tools · ✅ Jev ranks, or ⚠️ with the gap |

Then only these short lists. Add no other sections: placement reasoning belongs in the table's score column.

- **Watch list**: released but not runnable on this account yet.
- **Kept out on purpose**: model and reason.
- **Gaps**: anything that blocks a candidate from being picked (e.g. unranked in Jev), or a catalog that lists models the vendor does not serve.
- **Rule text**: each `when` or `why` edit, with the claim it fixes.
- Reminder: secondmate homes only receive `crew-dispatch.json` when their sync is not skipped, and remote (Mac mini) homes refuse it while it is a symlink.
