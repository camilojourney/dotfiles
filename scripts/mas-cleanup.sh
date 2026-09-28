#!/usr/bin/env bash

set -euo pipefail

mas_bin=$1
user_name=$2
shift 2

if [ ! -x "$mas_bin" ]; then
  exit 0
fi

# Runs from nix-darwin activation as root, but `mas` needs the console user's
# App Store session to list/uninstall anything.
run_as_primary_user() {
  if [ "$(/usr/bin/id -u)" -eq 0 ]; then
    /usr/bin/sudo -u "$user_name" -H "$@"
  else
    "$@"
  fi
}

# Space-padded so `case` can match a ${app_id} as a whole token, not a substring.
declared_mas_ids=" $* "
if installed_mas_apps="$(run_as_primary_user "$mas_bin" list)"; then
  installed_mas_ids="$(printf '%s\n' "$installed_mas_apps" | /usr/bin/sed -nE 's/.*\(([0-9]+)\)$/\1/p')"
  while IFS= read -r app_id; do
    [ -n "$app_id" ] || continue
    case "$declared_mas_ids" in
      *" $app_id "*) ;;
      *)
        echo "Removing undeclared Mac App Store app: $app_id"
        run_as_primary_user "$mas_bin" uninstall "$app_id" || true
        ;;
    esac
  done <<EOF
$installed_mas_ids
EOF
else
  echo "mas-cleanup: unable to list Mac App Store apps; skipping"
fi
