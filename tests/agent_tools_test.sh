#!/usr/bin/env bash
# Regression tests for agent-tool reconciliation and audit scripts
#
# Runs reconciliation and audit checks with stub package managers so no real
# network or system mutation occurs. Proves fresh activation installs the
# declared set (identical on every machine - one manifest, no host
# profiles), repeat activation is idempotent, setup hooks run, and missing
# package managers fail according to policy.
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
  cp "$REPO_ROOT/scripts/agent-tools/"*.sh "$REPO_ROOT/scripts/agent-tools/"*.py "$sandbox/repo/scripts/agent-tools/"
  chmod +x "$sandbox/repo/scripts/agent-tools/"*.sh
  # No real uv tool tracks latest, so a fixture entry keeps that path covered.
  local manifest="$sandbox/repo/nix/agent-tools.manifest.lock.json"
  "$(command -v jq)" '.uv += [{"name": "example-latest", "version": "latest"}]' "$manifest" >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"

  : >"$sandbox/uv-tool-list.txt"
  # Copying Apple's signed jq binary causes macOS to kill the copied executable.
  # A symlink retains the original executable while keeping the test PATH-masked.
  ln -s "$(command -v jq)" "$sandbox/stubs/jq"

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
if [ "${1:-}" = leaves ]; then
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

  cat >"$sandbox/stubs/uv" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
LOG="${AGENT_TOOLS_UV_LOG:?}"
echo "uv $*" >>"$LOG"
case "${1:-}" in
  tool)
    case "${2:-}" in
      list)
        cat "${AGENT_TOOLS_STUB_UV_LIST:?}"
        ;;
      install)
        pkg="${*: -1}"
        name="${pkg%%==*}"
        version="${pkg##*==}"
        [ "$pkg" != "$name" ] || version=latest
        list="${AGENT_TOOLS_STUB_UV_LIST:?}"
        grep -v "^${name} " "$list" >"${list}.tmp" 2>/dev/null || true
        mv "${list}.tmp" "$list"
        echo "${name} v${version}" >>"$list"
        mkdir -p "$HOME/.local/bin"
        case "$name" in
          mlx-lm) cmd=mlx_lm ;;
          mlx-optiq) cmd=optiq ;;
          *) cmd="$name" ;;
        esac
        printf '#!/usr/bin/env bash\necho %s stub\n' "$cmd" >"$HOME/.local/bin/$cmd"
        chmod +x "$HOME/.local/bin/$cmd"
        ;;
    esac
    ;;
esac
exit 0
STUB

  for tool in gh-axi lavish-axi chrome-devtools-axi tasks-axi tmux no-mistakes treehouse; do
    cat >"$sandbox/stubs/$tool" <<EOF
#!/usr/bin/env bash
LOG="\${AGENT_TOOLS_HOOK_LOG:?}"
echo "$tool \$*" >>"\$LOG"
if [ "$tool" = no-mistakes ] && [ -e "\$HOME/fail-no-mistakes-update" ]; then
  exit 42
fi
if [ "\$1" = setup ] && [ "\$2" = hooks ] && [ -e "\$HOME/fail-$tool-setup-hooks" ]; then
  exit 1
fi
exit 0
EOF
  done

  # Homebrew python3: logs pip calls; the undeclared-package helper reports
  # one stray package. fail-python-install makes `pip install` fail.
  cat >"$sandbox/stubs/python3" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  *python-undeclared.py) echo stray-pkg; exit 0 ;;
esac
echo "python3 $* PIP_REQUIRE_VIRTUALENV=${PIP_REQUIRE_VIRTUALENV:-unset}" >>"${AGENT_TOOLS_UV_LOG:?}"
if [ "${3:-}" = install ] && [ -e "$HOME/fail-python-install" ]; then
  exit 1
fi
exit 0
STUB

  chmod +x "$sandbox/stubs/"*
  printf '#!/usr/bin/env bash\necho stub-tmux\n' >"$sandbox/stubs/tmux"
  chmod +x "$sandbox/stubs/tmux"

  printf '%s' "$sandbox"
}

