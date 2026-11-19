# Native tracing boundaries

## Scope

Kind: technical
Capability: native-tracing

Owns: Retirement of global Pi and Claude Code Langfuse export and the scheduled
Fleet skill-usage collector in dotfiles. Authorized by the 2026-11-18 Fleet
foundation request, items 3 (corrected) and 5.
The separate Langfuse service remains owned by `agent-platform.md`.
Phrona owns its explicit tracing endpoint, native keys and received-trace checks.

## Requirements

### No agent-session export

`req~native-tracing.no-agent-export~1`

The authored global Pi settings SHALL NOT load the telemetry exporter package.
Claude Code telemetry SHALL be explicitly disabled, without OTLP export settings
or an `otelHeadersHelper` invocation. Unrelated settings SHALL remain intact.
The shared Langfuse service and Phrona's explicit tracing configuration and keys
SHALL remain available; retiring global agent export SHALL NOT disable them.

Needs: impl, utest

Implementation owners: `home/.pi/agent/settings.json`,
`home/.claude/settings.json`. JSON has no inline traceability comments.
Tests: `tests/langfuse_otel_export_test.py`, `tests/pi_settings_test.sh`.
These check authored entry points, not live delivery or absence of backend traffic.

### Shell isolation

`req~native-tracing.shell-isolation~1`

WHEN a fresh managed shell starts without inherited exporter settings, it SHALL
NOT provision Pi OTLP environment variables, generate agent header files or
register prompt-time agent trace tagging.
The Mini's optional Claude OAuth loader SHALL remain intact.
Explicit native Langfuse configuration supplied to Phrona SHALL NOT be removed.

Needs: impl, utest

Implementation owner: `nix/home.nix`.
Tests: `tests/langfuse_otel_headers_test.py`,
`tests/claude_headless_auth_test.py`.

### On-demand skill usage

`req~native-tracing.on-demand-usage~1`

No nix-darwin target SHALL declare `org.dotfiles.fleet-skill-usage` or replace it
with another scheduled usage/outcome exporter. Skill usage SHALL be on-demand
local records, owned by Fleet, not agent-session export to Langfuse.
The existing `home.activation.linkSkills` installer SHALL remain intact.

Needs: impl, utest

Implementation owners: `nix/configuration.nix`, `nix/home.nix`.
Tests: `tests/fleet_telemetry_test.py`.

## Retirement and reversal

The former private-header helper and exporter fixture are retained, inactive,
under `archive/agent-langfuse-export/`. The previous private-header-file and
shell-authentication requirements are retired, not current export requirements.
Do not delete stored traces, local skill records, logs, keys or installed
exporter source as part of this change.

Existing shells and agents retain inherited settings and already-loaded code.
After an operator-controlled rebuild and safe restart, verify the retired job is
absent, new Pi and Claude Code sessions produce no new Langfuse exports, and a
Phrona study still records received traces. Static tests are not live proof.
Re-enabling global agent export requires separate approval and coordinated
restoration of settings, shell wiring and the archived helper.
