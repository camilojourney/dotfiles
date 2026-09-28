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
printf '\nStorage by location (overlapping totals; do not add them)\n'
for path in \
  /nix/store /opt/homebrew/Cellar /opt/homebrew/Caskroom \
  "$HOME/Library/Caches" "$HOME/Library/Caches/Homebrew" \
  "$HOME/.cache" "${UV_CACHE_DIR:-$HOME/.cache/uv}" \
  "$HOME/.npm" "$HOME/.local" "$HOME/.nvm" \
  "$HOME/Library/pnpm" "$HOME/.cache/huggingface" "$HOME/.ollama" \
  "$HOME/.codex" "$HOME/.claude" "$HOME/.pi" \
  "$HOME/Library/Logs" "$HOME/Library/Developer" \
  "$HOME/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data" \
  "$HOME/Library/Containers/com.docker.docker" \
  "$HOME/.docker" "$HOME/.colima" \
  "$HOME/Downloads" "$HOME/.Trash" "$HOME/github"; do
  if [ -e "$path" ]; then
    if ! du -sh "$path"; then
      printf 'Could not fully measure: %s\n' "$path" >&2
    fi
  fi
done
printf '\nInspect a large directory with: du -h -d 1 "DIRECTORY"\n'
printf 'Some locations may be protected by macOS; this report never changes permissions.\n'
printf 'Cleanup guidance: docs/STORAGE.md. Nothing was deleted.\n'
