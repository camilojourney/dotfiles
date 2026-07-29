#!/bin/bash
#
# Sandboxed regression test for scripts/verify-graphify-sync.sh.
#
# Run: bash tests/graphify_sync_test.sh

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/graphify-sync-test.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT

FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME"

target="$REPO_ROOT/files/skills/graphify"
links=(
  ".claude/skills/graphify"
  ".codex/skills/graphify"
  ".cursor/skills/graphify"
  ".agents/skills/graphify"
  ".gemini/skills/graphify"
  ".gemini/antigravity/skills/graphify"
  ".gemini/antigravity-cli/skills/graphify"
  ".gemini/config/skills/graphify"
)

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

canonical_path() {
  local path="$1" parent base

  if [ -d "$path" ]; then
    (cd "$path" && pwd -P)
    return
  fi

  parent=$(dirname "$path")
  base=$(basename "$path")
  parent=$(cd "$parent" && pwd -P) || return 1
  printf '%s/%s\n' "$parent" "$base"
}

assert_path_under_sandbox() {
  local path="$1" label="$2" abs_path abs_sandbox

  abs_path=$(canonical_path "$path") ||
    fail "could not resolve $label path: $path"
  abs_sandbox=$(canonical_path "$SANDBOX") ||
    fail "could not resolve sandbox path: $SANDBOX"

  case "$abs_path" in
    "$abs_sandbox" | "$abs_sandbox"/*) ;;
    *) fail "$label escaped sandbox: $abs_path (sandbox: $abs_sandbox)" ;;
  esac
}

assert_path_not_source_git() {
  local path="$1" label="$2" abs_path source_top source_git_dir

  abs_path=$(canonical_path "$path") ||
    fail "could not resolve $label path: $path"
  source_top=$(canonical_path "$(git -C "$REPO_ROOT" rev-parse --show-toplevel)") ||
    fail "could not resolve source worktree top-level"
  source_git_dir=$(canonical_path "$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)") ||
    fail "could not resolve source git-dir"

  case "$abs_path" in
    "$source_top" | "$source_top"/*)
      fail "$label points at source worktree: $abs_path"
      ;;
    "$source_git_dir" | "$source_git_dir"/*)
      fail "$label points at source git-dir: $abs_path"
      ;;
  esac
}

remove_copied_git_metadata() {
  local repo="$1" copied_git

  copied_git="$repo/.git"

  assert_path_under_sandbox "$repo" "sandbox repo"
  assert_path_under_sandbox "$copied_git" "copied .git metadata"
  rm -rf "$copied_git"
}

assert_sandbox_git_isolated() {
  local repo="$1" git_dir top_level

  top_level=$(git -C "$repo" rev-parse --show-toplevel)
  git_dir=$(git -C "$repo" rev-parse --absolute-git-dir)

  assert_path_under_sandbox "$top_level" "sandbox git top-level"
  assert_path_under_sandbox "$git_dir" "sandbox git-dir"
  assert_path_not_source_git "$top_level" "sandbox git top-level"
  assert_path_not_source_git "$git_dir" "sandbox git-dir"
}

assert_verifier_rejects_target() {
  local rel="$1" rejected_target="$2" label="$3" output status

  rm "$FAKE_HOME/$rel"
  ln -s "$rejected_target" "$FAKE_HOME/$rel"

  set +e
  output=$(
    GRAPHIFY_SYNC_HOME="$FAKE_HOME" \
    GRAPHIFY_SYNC_DOTFILES_DIR="$REPO_ROOT" \
      bash "$REPO_ROOT/scripts/verify-graphify-sync.sh" 2>&1
  )
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "FAIL: verifier accepted non-portable $label target: $rejected_target" >&2
    exit 1
  fi
  if ! grep -qF "installed Graphify symlink target mismatch" <<<"$output"; then
    echo "FAIL: verifier did not report $label target mismatch" >&2
    exit 1
  fi

  rm "$FAKE_HOME/$rel"
  ln -s "$target" "$FAKE_HOME/$rel"
  echo "PASS: verifier rejects non-portable $label target"
}

make_sandbox_repo() {
  local name="$1" dest

  case "$name" in
    "" | */* | .* )
      fail "invalid sandbox repo name: $name"
      ;;
  esac

  dest="$SANDBOX/$name"

  rm -rf "$dest"
  mkdir -p "$dest"
  assert_path_under_sandbox "$dest" "sandbox repo destination"
  cp -R "$REPO_ROOT/." "$dest"
  remove_copied_git_metadata "$dest"
  git -C "$dest" init -q
  assert_sandbox_git_isolated "$dest"
  git -C "$dest" add -- .
  assert_sandbox_git_isolated "$dest"
  echo "$dest"
}

