---
name: update-models
description: Use when changing which AI models the agent fleet uses - bumping to a new model release, swapping a harness, adding a provider (e.g. Antigravity via Pi), or retiring a model. Covers every file that names a model (Firstmate crew dispatch, secondmate harness, Pi default, no-mistakes, and the test that pins Pi's default), how to verify each name exists before saving, and how to confirm Jev can actually pick it.
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

## Steps

1. Confirm the target models with the user. Do not assume a model exists because a version number looks like the next step: check news or vendor docs when the name is new.
2. Verify every model name against its harness's own catalog:
   - Pi: `pi --list-models <search>`. If the catalog looks stale, `pi update --models`; if that refresh fails, say so and fall back to vendor docs rather than guessing.
   - Claude: use aliases `opus`, `sonnet`, `haiku`; they always resolve to the latest (`claude --help`, `--model`). Never auto-select `fable` in dispatch: it stalls unattended on a usage-credit prompt.
   - Grok TUI: `grok models`.
   - Antigravity native: `agy models`.
   A name missing from a catalog that reached the account is a blocker, not a warning.
3. Smoke-test each new Pi model once: `pi --model <provider/id> --thinking low -p "Reply with exactly OK" </dev/null`. Without `</dev/null` it waits on stdin forever. Some providers (Antigravity) print the reply and then do not exit; the reply is the pass signal, kill the process after it.
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
6. Confirm Jev can pick the new profile. Jev (`bin/fm-dispatch-resolve.sh`, on when `TYPESAFE_API_KEY` is in `~/github/firstmate/.env`) picks the rule; then code picks the eligible candidate with the highest `spendPriority` from `quota-axi`. Write a small brief whose `## Captain's intent` and `## Firstmate spec` fit the tier you changed, then run `bin/fm-dispatch-resolve.sh <brief> --project <name>` from `~/github/firstmate`. Each new candidate must show `-> eligible`. `eligible, unranked` means its provider has no `spendPriority` (e.g. `agy` today), so Jev will never choose it while a ranked candidate exists; tell the user it is only a manual or fallback pick until `quota-axi` or the resolver ranks that provider.
7. Check `quota-axi` once: a provider shown as `auth_required` or `unknown` is never ranked above one with known quota, so its models will rarely be picked until auth is fixed.
8. Report what changed per file, and remind the user that secondmate homes only receive `crew-dispatch.json` when their sync is not skipped, and remote (Mac mini) homes refuse it while it is a symlink.
