#!/usr/bin/env bash
# reconcile.sh - idempotently install/reconcile the declared agent tool inventory
#
# Usage: reconcile.sh
#
# One inventory, every machine. Called from Home Manager activation on
# rebuild. Reads nix/agent-tools.manifest.lock.json.
set -euo pipefail

REPO_ROOT=${AGENT_TOOLS_REPO_ROOT:-"$(cd "$(dirname "$0")/../.." && pwd)"}
MANIFEST="${AGENT_TOOLS_MANIFEST:-$REPO_ROOT/nix/agent-tools.manifest.lock.json}"
BREW_BIN=${AGENT_TOOLS_BREW_BIN:-/opt/homebrew/bin}

# Home Manager activation hands this script a minimal PATH that can omit
# /usr/bin - guarantee it so POSIX tools like awk and curl are always found,
# regardless of what the caller's environment already had.
export PATH="${BREW_BIN}:${HOME}/.local/bin:${HOME}/.no-mistakes/bin:${PATH:-}:/usr/bin:/bin"

die() {
  printf 'agent-tools: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'agent-tools: %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

install_npm_globals() {
  require_cmd npm
  local specs
  while IFS= read -r specs; do
    [ -n "$specs" ] || continue
    info "npm: reconciling ${specs}"
    npm install -g --ignore-scripts "$specs"
  done < <(jq -r '.npm[] | "\(.name)@\(.version)"' "$MANIFEST")
}

uv_tool_list() {
  if [ -n "${AGENT_TOOLS_STUB_UV_LIST:-}" ] && [ -f "${AGENT_TOOLS_STUB_UV_LIST}" ]; then
    cat "${AGENT_TOOLS_STUB_UV_LIST}"
    return 0
  fi
  uv tool list
}

uv_tool_installed_version() {
  local name=$1
  uv_tool_list | awk -v n="$name" '$1 == n { sub(/^v/, "", $2); print $2; exit }'
}

install_uv_tools() {
  require_cmd uv
  local name version current
  while IFS=$'\t' read -r name version; do
    [ -n "$name" ] || continue
    current=$(uv_tool_installed_version "$name" || true)
    if [ "$current" = "$version" ]; then
      info "uv: ${name}==${version} already installed"
      continue
    fi
    info "uv: reconciling ${name}==${version}"
    uv tool install --force "${name}==${version}" || die "uv tool install failed for ${name}==${version}"
  done < <(jq -r '.uv[] | [.name, .version] | @tsv' "$MANIFEST")
}

# Homebrew's python3 holds only the libraries declared under .python, for
# scripts run with plain python3 (skills). Anything else pip put there is
# removed, the same way homebrew cleanup removes undeclared formulae. A
# failure warns instead of aborting the rebuild; the next rebuild retries.
reconcile_python_globals() {
  local py=${AGENT_TOOLS_PYTHON:-$BREW_BIN/python3}
  if [ ! -x "$py" ]; then
    info "python: ${py} not found; skipped"
    [ "${AGENT_TOOLS_STRICT:-0}" != 1 ] || return 1
    return 0
  fi
  # home.nix sets PIP_REQUIRE_VIRTUALENV=1 so nothing else installs here.
  export PIP_REQUIRE_VIRTUALENV=0
  local -a declared=() specs=() undeclared=()
  local name
  while IFS= read -r name; do
    [ -n "$name" ] && declared+=("$name")
  done < <(jq -r '.python[].name' "$MANIFEST")

  while IFS= read -r name; do
    [ -n "$name" ] && specs+=("$name")
  done < <(jq -r '.python[] | "\(.name)==\(.version)"' "$MANIFEST")
  if [ "${#specs[@]}" -gt 0 ]; then
    info "python: reconciling ${specs[*]}"
    if ! "$py" -m pip install --quiet --break-system-packages "${specs[@]}"; then
      printf 'agent-tools: python: install failed; skipping cleanup, the next rebuild will retry\n' >&2
      [ "${AGENT_TOOLS_STRICT:-0}" != 1 ] || return 1
      return 0
    fi
  fi

  while IFS= read -r name; do
    [ -n "$name" ] && undeclared+=("$name")
  done < <("$py" "$REPO_ROOT/scripts/agent-tools/python-undeclared.py" ${declared[@]+"${declared[@]}"})
  [ "${#undeclared[@]}" -gt 0 ] || return 0
  info "python: removing undeclared ${undeclared[*]}"
  if ! "$py" -m pip uninstall --quiet --yes --break-system-packages "${undeclared[@]}"; then
    printf 'agent-tools: python: cleanup failed; the next rebuild will retry\n' >&2
    [ "${AGENT_TOOLS_STRICT:-0}" != 1 ] || return 1
  fi
}

install_external_tools() {
  local tool
  while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    info "external: reconciling ${tool}"
    "$REPO_ROOT/scripts/agent-tools/install-external.sh" "$tool" "$MANIFEST"
  done < <(jq -r '.external | keys[]' "$MANIFEST")
}

reconcile_pi_packages() {
  local effective="$HOME/.local/state/agent-tools/pi-settings.json" sources source
  python3 "$REPO_ROOT/scripts/agent-tools/toolchain.py" render --manifest "$MANIFEST" --output "$effective"
  [ "$HOME/.pi/agent/settings.json" -ef "$effective" ] \
    || die "Pi settings are not linked to the managed pin overlay; run rebuild first"
  # Home Manager links settings.json to this effective overlay, not the authored
  # git file. Weekly bumps and ordinary activation use this same pin owner.
  export PI_SKIP_VERSION_CHECK=1 PI_TELEMETRY=0
  # Pi 1.4's updater skips pinned npm sources instead of installing new pins.
  # Explicit installs also avoid project discovery and a concurrent session's
  # mutable settings. Snapshot only authored, validated, pinned remote sources.
  sources=$(python3 "$REPO_ROOT/scripts/agent-tools/toolchain.py" sources --manifest "$MANIFEST")
  while IFS= read -r source; do
    [ -n "$source" ] || continue
    pi install "$source" --no-approve
  done <<<"$sources"
  # pi install persists its declaration; retain authored resource filters and
  # preferences rather than relying on the CLI's persistence representation.
  python3 "$REPO_ROOT/scripts/agent-tools/toolchain.py" render --manifest "$MANIFEST" --output "$effective"
}

run_setup_hooks() {
  local tool rc
  while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    require_cmd "$tool"
    info "setup hooks: ${tool}"
    # A tool's own hook install can fail transiently (e.g. it reads a config
    # symlink that a prior activation step hasn't relinked yet). Don't let
    # one tool's hook failure abort the whole rebuild - that would also block
    # the later activation step that would fix a stale symlink in the first
    # place. Warn and retry next rebuild instead.
    rc=0
    "$tool" setup hooks || rc=$?
    if [ "$rc" -ne 0 ]; then
      printf 'agent-tools: setup hooks: %s failed (exit %s); will retry next rebuild\n' "$tool" "$rc" >&2
      [ "${AGENT_TOOLS_STRICT:-0}" != 1 ] || return "$rc"
    fi
  done < <(jq -r '.setupHooks.npm[]' "$MANIFEST")
}

verify_bins() {
  local bin missing=0
  while IFS= read -r bin; do
    [ -n "$bin" ] || continue
    if command -v "$bin" >/dev/null 2>&1; then
      info "verify: ok ${bin}"
    else
      printf 'agent-tools: verify: MISSING %s\n' "$bin" >&2
      missing=1
    fi
  done < <(jq -r '.verify.bins[]' "$MANIFEST")

  [ "$missing" -eq 0 ] || die "verification failed: one or more required binaries missing"
}

main() {
  require_cmd jq
  [ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"

  require_cmd python3
  python3 "$REPO_ROOT/scripts/agent-tools/toolchain.py" validate --manifest "$MANIFEST"
  info "reconciling agent tool inventory"
  install_npm_globals
  install_uv_tools
  reconcile_python_globals
  install_external_tools
  reconcile_pi_packages
  run_setup_hooks
  verify_bins
  info "reconcile complete"
}

main "$@"
