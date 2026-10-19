#!/usr/bin/env bash
# Regression test for declarative Pi package configuration.
# Run: bash tests/pi_settings_test.sh

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
SETTINGS="$REPO_ROOT/home/.pi/agent/settings.json"
MODELS="$REPO_ROOT/home/.pi/agent/models.json"
DISPATCH="$REPO_ROOT/home/.firstmate/crew-dispatch.json"
CURSOR_PROVIDER="git:github.com/camilojourney/pi-cursor-provider@73fd2d75c58bfe1757a124e407fbc72f89642826"
# Laptop-only local install of unpublished commit 6e223b2 (metadata-only default);
# restore a published git pin before syncing to another host. See docs/AUTOMATIONS.md.
OTEL_PACKAGE="/Users/camiloslaptop/.local/share/pi-opentelemetry/install-6e223b2"
ANTIGRAVITY_PACKAGE="git:github.com/Rahularya01/pi-antigravity@f950c08e7a5c1069a0339af88252347a5ecb0f8c"

jq -e --arg cursor_provider "$CURSOR_PROVIDER" --arg otel_package "$OTEL_PACKAGE" \
  --arg antigravity_package "$ANTIGRAVITY_PACKAGE" '
  .packages as $packages
  | ($packages | map(select(test("cursor"; "i"))) == [$cursor_provider])
  and ($packages | map(select(test("opentelemetry"))) == [$otel_package])
  and ($packages | map(select(test("pi-antigravity"))) == [$antigravity_package])
  and ($packages | index("npm:pi-cursor-sdk") | not)
  and (.defaultProvider == "openai-codex")
  and (.defaultModel == "gpt-6.1-sol")
  and (.defaultThinkingLevel == "high")
  and (has("llamaServerUrl") | not)
' "$SETTINGS" >/dev/null

jq -e '
  (.providers | keys) == ["deepseek"]
  and (.providers.deepseek.modelOverrides | keys | sort == ["deepseek-v4-flash", "deepseek-v4-pro"])
  and ([.providers.deepseek.modelOverrides[].contextWindow] | all(. == 500000))
' "$MODELS" >/dev/null

# Claude: only Sonnet, only for external-facts research (rule 0) and read-only
# mapping (rule 7), captain-approved 2026-10-19. Opus stays reserved for the
# captain's own session; Fable and Haiku are not dispatched.
jq -e '
  def profiles($v): if ($v | type) == "array" then $v else [$v] end;
  def sonnet: .harness == "claude" and .model == "claude-sonnet-5-5" and .provider == "claude";
  ([.rules[].use, .default] | map(profiles(.)) | add) as $all
  | ($all | all(sonnet or (.harness == "pi" and (.model | test("claude|opus|sonnet|fable|haiku"; "i") | not) and .provider != "claude")))
  and ([.rules | to_entries[] | select(.value.use | profiles(.) | any(sonnet)) | .key] == [0, 7])
  and ([.rules[0].use, .rules[7].use] | map(profiles(.)) | all(any(sonnet and .effort == "medium")))
  and (.rules[7].when | test("^Read-only mapping"))
  and ([.rules[7].use] | map(profiles(.)) | all(any(.model == "openai-codex/gpt-6.1-sol" and .effort == "medium" and .provider == "codex")))
  and ([.rules[2].use, .rules[6].use] | map(profiles(.)) | all(any(.model == "openai-codex/gpt-6.1-sol" and .effort == "xhigh" and .provider == "codex")))
  and ([.rules[0].use, .rules[1].use] | map(profiles(.)) | all(any(.model == "antigravity/gemini-3.8-flash" and .effort == "medium" and .provider == "agy")))
  and ([.rules[3].use] | map(profiles(.)) | all(any(.model == "antigravity/gemini-3.8-flash" and .effort == "low" and .provider == "agy")))
  and ([.rules[2].use, .rules[5].use, .rules[6].use] | map(profiles(.)) | all(any(.model == "antigravity/gemini-4-argon" and .effort == "high" and .provider == "agy")))
  and ([.rules[4].use, .default] | map(profiles(.)) | all((first.model == "openai-codex/gpt-6.1-sol" and first.effort == "medium") and (any(.model == "antigravity/gemini-4-argon") | not)))
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

echo "PASS: declarative Pi settings, model overrides, crew dispatch, and secondmate selection are valid"
