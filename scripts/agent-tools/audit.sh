#!/usr/bin/env bash
# audit.sh - report unmanaged top-level agent/developer CLIs (never deletes)
#
# Usage: audit.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$REPO_ROOT/nix/agent-tools.manifest.lock.json"
BREW_BIN=${AGENT_TOOLS_BREW_BIN:-/opt/homebrew/bin}

export PATH="${BREW_BIN}:${HOME}/.local/bin:${HOME}/.no-mistakes/bin:${PATH:-}:/usr/bin:/bin"

die() {
  printf 'audit-agent-tools: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_cmd jq

[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"

collect_brew_formulas() {
  grep -hoE '"[a-z0-9+@._-]+"' "$REPO_ROOT/nix/configuration.nix" 2>/dev/null \
    | tr -d '"' \
    | sort -u || true
}

declared_uv=$(jq -r '.uv[].name' "$MANIFEST" | sort -u)
declared_external=$(jq -r '.external | keys[]' "$MANIFEST" | sort -u)
declared_brew=$(collect_brew_formulas)

echo "=== Declared agent tool inventory (manifest) ==="
echo "Manifest: $MANIFEST"
echo

report_section() {
  local title=$1
  shift
  echo "--- $title ---"
  if [ $# -eq 0 ] || [ -z "${1:-}" ]; then
    echo "(none)"
  else
    printf '%s\n' "$@"
  fi
  echo
}

# npm globals (skip npm itself - brew node owns it)
actual_npm=()
if command -v npm >/dev/null 2>&1; then
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    [ "$pkg" = npm ] && continue
    actual_npm+=("$pkg")
  done < <(npm list -g --depth=0 --json 2>/dev/null | jq -r '.dependencies | keys[]?' || true)
fi

unmanaged_npm=()
for pkg in "${actual_npm[@]:-}"; do
  if ! jq -e --arg p "$pkg" '.npm[] | select(. == $p)' "$MANIFEST" >/dev/null; then
    unmanaged_npm+=("$pkg")
  fi
done

# uv tool
actual_uv=()
if command -v uv >/dev/null 2>&1; then
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    actual_uv+=("$pkg")
  done < <(uv tool list 2>/dev/null | awk '$1 != "-" {print $1}' || true)
fi
unmanaged_uv=()
for pkg in "${actual_uv[@]:-}"; do
  grep -qxF "$pkg" <<<"$declared_uv" || unmanaged_uv+=("$pkg")
done

# brew formulas (top-level only: dependencies of declared formulae are not
# unmanaged, and cleanup keeps them while something needs them)
actual_brew_formulas=()
if command -v brew >/dev/null 2>&1; then
  while IFS= read -r f; do
    actual_brew_formulas+=("$f")
  done < <(brew leaves 2>/dev/null | sort)
fi
unmanaged_brew_formulas=()
for f in "${actual_brew_formulas[@]:-}"; do
  grep -qxF "$f" <<<"$declared_brew" || unmanaged_brew_formulas+=("$f")
done

# Homebrew python3 packages nothing declared needs (rebuild removes these)
declared_python=()
while IFS= read -r pkg; do
  [ -n "$pkg" ] && declared_python+=("$pkg")
done < <(jq -r '.python[].name' "$MANIFEST")
undeclared_python=()
if [ -x "$BREW_BIN/python3" ]; then
  while IFS= read -r pkg; do
    [ -n "$pkg" ] && undeclared_python+=("$pkg")
  done < <("$BREW_BIN/python3" "$REPO_ROOT/scripts/agent-tools/python-undeclared.py" ${declared_python[@]+"${declared_python[@]}"} 2>/dev/null || true)
fi

missing_external=()
for tool in $declared_external; do
  command -v "$tool" >/dev/null 2>&1 || missing_external+=("$tool")
done

report_section "Unmanaged npm globals (not in manifest)" "${unmanaged_npm[@]:-}"
report_section "Unmanaged uv tool apps (not in manifest)" "${unmanaged_uv[@]:-}"
report_section "Unmanaged Homebrew formulas (not in declared brew set)" "${unmanaged_brew_formulas[@]:-}"
report_section "Undeclared Homebrew python3 packages (not in manifest .python)" "${undeclared_python[@]:-}"
report_section "Declared external tools missing from PATH" "${missing_external[@]:-}"

echo "=== Notes ==="
echo "- This script reports only; it never deletes or uninstalls."
echo "- Rebuilds remove undeclared brew packages and undeclared Homebrew python3 packages; npm/uv tool/external extras stay until removed manually."
echo "- Add new required tools via nix/agent-tools.manifest.lock.json and nix/configuration.nix (brew), then rebuild."
