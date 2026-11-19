# Automations

These dotfiles no longer schedule periodic rebuilds or Fleet skill-usage
collection. A rebuild applies the declarations in `nix/configuration.nix`;
removing a job's block and rebuilding removes it.

The agent platform's launchd templates in `services/agent-platform/` are not
scheduled by a rebuild. Each is installed by hand, as
[agent platform](AGENT-PLATFORM.md) describes.

## Rebuild (manual)

The former daily `org.dotfiles.auto-rebuild` daemon is removed. [Auto-update](AUTO-UPDATE.md)
explains `scripts/auto-rebuild.sh`, which you run by hand.

## Fleet skill usage and task outcomes

Skill usage is on-demand local evidence, not a scheduled Langfuse export.
Fleet owns its collection and report interface; consult the installed Fleet
release's help before refreshing records. Existing local records remain under
`~/.local/share/fleet/telemetry/skill-usage/records/`. Read them with:

```bash
S=~/github/fleet-system/system/skills/meta/skill-creator-fleet/scripts/skill_usage.py
python3 "$S" report
python3 "$S" report --parts
```

The former `org.dotfiles.fleet-skill-usage` 15-minute job is no longer declared.
It scheduled both skill-usage updates and Firstmate outcome-export flushes.
There is no scheduled replacement. Preserve existing logs privately at
`~/Library/Logs/fleet-skill-usage.log`; this change deletes no logs or records.
`tests/fleet_telemetry_test.py` evaluates all four nix-darwin targets to check
the job is absent and both hosts still activate Fleet's skill installer.

The existing `home.activation.linkSkills` still calls Fleet's
`system/skills/link-skills.sh` during rebuild. Removing the usage job does not
remove, replace or reschedule this installer.

## Langfuse is for Phrona

Global Pi sessions no longer select `pi-opentelemetry`. Claude Code telemetry
is explicitly disabled, with its OTLP settings and header helper removed.
Managed shells no longer set agent exporter endpoints, refresh authentication
files, choose a Langfuse secrets file or tag agent spans at each prompt.
See the [tracing boundary contract](../specs/native-tracing.md).

Phrona supplies its own explicit tracing endpoint and
`LANGFUSE_PUBLIC_KEY` / `LANGFUSE_SECRET_KEY`; it does not use the removed
global Pi exporter or Claude helper. Keep its configuration and keys, the shared
`scripts/agent-tools/langfuse-up.sh` helper and
`services/agent-platform/langfuse/`. Do not stop or replace the shared service,
restore a trial store, revoke Phrona's keys or delete received data.

The export-only header helper and test fixture are preserved under
[the agent-export archive](../archive/agent-langfuse-export/README.md), not loaded
by any managed session. Keep the installed source/history for reversal, including
the former Pi build `~/.local/share/pi-opentelemetry/install-e097771`.
Do not install or reactivate that package as part of a normal rebuild.

### After-rebuild acceptance

Main coordinates the rebuild and normal safe restarts; no running agent is
reconfigured by these source edits. Existing shells and agents retain inherited
exporter variables and loaded code. Launch fresh shells from a clean parent,
rather than nesting them under an old exporting agent.

1. On both hosts, `launchctl print gui/$(id -u)/org.dotfiles.fleet-skill-usage`
   must report that the job does not exist. A remaining job is an operator-owned
   cleanup task; these tests never unload one.
2. Run fresh Pi and Claude Code sessions with invented, nonprivate input.
   Record their session identities and the observation window, then verify no
   new matching agent traces arrive in the native Langfuse project. Allow for
   old processes' buffered exports; do not use a total trace count as proof.
3. Run a normal synthetic Phrona study through its own configuration and verify
   its exact received trace/observation IDs. A configured endpoint or successful
   local test alone is not evidence of received traces.

Do not dump environments, headers or credentials during acceptance.
The offline shell/settings regressions prove source wiring, not live agent
traffic or Phrona operation.

### Reversal

Re-enabling global agent export requires separate approval. Restore the previous
Pi package selection, Claude telemetry settings, shell endpoint/header/tag wiring
and the archived helper together, along with the then-applicable tests and spec.
The scheduled collector is a separate restoration, also requiring approval.
Preserve local owner edits when restoring blocks. Rebuild and coordinate fresh
sessions, then verify actual received traces. Stored traces, keys, logs and the
shared Langfuse service are untouched by retirement.

## Headless Claude on the Mini

Claude Code and Pi's `claude-bridge` use the same Claude authentication. A login
keychain can be locked to SSH-started processes even when a desktop login works.
For the Mini only, `nix/home.nix` loads
`~/.config/secrets/claude-code-oauth.env` from `.zshenv` if it exists, so new
noninteractive SSH and interactive shells export `CLAUDE_CODE_OAUTH_TOKEN` to
children. Missing files are left alone; no token is generated by a rebuild.
This is an optional fallback: working local sign-in needs neither `setup-token`
nor this file. The laptop keeps its existing authentication. Never commit or copy
this file, inspect its contents through an agent, or dump the process environment.

If the fallback is needed after activation, the operator runs these commands
from their own laptop terminal. The first opens authorization and prints a token
for the operator only. In the second, paste it and press Enter; input is hidden,
shell quoting is preserved, and an existing file is tightened to 0600 before writing.

```sh
ssh -t mac-mini claude setup-token
ssh -t mac-mini 'umask 077; mkdir -p "$HOME/.config/secrets"; IFS= read -rs T && [ -n "$T" ] && { F="$HOME/.config/secrets/claude-code-oauth.env"; touch "$F" && chmod 600 "$F" && printf "export CLAUDE_CODE_OAUTH_TOKEN=%q\n" "$T" > "$F"; }; rc=$?; unset T F; exit "$rc"'
```

Do not paste the token into chat or an agent terminal. Existing processes do not
inherit later shell changes; Main coordinates any normal safe restart, not the
rebuild or this loader. The operator can check a fresh shell with `claude auth status`.
Package loading alone does not prove a working Claude reply. This setup does not
authorize Claude workers.

## Reproduce native agents on another Mac

Copy committed source, not a running home. Match the intended dotfiles, Fleet and
Firstmate commits and the tool inventory described in [auto-update](AUTO-UPDATE.md).
The authored Pi settings and manifest own active packages; no global telemetry
extension installation or agent-export credential provisioning is required.
Keep model credentials host-local and provision Phrona tracing separately through
its own protected configuration.

Run the offline source checks in [tests](../tests/README.md) before activation.
Authenticate model accounts locally. Matching source does not guarantee identical
model responses or account quotas.

Use separate operational Firstmate homes on the two machines. Never copy active
`state/`, locks, task metadata, terminal sockets, telemetry records or sessions as
new work. Recovery of the same task is a separate guarded Firstmate procedure.
Do not copy `node_modules`, caches, credentials or an installed executable from
another Mac. Existing Mac bootstrap and Firstmate home setup remain the owners
of activation and runtime setup.
