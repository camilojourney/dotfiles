---
name: update-models
description: Use when changing or re-checking which AI models the agent fleet uses - a new model release, a retired model, a new provider or harness (e.g. Antigravity via agy or Pi), or a periodic "are we on the newest, best-placed models?" review. Covers finding every model each harness can actually run, checking for newer releases, placing each model in the right Firstmate dispatch tier from coding benchmarks (and the right special-purpose rule for web research and images), verifying each one really works with tools, and editing every file that names a model.
---

# update-models

The goal is three things, in this order:

1. **Newest**: no tier uses a model when a newer, better one is runnable.
2. **Available**: every model in the config actually runs on this account, with tools, through the harness the config names.
3. **Right place**: each model sits in the tier its quality (or capability) earns.

Quota is not this skill's concern. At dispatch time Jev picks, within a tier, the candidate with the most spare quota (`spendPriority` from `quota-axi`), and an exhausted provider is skipped automatically until its reset. So never drop or demote a model because it is low on quota today. The only quota fact that matters here is the consequence of that ranking: a model with spare quota will win most of its tier's tasks, so every candidate in a tier must be good enough to do that tier's work.

Nothing runs this skill automatically. The daily auto-update (`docs/AUTO-UPDATE.md`) upgrades tool versions on both machines - Pi, quota-axi, Pi extensions, Homebrew - but never changes which models the fleet uses and does not refresh Pi's model catalog. New models reach the fleet only through this skill. A change pushed to `main` reaches the remote box at its next 05:00 run.

This skill lives in `.agents/skills/`; `.claude/skills` is a symlink to that directory, so edit it there only.

## Where models are set

| File | Controls | Takes effect |
|---|---|---|
| `home/.firstmate/crew-dispatch.json` | Model per crewmate task, by rule | Immediately (symlinked into `~/github/firstmate/config/`) |
| `home/.firstmate/secondmate-harness` | Secondmate runtime, one line: `<harness> <model> <effort>` | Next secondmate launch |
| `home/.pi/agent/settings.json` | Pi `defaultModel` | Immediately |
| `home/.no-mistakes/config.yaml` | no-mistakes pipeline `agent` / `agent_config` (one agent for every step, review included) | Immediately (symlinked to `~/.no-mistakes/config.yaml`) |
| `tests/pi_settings_test.sh` | Pins Pi `defaultModel`; must match `home/.pi/agent/settings.json` | Run `bash tests/pi_settings_test.sh` |

All are symlinked by `nix/home.nix` and shared by both machines; a new model-bearing file belongs there too. Find stragglers with `grep -rnE 'gpt-|grok-|gemini-|opus|sonnet|haiku' home/ tests/`.

## 1. Inventory: what can each harness run right now?

Build the list of runnable models from each harness's own catalog. Each catalog is the authority for its harness; never infer a name from a version pattern.

| Harness | Catalog command | Notes |
|---|---|---|
| Pi | `pi --list-models <search>` | Refresh first with `pi update --models`; the daily rebuild does not. A provider extension's list can lag the vendor: Pi still listed `antigravity/claude-sonnet-4-6` after Antigravity retired it, and did not list Sonnet/Opus 5.5. Pi accepts an unlisted `provider/id` with a "Using custom model id" warning, so check the vendor's own catalog for those. |
| Antigravity (`agy`) | `agy models` | Authoritative for Antigravity. It also serves Claude/GPT models (e.g. `claude-opus-5-5-high`) from a separate, smaller pool (see placement rules). Ids carry the effort suffix; effort caps at `high`. |
| Claude Code | `claude --model <id> -p "Reply with exactly the model name you are" </dev/null` | Use exact model ids, never the `opus`/`sonnet`/`haiku` aliases, so the config names the model that runs: `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-4-5-20251001` (2026-10-04). Aliases silently move to a new model; exact ids move only when this skill bumps them after the step 2 release check. Never dispatch `fable`: it stalls unattended on a usage-credit prompt. |
| Codex models via Pi | `pi --list-models openai-codex` | |
| Grok TUI | `grok models` | |
| Cursor via Pi | `pi --list-models cursor` | On this plan only `cursor/auto` is accepted (named models return `resource_exhausted`), and it stalls on any tool call (`UNHANDLED exec case`). Not dispatchable until the `pi-cursor-provider` fork fixes that. |

A provider error like "X is no longer available. Please switch to Y" is a retirement notice: replace X everywhere and check Y's catalog entry.

## 2. Newer models: is anything better released?

1. `scripts/aa-coding-agents.py --releases` lists the newest non-deprecated releases from the vendors the fleet can run (OpenAI, Anthropic, Google, xAI, Moonshot, DeepSeek, Meta), newest first.
2. For each release newer than what its tier uses, check whether it is in the step 1 inventory. Not in any catalog yet (e.g. Gemini 4 Argon on 2026-10-04): note it for the user as "released, not available on this account yet" and move on.
3. Also check news or the vendor's release notes for releases the page has not added yet.

## 3. Placement: which tier earns which model?

Coding tiers (recon, everyday, large, hardest, review, default) are placed from benchmarks:

