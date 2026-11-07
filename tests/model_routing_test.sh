#!/usr/bin/env bash
# Offline guards for concise routing text and quota coverage.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
jq -e '
  def words: [splits("\\s+") | select(length > 0)] | length;
  def has_profile($model; $effort): any(.model == $model and .effort == $effort and .harness == "pi");
  def profiles($v): if ($v | type) == "array" then $v else [$v] end;
  # Candidates sharing a quota scope always tie in Firstmate ranking and escalate.
  # The resolver binds every claude-bridge model, Fable included, to all_models.
  def scope_key: .provider + ":" + (if .provider == "agy" and (.model | test("claude|gpt")) then "claude_gpt" else "all" end);
  (has("preferred_provider") | not)
  and all(.rules[].use, .default; profiles(.) | map(scope_key) | length == (unique | length))
  and all(.rules[];
    (.when | words) <= 30 and (.why | words) <= 35
    and (.why | test("[0-9]{4}-[0-9]{2}-[0-9]{2}") | not))
  and (.rules[3].use | has_profile("claude-bridge/claude-haiku-5-5"; "medium"))
  and (.rules[4].use | has_profile("claude-bridge/claude-sonnet-5-5"; "medium"))
  and (.default | has_profile("claude-bridge/claude-sonnet-5-5"; "medium"))
' "$ROOT/home/.firstmate/crew-dispatch.json" >/dev/null
echo "PASS: concise rule text, no preferred provider, one candidate per quota scope and quota coverage"
