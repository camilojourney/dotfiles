#!/usr/bin/env bash
# Regression tests for agent-tool reconciliation and audit scripts
#
# Runs reconciliation and audit checks with stub package managers so no real
# network or system mutation occurs. Proves fresh activation installs the declared
# set, repeat activation is idempotent, setup hooks run, host-specific pipx
# packages stay scoped, missing package managers fail according to policy, and
# shared Homebrew formulas are recognized by the audit for both host profiles.
#
# Run: bash tests/agent_tools_test.sh

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
REAL_BASH=/bin/bash

FAILURES=0

fail() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "PASS: $1"
}

assert_contains() {
  local haystack=$1 needle=$2 msg=$3
  if ! grep -qF -- "$needle" <<<"$haystack"; then
    fail "$msg -- expected: $needle"
    return 1
  fi
  return 0
}

assert_not_contains() {
  local haystack=$1 needle=$2 msg=$3
  if grep -qF -- "$needle" <<<"$haystack"; then
    fail "$msg -- unexpected: $needle"
    return 1
  fi
  return 0
}

setup_sandbox() {
  local sandbox
  sandbox=$(mktemp -d "${TMPDIR:-/tmp}/agent-tools-test.XXXXXX")
  mkdir -p "$sandbox/home/bin" "$sandbox/home/.local/bin" "$sandbox/home/.no-mistakes/bin" \
    "$sandbox/log" "$sandbox/stubs" "$sandbox/repo/scripts/agent-tools"

  cp -R "$REPO_ROOT/nix" "$sandbox/repo/"
  cp "$REPO_ROOT/scripts/agent-tools/"*.sh "$sandbox/repo/scripts/agent-tools/"
  chmod +x "$sandbox/repo/scripts/agent-tools/"*.sh

  printf '{}' >"$sandbox/pipx-list.json"
  cp "$(command -v jq)" "$sandbox/stubs/jq"

  cat >"$sandbox/stubs/npm" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
LOG="${AGENT_TOOLS_NPM_LOG:?}"
echo "npm $*" >>"$LOG"
case "${1:-}" in
  install)
    spec="${*: -1}"
    name="${spec%@*}"
    mkdir -p "$HOME/stub-npm/bin"
    case "$name" in
      @earendil-works/pi-coding-agent) bins=(pi) ;;
      chrome-devtools-axi) bins=(chrome-devtools-axi) ;;
      gh-axi) bins=(gh-axi) ;;
      lavish-axi) bins=(lavish-axi) ;;
      quota-axi) bins=(quota-axi) ;;
      tasks-axi) bins=(tasks-axi) ;;
      *) bins=("${name##*/}") ;;
    esac
    touch "$HOME/stub-npm/installed-$(echo "$spec" | tr '/@' '__')"
    for bin in "${bins[@]}"; do
      printf '#!/usr/bin/env bash\necho %s stub\n' "$bin" >"$HOME/stub-npm/bin/$bin"
      chmod +x "$HOME/stub-npm/bin/$bin"
    done
    ;;
esac
exit 0
STUB

  cat >"$sandbox/stubs/brew" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = list ] && [ "${2:-}" = --formula ]; then
  echo uv
fi
STUB

  cat >"$sandbox/stubs/uname" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  -s) echo Linux ;;
  -m) echo x86_64 ;;
esac
STUB

  cat >"$sandbox/stubs/pipx" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
LOG="${AGENT_TOOLS_PIPX_LOG:?}"
echo "pipx $*" >>"$LOG"
case "${1:-}" in
  list)
    if [ "${2:-}" = --json ]; then
      cat "${AGENT_TOOLS_STUB_PIPX_LIST:?}"
      exit 0
    fi
    if [ "${2:-}" = --short ]; then
      jq -r '.venvs | keys[]' "${AGENT_TOOLS_STUB_PIPX_LIST:?}" 2>/dev/null || true
      exit 0
    fi
    ;;
  install)
    pkg="${*: -1}"
    name="${pkg%%==*}"
    version="${pkg##*==}"
    tmp=$(mktemp)
    jq --arg n "$name" --arg v "$version" \
      '.venvs[$n] = {metadata: {main_package: {package: $n, package_version: $v}}}' \
      "${AGENT_TOOLS_STUB_PIPX_LIST:?}" >"$tmp" && mv "$tmp" "${AGENT_TOOLS_STUB_PIPX_LIST:?}"
    mkdir -p "$HOME/.local/bin"
    case "$name" in
      graphifyy) cmd=graphify ;;
      mlx-lm) cmd=mlx_lm ;;
      mlx-optiq) cmd=optiq ;;
      *) cmd="$name" ;;
    esac
    printf '#!/usr/bin/env bash\necho %s stub\n' "$cmd" >"$HOME/.local/bin/$cmd"
    chmod +x "$HOME/.local/bin/$cmd"
    ;;