point_fake_home_at_repo() {
  local repo="$1" rel

  for rel in "${links[@]}"; do
    rm -rf "$FAKE_HOME/$rel"
    mkdir -p "$FAKE_HOME/$(dirname "$rel")"
    ln -s "$repo/files/skills/graphify" "$FAKE_HOME/$rel"
  done
}

if grep -qF "/Users/" "$REPO_ROOT/scripts/verify-graphify-sync.sh"; then
  echo "FAIL: verifier contains hardcoded /Users/ path" >&2
  exit 1
fi
echo "PASS: graphify sync verifier has no hardcoded /Users/ path"

python3 - "$REPO_ROOT/files/skills/graphify" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
version = (root / ".graphify_version").read_text(encoding="utf-8").strip()
files = [root / "SKILL.md", *sorted((root / "references").glob("*.md"))]
unpinned = []
for path in files:
    text = path.read_text(encoding="utf-8")
    for match in re.finditer(r"graphifyy(?:\[[^\]\s'\"]+\])?(?:==[0-9.]+)?", text):
        package = match.group()
        line = text.count("\n", 0, match.start()) + 1
        source_line = text.splitlines()[line - 1]
        context = text[max(0, match.start() - 20):match.end() + 20]
        if package == "graphifyy" and (
            "version('graphifyy')" in context
            or 'distribution("graphifyy")' in context
            or "distribution('graphifyy')" in context
        ):
            continue
        if package == "graphifyy" and source_line.strip() == 'GRAPHIFY_PACKAGE="graphifyy==$GRAPHIFY_VERSION"':
            continue
        if package != "graphifyy" and package.endswith(f"=={version}"):
            continue
        unpinned.append(f"{path}:{line}: {package}")
skill = (root / "SKILL.md").read_text(encoding="utf-8")
if f'GRAPHIFY_VERSION="{version}"' not in skill:
    unpinned.append("SKILL.md: missing Graphify runtime version assignment")
if 'GRAPHIFY_PACKAGE="graphifyy==$GRAPHIFY_VERSION"' not in skill:
    unpinned.append("SKILL.md: missing pinned Graphify package assignment")
for path in files:
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("graphify ") or "$(graphify " in stripped:
            unpinned.append(f"{path}:{line_number}: direct Graphify CLI invocation")
        if " -m graphify " in stripped:
            unpinned.append(f"{path}:{line_number}: shadowable Graphify module CLI invocation")
if unpinned:
    print("FAIL: unpinned Graphify runtime references:", file=sys.stderr)
    print("\n".join(unpinned), file=sys.stderr)
    sys.exit(1)
PY
echo "PASS: Graphify runtime references match vendored version"

GRAPHIFY_SYNC_HOME="$FAKE_HOME" \
GRAPHIFY_SYNC_DOTFILES_DIR="$REPO_ROOT" \
  bash "$REPO_ROOT/scripts/verify-graphify-sync.sh" >/dev/null
echo "PASS: graphify sync verifier allows a fully absent pre-activation link set"

RUNTIME_BIN="$SANDBOX/runtime-bin"
RUNTIME_WORK="$SANDBOX/runtime-work"
RUNTIME_STATE="$SANDBOX/runtime-version"
RUNTIME_PYTHON="$RUNTIME_BIN/mismatch-python"
TRUSTED_SITE="$SANDBOX/trusted-site"
mkdir -p "$RUNTIME_BIN" "$RUNTIME_WORK"
printf '0.9.30\n' > "$RUNTIME_STATE"

cat > "$RUNTIME_PYTHON" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
code="${2:-}"
if [[ "${1:-}" == -c && "$code" == *"from importlib.metadata import version"* ]]; then
  [[ "$(cat "$GRAPHIFY_RUNTIME_STATE")" == 0.9.29 ]]
elif [[ "${1:-}" == -c && "$code" == *"locate_file"* ]]; then
  printf '%s\n' "$GRAPHIFY_RUNTIME_SITE"
