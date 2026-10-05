#!/usr/bin/env bash
# Regression tests for linking ~/.claude/skills to the shared ~/.agents/skills.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
SCRIPT="$ROOT/scripts/agent-tools/link-claude-skills.sh"
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/link-claude-skills-test.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run() { HOME="$1" bash "$SCRIPT" 2>&1; }

# Fresh home: the link is created.
H="$SANDBOX/fresh"; mkdir -p "$H"
run "$H" >/dev/null
[ "$(readlink "$H/.claude/skills")" = "$H/.agents/skills" ] || fail "fresh home was not linked"
run "$H" >/dev/null
[ "$(readlink "$H/.claude/skills")" = "$H/.agents/skills" ] || fail "second run changed the link"

# Real directory: its skills move into the shared directory, then it is linked.
H="$SANDBOX/migrate"; mkdir -p "$H/.claude/skills/graphify" "$H/.agents/skills/no-mistakes"
printf 'claude skill\n' > "$H/.claude/skills/graphify/SKILL.md"
ln -s /elsewhere/phrona "$H/.claude/skills/phrona"
run "$H" >/dev/null
[ -L "$H/.claude/skills" ] || fail "migrated directory was not replaced by a link"
[ "$(<"$H/.agents/skills/graphify/SKILL.md")" = "claude skill" ] || fail "skill was not moved to the shared directory"
[ "$(readlink "$H/.agents/skills/phrona")" = "/elsewhere/phrona" ] || fail "skill symlink was not moved intact"
[ -d "$H/.agents/skills/no-mistakes" ] || fail "existing shared skill was lost"

# Same skill in both places: nothing moves and the directory stays for a human.
H="$SANDBOX/conflict"; mkdir -p "$H/.claude/skills/graphify" "$H/.agents/skills/graphify"
printf 'claude copy\n' > "$H/.claude/skills/graphify/SKILL.md"
printf 'shared copy\n' > "$H/.agents/skills/graphify/SKILL.md"
out=$(run "$H")
[ -d "$H/.claude/skills" ] && [ ! -L "$H/.claude/skills" ] || fail "conflicting directory was replaced"
[ "$(<"$H/.claude/skills/graphify/SKILL.md")" = "claude copy" ] || fail "conflicting skill changed"
[ "$(<"$H/.agents/skills/graphify/SKILL.md")" = "shared copy" ] || fail "shared skill was overwritten"
case "$out" in *"merge by hand"*) ;; *) fail "conflict was not reported" ;; esac

# A link pointing elsewhere is repointed.
H="$SANDBOX/repoint"; mkdir -p "$H/.claude" "$H/old"
ln -s "$H/old" "$H/.claude/skills"
run "$H" >/dev/null
[ "$(readlink "$H/.claude/skills")" = "$H/.agents/skills" ] || fail "stale link was not repointed"

echo "link_claude_skills_test: ok"
