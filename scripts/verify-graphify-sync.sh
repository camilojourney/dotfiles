#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
cd "$repo_root"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

pass() {
  echo "PASS: $1"
}

require_file() {
  local path="$1"
  if [ -f "$path" ]; then
    return 0
  fi
  fail "missing file: $path"
  return 1
}

graphify_root="files/skills/graphify"
expected_files=$(mktemp "${TMPDIR:-/tmp}/graphify-expected.XXXXXX")
actual_files=$(mktemp "${TMPDIR:-/tmp}/graphify-actual.XXXXXX")
trap 'rm -f "$expected_files" "$actual_files"' EXIT

cat > "$expected_files" <<'EOF'
files/skills/graphify/.graphify_version
files/skills/graphify/SKILL.md
files/skills/graphify/references/add-watch.md
files/skills/graphify/references/exports.md
files/skills/graphify/references/extraction-spec.md
files/skills/graphify/references/github-and-merge.md
files/skills/graphify/references/hooks.md
files/skills/graphify/references/query.md
files/skills/graphify/references/transcribe.md
files/skills/graphify/references/update.md
EOF

if [ -d "$graphify_root" ]; then
  find "$graphify_root" -type f -print | LC_ALL=C sort > "$actual_files"
  if cmp -s "$expected_files" "$actual_files"; then
    pass "vendored Graphify file set"
  else
    fail "vendored Graphify file set differs from expected paths"
    comm -23 "$expected_files" "$actual_files" | sed 's/^/  missing: /' >&2
    comm -13 "$expected_files" "$actual_files" | sed 's/^/  unexpected: /' >&2
  fi
else
  fail "missing vendored Graphify directory: $graphify_root"
fi

if require_file "$graphify_root/.graphify_version"; then
  version=$(tr -d '\n' < "$graphify_root/.graphify_version")
  if [ "$version" = "0.9.29" ]; then
    pass "Graphify version marker"
  else
    fail "Graphify version marker is $version, expected 0.9.29"
  fi
fi

check_hash() {
  local path="$1" expected="$2" actual
  require_file "$path" || return 0
  actual=$(shasum -a 256 "$path" | awk '{print $1}')
  if [ "$actual" = "$expected" ]; then
    pass "hash $path"
  else
    fail "hash mismatch: $path"
  fi
}

check_hash "files/skills/graphify/.graphify_version" "ada87d4c0acb429c346b48b561a7ac328c236cd25f3fede18a6719215c4c601e"
check_hash "files/skills/graphify/SKILL.md" "e6b883eed16008ce23a47893aa1e27b12bd97d19614fe671aad31e73560d99f8"
check_hash "files/skills/graphify/references/add-watch.md" "eda82f4c582580e40028778024a4002a9a1b906a2c74bcb664a4885ca3d5783c"
check_hash "files/skills/graphify/references/exports.md" "9a188a5d5ff12c1630a6d1e3c434b9f18c9785c044da99f28927139233d2b37f"
check_hash "files/skills/graphify/references/extraction-spec.md" "32d7decad42d58129c6694ea4e4ce1f72a531bc5161827d2095787e9448735e9"
check_hash "files/skills/graphify/references/github-and-merge.md" "df593874f7c61b770f21c62719072cb413aa908f9c0659a4371c0765eaa5e8be"
check_hash "files/skills/graphify/references/hooks.md" "24a2561cd2b3172499dafcffe5344ac0304e9654a92faff82dbb55a582c5ce12"
check_hash "files/skills/graphify/references/query.md" "5d8733dedc5d5fbb7887f852d0a9b55417a121c8381ce841957a70c1f94fb293"
check_hash "files/skills/graphify/references/transcribe.md" "676a1e39aa6d43cdfcc416ec56616e36f7bad74066a82bd33a9485515b9a865c"
check_hash "files/skills/graphify/references/update.md" "8909c388a39417300751448a83c3473334f33bedbacb566770e17089993e6016"

python3 - <<'PY' || failures=$((failures + 1))
import re
import sys
from pathlib import Path

nix = Path("nix/shared/user.nix").read_text(encoding="utf-8")
expected = [
    ".claude/skills/graphify",
    ".codex/skills/graphify",
    ".cursor/skills/graphify",
    ".agents/skills/graphify",
    ".gemini/skills/graphify",
    ".gemini/antigravity/skills/graphify",
    ".gemini/antigravity-cli/skills/graphify",
    ".gemini/config/skills/graphify",
]
source = 'source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/skills/graphify";'
ok = True
for path in expected:
    match = re.search(rf'"{re.escape(path)}"\s*=\s*\{{(?P<body>.*?)\n\s*\}};', nix, re.S)
    if not match:
        print(f"FAIL: missing Home Manager Graphify declaration: {path}", file=sys.stderr)
        ok = False
        continue
    body = match.group("body")
    if source not in body:
        print(f"FAIL: wrong Home Manager Graphify target: {path}", file=sys.stderr)
        ok = False
    if "force = true;" not in body:
        print(f"FAIL: missing force takeover on Home Manager Graphify link: {path}", file=sys.stderr)
        ok = False