elif [[ "${1:-}" == -m && "${2:-}" == pip && "${3:-}" == install ]]; then
  [[ " $* " == *" graphifyy==0.9.29 "* ]]
  printf '0.9.29\n' > "$GRAPHIFY_RUNTIME_STATE"
elif [[ "${1:-}" == -c && "$code" == *".graphify_interpreter"* ]]; then
  mkdir -p graphify-out
  printf '%s\n' "$0" > graphify-out/.graphify_interpreter
fi
STUB
chmod +x "$RUNTIME_PYTHON"
ln -s "$RUNTIME_PYTHON" "$RUNTIME_BIN/python3"
printf '#!%s\nexit 0\n' "$RUNTIME_PYTHON" > "$RUNTIME_BIN/graphify"
chmod +x "$RUNTIME_BIN/graphify"

awk '
  /^### Step 1 - Ensure graphify is installed$/ { in_step = 1; next }
  in_step && /^```bash$/ { in_block = 1; next }
  in_block && /^```$/ { exit }
  in_block { gsub(/INPUT_PATH/, "."); print }
' "$REPO_ROOT/files/skills/graphify/SKILL.md" > "$SANDBOX/graphify-step1.sh"

(
  cd "$RUNTIME_WORK"
  GRAPHIFY_RUNTIME_STATE="$RUNTIME_STATE" \
  GRAPHIFY_RUNTIME_SITE="$TRUSTED_SITE" \
  PATH="$RUNTIME_BIN:/usr/bin:/bin" \
    bash "$SANDBOX/graphify-step1.sh"
)

if [ "$(cat "$RUNTIME_STATE")" != "0.9.29" ]; then
  echo "FAIL: Step 1 accepted an installed mismatched Graphify runtime" >&2
  exit 1
fi
echo "PASS: Step 1 replaces an installed mismatched Graphify runtime"

ENTRYPOINT_MARKER="$SANDBOX/entrypoint-marker"
mkdir -p "$TRUSTED_SITE/graphify" "$TRUSTED_SITE/graphifyy-0.9.29.dist-info"

cat > "$TRUSTED_SITE/graphify/__init__.py" <<'PY'
import os
from pathlib import Path

def main():
    Path(os.environ["GRAPHIFY_ENTRYPOINT_MARKER"]).write_text("trusted", encoding="utf-8")
PY

cat > "$TRUSTED_SITE/graphifyy-0.9.29.dist-info/METADATA" <<'EOF'
Metadata-Version: 2.1
Name: graphifyy
Version: 0.9.29
EOF

cat > "$TRUSTED_SITE/graphifyy-0.9.29.dist-info/entry_points.txt" <<'EOF'
[console_scripts]
graphify = graphify:main
EOF

cat > "$RUNTIME_WORK/graphify.py" <<'PY'
import os
from pathlib import Path

def main():
    Path(os.environ["GRAPHIFY_ENTRYPOINT_MARKER"]).write_text("shadowed", encoding="utf-8")
PY

mkdir -p "$RUNTIME_WORK/graphify-out/graphifyy-0.9.29.dist-info"
cp "$TRUSTED_SITE/graphifyy-0.9.29.dist-info/METADATA" \
  "$RUNTIME_WORK/graphify-out/graphifyy-0.9.29.dist-info/METADATA"
cat > "$RUNTIME_WORK/graphify-out/graphifyy-0.9.29.dist-info/entry_points.txt" <<'EOF'
[console_scripts]
graphify = graphify:main
EOF
cat > "$RUNTIME_WORK/graphify-out/graphify.py" <<'PY'
import os
from pathlib import Path

def main():
    Path(os.environ["GRAPHIFY_ENTRYPOINT_MARKER"]).write_text("forged", encoding="utf-8")
PY
printf '%s\n' "/usr/bin/python3" > "$RUNTIME_WORK/graphify-out/.graphify_interpreter"

(
  cd "$RUNTIME_WORK"
  GRAPHIFY_ENTRYPOINT_MARKER="$ENTRYPOINT_MARKER" \
  PYTHONPATH="$TRUSTED_SITE" \
    "$(cat graphify-out/.graphify_python)" graphify-out/.graphify_cli.py query
)

if [ "$(cat "$ENTRYPOINT_MARKER")" != "trusted" ]; then
  echo "FAIL: pinned Graphify CLI wrapper loaded a repository shadow module" >&2
  exit 1
fi
echo "PASS: pinned Graphify CLI wrapper rejects repository module shadowing"