run_reconcile() {
  local log=$1 sandbox=$2
  local repo="$sandbox/repo"
  local manifest="$repo/nix/agent-tools.manifest.lock.json"
  local brew_bin="$sandbox/stubs"
  local stub_uv="$sandbox/uv-tool-list.txt"
  local home_dir="$sandbox/home"
  mkdir -p "$log"
  env -i \
    HOME="$home_dir" \
    AGENT_TOOLS_REPO_ROOT="$repo" \
    AGENT_TOOLS_MANIFEST="$manifest" \
    AGENT_TOOLS_BREW_BIN="$brew_bin" \
    AGENT_TOOLS_STUB_UV_LIST="$stub_uv" \
    AGENT_TOOLS_TEST_MODE=1 \
    AGENT_TOOLS_NPM_LOG="$log/npm.log" \
    AGENT_TOOLS_UV_LOG="$log/uv.log" \
    AGENT_TOOLS_HOOK_LOG="$log/hooks.log" \
    PATH="$brew_bin:$home_dir/stub-npm/bin:$home_dir/.local/bin:$home_dir/.no-mistakes/bin:/usr/bin:/bin" \
    "$REAL_BASH" "$repo/scripts/agent-tools/reconcile.sh" \
    >"$log/stdout.log" 2>"$log/stderr.log"
}

test_fresh_install() {
  local sandbox log out rc=0
  sandbox=$(setup_sandbox)
  log="$sandbox/log/fresh"

  run_reconcile "$log" "$sandbox" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "reconcile failed (rc=$rc)" >&2
    cat "$log/stderr.log" >&2 || true
    fail "reconcile exited $rc"
    rm -rf "$sandbox"
    return 0
  fi
  out=$(cat "$log/stdout.log" "$log/stderr.log" "$log/npm.log" "$log/uv.log" "$log/hooks.log")

  assert_contains "$out" "npm: reconciling @earendil-works/pi-coding-agent@latest" "fresh install installs pi"
  assert_contains "$out" "npm: reconciling tasks-axi@latest" "fresh install updates tasks-axi from latest"
  assert_contains "$out" "no-mistakes update --yes" "fresh install self-updates no-mistakes"
  assert_contains "$out" "treehouse update" "fresh install self-updates Treehouse"
  assert_contains "$out" "uv: reconciling example-latest at latest" "fresh install installs a latest uv tool"
  assert_contains "$out" "uv tool install --force --upgrade example-latest" "a latest uv tool installs unpinned with upgrade"
  assert_contains "$out" "uv: reconciling mlx-lm==0.31.3" "fresh install installs mlx-lm on every machine"
  assert_contains "$out" "uv: reconciling mlx-optiq==0.5.13" "fresh install installs mlx-optiq on every machine"
  assert_contains "$out" "python3 -m pip install --quiet --upgrade --break-system-packages pymupdf pypdf PIP_REQUIRE_VIRTUALENV=0" \
    "declared global python3 libraries install at latest, bypassing the virtualenv guard"
  assert_contains "$out" "python3 -m pip uninstall --quiet --yes --break-system-packages stray-pkg" \
    "undeclared global python3 packages are removed"
  assert_contains "$out" "gh-axi setup hooks" "setup hooks run"
  assert_not_contains "$out" "lavish-axi setup hooks" "lavish-axi setup hooks does not run automatically"
  assert_contains "$out" "reconcile complete" "fresh install completes"

  rm -rf "$sandbox"
  pass "fresh activation installs the one shared inventory identically"
}

