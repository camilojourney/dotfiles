#!/usr/bin/env bash
# Regression test for declarative Pi package configuration.
# Run: bash tests/pi_settings_test.sh

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
SETTINGS="$REPO_ROOT/home/.pi/agent/settings.json"
MODELS="$REPO_ROOT/home/.pi/agent/models.json"
CURSOR_PROVIDER="git:github.com/camilojourney/pi-cursor-provider#73fd2d75c58bfe1757a124e407fbc72f89642826"
OTEL_PACKAGE="git:github.com/camilojourney/pi-opentelemetry#9cf23282c3f7ebf315a04b95c9135cd2a4290334"

jq -e --arg cursor_provider "$CURSOR_PROVIDER" --arg otel_package "$OTEL_PACKAGE" '
  .packages as $packages
  | ($packages | map(select(test("cursor"; "i"))) == [$cursor_provider])
  and ($packages | map(select(test("opentelemetry"))) == [$otel_package])
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

echo "PASS: declarative Pi settings and model overrides are valid"
