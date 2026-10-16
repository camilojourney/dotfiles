#!/usr/bin/env python3
"""Claude Code PreToolUse hook: no code edit before the session loads /code.

Wired in home/.claude/settings.json for Edit, Write and MultiEdit. Claude Code
decides from a skill's description whether to load it, and on 2026-10-16 only
1 of 9 Claude Code workers that edited code had loaded /code. This makes the
load deterministic: the first edit to a code file in a session without /code is
refused once, with a message telling the model to load it; the model loads it
and retries.

Allows everything else: non-code files (notes, briefs, specs, JSON, YAML),
temporary and Firstmate state paths, sessions where /code is not installed, and
any input it cannot read. Exit 2 blocks the tool call and shows stderr to the model.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

CODE = {".py", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".go", ".rs", ".java", ".kt", ".swift",
        ".rb", ".php", ".c", ".h", ".cc", ".cpp", ".hpp", ".cs", ".sh", ".bash", ".zsh", ".sql",
        ".nix", ".lua", ".scala", ".vue", ".svelte"}
# Scratch and agent bookkeeping, never product code.
EXEMPT = re.compile(r"^(/private)?/tmp/|^/var/folders/|/scratchpad/|/\.firstmate-homes/[^/]+/(state|data)/"
                    r"|/github/firstmate/state/|/\.claude/|/\.pi/")
LOADED = re.compile(r'"name":\s*"Skill".{0,200}?"skill":\s*"/?code"'
                    r'|<command-name>/code</command-name>'
                    r"|Base directory for this skill: \S*/code(?![\w-])")


def main() -> int:
    try:
        event = json.load(sys.stdin)
        path = str((event.get("tool_input") or {}).get("file_path") or "")
        transcript = Path(event["transcript_path"])
    except (ValueError, KeyError, TypeError):
        return 0
    if Path(path).suffix.lower() not in CODE or EXEMPT.search(path):
        return 0
    if not (Path.home() / ".claude/skills/code/SKILL.md").is_file():
        return 0  # nothing to load on this machine
    try:
        if any(LOADED.search(line) for line in transcript.open(errors="replace")):
            return 0
    except OSError:
        return 0
    print("This session has not loaded the /code skill. Load it with the Skill tool (skill: code), "
          "follow it, then retry this edit.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