esac
exit 0
STUB

  for tool in gh-axi lavish-axi chrome-devtools-axi tasks-axi graphify tmux; do
    cat >"$sandbox/stubs/$tool" <<EOF
#!/usr/bin/env bash
LOG="\${AGENT_TOOLS_HOOK_LOG:?}"
echo "$tool \$*" >>"\$LOG"
exit 0
EOF
  done

  chmod +x "$sandbox/stubs/"*
  printf '#!/usr/bin/env bash\necho stub-tmux\n' >"$sandbox/stubs/tmux"
  chmod +x "$sandbox/stubs/tmux"

  printf '%s' "$sandbox"
}

run_reconcile() {
  local profile=$1 log=$2 sandbox=$3
  local repo="$sandbox/repo"
  local manifest="$repo/nix/shared/agent-tools/manifest.lock.json"
  local brew_bin="$sandbox/stubs"
  local stub_pipx="$sandbox/pipx-list.json"
  local home_dir="$sandbox/home"
  mkdir -p "$log"
  env -i \
    HOME="$home_dir" \
    AGENT_TOOLS_REPO_ROOT="$repo" \
    AGENT_TOOLS_MANIFEST="$manifest" \
    AGENT_TOOLS_BREW_BIN="$brew_bin" \
    AGENT_TOOLS_STUB_PIPX_LIST="$stub_pipx" \
    AGENT_TOOLS_TEST_MODE=1 \
    AGENT_TOOLS_NPM_LOG="$log/npm.log" \
    AGENT_TOOLS_PIPX_LOG="$log/pipx.log" \
    AGENT_TOOLS_HOOK_LOG="$log/hooks.log" \
    PATH="$brew_bin:$home_dir/stub-npm/bin:$home_dir/.local/bin:$home_dir/.no-mistakes/bin:/usr/bin:/bin" \
    "$REAL_BASH" "$repo/scripts/agent-tools/reconcile.sh" "$profile" \
    >"$log/stdout.log" 2>"$log/stderr.log"
}

test_fresh_install_shared() {
  local sandbox log out rc=0
  sandbox=$(setup_sandbox)
  log="$sandbox/log/fresh"

  run_reconcile camilo-mini "$log" "$sandbox" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "reconcile failed (rc=$rc)" >&2
    cat "$log/stderr.log" >&2 || true
    fail "reconcile exited $rc"
    rm -rf "$sandbox"
    return 0
  fi
  out=$(cat "$log/stdout.log" "$log/stderr.log" "$log/npm.log" "$log/pipx.log" "$log/hooks.log")

  assert_contains "$out" "npm: reconciling @earendil-works/pi-coding-agent@0.84.1" "fresh mini installs pi"
  assert_contains "$out" "pipx: reconciling graphifyy==0.9.34" "fresh mini installs graphifyy"
  assert_not_contains "$out" "mlx-lm" "mini skips laptop mlx"
  assert_contains "$out" "gh-axi setup hooks" "setup hooks run"
  assert_contains "$out" "graphify install --platform pi" "graphify platform hook"
  assert_contains "$out" "reconcile complete" "fresh mini completes"

  rm -rf "$sandbox"
  pass "fresh activation installs shared inventory for camilo-mini"
}

