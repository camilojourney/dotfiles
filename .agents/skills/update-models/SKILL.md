---
name: update-models
description: Use when changing which AI models the agent fleet uses - bumping to a new model release, swapping a harness, adding a provider (e.g. Antigravity via Pi), retiring a model, or re-checking which models are the best value per tier against current coding benchmarks. Covers online benchmark research (score vs cost per task), every file that names a model (Firstmate crew dispatch, secondmate harness, Pi default, no-mistakes, and the test that pins Pi's default), how to verify each name exists before saving, and how to confirm Jev can actually pick it.
---

# update-models

Model names live in several files. A bump that misses one leaves part of the fleet on the old model, and a name that does not exist makes launches fail or get blocked. Always update and verify all of them together.

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

## Dispatch profile shape

- `pi` profiles must declare `provider`: the provider name as `quota-axi` prints it, not the Pi model prefix. `openai-codex/...` uses `codex`, `xai/...` uses `grok`, `antigravity/...` uses `agy`.
- Antigravity can run two ways: Pi with `antigravity/<bare id>` (e.g. `antigravity/gemini-3.8-flash`, effort via Pi's thinking level), or the native `agy` harness with the suffixed ids from `agy models` (e.g. `gemini-3.8-flash-high`, effort `low|medium|high` only). Both draw from the same `agy` quota.

## Choosing models from benchmarks

Pick each tier's models from current measurements, not from version numbers or a single vendor claim. Do this research before proposing any change, and again whenever the user asks to refresh the fleet.

1. Run `scripts/aa-coding-agents.py` (this skill's directory). It prints the [Artificial Analysis Coding Agent Index](https://artificialanalysis.ai/agents/coding-agents) - DeepSWE, Terminal-Bench, and SWE-Atlas-QnA averaged - with cost and minutes per task for each agent + model + effort. The page draws its charts with JavaScript, so a plain fetch shows "Not publicly available"; the script decodes the embedded data instead. If it exits with "no benchmarkRows found", read the page in a browser.
2. Cross-check anything that would change a tier with one more independent source: SWE-Bench Pro (vendor model pages or a web search), or the vendor's release post. One benchmark alone can mislead: Gemini 3.8 Flash reported 61.6% on SWE-Bench Pro but scores 41.9 on the Coding Agent Index, about 20 points under GPT-6.1 Sol.
3. Decide per tier with these rules:
   - Quality first: within a tier, the candidates should be the highest-scoring models available to the account. Cost per task breaks ties only between models within about 2 points of each other.
   - Effort is a cost knob, not a free upgrade: when a higher effort of the same model does not score higher (GPT-6.1 Sol medium 61.4, high 60.1, max 60.1), use the cheaper effort except in the hardest tier.
   - Prefer the newer, cheaper model when it matches an older or pricier one (GPT-6.1 Sol replaced GPT-6 Astra this way).
   - A model that is free to run on spare quota is still a quality trade: Jev ranks only by quota `spendPriority`, so a weak model in a tier will win that tier while its quota lasts. Put spare-quota models only where their score is close to the tier's best, or in the recon tier.
   - Scores are measured in each vendor's own agent (Codex CLI, Claude Code, Antigravity SDK), while the fleet often runs the model through Pi; treat them as directional, and do not swap tiers over a gap smaller than about 2 points.
4. Show the user the relevant rows (score, $/task, minutes) and the proposed tier changes before editing, unless they already named the change.

## Steps

1. Confirm the target models with the user, backed by the benchmark research above. Do not assume a model exists because a version number looks like the next step: check news or vendor docs when the name is new.
2. Verify every model name against its harness's own catalog:
   - Pi: `pi --list-models <search>`. If the catalog looks stale, `pi update --models`; if that refresh fails, say so and fall back to vendor docs rather than guessing.
   - Claude: use aliases `opus`, `sonnet`, `haiku`; they always resolve to the latest (`claude --help`, `--model`). Never auto-select `fable` in dispatch: it stalls unattended on a usage-credit prompt.
   - Grok TUI: `grok models`.
   - Antigravity native: `agy models`.
   A name missing from a catalog that reached the account is a blocker, not a warning.
3. Smoke-test each new Pi model once: `pi --model <provider/id> --thinking low -p "Reply with exactly OK" </dev/null`. Without `</dev/null` it waits on stdin forever. It must exit within seconds of printing the reply; if it hangs, a Pi extension is holding the process open (test each with `pi --no-extensions -e <path> ...`), and every no-mistakes step will stall until its timeout.
4. Edit all files above consistently. Keep each dispatch tier's reasoning class: frontier models stay in the hardest tier, cheap models in the recon tier. Edit JSON with `jq` or exact full-line matches; a substring replace on an indented line also hits the more-indented copy of it.
5. Validate `crew-dispatch.json` with Firstmate's own checker, `crew_dispatch_validate` in `~/github/firstmate/bin/fm-bootstrap.sh`. Do not run the whole `fm-bootstrap.sh` to do it: it ignores `--help` and runs a full bootstrap. Extract the function and run it against a scratch copy of the config:
   ```sh
   cd ~/github/firstmate
   S=$(mktemp -d); mkdir "$S/cfg"; cp ~/github/dotfiles/home/.firstmate/crew-dispatch.json "$S/cfg/"
   sed -n '/^crew_dispatch_validate() {/,/^}/p' bin/fm-bootstrap.sh > "$S/v.sh"
   bash -c ". bin/fm-control-lib.sh; . bin/fm-quota-axi-lib.sh; install_cmd(){ :; }; fmx_env_get(){ :; }
     FM_HOME=$PWD CONFIG=$S/cfg; . $S/v.sh; crew_dispatch_validate"
   ```
   No output means valid; any `CREW_DISPATCH:` line is an error to fix.
6. Confirm Jev can pick the new profile. Jev (`bin/fm-dispatch-resolve.sh`, on when `TYPESAFE_API_KEY` is in `~/github/firstmate/.env`) picks the rule; then code picks the eligible candidate with the highest `spendPriority` from `quota-axi`. Write a small brief whose `## Captain's intent` and `## Firstmate spec` fit the tier you changed, then run `bin/fm-dispatch-resolve.sh <brief> --project <name>` from `~/github/firstmate`. Each new candidate must show `-> eligible`. `eligible, unranked` means its provider has no `spendPriority` or no quota row the resolver binds to its model, so Jev will never choose it while a ranked candidate exists; tell the user it is only a manual or fallback pick until `quota-axi` or the resolver ranks that provider. Antigravity needs quota-axi windows with `windowSeconds` and the resolver's `gemini`/`claude_gpt` scope binding to rank.
7. Check `quota-axi` once: a provider shown as `auth_required` or `unknown` is never ranked above one with known quota, so its models will rarely be picked until auth is fixed.
8. Report what changed per file, and remind the user that secondmate homes only receive `crew-dispatch.json` when their sync is not skipped, and remote (Mac mini) homes refuse it while it is a symlink.
