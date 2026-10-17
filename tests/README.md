# Tests

Run all tests with:

```bash
bash tests/mac_setup_test.sh
bash tests/rebuild_test.sh
bash tests/agent_tools_test.sh
bash tests/baby_menu_config_test.sh
bash tests/pi_settings_test.sh
bash tests/claude_settings_test.sh
python3 tests/agent_platform_test.py
python3 tests/agent_platform_langfuse_test.py
```

`agent_platform_test.py` exercises the encrypted, unlocked, ownership-enabled
SSD gate and dedicated central terminal job wiring in isolated fixtures;
it never changes a mount or starts a service. It also compiles the dedicated
exec-only launcher in a temporary directory using `/usr/bin/clang` (Command Line
Tools required), checking PID/argument/status preservation and refusal paths.
The separate opt-in Durable trial
uses `npm ci --ignore-scripts --prefix services/agent-platform/pilot`, followed by
`npm --prefix services/agent-platform/pilot test`. It uses only public fixtures,
owned child processes and temporary local stores, never real credentials/models.
See [the pilot guide](../docs/AGENT-PLATFORM.md) for the operational boundary.

`agent_platform_langfuse_test.py` checks the fresh stack's digest pins, private
ports, memory/log limits, isolated VM definition, query-worker regression and
metadata-only OTLP probe. Transport is mocked: tests never read real credentials,
contact a backend, start a VM or claim browser/load acceptance. The independent
operational proof is private, not committed here.

`agent_tools_test.sh` exercises the agent-tool reconciliation and audit scripts with stubbed `npm`, `uv`, external installers, and Homebrew.
It proves fresh activation installs the one declared inventory identically on every machine (no per-host profiles), repeat activation does not downgrade self-updating tools, npm tools follow their latest channel, external updaters run safely, setup hooks run, and missing package managers fail clearly.
It also proves the declared global python3 libraries install at latest, undeclared ones are removed, a failed install skips cleanup without aborting the rebuild, and the undeclared-package helper keeps declared packages, their runtime dependencies, and Homebrew's own.
It never touches the real network or host package state.

`baby_menu_config_test.sh` proves a rebuild preserves conflicting starter configuration, restores the three authored Baby Menu links, leaves runtime state untouched, and remains idempotent.

`pi_settings_test.sh` is a regression test for the declarative Pi settings and model overrides.
It ensures the package list retains the intended Cursor, telemetry, and Argon-discovery extension pins, keeps GPT-6.1 Sol with high thinking as the Pi default, removes the fixed llama.cpp URL, and limits custom model metadata to DeepSeek's 500,000-token context overrides.
It also checks that `crew-dispatch.json` routes Claude profiles through Pi (`claude-bridge/`), keeps `antigravity/gemini-3.8-flash` on low-effort/special-purpose rules while placing `antigravity/gemini-4-argon` (`high`) on `review`, `large`, and `hardest`, keeps Codex Sol leading `everyday` and `default`, pins secondmate to Pi Claude Opus 5.5 (`claude-bridge/claude-opus-5-5`) at xhigh, and verifies that Home Manager links settings, crew dispatch, and secondmate selection to their authored owners.

`claude_settings_test.sh` requires the authored `syncClaudeAiSkills` setting to stay
false. Skill overrides alone do not stop account-skill downloads. The test reads
JSON only; it never starts Claude or contacts a provider.

`mac_setup_test.sh` is a regression test for `setup/mac.sh`.
`rebuild_test.sh` checks the one shared `rebuild.sh` helper's account-based
flake-attr detection (both `camiloslaptop`/`camilo` and `camilo_mini`/
`camilo-remote`, plus an unrecognized account failing loudly), the installed
fast path, and that a missing `darwin-rebuild` points existing installations
to recovery while retaining `setup/mac.sh` guidance for a fresh machine.
It never runs the script against the real machine, since that script installs Nix and activates a real `nix-darwin` system.
Instead it runs the actual `setup/mac.sh` against a PATH-masked sandbox of stub executables (`curl`, `sh`, `nix`, `darwin-rebuild`, `sudo`, `bash`) that simulate a fresh Mac.
The stubs also make sure the bootstrap uses the canonical `install.determinate.systems` installer URL.
The harness re-homes `NVM_DIR` under the sandboxed `HOME`, clears inherited `BASH_ENV`/`ENV` for the script invocation, and guards all harness/stub write paths so parent traversal or symlink escapes fail before anything is written.
It also self-tests that sandbox guard before running the bootstrap scenarios.

Bootstrap coverage includes:

- a fresh machine, where the script must install Nix, source the daemon profile into the current shell, and activate `nix-darwin` for the first time, all in a single pass with no second-session step
- an already-bootstrapped machine, where the existing `darwin-rebuild switch` fast path is used instead
- a stale shell with the source-once guard already set, where the installed profile restores PATH without reinstalling
- an unmounted store with an existing service plist, a dangling daemon plist, or a dangling profile, where setup stops before downloads or activation
- an available Nix binary whose daemon check prints partial JSON and then fails, where the nonzero exit status stops setup and preserves the error

The Nix profile and launch-daemon directory are redirected into each sandbox,
so the tests do not consult an existing macOS installation.

`setup/mac.sh` is the only place that bootstrap logic lives now - `rebuild.sh` assumes it has already run and fails with a clear message if `darwin-rebuild` isn't installed yet.
