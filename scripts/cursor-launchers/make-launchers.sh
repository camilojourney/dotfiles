#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest="$script_dir/launchers.tsv"
destination="${1:-$HOME/Applications/Cursor Launchers}"
osacompile_bin="${OSACOMPILE_BIN:-osacompile}"

command -v "$osacompile_bin" >/dev/null || {
  echo "osacompile is required (run this on macOS)." >&2
  exit 1
}

mkdir -p "$destination"

while IFS=$'\t' read -r name target || [[ -n "$name" ]]; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  [[ "$name" =~ ^[A-Za-z][A-Za-z[:space:]-]*$ && "$target" =~ ^[a-z][a-z0-9-]*$ ]] || {
    echo "Invalid launcher manifest entry: $name" >&2
    exit 1
  }
  "$script_dir/cursor-go" --validate-target "$target"

  app="$destination/Cursor $name.app"
  source=$(printf '%s\n%s\n' \
    'set helperPath to (POSIX path of (path to home folder)) & "bin/cursor-go-bg"' \
    "do shell script quoted form of helperPath & \" \" & quoted form of \"$target\"")

  rm -rf "$app"
  "$osacompile_bin" -o "$app" -e "$source"
  echo "Created: $app"
done < "$manifest"
