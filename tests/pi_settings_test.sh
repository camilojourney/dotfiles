#!/usr/bin/env bash
# Regression test for declarative Pi package configuration.
# Run: bash tests/pi_settings_test.sh

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
SETTINGS="$REPO_ROOT/home/.pi/agent/settings.json"
MODELS="$REPO_ROOT/home/.pi/agent/models.json"
DISPATCH="$REPO_ROOT/home/.firstmate/crew-dispatch.json"
WEB_SEARCH="$REPO_ROOT/home/.pi/web-search.json"
CURSOR_PROVIDER="git:github.com/camilojourney/pi-cursor-provider@73fd2d75c58bfe1757a124e407fbc72f89642826"
# Laptop-only local install of unpublished commit 6e223b2 (metadata-only default);
# restore a published git pin before syncing to another host. See docs/AUTOMATIONS.md.
OTEL_PACKAGE="/Users/camiloslaptop/.local/share/pi-opentelemetry/install-6e223b2"
ANTIGRAVITY_PACKAGE="git:github.com/Rahularya01/pi-antigravity@f950c08e7a5c1069a0339af88252347a5ecb0f8c"
# Public PR #18 author's revision, not a locally maintained patch.
COMPACTION_PACKAGE="git:github.com/kunchenguid/pi-openai-server-compaction@cf30a9fee30312ef33d03fd1d99ad511e81e2b95"

jq -e --arg cursor_provider "$CURSOR_PROVIDER" --arg otel_package "$OTEL_PACKAGE" \
  --arg antigravity_package "$ANTIGRAVITY_PACKAGE" --arg compaction_package "$COMPACTION_PACKAGE" '
  .packages as $packages
  | ($packages | map(select(test("cursor"; "i"))) == [$cursor_provider])
  and ($packages | map(select(test("opentelemetry"))) == [$otel_package])
  and ($packages | map(select(test("pi-antigravity"))) == [$antigravity_package])
  and ($packages | map(select(test("pi-openai-server-compaction"))) == [$compaction_package])
  and ($packages | index("npm:pi-cursor-sdk") | not)
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
STORAGE_SKILL="$REPO_ROOT/.agents/skills/storage-audit/SKILL.md"
[[ -f "$STORAGE_SKILL" ]]
# [utest->req~storage-audit.inventory~1]
grep -Fq 'umask 077' "$STORAGE_SKILL"
grep -Fq 'state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/storage-audit"' "$STORAGE_SKILL"
grep -Fq 'report="$state_dir/inventory-$(date -u +%Y%m%dT%H%M%SZ).txt"' "$STORAGE_SKILL"
grep -Fq 'mark it incomplete' "$STORAGE_SKILL"
# [utest->req~storage-audit.cleanup-approval~1]
grep -Fq 'Never delete during an audit-only request.' "$STORAGE_SKILL"
grep -Fq 'Show the plan and get approval for the exact targets.' "$STORAGE_SKILL"

jq -e '
  .provider == "anysearch" and .toolExposure == "deferred"
' "$WEB_SEARCH" >/dev/null

jq -e '
  (.providers | keys) == ["deepseek"]
  and (.providers.deepseek.modelOverrides | keys | sort == ["deepseek-v4-flash", "deepseek-v4-pro"])
  and ([.providers.deepseek.modelOverrides[].contextWindow] | all(. == 500000))
' "$MODELS" >/dev/null

