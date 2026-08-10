#!/usr/bin/env bash
# audit.sh - report unmanaged top-level agent/developer CLIs (never deletes)
#
# Usage: audit.sh [host-profile]
#   host-profile defaults to camilo
set -euo pipefail

HOST_PROFILE=${1:-camilo}
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$REPO_ROOT/nix/shared/agent-tools/manifest.lock.json"
BREW_BIN=/opt/homebrew/bin

export PATH="${BREW_BIN}:${HOME}/.local/bin:${HOME}/.no-mistakes/bin:${PATH:-}"

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
  grep -hoE '"[a-z0-9+@._-]+"' "$REPO_ROOT/nix/shared/host.nix" "$REPO_ROOT/nix/${HOST_PROFILE}/host.nix" 2>/dev/null \
    | tr -d '"' \
    | sort -u || true
}

declared_npm=$(jq -r '.npm[].name' "$MANIFEST" | sort -u)
declared_pipx=$(jq -r '.pipx.shared[].name' "$MANIFEST")
if [ "$HOST_PROFILE" = camilo ]; then
  declared_pipx=$(printf '%s\n%s\n' "$declared_pipx" "$(jq -r '.pipx.camilo[]?.name // empty' "$MANIFEST")")
fi
declared_pipx=$(printf '%s\n' "$declared_pipx" | sed '/^$/d' | sort -u)
declared_external=$(jq -r '.external | keys[]' "$MANIFEST" | sort -u)
declared_brew=$(collect_brew_formulas)

echo "=== Declared agent tool inventory (manifest) ==="
echo "Manifest: $MANIFEST"
echo "Host profile: $HOST_PROFILE"
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
  if ! jq -e --arg p "$pkg" '.npm[] | select(.name == $p)' "$MANIFEST" >/dev/null; then
    unmanaged_npm+=("$pkg")
  fi
done

# pipx
actual_pipx=()
if command -v pipx >/dev/null 2>&1; then
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    actual_pipx+=("$pkg")
  done < <(pipx list --short 2>/dev/null | awk '{print $1}' || true)
fi
unmanaged_pipx=()
for pkg in "${actual_pipx[@]:-}"; do
  grep -qxF "$pkg" <<<"$declared_pipx" || unmanaged_pipx+=("$pkg")
done

# brew formulas (top-level only)
actual_brew_formulas=()
if command -v brew >/dev/null 2>&1; then
  while IFS= read -r f; do
    actual_brew_formulas+=("$f")
  done < <(brew list --formula 2>/dev/null | sort)
fi
unmanaged_brew_formulas=()
for f in "${actual_brew_formulas[@]:-}"; do
  grep -qxF "$f" <<<"$declared_brew" || unmanaged_brew_formulas+=("$f")
done

missing_external=()
for tool in $declared_external; do
  command -v "$tool" >/dev/null 2>&1 || missing_external+=("$tool")
done

report_section "Unmanaged npm globals (not in manifest)" "${unmanaged_npm[@]:-}"
report_section "Unmanaged pipx apps (not in manifest for ${HOST_PROFILE})" "${unmanaged_pipx[@]:-}"
report_section "Unmanaged Homebrew formulas (not in declared brew set)" "${unmanaged_brew_formulas[@]:-}"
report_section "Declared external tools missing from PATH" "${missing_external[@]:-}"

echo "=== Notes ==="
echo "- This script reports only; it never deletes or uninstalls."
echo "- Homebrew cleanup removes undeclared brew packages on rebuild; npm/pipx/external extras stay until removed manually."
echo "- Add new required tools via nix/shared/agent-tools/manifest.lock.json and nix/shared/host.nix (brew), then rebuild."
