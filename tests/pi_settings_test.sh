#!/usr/bin/env bash
# Regression test for declarative Pi package configuration.
# Run: bash tests/pi_settings_test.sh

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
SETTINGS="$REPO_ROOT/home/.pi/agent/settings.json"
MODELS="$REPO_ROOT/home/.pi/agent/models.json"
DISPATCH="$REPO_ROOT/home/.firstmate/crew-dispatch.json"
WEB_SEARCH="$REPO_ROOT/home/.pi/web-search.json"
# Each host installs the same unpublished build in its own home. Pi expands ~.
# See docs/AUTOMATIONS.md for source-only transfer and host-local credentials.
OTEL_PACKAGE="~/.local/share/pi-opentelemetry/install-e097771"
ANTIGRAVITY_PACKAGE="git:github.com/Rahularya01/pi-antigravity@f950c08e7a5c1069a0339af88252347a5ecb0f8c"
# Our maintained local checkout; see docs/PI-COMPACTION.md.
COMPACTION_PACKAGE="../../github/pi-openai-server-compaction"

jq -e --arg otel_package "$OTEL_PACKAGE" \
  --arg antigravity_package "$ANTIGRAVITY_PACKAGE" --arg compaction_package "$COMPACTION_PACKAGE" '
  .packages as $packages
  | ($packages | map(select(test("cursor"; "i"))) == [])
  and ($packages | map(select(test("opentelemetry"))) == [$otel_package])
  and ($packages | all(startswith("/Users/") | not))
  and ($packages | map(select(test("pi-antigravity"))) == [$antigravity_package])
  and ($packages | map(select(test("pi-openai-server-compaction"))) == [$compaction_package])
  and ($packages | map(select(test("^npm:pi-web-access(@|$)"))) == ["npm:pi-web-access"])
  and ($packages | all(contains("pi-extension-codex-fast-mode") | not))
  and (.defaultProjectTrust == "always")
  and (.defaultTools == ["+codemode", "+tool_search"])
  and (.codemode.mode == "on")
  and (.defaultProvider == "openai-codex")
  and (.defaultModel == "gpt-6.1-sol")
  and (.defaultThinkingLevel == "high")
  and (.skills == ["~/github/dotfiles/.agents/skills/storage-audit"])
  and (has("llamaServerUrl") | not)
' "$SETTINGS" >/dev/null
# Cursor must not be reinstalled or rediscovered as a Baby Menu widget.
[[ ! -d "$REPO_ROOT/home/.baby-menu/extensions/cursor-quota" ]]
if grep -Fq '"cursor-quota"' "$REPO_ROOT/home/.baby-menu/extensions/layout.tsx" \
  || grep -Eq '^ *"cursor(-agent|-cli)?"' "$REPO_ROOT/nix/configuration.nix" \
  || grep -Eiq '"[^"[:space:]]*cursor[^"[:space:]]*"' "$REPO_ROOT/nix/agent-tools.manifest.lock.json"; then
  echo "FAIL: Cursor is still declared in Baby Menu or managed installs" >&2
  exit 1
fi

STORAGE_SKILL="$REPO_ROOT/.agents/skills/storage-audit/SKILL.md"
[[ -f "$STORAGE_SKILL" ]]
# [utest->req~storage-audit.inventory~2]
grep -Fq 'umask 077' "$STORAGE_SKILL"
grep -Fq "state_dir=\"\${XDG_STATE_HOME:-\$HOME/.local/state}/storage-audit\"" "$STORAGE_SKILL"
grep -Fq "report=\"\$state_dir/inventory-\$(date -u +%Y%m%dT%H%M%SZ).txt\"" "$STORAGE_SKILL"
grep -Fq 'du -h -d 1 /System/Volumes/Data' "$STORAGE_SKILL"
grep -Fq 'mark it incomplete' "$STORAGE_SKILL"
# [utest->req~storage-audit.cleanup-approval~1]
grep -Fq 'Never delete during an audit-only request.' "$STORAGE_SKILL"
grep -Fq 'Show the plan and get approval for the exact targets.' "$STORAGE_SKILL"

jq -e '
  .provider == "anysearch" and .toolExposure == "deferred"
' "$WEB_SEARCH" >/dev/null

jq -e '
  (.providers | keys) == ["deepseek", "ollama"]
  and (.providers.ollama.baseUrl == "http://127.0.0.1:11434/v1")
  and ([.providers.ollama.models[].cost | .input, .output] | all(. == 0))
  and (.providers.deepseek.modelOverrides | keys | sort == ["deepseek-v4-flash", "deepseek-v4-pro"])
  and ([.providers.deepseek.modelOverrides[].contextWindow] | all(. == 500000))
' "$MODELS" >/dev/null