test_idempotent_repeat() {
  local sandbox log out2 rc=0
  sandbox=$(setup_sandbox)
  log="$sandbox/log/idempotent"

  run_reconcile "$log/first" "$sandbox" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "first reconcile failed" >&2; cat "$log/first/stderr.log" >&2 || true
    fail "first reconcile exited $rc"; rm -rf "$sandbox"; return 0
  fi

  run_reconcile "$log/second" "$sandbox" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "second reconcile failed" >&2; cat "$log/second/stderr.log" >&2 || true
    fail "second reconcile exited $rc"; rm -rf "$sandbox"; return 0
  fi
  out2=$(cat "$log/second/stdout.log" "$log/second/stderr.log" 2>/dev/null || true)
  assert_contains "$out2" "mlx-lm==0.31.3 already installed" "repeat skips unchanged pinned uv tool"
  assert_contains "$out2" "uv: reconciling example-latest at latest" "repeat upgrades a latest uv tool every time"
  assert_contains "$out2" "preserving self-updating no-mistakes" "repeat does not downgrade no-mistakes"
  assert_contains "$out2" "preserving self-updating treehouse" "repeat does not downgrade Treehouse"

  rm -rf "$sandbox"
  pass "repeat activation is idempotent for unchanged uv tool"
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
    AGENT_TOOLS_MANIFEST="$sandbox/repo/nix/agent-tools.manifest.lock.json" \
    AGENT_TOOLS_BREW_BIN="$sandbox/stubs" \
    AGENT_TOOLS_STUB_UV_LIST="$sandbox/uv-tool-list.txt" \
    AGENT_TOOLS_TEST_MODE=1 \
    AGENT_TOOLS_NPM_LOG="$log/npm.log" \
    PATH="$sandbox/stubs:$sandbox/home/.local/bin:/usr/bin:/bin" \
    "$REAL_BASH" "$sandbox/repo/scripts/agent-tools/reconcile.sh" \
    >"$log/stdout.log" 2>"$log/stderr.log" || rc=$?

  [ "$rc" -ne 0 ] || fail "missing npm should fail"
  assert_contains "$(cat "$log/stderr.log")" "required command not found: npm" "missing npm reports failure"

  rm -rf "$sandbox"
  pass "missing npm fails with clear error"
}

test_manifest_json_valid() {
  jq -e '
    .npm and .uv and .external and .setupHooks
    and (.profiles | not)
    and ([.npm[] | type] | all(. == "string"))
    and (.external["no-mistakes"].version == "latest")
    and (.external["no-mistakes"].bootstrapVersion == "1.79.0")
    and (.external["no-mistakes"].selfUpdateCommand == ["update", "--yes"])
    and (.external["no-mistakes"].selfUpdateFailure == "defer")
    and (.external.treehouse.version == "latest")
    and (.external.treehouse.bootstrapVersion == "3.1.0")
    and (.external.treehouse.selfUpdateCommand == ["update"])
  ' "$REPO_ROOT/nix/agent-tools.manifest.lock.json" >/dev/null
  pass "manifest.lock.json is one flat list (no per-host profiles), latest npm tools, declared external self-updaters"
}

test_deferred_no_mistakes_update_does_not_block_rebuild() {
  local sandbox log out rc=0
  sandbox=$(setup_sandbox)
  log="$sandbox/log/deferred-update"
  touch "$sandbox/home/fail-no-mistakes-update"

  run_reconcile "$log" "$sandbox" || rc=$?
  [ "$rc" -eq 0 ] || fail "deferred no-mistakes update blocked reconciliation (rc=$rc)"
  out=$(cat "$log/stdout.log" "$log/stderr.log" "$log/hooks.log" 2>/dev/null || true)
  assert_contains "$out" "deferred no-mistakes self-update after exit 42" \
    "active-run-style no-mistakes refusal is surfaced as deferred"
  assert_contains "$out" "treehouse update" "other self-updaters still run after a deferred update"

  rm -rf "$sandbox"
  pass "a refused no-mistakes self-update is retried on a later rebuild"
}

test_failed_setup_hook_does_not_block_rebuild() {
  local sandbox log out rc=0
  sandbox=$(setup_sandbox)
  log="$sandbox/log/failed-hook"
  touch "$sandbox/home/fail-chrome-devtools-axi-setup-hooks"

  run_reconcile "$log" "$sandbox" || rc=$?
  [ "$rc" -eq 0 ] || fail "a single failing setup hook blocked the whole rebuild (rc=$rc)"
  out=$(cat "$log/stdout.log" "$log/stderr.log" "$log/hooks.log" 2>/dev/null || true)
  assert_contains "$out" "setup hooks: chrome-devtools-axi failed" \
    "a failing setup hook is surfaced as a warning, not a fatal error"
  assert_contains "$out" "tasks-axi setup hooks" \
    "later setup hooks still run after an earlier one fails"
  assert_contains "$out" "reconcile complete" \
    "reconciliation still completes (and can relink stale symlinks) after a setup hook fails"

  rm -rf "$sandbox"
  pass "a failing setup hook is deferred and does not abort the rebuild"
}

