#!/usr/bin/env bash
# Read-only: no installs, cleanup, sudo, or package-manager hooks.
set -euo pipefail
if [ "$#" -ne 0 ]; then
  echo 'Usage: bash scripts/storage-report.sh (read-only)' >&2
  exit 2
fi
: "${HOME:?HOME must be set}"
printf 'Available disk space\n'
df -h "$HOME"
printf '\nImmediate home directories (one level; totals overlap)\n'
# [impl->req~storage-audit.inventory~2]
if ! du -h -d 1 "$HOME"; then
  printf 'Could not fully measure immediate home directories: %s\n' "$HOME" >&2
fi

for path in "$HOME/Library" "$HOME/Library/Application Support"; do
  if [ -d "$path" ]; then
    printf '\nImmediate directories under: %s\n' "$path"
    if ! du -h -d 1 "$path"; then
      printf 'Could not fully measure: %s\n' "$path" >&2
    fi
  fi
done

printf '\nSelected system and external roots (overlapping totals; do not add them)\n'
for path in \
  /nix/store /opt/homebrew/Cellar /opt/homebrew/Caskroom \
  "${UV_CACHE_DIR:-$HOME/.cache/uv}" "$HOME/.cache/huggingface" \
  "$HOME/Library/Caches/Homebrew" "$HOME/Library/pnpm" \
  "$HOME/Library/Application Support/Google/Chrome" \
  "$HOME/Library/Application Support/Google/Chrome Canary" \
  "$HOME/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data" \
  "$HOME/Library/Containers/com.docker.docker"; do
  if [ -e "$path" ]; then
    if ! du -sh "$path"; then
      printf 'Could not fully measure: %s\n' "$path" >&2
    fi
  fi
done
printf '\nInspect a large directory with: du -h -d 1 "DIRECTORY"\n'
printf 'Some locations may be protected by macOS; this report never changes permissions.\n'
printf 'Cleanup guidance: docs/STORAGE.md. Nothing was deleted.\n'
