#!/usr/bin/env bash
# Read-only preview using the exact same age/OSV policy as the weekly job.
set -euo pipefail
REPO_ROOT=${AGENT_TOOLS_REPO_ROOT:-"$(cd "$(dirname "$0")/../.." && pwd)"}
exec python3 "$REPO_ROOT/scripts/agent-tools/toolchain.py" select \
  --manifest "${AGENT_TOOLS_MANIFEST:-$REPO_ROOT/nix/agent-tools.manifest.lock.json}"