# Claude models run only through Pi, never the Claude Code harness (captain,
# 2026-10-19): Sonnet 5.5 for external-facts research (rule 0) and read-only
# mapping (rule 7), Haiku 5.5 for evaluation judging (rule 8). Opus stays
# reserved for the captain's own session; Fable is not dispatched.
jq -e '
  def profiles($v): if ($v | type) == "array" then $v else [$v] end;
  def sonnet: .model == "claude-bridge/claude-sonnet-5-5" and .provider == "claude"
    or .model == "antigravity/claude-sonnet-5-5" and .provider == "agy";
  def haiku: .model == "claude-bridge/claude-haiku-5-5" and .provider == "claude";
  def keys_using(f): [.rules | to_entries[] | select(.value.use | profiles(.) | any(f)) | .key];
  ([.rules[].use, .default] | map(profiles(.)) | add) as $all
  | ($all | all(.harness == "pi"))
  and ($all | all(sonnet or haiku or ((.model | test("claude|opus|sonnet|fable|haiku"; "i") | not) and .provider != "claude")))
  and (keys_using(sonnet) == [0, 7])
  and (keys_using(haiku) == [8])
  and ([.rules[0].use, .rules[7].use] | map(profiles(.)) | all(any(sonnet and .provider == "claude" and .effort == "medium") and any(sonnet and .provider == "agy" and .effort == "medium")))
  and (.rules[7].when | test("^Read-only mapping"))
  and (.rules[8].when | test("^Evaluation judging"))
  and ([.rules[7].use] | map(profiles(.)) | all(any(.model == "openai-codex/gpt-6.1-sol" and .effort == "medium" and .provider == "codex")))
  and ([.rules[2].use, .rules[6].use] | map(profiles(.)) | all(any(.model == "openai-codex/gpt-6.1-sol" and .effort == "xhigh" and .provider == "codex")))
  and ([.rules[0].use, .rules[1].use] | map(profiles(.)) | all(any(.model == "antigravity/gemini-3.8-flash" and .effort == "medium" and .provider == "agy")))
  and ([.rules[3].use] | map(profiles(.)) | all(any(.model == "antigravity/gemini-3.8-flash" and .effort == "low" and .provider == "agy")))
  and ([.rules[2].use, .rules[5].use, .rules[6].use] | map(profiles(.)) | all(any(.model == "antigravity/gemini-4-argon" and .effort == "high" and .provider == "agy")))
  and ([.rules[4].use, .default] | map(profiles(.)) | all((first.model == "openai-codex/gpt-6.1-sol" and first.effort == "medium") and (any(.model == "antigravity/gemini-4-argon") | not)))
  # Luna xhigh codes only ordinary, clear-path work (captain, 2026-10-19): an eval
  # found it faster and cheaper than Sol xhigh but it missed a subtle edge Sol caught.
  and (.rules[4].when | test("^Ordinary implementation"))
  and (keys_using(.model == "openai-codex/gpt-6-luna" and .effort == "xhigh" and .provider == "codex") == [4])
' "$DISPATCH" >/dev/null

# Each selection has one authored owner, linked into Firstmate by Home Manager.
[[ $(<"$REPO_ROOT/home/.firstmate/secondmate-harness") == "pi openai-codex/gpt-6.1-sol xhigh" ]]
[[ $(<"$REPO_ROOT/home/.firstmate/secondmate-harness.backup") == "pi antigravity/gemini-4-argon high" ]]
# Match literal Nix interpolation, not a shell variable.
# shellcheck disable=SC2016
grep -Fq '"github/firstmate/config/crew-dispatch.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.firstmate/crew-dispatch.json";' "$REPO_ROOT/nix/home.nix"
# shellcheck disable=SC2016
grep -Fq '"github/firstmate/config/secondmate-harness".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.firstmate/secondmate-harness";' "$REPO_ROOT/nix/home.nix"
# shellcheck disable=SC2016
grep -Fq '"github/firstmate/config/secondmate-harness.backup".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.firstmate/secondmate-harness.backup";' "$REPO_ROOT/nix/home.nix"
# shellcheck disable=SC2016
grep -Fq '".pi/agent/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.pi/agent/settings.json";' "$REPO_ROOT/nix/home.nix"

# shellcheck disable=SC2016
grep -Fq '".pi/web-search.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.pi/web-search.json";' "$REPO_ROOT/nix/home.nix"

echo "PASS: declarative Pi tools, deferred web search, model overrides, crew dispatch, and secondmate selection are valid"
