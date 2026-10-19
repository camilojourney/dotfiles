# Pi tools for Firstmate

[`home/.pi/agent/settings.json`](../home/.pi/agent/settings.json) enables
codemode in `on` mode alongside ordinary tools, plus `tool_search`.
It does not select `only` mode or install a separate subagent framework.
Codemode's nested calls still pass through Pi's tool-call hooks.

[`home/.pi/web-search.json`](../home/.pi/web-search.json) keeps the existing
Anysearch provider and selects deferred web-tool exposure. Home Manager links
it at `~/.pi/web-search.json`. Full web schemas stay out of requests until
`web_enable` or `tool_search` loads them. Start a new session to use the new
initial tool selection; resumed sessions retain their recorded selection.
This changes exposure, not provider credentials or available capabilities.

Pi-web-access resolves `web-search.json` inside `PI_CODING_AGENT_DIR` when that
variable is explicitly set. An isolated agent directory therefore needs its own
web configuration. Without the override, the installed extension recognizes the
managed `~/.pi/web-search.json` location when no agent-local file takes priority.

An isolated real Pi 1.3.0 CLI fixture verified ordinary tools, nested codemode
bash, Firstmate's denial of a forbidden watcher command, deferred web schemas,
and discovery through `tool_search`. Provider responses were local fixtures.
This does not prove every Firstmate workflow or external web provider works.
Firstmate's supervision branch separately controls its resource loading; global
extension settings do not enable or select its supervision model.

## Waiting workers

Firstmate's `config/wait-no-turns` is a per-operational-home presence flag,
not a Pi setting and not inherited from the main home. Enable it in each intended
home before generating the next worker brief. It avoids waiting-only polling;
it neither rewrites existing briefs nor repairs missing wake delivery.
These local runtime flags are not distributed by this repository.

Package-update behavior is documented in [Auto-update](AUTO-UPDATE.md).
The tested compaction pin and its remaining limitation are documented in
[Pi compaction](PI-COMPACTION.md).
