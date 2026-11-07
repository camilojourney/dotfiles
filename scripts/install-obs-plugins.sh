#!/usr/bin/env bash
# Install the pinned OBS plugins into ~/Library/Application Support/obs-studio/plugins.
# Each package is checked against its pinned SHA-256 before it is installed.
# Quit OBS first: plugins load only at startup.
set -euo pipefail

# repo tag asset sha256
PLUGINS=(
  "Aitum/obs-aitum-stream-suite 1.2.5 aitum-stream-suite-macos-universal.pkg 977d379cd28824cf01560787e7c270bee2aaeecfff906b1f646409d8b7dc5609"
  "exeldro/obs-move-transition 3.2.1 move-transition-3.2.1-macos-universal.pkg 5a6ce90df677ad2cb0fcc642ddaf855a56ef4495c24e21030ac46a1c555e3dde"
  "exeldro/obs-source-clone 0.2.3 source-clone-0.2.3-macos-universal.pkg 0ba28bf57a2d4b95d9e7b60482e01417912a95a911d472ae8fdacb39d21c589e"
  "exeldro/obs-downstream-keyer 0.4.5 downstream-keyer-0.4.5-macos-universal.pkg 5e12ad37ec4760ae809ff9dcb7b60c8c0dbdb995b9d3ae4cfed30e663bb248ea"
  "FiniteSingularity/obs-advanced-masks v1.6.1 obs-advanced-masks-1.6.1-macos-universal.pkg bf1aea0b1d17a89dd9f609428a59abc4175a0817a2ccd7eeda7be7d353fd5e2a"
  "FiniteSingularity/obs-stroke-glow-shadow v1.6.1 obs-stroke-glow-shadow-1.6.1-macos-universal.pkg e041ea3d8bd2886331608b4ec011d69660a26de4fbc87b8453d8abac0abfad21"
  "FiniteSingularity/obs-composite-blur v1.6.1 obs-composite-blur-1.6.1-macos-universal.pkg 8f9a9ed54a8718fd60888837518b8916cd391c65e0335cfff9bef9daa462c7a3"
  "locaal-ai/obs-backgroundremoval 1.4.1 obs-backgroundremoval-1.4.1-macos-universal.pkg 62457287fac42a6fcf4d2f90fa8a52219ef9f7264e3029d663061f690d0776ea"
)

if pgrep -x OBS >/dev/null; then
  echo "Quit OBS before installing plugins." >&2
  exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for entry in "${PLUGINS[@]}"; do
  read -r repo tag asset sha <<<"$entry"
  curl -fsSL -o "$WORK/$asset" "https://github.com/$repo/releases/download/$tag/$asset"
  echo "$sha  $WORK/$asset" | shasum -a 256 -c --quiet
  installer -pkg "$WORK/$asset" -target CurrentUserHomeDirectory >/dev/null
  echo "installed $repo $tag"
done
