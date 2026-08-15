#!/usr/bin/env bash
# reconcile.sh - idempotently install/reconcile declared agent tool inventory
#
# Usage: reconcile.sh <host-profile>
#   host-profile: camilo | camilo-remote
#
# Called from Home Manager activation on rebuild. Reads nix/shared/agent-tools/manifest.lock.json.
set -euo pipefail

HOST_PROFILE=${1:?usage: reconcile.sh <camilo|camilo-remote>}
REPO_ROOT=${AGENT_TOOLS_REPO_ROOT:-"$(cd "$(dirname "$0")/../.." && pwd)"}
MANIFEST="${AGENT_TOOLS_MANIFEST:-$REPO_ROOT/nix/shared/agent-tools/manifest.lock.json}"
BREW_BIN=${AGENT_TOOLS_BREW_BIN:-/opt/homebrew/bin}

export PATH="${BREW_BIN}:${HOME}/.local/bin:${HOME}/.no-mistakes/bin:${PATH:-}"

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
  local specs name version
  while IFS= read -r specs; do
    [ -n "$specs" ] || continue
    info "npm: reconciling ${specs}"
    npm install -g --ignore-scripts "$specs"
  done < <(jq -r '.npm[] | "\(.name)@\(.version)"' "$MANIFEST")
}

pipx_list_json() {
  if [ -n "${AGENT_TOOLS_STUB_PIPX_LIST:-}" ] && [ -f "${AGENT_TOOLS_STUB_PIPX_LIST}" ]; then
    cat "${AGENT_TOOLS_STUB_PIPX_LIST}"
    return 0
  fi
  pipx list --json
}

pipx_installed_version() {
  local name=$1
  pipx_list_json | jq -r --arg n "$name" '.venvs[$n].metadata.main_package.package_version // empty'
}

install_pipx_packages() {
  require_cmd pipx
  local filter='.pipx.shared[]'
  if [ "$HOST_PROFILE" = camilo ]; then
    filter='.pipx.shared[], .pipx.camilo[]?'
  fi

  local name version current
  while IFS=$'\t' read -r name version; do
    [ -n "$name" ] || continue
    current=$(pipx_installed_version "$name" || true)
    if [ "$current" = "$version" ]; then
      info "pipx: ${name}==${version} already installed"
      continue
    fi
    info "pipx: reconciling ${name}==${version}"
    pipx install --force "${name}==${version}" || die "pipx install failed for ${name}==${version}"
  done < <(jq -r "$filter | [.name, .version] | @tsv" "$MANIFEST")
}

install_external_tools() {
  local tool
  while IFS= read -r tool; do
    [ -n "$tool" ] || continue
  info "external: reconciling ${tool}"
    "$REPO_ROOT/scripts/agent-tools/install-external.sh" "$tool" "$MANIFEST"
  done < <(jq -r '.external | keys[]' "$MANIFEST")
}

run_setup_hooks() {
  local tool
  while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    require_cmd "$tool"
    info "setup hooks: ${tool}"
    "$tool" setup hooks
  done < <(jq -r '.setupHooks.npm[]' "$MANIFEST")

  if jq -e '.setupHooks.graphify' "$MANIFEST" >/dev/null; then
    require_cmd graphify
    local platform
    while IFS= read -r platform; do
      [ -n "$platform" ] || continue
      info "graphify install --platform ${platform}"
      graphify install --platform "$platform"
    done < <(jq -r '.setupHooks.graphify.platforms[]' "$MANIFEST")
  fi
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

  if [ "$HOST_PROFILE" = camilo ]; then
    while IFS= read -r bin; do
      [ -n "$bin" ] || continue
      if command -v "$bin" >/dev/null 2>&1; then
        info "verify: ok ${bin} (host ${HOST_PROFILE})"
      else
        printf 'agent-tools: verify: MISSING %s (host %s)\n' "$bin" "$HOST_PROFILE" >&2
        missing=1
      fi
    done < <(jq -r --arg h "$HOST_PROFILE" '.verify.hostBins[$h][]? // empty' "$MANIFEST")
  fi

  [ "$missing" -eq 0 ] || die "verification failed: one or more required binaries missing"
}

main() {
  require_cmd jq
  [ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"
  case "$HOST_PROFILE" in
    camilo | camilo-remote) ;;
    *) die "unknown host profile: $HOST_PROFILE" ;;
  esac

  info "reconciling inventory for host profile ${HOST_PROFILE}"
  install_npm_globals
  install_pipx_packages
  install_external_tools
  run_setup_hooks
  verify_bins
  info "reconcile complete"
}

main "$@"
