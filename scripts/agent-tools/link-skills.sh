#!/usr/bin/env bash
# Link exactly the fleet skills declared in fleet-system's
# system/skills/links.json into each harness's global skills directory:
#   claude -> ~/.claude/skills (Claude Code)
#   agents -> ~/.agents/skills (Pi and other Agent Skills harnesses)
# Every global skill costs tokens on every turn, so the two directories are
# separate: neither harness loads the other's skills. A link into the fleet
# checkout that links.json does not declare is removed. Entries other tools
# install (no-mistakes, phrona, Claude's synced/) are left alone.
set -euo pipefail

fleet="${FLEET_ROOT:-$HOME/github/fleet-system}"
manifest="$fleet/system/skills/links.json"
jq="${JQ:-jq}"

claude="$HOME/.claude/skills"
agents="$HOME/.agents/skills"

# ~/.claude/skills used to be a link to ~/.agents/skills; make it its own directory.
if [ -L "$claude" ]; then
  rm "$claude"
  echo "link-skills: $claude is now its own directory"
fi
mkdir -p "$claude" "$agents"

declared=""
if [ -f "$manifest" ]; then
  # shellcheck disable=SC2016 # jq variables, not shell ones
  declared=$("$jq" -r '.links[] | .skill as $s | .into[] | "\(.)\t\($s)"' "$manifest")
else
  echo "link-skills: $manifest not found; no fleet skills linked" >&2
fi

dir_for() {
  case "$1" in
    claude) echo "$claude" ;;
    agents) echo "$agents" ;;
    *) echo "link-skills: unknown target '$1' in $manifest" >&2; return 1 ;;
  esac
}

# Remove fleet links that are no longer declared.
for dir in "$claude" "$agents"; do
  for entry in "$dir"/*; do
    [ -L "$entry" ] || continue
    target=$(readlink "$entry")
    case "$target" in "$fleet"/*) ;; *) continue ;; esac
    keep=0
    while IFS=$'\t' read -r into skill; do
      [ -n "$into" ] || continue
      if [ "$(dir_for "$into")" = "$dir" ] && [ "$target" = "$fleet/$skill" ]; then keep=1; fi
    done <<< "$declared"
    if [ "$keep" = 0 ]; then
      rm "$entry"
      echo "link-skills: removed $entry"
    fi
  done
done

# Create the declared links.
while IFS=$'\t' read -r into skill; do
  [ -n "$into" ] || continue
  dir=$(dir_for "$into")
  src="$fleet/$skill"
  if [ ! -f "$src/SKILL.md" ]; then
    echo "link-skills: $src has no SKILL.md; not linked" >&2
    continue
  fi
  link="$dir/$(basename "$skill")"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$src" ]; then continue; fi
  if [ -e "$link" ] || [ -L "$link" ]; then
    echo "link-skills: $link exists and is not this skill's link; left alone" >&2
    continue
  fi
  ln -s "$src" "$link"
  echo "link-skills: $link -> $src"
done <<< "$declared"
