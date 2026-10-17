#!/usr/bin/env bash
# Account-skill downloads must stay disabled, independently of skillOverrides.
# Reads authored JSON only; never starts Claude or contacts a provider.
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
SETTINGS="$REPO_ROOT/home/.claude/settings.json"

jq -e '.syncClaudeAiSkills == false' "$SETTINGS" >/dev/null

echo "PASS: Claude account skill synchronization is explicitly disabled"
