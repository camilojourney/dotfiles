#!/usr/bin/env bash
# Install the official Cursor Agent CLI into ~/.local/bin when it is missing.
set -euo pipefail

install_dir="${HOME}/.local/bin"
binary="${install_dir}/cursor-agent"

if [ -x "$binary" ]; then
  printf 'agent-tools: cursor-agent already installed at %s\n' "$binary"
  exit 0
fi

if [ "${AGENT_TOOLS_TEST_MODE:-}" = 1 ]; then
  mkdir -p "$install_dir"
  printf '#!/usr/bin/env bash\necho synthetic cursor-agent\n' >"$binary"
  chmod +x "$binary"
  printf 'agent-tools: test-mode installed cursor-agent to %s\n' "$binary"
  exit 0
fi

command -v curl >/dev/null 2>&1 || {
  echo 'agent-tools: required command not found: curl' >&2
  exit 1
}
curl https://cursor.com/install -fsS | bash
[ -x "$binary" ] || {
  echo "agent-tools: official installer did not create executable $binary" >&2
  exit 1
}
printf 'agent-tools: installed cursor-agent to %s\n' "$binary"
