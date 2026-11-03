#!/usr/bin/env bash
# Evaluate the real activation for both Macs, then run it at fake OS boundaries.
# No sudo, Homebrew installation/upgrade, switch or browser is executed.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/chrome-update-test.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT
export TEST_STATE="$SANDBOX/state.json" TEST_TRACE="$SANDBOX/trace"
export TEST_BREWFILE="$SANDBOX/Brewfile"
mkdir -p "$SANDBOX/bin" "$SANDBOX/brew/bin"
cat > "$SANDBOX/bin/sudo" <<'SH'
#!/bin/bash
# Accept only nix-darwin's user boundary, never delegate to real sudo.
case "$*" in *--user="$TEST_USER"*--set-home*) ;; *) exit 99 ;; esac
while [ "$1" != env ]; do shift; done
exec "$@"
SH
cat > "$SANDBOX/brew/bin/brew" <<'PY'
#!/usr/bin/env python3
import json
import os
from pathlib import Path
import re
import sys

args = sys.argv[1:]
state_path = Path(os.environ['TEST_STATE'])
state = json.loads(state_path.read_text())
trace = Path(os.environ['TEST_TRACE'])

def record(message):
    with trace.open('a') as log:
        log.write(message + '\n')

record('brew ' + ' '.join(args))
if args == ['list', '--cask', '--versions', 'google-chrome']:
    if not state['installed']:
        sys.exit(1)
    print('google-chrome 1.0')
elif args == ['install', '--cask', 'google-chrome']:
    assert os.environ.get('HOMEBREW_NO_INSTALL_UPGRADE') == '1'
    if os.environ.get('TEST_INSTALL_FAIL'):
        sys.exit(42)
    assert not state['installed'], 'must never install over existing Chrome'
    state['installed'] = True
    record('installed google-chrome')
elif args == ['pin', '--cask', 'google-chrome']:
    assert state['installed'], 'cannot pin before first install'
    if os.environ.get('TEST_PIN_FAIL'):
        sys.exit(42)
    if not os.environ.get('TEST_PIN_NO_EFFECT'):
        state['pinned'] = True
elif args == ['list', '--cask', '--pinned', 'google-chrome']:
    if state['pinned']:
        print('google-chrome')
    if os.environ.get('TEST_VERIFY_FAIL'):
        sys.exit(42)
elif args[0] == 'bundle':
    assert '--force-cleanup' in args, args
    assert '--no-upgrade' not in args, args
    assert any(arg.startswith('--file=/nix/store/') for arg in args), args
    for name in re.findall(r'^cask "([^"]+)"', Path(os.environ['TEST_BREWFILE']).read_text(), re.M):
        if name == 'google-chrome':
            if not state['installed']:
                state['installed'] = True
                record('installed google-chrome')
            elif not state['pinned']:
                record('REPLACED running google-chrome')
        else:
            record('upgraded ' + name)
else:
    raise AssertionError(args)
state_path.write_text(json.dumps(state))
PY
chmod +x "$SANDBOX/bin/sudo" "$SANDBOX/brew/bin/brew"
export PATH="$SANDBOX/bin:$PATH"

for target in camilo camilo-total camilo-remote camilo-remote-total; do
  export TEST_USER=camiloslaptop
  case "$target" in camilo-remote*) TEST_USER=camilo_mini ;; esac
  # Only substitute the external Homebrew prefix. The activation body and
  # bundle command come from the real locked modules, not a source-text copy.
  nix eval --impure --json --expr "
    let
      flake = builtins.getFlake \"$ROOT\";
      evaluated = flake.darwinConfigurations.\"$target\".extendModules {
        modules = [{ homebrew.prefix = \"$SANDBOX/brew\"; }];
      };
      config = evaluated.config;
    in {
      inherit (config.homebrew.onActivation) cleanup upgrade;
      casks = map (cask: cask.name) config.homebrew.casks;
      inherit (config.homebrew) brewfile;
      activation = config.system.activationScripts.homebrew.text;
      # hasInfix builds a regex; strip dependency context only for that needle.
      activationIsInSystemScript = flake.inputs.nixpkgs.lib.hasInfix
        (builtins.unsafeDiscardStringContext config.system.activationScripts.homebrew.text)
        config.system.activationScripts.script.text;
    }
  " > "$SANDBOX/config.json"
  python3 - "$SANDBOX" <<'PY'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
config = json.loads((root / 'config.json').read_text())
assert 'google-chrome' in config['casks']
assert 'google-chrome@canary' in config['casks']
assert config['cleanup'] == 'uninstall'
assert config['upgrade'] is True
assert config['activationIsInSystemScript'] is True
(root / 'activation.sh').write_text(config['activation'])
(root / 'Brewfile').write_text(config['brewfile'])
PY

  for installed in false true; do
    printf '{"installed":%s,"pinned":false}\n' "$installed" > "$TEST_STATE"
    : > "$TEST_TRACE"
    # Two activations prove bootstrap and idempotency, including existing pins.
    for _ in 1 2; do
      /bin/bash -e "$SANDBOX/activation.sh" > "$SANDBOX/output" 2>&1
    done
    python3 - "$installed" <<'PY'
import json
import os
from pathlib import Path
import sys
state = json.loads(Path(os.environ['TEST_STATE']).read_text())
lines = Path(os.environ['TEST_TRACE']).read_text().splitlines()
assert state == {'installed': True, 'pinned': True}, (state, lines)
assert 'REPLACED running google-chrome' not in lines, lines
assert lines.count('installed google-chrome') == (sys.argv[1] == 'false'), lines
assert lines.count('brew pin --cask google-chrome') == 2, lines
assert lines.count('upgraded wezterm') == 2, lines
assert lines.count('upgraded google-chrome@canary') == 2, lines
pin_index = lines.index('brew pin --cask google-chrome')
bundle_index = next(i for i, line in enumerate(lines) if line.startswith('brew bundle '))
assert pin_index < bundle_index, lines
PY
  done

  for installed in false true; do
    for failure in TEST_PIN_FAIL TEST_PIN_NO_EFFECT TEST_VERIFY_FAIL TEST_INSTALL_FAIL; do
      # Install failure only applies to first bootstrap.
      if [ "$installed" = true ] && [ "$failure" = TEST_INSTALL_FAIL ]; then
        continue
      fi
      printf '{"installed":%s,"pinned":false}\n' "$installed" > "$TEST_STATE"
      : > "$TEST_TRACE"
      env "$failure=1" /bin/bash -e "$SANDBOX/activation.sh" > "$SANDBOX/output" 2>&1
      grep -q '^Pinning google-chrome has failed!$' "$SANDBOX/output"
      grep -q 'skipping Homebrew bundle' "$SANDBOX/output"
      if grep -q 'brew bundle\|REPLACED' "$TEST_TRACE"; then
        echo "FAIL: bundle must not run without an effective Chrome pin ($failure)" >&2
        exit 1
      fi
    done
  done
  echo "PASS: $target retains casks/cleanup; bootstrap, repeat and installed pin precede upgrades; pin failures fail closed"
done