test_audit_runs_with_no_arguments() {
  local sandbox out unmanaged
  sandbox=$(setup_sandbox)

  out=$(env -i \
    HOME="$sandbox/home" \
    AGENT_TOOLS_BREW_BIN="$sandbox/stubs" \
    PATH="$sandbox/stubs:/usr/bin:/bin" \
    "$REAL_BASH" "$sandbox/repo/scripts/agent-tools/audit.sh")
  assert_contains "$out" "--- Unmanaged Homebrew formulas (not in declared brew set) ---" \
    "audit reports Homebrew formula status"
  unmanaged=$(printf '%s\n' "$out" | awk '
    /^--- Unmanaged Homebrew formulas/{in_section=1; next}
    /^--- /{in_section=0}
    in_section {print}
  ')
  assert_not_contains "$unmanaged" "uv" "audit recognizes shared uv"

  rm -rf "$sandbox"
  pass "audit runs identically with no host-profile argument"
}

test_failed_python_install_does_not_block_rebuild() {
  local sandbox log out rc=0
  sandbox=$(setup_sandbox)
  log="$sandbox/log/failed-python"
  touch "$sandbox/home/fail-python-install"

  run_reconcile "$log" "$sandbox" || rc=$?
  [ "$rc" -eq 0 ] || fail "a failed python3 install blocked the whole rebuild (rc=$rc)"
  out=$(cat "$log/stdout.log" "$log/stderr.log" "$log/uv.log" 2>/dev/null || true)
  assert_contains "$out" "python: install failed; skipping cleanup" "a failed python3 install is surfaced as a warning"
  assert_not_contains "$out" "pip uninstall" "cleanup is skipped when the declared install failed"
  assert_contains "$out" "reconcile complete" "reconciliation still completes after a failed python3 install"

  rm -rf "$sandbox"
  pass "a failed python3 install skips cleanup and does not abort the rebuild"
}

# Runs the real helper against fake dist-info metadata: declared packages and
# their runtime dependencies stay, as do packages Homebrew installed itself
# and their dependencies;
# extras-only and other-platform requirements do not keep anything.
test_python_undeclared_helper() {
  local py=/opt/homebrew/bin/python3 site out
  if [ ! -x "$py" ]; then
    pass "python-undeclared helper (skipped: no Homebrew python3)"
    return 0
  fi
  site=$(mktemp -d "${TMPDIR:-/tmp}/python-undeclared.XXXXXX")
  fake_dist() {  # <name> <installer> [Requires-Dist ...]
    local dir="$site/$1-1.0.dist-info" req
    mkdir -p "$dir"
    printf 'Metadata-Version: 2.1\nName: %s\nVersion: 1.0\n' "$1" >"$dir/METADATA"
    for req in "${@:3}"; do printf 'Requires-Dist: %s\n' "$req" >>"$dir/METADATA"; done
    printf '%s\n' "$2" >"$dir/INSTALLER"
  }
  fake_dist Declared_Lib pip 'dep-a>=1' 'only-extra; extra == "docs"' 'only-windows; sys_platform == "win32"'
  fake_dist dep-a pip dep-b
  fake_dist dep-b pip
  fake_dist only-extra pip
  fake_dist only-windows pip
  fake_dist stray pip
  fake_dist wheel brew brew-dep
  fake_dist brew-dep pip

  out=$("$py" "$REPO_ROOT/scripts/agent-tools/python-undeclared.py" --path "$site" declared-lib)
  rm -rf "$site"
  [ "$out" = "$(printf 'only-extra\nonly-windows\nstray')" ] \
    || fail "python-undeclared helper kept or dropped the wrong packages: $(echo "$out" | tr '\n' ' ')"
  pass "python-undeclared helper keeps declared packages, their dependencies, and Homebrew's own"
}

test_fresh_install
test_idempotent_repeat
test_missing_npm_fails
test_manifest_json_valid
test_deferred_no_mistakes_update_does_not_block_rebuild
test_failed_setup_hook_does_not_block_rebuild
test_audit_runs_with_no_arguments
test_failed_python_install_does_not_block_rebuild
test_python_undeclared_helper

if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES test(s) failed" >&2
  exit 1
fi

echo "All agent_tools_test.sh scenarios passed."
