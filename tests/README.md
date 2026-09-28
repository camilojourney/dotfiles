# Tests

Run all tests with:

```bash
bash tests/mac_setup_test.sh
bash tests/rebuild_remote_test.sh
bash tests/agent_tools_test.sh
bash tests/pi_settings_test.sh
```

`agent_tools_test.sh` exercises the agent-tool reconciliation and audit scripts with stubbed `npm`, `pipx`, external installers, and Homebrew.
It proves fresh activation installs the declared inventory, repeat activation is idempotent, Pi packages and Treehouse update after tool installation, setup hooks run, host-specific pipx packages stay scoped, missing package managers fail clearly, and shared Homebrew formulas are recognized for both host profiles.
It never touches the real network or host package state.

`pi_settings_test.sh` is a regression test for the declarative Pi settings and model overrides.
It ensures the package list retains only the intended Cursor provider, keeps GPT-6 Sol with high thinking as the default, removes the fixed llama.cpp URL, and limits custom model metadata to DeepSeek's 500,000-token context overrides.

`mac_setup_test.sh` is a regression test for `setup/mac.sh`.
`rebuild_remote_test.sh` checks the remote rebuild helper's first activation,
installed fast path, and missing-Nix diagnostic using stubbed sudo and Nix.
It never runs the script against the real machine, since that script installs Nix and activates a real `nix-darwin` system.
Instead it runs the actual `setup/mac.sh` against a PATH-masked sandbox of stub executables (`curl`, `sh`, `nix`, `darwin-rebuild`, `sudo`, `bash`) that simulate a fresh Mac.
The stubs also make sure the bootstrap uses the canonical `install.determinate.systems` installer URL.
The harness re-homes `NVM_DIR` under the sandboxed `HOME`, clears inherited `BASH_ENV`/`ENV` for the script invocation, and guards all harness/stub write paths so parent traversal or symlink escapes fail before anything is written.
It also self-tests that sandbox guard before running the bootstrap scenarios.

It covers two scenarios:

- a fresh machine, where the script must install Nix, source the daemon profile into the current shell, and activate `nix-darwin` for the first time, all in a single pass with no second-session step
- an already-bootstrapped machine, where the existing `darwin-rebuild switch` fast path is used instead

See `AGENTS.md` for the fresh-machine single-pass contract these tests protect.