1. `scripts/aa-coding-agents.py` prints the [Artificial Analysis Coding Agent Index](https://artificialanalysis.ai/agents/coding-agents) (DeepSWE, Terminal-Bench, SWE-Atlas-QnA) with cost and minutes per task for each agent + model + effort. The page renders with JavaScript, so a plain fetch shows "Not publicly available"; the script decodes the embedded data. If it fails, read the page in a browser.
2. Cross-check any tier change with one independent source (SWE-Bench Pro, vendor release post). One benchmark alone misleads: Gemini 3.8 Flash reports 61.6% SWE-Bench Pro but scores 41.9 on the index, about 20 under GPT-6.1 Sol.
3. Rules:
   - Quality first: a tier's candidates are the highest-scoring runnable models. Cost per task breaks ties only within about 2 points.
   - Effort is a cost knob: when a higher effort does not score higher (Sol medium 61.4, high 60.1, max 60.1), use the cheaper one, except in the hardest tier (Sol xhigh 62.9 at $1.04).
   - A newer, cheaper model that matches an older one replaces it (Sol 6.1 xhigh 62.9 at $1.04 replaced Astra max 61.6 at $7.47).
   - The same model through a different harness is the same quality, but size its quota pool before choosing tiers. Antigravity's two pools are separate: `gemini` is large (a dozen calls left it at 99%), `claude_gpt` is small (five short tool calls used about 7% of its 5-hour window on 2026-10-04). So Gemini serves the high-volume rules (recon, web research, images), and agy Claude is limited to one short, infrequent job - review - where it adds capacity without draining. Jev's `spendPriority` also drops a fast-draining pool out of the ranking on its own.
   - A model below a tier's best (more than about 2 points) goes in only as a deliberate, user-approved trade, because spare quota will make it win that tier. Record the trade in the rule's `why`.
   - A harness that caps effort below a tier's effort (agy caps at `high`) stays out of that tier (the hardest tier runs `xhigh`).
   - Scores come from each vendor's own agent (Codex CLI, Claude Code, Antigravity SDK); the fleet often runs the model through Pi or agy. Treat them as directional.

Special-purpose rules are placed by capability, not the coding index:

| Rule | Needs | Who has it |
|---|---|---|
| Live web facts | A web search tool | Every Pi model (`pi-web-access` extension: Codex-backed OpenAI search for `openai-codex/*`, Exa otherwise), Claude Code (built-in), Grok TUI (native, plus live X data) |
| Images | An image generation tool | Pi with the `pi-antigravity` extension (`generate_image`, saves under `.pi/generated-images/`) |

For these, a fast model with a weak coding score is fine (Gemini 3.8 Flash answers web lookups in about 20s versus about 60s for Sol).

Show the user the relevant benchmark rows (score, $/task, minutes) and the proposed placement before editing, unless they already named the change.

## 4. Verify each new model really works

For every model you add or move, through the exact harness and effort the config will use:

- **Pi**: `pi --model <provider/id> --thinking <effort> -p "Use your bash tool to run: ls | head -2. Then reply DONE" </dev/null`
- **agy**: `agy -p "Use your shell tool to run: ls | head -2. Then reply DONE" --model <id> --effort <effort> --dangerously-skip-permissions </dev/null`

Pass means it ran the tool, printed `DONE`, and exited within seconds. A plain "reply OK" test is not enough: `cursor/auto` answers that and still hangs on the first tool call. For the special-purpose rules also exercise the capability (a `web_search` for a current fact you can check, a `generate_image` call). Without `</dev/null`, `pi -p` waits on stdin forever. If Pi prints the reply but never exits, an extension is holding the process open: find it with `pi --no-extensions -e <path> ...` one extension at a time (this is how the `pi-cursor-provider` proxy bug was found); until fixed, every no-mistakes step stalls to its timeout.

## 5. Edit, validate, and confirm Jev can pick it

Dispatch profile shape:

- `pi` profiles must declare `provider` as `quota-axi` names it, not the Pi model prefix: `openai-codex/...` is `codex`, `xai/...` is `grok`, `antigravity/...` is `agy`, `cursor/...` is `cursor`.
- Native `agy` profiles need no `provider` (Firstmate maps `agy` itself) and use the suffixed ids from `agy models`.

Then:

1. Edit all files above consistently. Edit JSON with `jq` or exact full-line matches; a substring replace on an indented line also hits the more-indented copy of it.
2. Validate `crew-dispatch.json` with Firstmate's own checker. Do not run the whole `fm-bootstrap.sh` (it ignores `--help` and runs a full bootstrap); extract the function:
   ```sh
   cd ~/github/firstmate
   S=$(mktemp -d); mkdir "$S/cfg"; cp ~/github/dotfiles/home/.firstmate/crew-dispatch.json "$S/cfg/"
   sed -n '/^crew_dispatch_validate() {/,/^}/p' bin/fm-bootstrap.sh > "$S/v.sh"
   bash -c ". bin/fm-control-lib.sh; . bin/fm-quota-axi-lib.sh; install_cmd(){ :; }; fmx_env_get(){ :; }
     FM_HOME=$PWD CONFIG=$S/cfg; . $S/v.sh; crew_dispatch_validate"
   ```
   No output means valid.
3. Confirm Jev can rank each new candidate: write a brief whose `## Captain's intent` and `## Firstmate spec` fit the tier, then `bin/fm-dispatch-resolve.sh <brief> --project <name>` from `~/github/firstmate`. Every new candidate must show `-> eligible` with a `scope=` and a numeric `spendPriority`. Which candidate wins today does not matter (that is quota). `eligible, unranked: no applicable quota row` means the resolver cannot bind the model to a quota row, so it can never win: that is a configuration or resolver gap to fix, not a quota state. Antigravity models rank only with quota-axi's agy `windowSeconds` fix (`docs/AUTO-UPDATE.md`) and the resolver's `gemini`/`claude_gpt` scope binding (firstmate PR #6569). A row reading `unknown` once can be a transient quota read; re-run before concluding.

## 6. Report

Per file: what changed and the benchmark rows or capability test behind it. List released-but-unavailable models to watch, and any model kept out on purpose with the reason (e.g. `cursor/auto`: tool calls stall). Remind the user that secondmate homes only receive `crew-dispatch.json` when their sync is not skipped, and remote (Mac mini) homes refuse it while it is a symlink.
