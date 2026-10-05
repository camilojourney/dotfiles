#!/usr/bin/env bash
# TEMPORARY until kunchenguid/quota-axi#308 ships in an npm release.
#
# Every rebuild reinstalls quota-axi@latest (nix/agent-tools.manifest.lock.json),
# and the released build cannot score Antigravity quota (no windowSeconds on
# agy windows), so Firstmate's Jev resolver stops ranking Antigravity models.
# When the installed build lacks the fix, rebuild it from ~/github/quota-axi
# and install that instead. Once a release contains the fix this does nothing;
# delete this script and its activation entry in nix/home.nix then.
set -uo pipefail

src="$HOME/github/quota-axi"
installed="$(npm root -g)/quota-axi/dist/src/providers/agy.js"

[ -f "$installed" ] || exit 0
grep -q windowSeconds "$installed" && exit 0
if [ ! -d "$src" ]; then
  echo "quota-axi-agy-fix: $src missing; Antigravity quota stays unscored until quota-axi#308 is released" >&2
  exit 0
fi

cd "$src" || exit 0
if pnpm install --frozen-lockfile --silent && pnpm run build >/dev/null && tarball=$(npm pack --silent) \
  && npm install -g --ignore-scripts "$PWD/$tarball" >/dev/null; then
  rm -f "$tarball"
  echo "quota-axi-agy-fix: installed the local Antigravity quota fix"
else
  echo "quota-axi-agy-fix: reinstall failed; Antigravity quota stays unscored until the next rebuild" >&2
fi
exit 0