# 1. Positive case: all 8 symlink targets present under fake home
for rel in "${links[@]}"; do
  mkdir -p "$FAKE_HOME/$(dirname "$rel")"
  ln -s "$target" "$FAKE_HOME/$rel"
done

GRAPHIFY_SYNC_HOME="$FAKE_HOME" \
GRAPHIFY_SYNC_DOTFILES_DIR="$REPO_ROOT" \
  bash "$REPO_ROOT/scripts/verify-graphify-sync.sh" >/dev/null
echo "PASS: positive test with portable fake home and all 8 symlinks"

# 2. Negative case: wrong symlink target
rm "$FAKE_HOME/.codex/skills/graphify"
ln -s "$SANDBOX/wrong-target" "$FAKE_HOME/.codex/skills/graphify"

set +e
bad_output=$(
  GRAPHIFY_SYNC_HOME="$FAKE_HOME" \
  GRAPHIFY_SYNC_DOTFILES_DIR="$REPO_ROOT" \
    bash "$REPO_ROOT/scripts/verify-graphify-sync.sh" 2>&1
)
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: verifier accepted a wrong installed symlink target" >&2
  exit 1
fi
if ! grep -qF "installed Graphify symlink target mismatch" <<<"$bad_output"; then
  echo "FAIL: verifier failure did not identify the symlink target check" >&2
  exit 1
fi
echo "PASS: graphify sync verifier rejects wrong sandboxed symlink target"

# Restore valid symlink for next sub-tests
rm "$FAKE_HOME/.codex/skills/graphify"
ln -s "$target" "$FAKE_HOME/.codex/skills/graphify"

# 3. Negative case: non-symlink path (e.g. real directory)
rm "$FAKE_HOME/.claude/skills/graphify"
mkdir -p "$FAKE_HOME/.claude/skills/graphify"

set +e
non_sym_output=$(
  GRAPHIFY_SYNC_HOME="$FAKE_HOME" \
  GRAPHIFY_SYNC_DOTFILES_DIR="$REPO_ROOT" \
    bash "$REPO_ROOT/scripts/verify-graphify-sync.sh" 2>&1
)
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: verifier accepted non-symlink installed path" >&2
  exit 1
fi
if ! grep -qF "installed Graphify path is not a symlink" <<<"$non_sym_output"; then
  echo "FAIL: verifier did not report non-symlink failure" >&2
  exit 1
fi
echo "PASS: graphify sync verifier rejects non-symlink installed path"

# Restore valid symlink
rm -rf "$FAKE_HOME/.claude/skills/graphify"
ln -s "$target" "$FAKE_HOME/.claude/skills/graphify"

# 4. Negative case: partially installed link set
rm "$FAKE_HOME/.gemini/config/skills/graphify"

set +e
partial_output=$(
  GRAPHIFY_SYNC_HOME="$FAKE_HOME" \
  GRAPHIFY_SYNC_DOTFILES_DIR="$REPO_ROOT" \
    bash "$REPO_ROOT/scripts/verify-graphify-sync.sh" 2>&1
)
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: verifier accepted a partially installed Graphify link set" >&2
  exit 1
fi
if ! grep -qF "installed Graphify path is missing: .gemini/config/skills/graphify" <<<"$partial_output"; then
  echo "FAIL: verifier did not report the missing installed Graphify path" >&2
  exit 1
fi
echo "PASS: graphify sync verifier rejects partially installed link set"

ln -s "$target" "$FAKE_HOME/.gemini/config/skills/graphify"

# 5. Portability checks: absolute Fleet checkout targets must not be whitelisted.
assert_verifier_rejects_target \
  ".cursor/skills/graphify" \
  "/Users/camiloslaptop/github/fleet-system/system/skills/platform/graphify" \
  "laptop Fleet"

assert_verifier_rejects_target \
  ".agents/skills/graphify" \
  "/Users/mini/.openclaw/workspace/github/~fleet-system/system/skills/platform/graphify" \
  "Mini Fleet"

# 6. Negative case in sandboxed repo: forbidden tracked Herdr runtime files
SANDBOX_REPO=$(make_sandbox_repo "repo-forbidden-tracked")
point_fake_home_at_repo "$SANDBOX_REPO"
forbidden_paths=(
  "files/.config/herdr/session.json"
  "files/.config/herdr/release-notes.json"
  "files/.config/herdr/sessions/current.json"
  "files/.config/herdr/projects/sessions/current.json"
  "files/.config/herdr/current.log"
  "files/.config/herdr/current.sock"
  "files/.config/herdr/projects/current.log"
  "files/.config/herdr/projects/current.sock"
)