if ok:
    print("PASS: Home Manager Graphify link declarations")
sys.exit(0 if ok else 1)
PY

home_dir="${GRAPHIFY_SYNC_HOME:-$HOME}"
dotfiles_dir="${GRAPHIFY_SYNC_DOTFILES_DIR:-$home_dir/github/dotfiles}"
installed_target="$dotfiles_dir/files/skills/graphify"
installed_paths=(
  ".claude/skills/graphify"
  ".codex/skills/graphify"
  ".cursor/skills/graphify"
  ".agents/skills/graphify"
  ".gemini/skills/graphify"
  ".gemini/antigravity/skills/graphify"
  ".gemini/antigravity-cli/skills/graphify"
  ".gemini/config/skills/graphify"
)

installed_checked=0
for rel in "${installed_paths[@]}"; do
  path="$home_dir/$rel"
  if [ -e "$path" ] || [ -L "$path" ]; then
    installed_checked=1
    break
  fi
done
if [ "$installed_checked" -eq 0 ]; then
  pass "installed Graphify symlinks skipped (none present under selected home)"
else
  for rel in "${installed_paths[@]}"; do
    path="$home_dir/$rel"
    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
      fail "installed Graphify path is missing: $rel"
      continue
    fi
    if [ ! -L "$path" ]; then
      fail "installed Graphify path is not a symlink: $rel"
      continue
    fi
    target=$(readlink "$path")
    if [ "$target" != "$installed_target" ]; then
      fail "installed Graphify symlink target mismatch: $rel (target is $target)"
    fi
  done
  if [ "$failures" -eq 0 ]; then
    pass "installed Graphify symlink targets"
  fi
fi

require_gitignore_pattern() {
  local pattern="$1"
  if grep -qxF "$pattern" .gitignore; then
    pass "gitignore pattern $pattern"
  else
    fail "missing gitignore pattern: $pattern"
  fi
}

require_gitignore_pattern ".pipeline-state/"
require_gitignore_pattern ".worktrees/"
require_gitignore_pattern "graphify-out/"
require_gitignore_pattern ".DS_Store"
require_gitignore_pattern "**/.DS_Store"
require_gitignore_pattern ".cache/"
require_gitignore_pattern "**/.cache/"
require_gitignore_pattern "files/.config/herdr/*.log"
require_gitignore_pattern "files/.config/herdr/*.sock"
require_gitignore_pattern "files/.config/herdr/**/*.log"
require_gitignore_pattern "files/.config/herdr/**/*.sock"
require_gitignore_pattern "files/.config/herdr/session.json"
require_gitignore_pattern "files/.config/herdr/release-notes.json"
require_gitignore_pattern "files/.config/herdr/sessions/"
require_gitignore_pattern "files/.config/herdr/**/sessions/"
require_gitignore_pattern "files/.config/cursor-launchers/config.sh"
require_gitignore_pattern "!files/.config/cursor-launchers/config.sh.example"

forbidden_tracked=$(
  git ls-files -z | python3 -c '
import sys
paths = sys.stdin.buffer.read().split(b"\0")
bad = []
for raw in paths:
    if not raw:
        continue
    path = raw.decode("utf-8", "surrogateescape")
    herdr_prefix = "files/.config/herdr/"
    is_herdr_runtime_path = False
    if path.startswith(herdr_prefix):
        herdr_rel = path[len(herdr_prefix):]
        is_herdr_runtime_path = (
            herdr_rel in {"session.json", "release-notes.json"}
            or herdr_rel.startswith("sessions/")
            or "/sessions/" in herdr_rel
            or herdr_rel.endswith(".log")
            or herdr_rel.endswith(".sock")
        )
    if (
        path == ".DS_Store"
        or path.endswith("/.DS_Store")
        or path.startswith(".pipeline-state/")
        or path.startswith(".worktrees/")
        or path.startswith(".no-mistakes/")
        or path.startswith("graphify-out/")
        or is_herdr_runtime_path
        or path.startswith(".cache/")
        or "/.cache/" in path
        or path == "files/.config/cursor-launchers/config.sh"
        or path.endswith(".pem")
        or path.endswith(".key")
        or path == ".env"
        or path.startswith(".env.")
    ):
        bad.append(path)
if bad:
    print("\n".join(bad))
'
)
if [ -n "$forbidden_tracked" ]; then
  fail "forbidden volatile or secret-like tracked paths detected"
  printf '%s\n' "$forbidden_tracked" | sed 's/^/  tracked: /' >&2
else
  pass "forbidden volatile tracked files"
fi

if [ "$failures" -ne 0 ]; then
  echo "Graphify sync verification failed with $failures failure(s)." >&2
  exit 1
fi

echo "Graphify sync verification passed."
