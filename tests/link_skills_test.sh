#!/usr/bin/env bash
# Regression tests for linking only the fleet skills declared in links.json.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
SCRIPT="$ROOT/scripts/agent-tools/link-skills.sh"
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/link-skills-test.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# home <dir>: a home with a fleet checkout holding two skills.
home() {
  H="$SANDBOX/$1"; F="$H/fleet"
  mkdir -p "$F/system/skills/platform/code" "$F/system/skills/meta/doctor"
  touch "$F/system/skills/platform/code/SKILL.md" "$F/system/skills/meta/doctor/SKILL.md"
}
declare_links() { printf '{"links": %s}\n' "$1" > "$F/system/skills/links.json"; }
run() { HOME="$H" FLEET_ROOT="$F" bash "$SCRIPT" 2>&1; }

# The old shared link becomes two separate directories; other entries stay.
home split
mkdir -p "$H/.agents/skills/no-mistakes" "$H/.claude"
ln -s /elsewhere/phrona "$H/.agents/skills/phrona"
ln -s "$H/.agents/skills" "$H/.claude/skills"
declare_links '[]'
run >/dev/null
[ -d "$H/.claude/skills" ] && [ ! -L "$H/.claude/skills" ] || fail "claude skills is still a link"
[ -d "$H/.agents/skills/no-mistakes" ] || fail "tool-installed skill was removed"
[ "$(readlink "$H/.agents/skills/phrona")" = /elsewhere/phrona ] || fail "non-fleet link was changed"
[ ! -e "$H/.claude/skills/no-mistakes" ] || fail "agents skills leaked into claude skills"

# Declared skills are linked only into their declared directories.
home declared
declare_links '[{"skill": "system/skills/platform/code", "into": ["claude", "agents"]},
                {"skill": "system/skills/meta/doctor", "into": ["claude"]}]'
run >/dev/null
[ "$(readlink "$H/.claude/skills/code")" = "$F/system/skills/platform/code" ] || fail "code not linked for claude"
[ "$(readlink "$H/.agents/skills/code")" = "$F/system/skills/platform/code" ] || fail "code not linked for agents"
[ "$(readlink "$H/.claude/skills/doctor")" = "$F/system/skills/meta/doctor" ] || fail "doctor not linked for claude"
[ ! -e "$H/.agents/skills/doctor" ] || fail "doctor linked where it was not declared"
[ -z "$(run)" ] || fail "second run was not a no-op"

# Undeclared fleet links are removed.
declare_links '[{"skill": "system/skills/platform/code", "into": ["agents"]}]'
run >/dev/null
[ ! -e "$H/.claude/skills/code" ] && [ ! -L "$H/.claude/skills/code" ] || fail "undeclared code link kept"
[ ! -L "$H/.claude/skills/doctor" ] || fail "undeclared doctor link kept"
[ -L "$H/.agents/skills/code" ] || fail "declared link removed"

# A missing skill, a real directory in the way, and a missing manifest are reported, not fatal.
declare_links '[{"skill": "system/skills/missing", "into": ["agents"]},
                {"skill": "system/skills/meta/doctor", "into": ["agents"]}]'
mkdir -p "$H/.agents/skills/doctor"
out=$(run)
case "$out" in *"has no SKILL.md"*) ;; *) fail "missing skill not reported" ;; esac
case "$out" in *"left alone"*) ;; *) fail "blocking directory not reported" ;; esac
[ -d "$H/.agents/skills/doctor" ] && [ ! -L "$H/.agents/skills/doctor" ] || fail "blocking directory replaced"
rm "$F/system/skills/links.json"
out=$(run)
case "$out" in *"not found"*) ;; *) fail "missing manifest not reported" ;; esac
[ ! -L "$H/.agents/skills/code" ] || fail "fleet link kept without a manifest"

echo "link_skills_test: ok"
