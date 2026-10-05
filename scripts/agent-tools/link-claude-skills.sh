#!/usr/bin/env bash
# Make ~/.claude/skills a symlink to ~/.agents/skills, the one shared skills
# directory. Pi and other Agent Skills harnesses read ~/.agents/skills
# natively; Claude Code only reads ~/.claude/skills, so it gets the link.
# A real ~/.claude/skills directory is migrated: entries missing from
# ~/.agents/skills move there; if any entry exists in both, nothing is
# replaced and the directory is left for a human to merge.
set -euo pipefail

shared="$HOME/.agents/skills"
claude="$HOME/.claude/skills"

mkdir -p "$shared" "$HOME/.claude"

if [ -L "$claude" ]; then
  [ "$(readlink "$claude")" = "$shared" ] && exit 0
  rm "$claude"
elif [ -d "$claude" ]; then
  for entry in "$claude"/* "$claude"/.[!.]*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name=$(basename "$entry")
    if [ -e "$shared/$name" ] || [ -L "$shared/$name" ]; then
      echo "link-claude-skills: $name exists in both $claude and $shared; merge by hand, then rebuild" >&2
      exit 0
    fi
  done
  for entry in "$claude"/* "$claude"/.[!.]*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    mv "$entry" "$shared/"
  done
  rmdir "$claude"
elif [ -e "$claude" ]; then
  echo "link-claude-skills: $claude is not a directory; left alone" >&2
  exit 0
fi

ln -s "$shared" "$claude"
echo "link-claude-skills: $claude -> $shared"
