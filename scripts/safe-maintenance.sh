#!/usr/bin/env bash
# Preview-first, per-machine dotfiles maintenance planner.
# No command in this script installs, deletes, deploys, or changes services.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: safe-maintenance.sh [--profile camilo|camilo-remote] [--action setup|update|cleanup]
                           [--root HOME] [--path PATH] [--apply]

All actions are previews. --apply is intentionally unavailable until a reviewed
allowlist and retention policy are approved.
EOF
}

profile=""
action="setup"
root="${HOME:-}"
requested_path=""
apply=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; profile=$2; shift 2 ;;
    --action) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; action=$2; shift 2 ;;
    --root) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; root=$2; shift 2 ;;
    --path) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; requested_path=$2; shift 2 ;;
    --apply) apply=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'safe-maintenance: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$action" in setup|update|cleanup) ;; *) printf 'safe-maintenance: invalid action: %s\n' "$action" >&2; exit 2 ;; esac
case "$profile" in "") ;; camilo|camilo-remote) ;; *) printf 'safe-maintenance: invalid profile: %s\n' "$profile" >&2; exit 2 ;; esac

# The explicit profile is authoritative. Auto-detection is deliberately narrow:
# it uses the configured home owner, never a fuzzy hostname or directory scan.
if [ -z "$profile" ]; then
  owner=$(basename -- "${root%/}")
  case "$owner" in
    camiloslaptop) profile=camilo ;;
    mini) profile=camilo-remote ;;
    *) printf 'safe-maintenance: cannot safely detect a machine profile for %s\n' "$root" >&2; exit 3 ;;
  esac
fi
expected_owner=mini
[ "$profile" = camilo ] && expected_owner=camiloslaptop

[ -n "$root" ] || { printf 'safe-maintenance: HOME is unset\n' >&2; exit 3; }
[ -d "$root" ] || { printf 'safe-maintenance: target home does not exist: %s\n' "$root" >&2; exit 3; }
resolved_root=$(cd -- "$root" 2>/dev/null && pwd -P) || { printf 'safe-maintenance: cannot resolve target home\n' >&2; exit 3; }
case "$resolved_root" in */Users/"$expected_owner") ;; \
  *) printf 'safe-maintenance: wrong-machine target: profile %s requires /Users/%s\n' "$profile" "$expected_owner" >&2; exit 4;;
esac
if [ "${SAFE_MAINTENANCE_TEST_MODE:-0}" != 1 ] && [ "$(id -un)" != "$expected_owner" ]; then
  printf 'safe-maintenance: refusing profile %s for OS user %s\n' "$profile" "$(id -un)" >&2; exit 4
fi
if [ "$apply" -eq 1 ]; then
  printf 'safe-maintenance: apply unavailable: reviewed cleanup allowlist and retention policy required\n' >&2
  exit 5
fi

printf 'profile: %s\n' "$profile"
printf 'target: %s\n' "$resolved_root"
printf 'action: %s (preview only; no files changed)\n' "$action"
case "$profile" in
  camilo) printf 'declared setup source: darwinConfigurations.camilo\n' ;;
  camilo-remote)
    printf 'declared setup source: darwinConfigurations.camilo-remote\n'
    printf 'Mini project scope: Pythia, Trader, Pilaster, and verified dependencies only\n'
    ;;
esac

if [ -n "$requested_path" ]; then
  [ -e "$requested_path" ] || { printf 'safe-maintenance: ambiguous/nonexistent path refused: %s\n' "$requested_path" >&2; exit 6; }
  [ ! -L "$requested_path" ] || { printf 'safe-maintenance: symlink path refused: %s\n' "$requested_path" >&2; exit 6; }
  resolved_path=$(cd -- "$(dirname -- "$requested_path")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename -- "$requested_path")") || exit 6
  case "$resolved_path" in "$resolved_root"/*) ;; *) printf 'safe-maintenance: symlink escape or outside target refused: %s\n' "$requested_path" >&2; exit 6;; esac
  case "$resolved_path" in
    */.git/*|*/.git|*/.ssh/*|*/.ssh|*/.gnupg/*|*/.gnupg|*/Library/Keychains/*|*/Library/Keychains|*/Library/Mail/*|*/Library/Mail|*/.local/share/*|*/.local/share)
      printf 'safe-maintenance: protected path refused: %s\n' "$requested_path" >&2; exit 7;;
  esac
  printf 'candidate path: %s\n' "$resolved_path"
fi

if [ "$action" = cleanup ]; then
  cat <<'EOF'
proposed cleanup categories (approval required, exact list):
- declared generated build/cache artifacts
- stale package-manager download caches
- stale logs explicitly owned by this dotfiles profile
- temporary files explicitly created by this maintenance tool
No category above has an approved allowlist. Cleanup apply is unavailable.
Protected: source, branches, active/dirty/unpublished work, databases, history,
research/private data, credentials/keys, backups, and required services.
EOF
else
  printf 'effects: inspect profile and report planned setup/update only; install/apply is not performed\n'
fi