for rel in "${forbidden_paths[@]}"; do
  mkdir -p "$SANDBOX_REPO/$(dirname "$rel")"
  printf 'runtime\n' > "$SANDBOX_REPO/$rel"
  git -C "$SANDBOX_REPO" add -f "$rel"
done

set +e
forbidden_output=$(
  GRAPHIFY_SYNC_HOME="$FAKE_HOME" \
  GRAPHIFY_SYNC_DOTFILES_DIR="$SANDBOX_REPO" \
    bash "$SANDBOX_REPO/scripts/verify-graphify-sync.sh" 2>&1
)
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: verifier accepted forbidden tracked Herdr runtime paths" >&2
  exit 1
fi
for rel in "${forbidden_paths[@]}"; do
  if ! grep -qF "tracked: $rel" <<<"$forbidden_output"; then
    echo "FAIL: verifier did not report forbidden tracked path: $rel" >&2
    exit 1
  fi
done
echo "PASS: graphify sync verifier rejects forbidden tracked Herdr runtime paths"

# 7. Negative case in sandboxed repo: version drift
SANDBOX_REPO=$(make_sandbox_repo "repo-version-drift")
point_fake_home_at_repo "$SANDBOX_REPO"

echo "0.9.30" > "$SANDBOX_REPO/files/skills/graphify/.graphify_version"

set +e
version_output=$(
  GRAPHIFY_SYNC_HOME="$FAKE_HOME" \
  GRAPHIFY_SYNC_DOTFILES_DIR="$SANDBOX_REPO" \
    bash "$SANDBOX_REPO/scripts/verify-graphify-sync.sh" 2>&1
)
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: verifier accepted version drift" >&2
  exit 1
fi
if ! grep -qF "Graphify version marker is 0.9.30, expected 0.9.29" <<<"$version_output"; then
  echo "FAIL: verifier did not report version drift correctly" >&2
  exit 1
fi
echo "PASS: graphify sync verifier rejects version drift"

# 8. Negative case in sandboxed repo: file set drift (missing file)
SANDBOX_REPO=$(make_sandbox_repo "repo-fileset-drift")
point_fake_home_at_repo "$SANDBOX_REPO"
rm "$SANDBOX_REPO/files/skills/graphify/SKILL.md"

set +e
fileset_output=$(
  GRAPHIFY_SYNC_HOME="$FAKE_HOME" \
  GRAPHIFY_SYNC_DOTFILES_DIR="$SANDBOX_REPO" \
    bash "$SANDBOX_REPO/scripts/verify-graphify-sync.sh" 2>&1
)
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: verifier accepted missing vendored file" >&2
  exit 1
fi
if ! grep -qF "vendored Graphify file set differs from expected paths" <<<"$fileset_output"; then
  echo "FAIL: verifier did not report file set drift" >&2
  exit 1
fi
echo "PASS: graphify sync verifier rejects file set drift"

# 9. Negative case in sandboxed repo: missing Home Manager link declaration
SANDBOX_REPO=$(make_sandbox_repo "repo-nix-drift")
point_fake_home_at_repo "$SANDBOX_REPO"
sed -i '' '/\.claude\/skills\/graphify/d' "$SANDBOX_REPO/nix/shared/user.nix" 2>/dev/null || sed -i '/\.claude\/skills\/graphify/d' "$SANDBOX_REPO/nix/shared/user.nix"

set +e
nix_output=$(
  GRAPHIFY_SYNC_HOME="$FAKE_HOME" \
  GRAPHIFY_SYNC_DOTFILES_DIR="$SANDBOX_REPO" \
    bash "$SANDBOX_REPO/scripts/verify-graphify-sync.sh" 2>&1
)
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: verifier accepted missing Home Manager link declaration" >&2
  exit 1
fi
if ! grep -qF "missing Home Manager Graphify declaration: .claude/skills/graphify" <<<"$nix_output"; then
  echo "FAIL: verifier did not report missing Home Manager declaration" >&2
  exit 1
fi
echo "PASS: graphify sync verifier rejects missing Home Manager declaration"

echo "ALL GRAPHIFY SYNC VERIFIER TESTS COMPLETED SUCCESSFULLY."
