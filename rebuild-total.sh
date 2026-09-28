#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Same script as rebuild.sh, plus the personal extras in nix/camilo-extra.nix
# (Camo, OBS, WhatsApp, Dato, etc.) - typically only ever needed on the
# laptop. Everyday coding work should use plain ./rebuild.sh instead.
export REBUILD_SUFFIX="-total"
exec "$DIR/rebuild.sh"
