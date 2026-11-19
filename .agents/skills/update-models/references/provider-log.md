# Provider log for update-models

Compact per-provider record of route versions, active workarounds, and what must be removed once an upstream fix lands. Update the dated row whenever a provider source, pin, or workaround changes.

| Provider | Last checked | Current source / pin | Latest observed | Workaround / waiting on |
|---|---|---|---|---|
| `openai-codex` | 2026-11-19 | Pi `1.5.2` (`@earendil-works/pi-coding-agent` in [manifest](../../../../nix/agent-tools.manifest.lock.json)) + `pi update --models` | Pi `1.5.2` (2026-11-10) | No workaround. `gpt-6.2-sol` / `gpt-6.2-astra` / `gpt-6.1-sol` pass probes. |
| `claude-bridge` | 2026-11-19 | `pi-claude-bridge@0.12.0` on Pi `1.5.2` (bundled SDK `0.3.321` / Claude Code `2.1.321`; shares login with Homebrew `claude` `2.1.311`, does not invoke it). Model list comes from Pi's `anthropic` catalog, so it already serves Fable 5.2, Opus 5.5, Sonnet 5.5 and Haiku 5.5. | `0.13.0` (2026-11-16, 7-day eligible 2026-11-23), same SDK `0.3.321`. Adds access-gated Mythos 5.2 / 5.1 (this account returns `404`), fixes hangs on rejected tool calls (#218), and now forwards Pi's whole system prompt (opt-out `provider.systemPromptPreset: false`). | No workaround. Optional on or after 2026-11-23: adopt for the hang fix. Mythos rows will show but fail. Watch `quota-axi` for `isUsingOverage` after adopting, because the full-prompt forward can trip Anthropic's third-party gate on some `AGENTS.md` wording. |
| `openai`, `anthropic` (Pi built-ins) | 2026-11-19 | Signed out with `pi auth logout openai` / `pi auth logout anthropic` (backup `~/.pi/agent/auth.json.bak-20261119122838`) | - | Intentionally hidden so the picker shows one route per vendor (`openai-codex`, `claude-bridge`). Nothing else reads them: `quota-axi` uses `pi:openai-codex`, and `pi-web-access` tries `openai-codex` first. Repeat on the Mac mini. |
| `antigravity` | 2026-11-19 | `git:github.com/Rahularya01/pi-antigravity@f950c08e7a5c1069a0339af88252347a5ecb0f8c` in [Pi settings](../../../../home/.pi/agent/settings.json) (separate from Homebrew `agy` `1.5.12`) | `v0.14.0` (`1e7697b23a0bf4c7c0bc1e2cc00238c8b422dfb9`, 2026-11-14) - still fails with stock Pi prompt | **Active workaround (laptop, uncommitted):** [antigravity-system-prompt.ts](../../../../home/.pi/agent/extensions/antigravity-system-prompt.ts) (see [cleanup below](#antigravity-cleanup-when-upstream-fixes-148--152)). |
| `xai` | 2026-11-19 | Pi `1.5.2` (`xai/`) + `pi update --models`; native `grok` CLI `1.0.77` (Homebrew) | `xai/grok-4.7` passes probes | No workaround. |
| `meta` | 2026-11-19 | Pi `1.5.2` (`meta/`) + `pi update --models` | Catalog confirmed (`meta/muse-wonder-1.0` etc.), OAuth ready | No workaround; billing/quota binding unresolved. |
| `cursor` | 2026-11-19 | Excluded from managed Pi packages (`tests/pi_settings_test.sh`) | Not dispatchable | Disabled. |

## Antigravity cleanup when upstream fixes #148 / #152

- **Added on 2026-11-19:** [`antigravity-system-prompt.ts`](../../../../home/.pi/agent/extensions/antigravity-system-prompt.ts) swaps Pi's stock system prompt prefix for `"You are a helpful assistant. Use available tools when asked."` only for `antigravity` when no custom or forced prompt is set, keeping project instructions (`AGENTS.md`), skills, and tool permissions intact. Verified on `gemini-3.8-flash` high and `gemini-4-neon` high.
- **Waiting on:** a vetted `pi-antigravity` release (7-day age + code diff + [#154](https://github.com/Rahularya01/pi-antigravity/issues/154) account-risk review) that fixes [#148](https://github.com/Rahularya01/pi-antigravity/issues/148) / [#152](https://github.com/Rahularya01/pi-antigravity/issues/152) / [#160](https://github.com/Rahularya01/pi-antigravity/issues/160) and passes `antigravity/gemini-3.8-flash` high and `antigravity/gemini-4-neon` high tool probes **without** the local extension (using Pi's stock prompt).
- **Delete when adopting that update:**
  1. `home/.pi/agent/extensions/antigravity-system-prompt.ts`
  2. `tests/pi_antigravity_prompt_test.mjs`
  3. The `Antigravity RESOURCE_EXHAUSTED` section in [`docs/PI-TOOLS.md`](../../../../docs/PI-TOOLS.md#antigravity-resource_exhausted) and the `pi_antigravity_prompt_test.mjs` lines in [`tests/README.md`](../../../../tests/README.md)
  4. Remove this cleanup block and update the `antigravity` row above with the new commit, date, and verified stock-prompt result.
