#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest="$script_dir/launchers.tsv"
destination="${1:-$HOME/Applications/Cursor Launchers}"
plistbuddy_bin="${PLISTBUDDY_BIN:-/usr/libexec/PlistBuddy}"
osadecompile_bin="${OSADECOMPILE_BIN:-osadecompile}"
codesign_bin="${CODESIGN_BIN:-codesign}"

expected=0
while IFS=$'\t' read -r name target || [[ -n "$name" ]]; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  expected=$((expected + 1))
  app="$destination/Cursor $name.app"

  [[ -d "$app" ]] || { echo "Missing: $app" >&2; exit 1; }
  actual_name="$("$plistbuddy_bin" -c 'Print :CFBundleName' "$app/Contents/Info.plist")"
  [[ "$actual_name" == "Cursor $name" ]] || { echo "Wrong bundle name: $app" >&2; exit 1; }
  "$osadecompile_bin" "$app/Contents/Resources/Scripts/main.scpt" | grep -Fq "quoted form of \"$target\"" || {
    echo "Wrong target in: $app" >&2
    exit 1
  }
  "$codesign_bin" --verify --deep --strict "$app"
done < "$manifest"

actual="$(find "$destination" -maxdepth 1 -type d -name 'Cursor *.app' | wc -l | tr -d ' ')"
[[ "$actual" -eq "$expected" ]] || {
  echo "Expected $expected Cursor launcher apps, found $actual in $destination" >&2
  exit 1
}

echo "Verified $expected Cursor launcher apps in $destination"