# Claude models run only through Pi, never the Claude Code harness (captain,
# 2026-10-19). No provider family is preferred (captain, 2026-10-30): each rule
# lists its best candidates, one per quota pool, and Firstmate picks by quota.
# Opus in review and hardest, Fable in large, Sonnet for routine coding and
# mapping, Haiku for recon and judging; Gemini Flash covers quick research,
# images and recon. Secondmate choices stay separate.
# No rule uses Gemini Argon: the captain has no Argon quota (2026-10-29).
jq -e '
  def profiles($v): if ($v | type) == "array" then $v else [$v] end;
  def sonnet: .model == "claude-bridge/claude-sonnet-5-5" and .provider == "claude"
    or .model == "antigravity/claude-sonnet-5-5" and .provider == "agy";
  def haiku: .model == "claude-bridge/claude-haiku-5-5" and .provider == "claude";
  def opus: .model == "claude-bridge/claude-opus-5-5" and .provider == "claude"
    or .model == "antigravity/claude-opus-5-5" and .provider == "agy";
  def fable: .model == "claude-bridge/claude-fable-5-1" and .provider == "claude";
  def keys_using(f): [.rules | to_entries[] | select(.value.use | profiles(.) | any(f)) | .key];
  ([.rules[].use, .default] | map(profiles(.)) | add) as $all
  | (has("preferred_provider") | not)
  and ($all | all(.harness == "pi"))
  and ($all | all(sonnet or haiku or opus or fable or ((.model | test("claude|opus|sonnet|fable|haiku"; "i") | not) and .provider != "claude")))
  and (keys_using(sonnet) == [0, 4, 7])
  and (keys_using(haiku) == [3, 8])
  and (keys_using(opus) == [2, 6])
  and (keys_using(fable) == [5])
  # Evaluation judging is Haiku first again after the local Qwen trial (captain, 2026-10-25).
  and (.rules[8].use[0].model == "claude-bridge/claude-haiku-5-5")
  and ([.rules[7].use] | map(profiles(.)) | all(any(sonnet and .provider == "claude" and .effort == "medium") and any(sonnet and .provider == "agy" and .effort == "medium")))
  # Quick research keeps Flash and no Claude-bridge candidate.
  and ([.rules[0].use] | map(profiles(.)) | all(any(sonnet and .provider == "agy" and .effort == "medium") and (any(.provider == "claude") | not)))
  and (.rules[7].when | test("^Read-only mapping"))
  and (.rules[8].when | test("^Evaluation judging"))
  and ([.rules[7].use] | map(profiles(.)) | all(any(.model == "openai-codex/gpt-6.1-sol" and .effort == "medium" and .provider == "codex")))
  and ([.rules[2].use, .rules[6].use] | map(profiles(.)) | all(any(.model == "openai-codex/gpt-6.1-sol" and .effort == "xhigh" and .provider == "codex")))
  and ([.rules[0].use, .rules[1].use] | map(profiles(.)) | all(any(.model == "antigravity/gemini-3.8-flash" and .effort == "medium" and .provider == "agy")))
  and ([.rules[3].use] | map(profiles(.)) | all(any(.model == "antigravity/gemini-3.8-flash" and .effort == "low" and .provider == "agy")))
  and (keys_using(.model == "antigravity/gemini-4-argon") == [])
  and ([.rules[4].use, .default] | map(profiles(.)) | all((first | sonnet and .provider == "claude" and .effort == "medium") and any(.model == "openai-codex/gpt-6.1-sol" and .effort == "medium" and .provider == "codex")))
  and (.rules[4].when | test("^Ordinary implementation"))
  # Luna stays only as the judging fallback (captain, 2026-10-25); Terra low replaced it in recon.
  and (keys_using(.model == "openai-codex/gpt-6-luna") == [8])
  and ([.rules[3].use] | map(profiles(.)) | all(any(.model == "openai-codex/gpt-6.1-terra" and .effort == "low" and .provider == "codex")))
' "$DISPATCH" >/dev/null

# Each selection has one authored owner, linked into Firstmate by Home Manager.
# Second mates run Codex Sol (captain, 2026-10-23, replacing Opus); pythia-v2-lab is pinned to
# Opus high. The manual backup is Flash;
# Argon was dropped because the captain has no Argon quota (2026-10-29).
[[ $(<"$REPO_ROOT/home/.firstmate/secondmate-harness") == $'pi openai-codex/gpt-6.1-sol xhigh\nmate pythia-v2-lab: pi claude-bridge/claude-opus-5-5 high' ]]
[[ $(<"$REPO_ROOT/home/.firstmate/secondmate-harness.backup") == "pi antigravity/gemini-3.8-flash high" ]]
[[ $(<"$REPO_ROOT/home/.firstmate/supervision-branch-model") == "openai-codex/gpt-6-luna" ]]
[[ $(<"$REPO_ROOT/home/.firstmate/supervision-branch-effort") == "medium" ]]
# Match literal Nix interpolation, not a shell variable.
# shellcheck disable=SC2016
grep -Fq '"github/firstmate/config/crew-dispatch.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.firstmate/crew-dispatch.json";' "$REPO_ROOT/nix/home.nix"
# shellcheck disable=SC2016
grep -Fq '"github/firstmate/config/secondmate-harness".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.firstmate/secondmate-harness";' "$REPO_ROOT/nix/home.nix"
# shellcheck disable=SC2016
grep -Fq '"github/firstmate/config/secondmate-harness.backup".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.firstmate/secondmate-harness.backup";' "$REPO_ROOT/nix/home.nix"
# shellcheck disable=SC2016
grep -Fq '"github/firstmate/config/supervision-branch-model".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.firstmate/supervision-branch-model";' "$REPO_ROOT/nix/home.nix"
# shellcheck disable=SC2016
grep -Fq '"github/firstmate/config/supervision-branch-effort".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.firstmate/supervision-branch-effort";' "$REPO_ROOT/nix/home.nix"
# shellcheck disable=SC2016
grep -Fq '".pi/agent/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.pi/agent/settings.json";' "$REPO_ROOT/nix/home.nix"

# shellcheck disable=SC2016
grep -Fq '".pi/web-search.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.pi/web-search.json";' "$REPO_ROOT/nix/home.nix"

echo "PASS: declarative Pi tools, deferred web search, model overrides, crew dispatch, and secondmate selection are valid"
