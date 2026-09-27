#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export PATH="$TMP/bin:/usr/bin:/bin"
export AGENT_TOOLS_TEST_MODE=1
mkdir -p "$HOME/.local/bin" "$TMP/bin"
printf '#!/usr/bin/env bash\necho unrelated-agent\n' >"$HOME/.local/bin/agent"
printf '#!/usr/bin/env bash\necho cursor-desktop-app\n' >"$HOME/.local/bin/cursor"
chmod +x "$HOME/.local/bin/agent" "$HOME/.local/bin/cursor"

"$ROOT/scripts/agent-tools/install-cursor-agent.sh"
[ -x "$HOME/.local/bin/cursor-agent" ]
[ "$("$HOME/.local/bin/cursor-agent")" = 'synthetic cursor-agent' ]
[ "$("$HOME/.local/bin/agent")" = 'unrelated-agent' ]
[ "$("$HOME/.local/bin/cursor")" = 'cursor-desktop-app' ]

# Existing CLI is detected without replacement.
printf '#!/usr/bin/env bash\necho preexisting-cursor-agent\n' >"$HOME/.local/bin/cursor-agent"
chmod +x "$HOME/.local/bin/cursor-agent"
"$ROOT/scripts/agent-tools/install-cursor-agent.sh"
[ "$("$HOME/.local/bin/cursor-agent")" = 'preexisting-cursor-agent' ]
printf 'cursor-agent synthetic setup test passed\n'
