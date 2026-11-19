# Tests

Run all tests with:

```bash
bash tests/mac_setup_test.sh
bash tests/rebuild_test.sh
bash tests/agent_tools_test.sh
bash tests/baby_menu_config_test.sh
bash tests/pi_settings_test.sh
bash tests/model_routing_test.sh
bash tests/storage_report_test.sh
bash tests/claude_settings_test.sh
python3 tests/agent_platform_test.py
python3 tests/agent_platform_langfuse_test.py
python3 tests/fleet_telemetry_test.py
python3 tests/langfuse_otel_headers_test.py
python3 tests/langfuse_otel_export_test.py
python3 tests/claude_headless_auth_test.py
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

`pi_settings_test.sh` is a regression test for the declarative Pi settings and model overrides. It also keeps the repository's storage audit skill available in Pi.

<<<<<<< Updated upstream
It ensures Cursor is absent from Pi packages, Baby Menu, and managed installs, retains the host-relative telemetry build and Argon-discovery pin, selects our maintained local compaction checkout, leaves `pi-web-access` unversioned for daily updates, excludes Codex fast-mode, preserves automatic project trust, enables codemode alongside ordinary tools and `tool_search`, and links deferred web configuration. It keeps GPT-6.1 Sol with high thinking as the Pi default, removes the fixed llama.cpp URL, and limits custom model metadata to DeepSeek's 500,000-token context overrides. See [Pi tools](../docs/PI-TOOLS.md) and [Pi compaction](../docs/PI-COMPACTION.md) for activation and fork maintenance.
It also checks that `crew-dispatch.json` routes Claude profiles through Pi, permits Opus 5.5 only on the hardest-work crew rule, and keeps the existing Sonnet, Haiku, Gemini and Codex routing. Secondmates use Pi Opus 5.5 at xhigh, with Gemini 4 Argon and Gemini 3.8 Flash at high as saved manual alternatives. Home Manager links settings, crew dispatch, and both Secondmate selections to their authored owners. The backup is not automatic failover.
=======
It ensures Cursor is absent from Pi packages, Baby Menu, and managed installs, retains the intended telemetry and Argon-discovery pins, selects our maintained local compaction checkout, leaves `pi-web-access` unversioned for daily updates, excludes Codex fast-mode, preserves automatic project trust, enables codemode alongside ordinary tools and `tool_search`, and links deferred web configuration. It keeps GPT-6.1 Sol with high thinking as the Pi default, removes the fixed llama.cpp URL, and limits custom model metadata to DeepSeek's 500,000-token context overrides. See [Pi tools](../docs/PI-TOOLS.md) and [Pi compaction](../docs/PI-COMPACTION.md) for activation and fork maintenance.
It also checks that `crew-dispatch.json` sets no preferred provider family, so Firstmate picks within each rule by quota, and routes Claude profiles through Pi: Opus 5.5 in review and hardest work, Fable 5.1 in large changes, Sonnet for routine coding and mapping, Haiku for recon and judging, alongside Gemini Flash and Codex routes. `model_routing_test.sh` guards one candidate per quota scope in each rule (shared scopes tie in Firstmate ranking), quota coverage and concise rule text (30 words for `when`, 35 for `why`). Live Jev classification and Firstmate quota ranking still require the update-models skill's synthetic resolver smoke check. Secondmates use Pi GPT-6.1 Sol at xhigh (pythia-v2-lab is pinned to Opus 5.5 high), with Gemini 3.8 Flash at high as the saved manual alternative. Home Manager links settings, crew dispatch, and both Secondmate selections to their authored owners. The backup is not automatic failover.
>>>>>>> Stashed changes

`storage_report_test.sh` checks that the read-only storage report includes Firstmate homes, Treehouse, Chrome profiles, and arbitrary unlisted home and Application Support roots using a disposable fake home.

The repository-local `tool-maintenance` skill has routing examples and a synthetic
read-only behavior case under `.agents/skills/tool-maintenance/evals/`.
Fleet's creator `quick_validate.py` and Vale check its resources. Case validation
checks fixture readiness only; an authorized model run is needed to grade behavior.
The initial Pi CLI smoke verified command expansion using a local response fixture,
not maintenance judgment or live fleet delivery.

`claude_settings_test.sh` requires the authored `syncClaudeAiSkills` setting to stay
false. Skill overrides alone do not stop account-skill downloads. The test reads
JSON only; it never starts Claude or contacts a provider.

`claude_headless_auth_test.py` evaluates each host's actual zsh environment with
offline Nix and runs noninteractive, login and interactive shells with isolated
homes. Synthetic tokens prove the Mini exports the optional private-file token to
children, a missing file stays absent and preserves an explicitly inherited token,
and the laptop never loads this Mini-only file. It never reads real credentials
or starts Claude, Pi or an agent session. See [headless Claude auth](../docs/AUTOMATIONS.md#headless-claude-on-the-mini).

`langfuse_otel_headers_test.py` evaluates both hosts' managed shell setup with
offline Nix, then runs isolated noninteractive, login and interactive shells.
Synthetic secrets prove startup provisions no agent-export variables or header
files. It also checks prompt-time trace tagging is absent and explicit native
Langfuse configuration is left intact.

`langfuse_otel_export_test.py` checks the authored Pi package entry points
and manifest, explicit Claude telemetry disablement and absence of OTLP
settings or a header helper. It verifies export-only helpers moved to the
inactive archive and shared Langfuse service files remain. No installed exporter,
real credentials, models, network or running agents are used. These are
retirement regressions, not live no-traffic or Phrona-delivery proof.

`fleet_telemetry_test.py` evaluates all four targets with offline Nix and proves
the scheduled skill-usage job is absent. It also verifies both hosts keep the
existing Fleet skill installer and its activation ordering. It never unloads
jobs, activates a rebuild or changes a service.

For a non-activating full configuration evaluation, run from the repository root:

```bash
for target in camilo camilo-remote camilo-total camilo-remote-total; do
  nix eval --offline --raw ".#darwinConfigurations.$target.system.drvPath"
done
```

This evaluates the system derivations without building, switching or running
activation scripts. Live acceptance belongs to Main after a rebuild: no loaded
usage job, no new Pi/Claude exports, and received Phrona traces. See
[automations](../docs/AUTOMATIONS.md#after-rebuild-acceptance).

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