test_idempotent_repeat() {
  local sandbox log out2 rc=0
  sandbox=$(setup_sandbox)
  log="$sandbox/log/idempotent"

  run_reconcile camilo "$log/first" "$sandbox" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "first reconcile failed" >&2; cat "$log/first/stderr.log" >&2 || true
    fail "first reconcile exited $rc"; rm -rf "$sandbox"; return 0
  fi
  jq '.venvs.graphifyy = {metadata: {main_package: {package: "graphifyy", package_version: "0.9.34"}}}' \
    "$sandbox/pipx-list.json" >"$sandbox/pipx-list.tmp" && mv "$sandbox/pipx-list.tmp" "$sandbox/pipx-list.json"

  run_reconcile camilo "$log/second" "$sandbox" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "second reconcile failed" >&2; cat "$log/second/stderr.log" >&2 || true
    fail "second reconcile exited $rc"; rm -rf "$sandbox"; return 0
  fi
  out2=$(cat "$log/second/stdout.log" "$log/second/stderr.log" 2>/dev/null || true)
  assert_contains "$out2" "graphifyy==0.9.34 already installed" "repeat skips unchanged pipx"

  rm -rf "$sandbox"
  pass "repeat activation is idempotent for unchanged pipx"
}

test_host_scoped_pipx() {
  local sandbox log out
  sandbox=$(setup_sandbox)
  log="$sandbox/log/host"

  run_reconcile camilo "$log" "$sandbox"
  out=$(cat "$log/pipx.log")
  assert_contains "$out" "mlx-lm==0.31.3" "laptop installs mlx-lm"
  assert_contains "$out" "mlx-optiq==0.4.7" "laptop installs mlx-optiq"

  rm -rf "$sandbox"
  pass "host-specific pipx packages install only on camilo"
}

test_missing_npm_fails() {
  local sandbox log rc=0
  sandbox=$(setup_sandbox)
  log="$sandbox/log/missing"
  mkdir -p "$log"
  rm "$sandbox/stubs/npm"

  env -i \
    HOME="$sandbox/home" \
    AGENT_TOOLS_REPO_ROOT="$sandbox/repo" \
    AGENT_TOOLS_MANIFEST="$sandbox/repo/nix/shared/agent-tools/manifest.lock.json" \
    AGENT_TOOLS_BREW_BIN="$sandbox/stubs" \
    AGENT_TOOLS_STUB_PIPX_LIST="$sandbox/pipx-list.json" \
    AGENT_TOOLS_TEST_MODE=1 \
    AGENT_TOOLS_NPM_LOG="$log/npm.log" \
    PATH="$sandbox/stubs:$sandbox/home/.local/bin:/usr/bin:/bin" \
    "$REAL_BASH" "$sandbox/repo/scripts/agent-tools/reconcile.sh" camilo-mini \
    >"$log/stdout.log" 2>"$log/stderr.log" || rc=$?

  [ "$rc" -ne 0 ] || fail "missing npm should fail"
  assert_contains "$(cat "$log/stderr.log")" "required command not found: npm" "missing npm reports failure"

  rm -rf "$sandbox"
  pass "missing npm fails with clear error"
}

test_manifest_json_valid() {
  jq -e '.npm and .pipx and .external and .setupHooks' \
    "$REPO_ROOT/nix/shared/agent-tools/manifest.lock.json" >/dev/null
  pass "manifest.lock.json parses and has required sections"
}

test_audit_recognizes_shared_uv_for_both_hosts() {
  local sandbox profile out unmanaged
  sandbox=$(setup_sandbox)

  for profile in camilo camilo-mini; do
    out=$(env -i \
      HOME="$sandbox/home" \
      AGENT_TOOLS_BREW_BIN="$sandbox/stubs" \
      PATH="$sandbox/stubs:/usr/bin:/bin" \
      "$REAL_BASH" "$sandbox/repo/scripts/agent-tools/audit.sh" "$profile")
    assert_contains "$out" "--- Unmanaged Homebrew formulas (not in declared brew set) ---" \
      "audit reports Homebrew formula status for $profile"
    unmanaged=$(printf '%s\n' "$out" | awk '
      /^--- Unmanaged Homebrew formulas/{in_section=1; next}
      /^--- /{in_section=0}
      in_section {print}
    ')
    assert_not_contains "$unmanaged" "uv" "audit recognizes shared uv for $profile"
  done

  rm -rf "$sandbox"
  pass "audit recognizes shared uv for both host profiles"
}

test_fresh_install_shared
test_idempotent_repeat
test_host_scoped_pipx
test_missing_npm_fails
test_manifest_json_valid
test_audit_recognizes_shared_uv_for_both_hosts

if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES test(s) failed" >&2
  exit 1
fi

echo "All agent_tools_test.sh scenarios passed."
