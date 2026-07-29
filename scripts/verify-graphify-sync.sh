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
check_hash "files/skills/graphify/SKILL.md" "9024289348cceb6140af33e9875742dc55f55e5d574e44e5a21bb36239b1bcf4"
check_hash "files/skills/graphify/references/add-watch.md" "b3f67570240582689c2834b4831917550c2d1aaf042148868c39dcbf387ce3fd"
check_hash "files/skills/graphify/references/exports.md" "ee47fae477f106d8aed38798c58493b5a7f060a0d9d2581ce6132302827bc14b"
check_hash "files/skills/graphify/references/extraction-spec.md" "32d7decad42d58129c6694ea4e4ce1f72a531bc5161827d2095787e9448735e9"
check_hash "files/skills/graphify/references/github-and-merge.md" "e5ebd90c7686f50363ff7a535556bc2f596d4c47ec1e6c8b95e11e36a0dfea2b"
check_hash "files/skills/graphify/references/hooks.md" "b9a4e9f66813c6fc720589f1071d1a03c95756ab7101447e14e57291fe7844e5"
check_hash "files/skills/graphify/references/query.md" "e563ddcb1e155aa230f107e5ef9380bc1249c5cd8241128de7ed8a7bd9c20cf5"
check_hash "files/skills/graphify/references/transcribe.md" "676a1e39aa6d43cdfcc416ec56616e36f7bad74066a82bd33a9485515b9a865c"
check_hash "files/skills/graphify/references/update.md" "661f559b3ff4f3db7ba47bc2ba1c7e19f1c1d66a36f647e49221eecb174f2228"

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
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    continue
  fi
  installed_checked=$((installed_checked + 1))
  if [ ! -L "$path" ]; then
    fail "installed Graphify path is not a symlink: $rel"
    continue
  fi
  target=$(readlink "$path")
  if [ "$target" != "$installed_target" ]; then
    fail "installed Graphify symlink target mismatch: $rel (target is $target)"
  fi
done
if [ "$installed_checked" -eq 0 ]; then
  pass "installed Graphify symlinks skipped (none present under selected home)"
elif [ "$failures" -eq 0 ]; then
  pass "installed Graphify symlink targets"
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
