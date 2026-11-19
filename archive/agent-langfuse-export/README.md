# Retired global agent export

Archived on 2026-11-18 for the Fleet foundation request, items 3 (corrected) and 5.
These files are historical source, not installed or invoked by managed shells,
Pi, Claude Code, tests or a rebuild:

- `scripts/agent-tools/langfuse-otel-headers.sh`: former agent authentication helper.
- `tests/fixtures/pi_otel_export.mjs`: former installed-exporter HTTP test fixture.

Their bytes are preserved from the pre-retirement versions. The helper's old
requirement marker is historical, not an active export requirement.
The former global Pi selection was
`~/.local/share/pi-opentelemetry/install-e097771`; its host-local source and
history remain untouched. No credentials, data or installed packages are archived
here.

Do not invoke these files or automatically rediscover them as active helpers.
Re-enabling global agent export needs separate approval and coordinated restoration
of the previous settings, shell wiring, helper and tests from source history.
See [the tracing contract](../../specs/native-tracing.md) and
[operational acceptance and reversal](../../docs/AUTOMATIONS.md).
Phrona's own tracing and the shared Langfuse service remain active and unchanged.
