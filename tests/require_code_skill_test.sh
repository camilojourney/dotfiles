#!/usr/bin/env bash
# Regression test for the Claude Code hook that requires /code before code edits.
# Run: bash tests/require_code_skill_test.sh

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
HOOK="$REPO_ROOT/scripts/agent-tools/require-code-skill.py"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# A fake home with /code installed, so the test never depends on this machine.
mkdir -p "$WORK/home/.claude/skills/code"
echo "# code" > "$WORK/home/.claude/skills/code/SKILL.md"
EMPTY="$WORK/empty.jsonl"; : > "$EMPTY"
TOOL="$WORK/tool.jsonl"
echo '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"code"}}]}}' > "$TOOL"
COMMAND="$WORK/command.jsonl"
echo '{"message":{"role":"user","content":"<command-name>/code</command-name>"}}' > "$COMMAND"
OTHER="$WORK/other.jsonl"
echo '{"message":{"role":"user","content":"Base directory for this skill: /x/.claude/skills/code-review\n"}}' > "$OTHER"
failures=0

check() {  # check <expected exit> <transcript> <file path> <name> [home]
  local expected=$1 transcript=$2 path=$3 name=$4 home=${5:-$WORK/home} actual=0
  printf '{"transcript_path":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$transcript" "$path" \
    | HOME="$home" python3 "$HOOK" 2>/dev/null || actual=$?
  if [ "$actual" -eq "$expected" ]; then echo "ok   $name"; else echo "FAIL $name: exit $actual, want $expected"; failures=$((failures + 1)); fi
}

check 2 "$EMPTY" /repo/src/app.py "code edit before /code is refused"
check 0 "$TOOL" /repo/src/app.py "code edit after a Skill tool load passes"
check 0 "$COMMAND" /repo/src/app.ts "code edit after the user typed /code passes"
check 2 "$OTHER" /repo/src/app.go "a different skill named code-something does not count"
check 0 "$EMPTY" /repo/README.md "Markdown is never blocked"
check 0 "$EMPTY" /repo/config.json "JSON config is never blocked"
check 0 "$EMPTY" "$HOME/.firstmate-homes/phrona-lab/state/brief.sh" "second-mate state files are never blocked"
check 0 "$EMPTY" /private/tmp/scratch.py "temporary files are never blocked"
check 0 "$EMPTY" /repo/src/app.py "machines without /code installed are never blocked" "$WORK/nohome"
if printf 'not json' | python3 "$HOOK"; then echo "ok   unreadable input passes"; else echo "FAIL unreadable input"; failures=$((failures + 1)); fi

[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
