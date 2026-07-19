#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# Absolute path: sudo does not inherit interactive PATH
exec sudo /run/current-system/sw/bin/darwin-rebuild switch --flake "$DIR#camilo"
