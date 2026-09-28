#!/usr/bin/env bash
# check-pins.sh - report newer registry/release versions without changing the manifest
#
# This is an advisory periodic check. Rebuilds continue to install only the
# versions and checksums committed in manifest.lock.json.
set -euo pipefail

REPO_ROOT=${AGENT_TOOLS_REPO_ROOT:-"$(cd "$(dirname "$0")/../.." && pwd)"}
MANIFEST=${AGENT_TOOLS_MANIFEST:-$REPO_ROOT/nix/agent-tools.manifest.lock.json}

command -v jq >/dev/null || { echo "check-pins: required command not found: jq" >&2; exit 1; }
command -v npm >/dev/null || { echo "check-pins: required command not found: npm" >&2; exit 1; }
command -v curl >/dev/null || { echo "check-pins: required command not found: curl" >&2; exit 1; }

printf '%-42s %-12s %s\n' package pinned latest
while IFS= read -r name; do
  latest=$(npm view "$name" version 2>/dev/null || latest="unavailable")
  printf '%-42s %-12s %s\n' "$name" "latest" "$latest"
done < <(jq -r '.npm[]' "$MANIFEST")

printf '\n%-42s %-12s %s\n' package pinned latest
while IFS=$'\t' read -r name pinned; do
  latest=$(python3 -m pip index versions "$name" 2>/dev/null | awk 'NR==1 {sub(/^.*\(/, ""); sub(/\).*$/, ""); print; exit}' || true)
  printf '%-42s %-12s %s\n' "$name" "$pinned" "${latest:-unavailable}"
done < <(jq -r '.uv[] | [.name, .version] | @tsv' "$MANIFEST")

printf '\n%-42s %-12s %s\n' release pinned latest
while IFS=$'\t' read -r name repo pinned; do
  latest=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | jq -r '.tag_name // "unavailable"' || true)
  latest=${latest#v}
  printf '%-42s %-12s %s\n' "$name" "$pinned" "${latest:-unavailable}"
done < <(jq -r '.external | to_entries[] | [.key, .value.repo, .value.version] | @tsv' "$MANIFEST")

printf '\nAdvisory only: review compatibility and checksums before editing pins.\n'
