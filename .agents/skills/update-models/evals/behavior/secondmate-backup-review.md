# Review both Secondmate selections

## Task

Review the Secondmate configuration using this synthetic evidence. Do not edit files, run probes or read credentials. Report the selections and remaining verification.

- The active file contains `pi openai-codex/gpt-6.1-sol xhigh`.
- The backup contains `pi claude-bridge/claude-opus-5-5 xhigh`.
- Both files are authored in dotfiles and linked into Firstmate's config.
- The supplied catalogs confirm both model IDs. The active route's probe ran `ls | head -2.` with an accidental trailing period. The tool failed, but the model replied `DONE`. No backup probe or effective-effort verification is supplied.
- Firstmate's resolver reads only the active file. No backup-selection mechanism is configured.
- The user explicitly chose the active model and asked to preserve the backup.

## Checklist

1. Includes both active and backup selections, with each harness, model and effort.
2. Checks each selection against its own route rather than treating the primary's availability as proof for the backup.
3. Reports the active probe as failed despite `DONE`, keeps the backup and effective efforts unverified, and requires a corrected bounded probe.
4. Identifies the backup as a saved alternative, not automatic failover or an active runtime.
5. Preserves the explicit primary selection and unchanged backup rather than performing an unrelated tier sweep.
6. Names both authored files, their Home Manager links and the selection assertions in `tests/pi_settings_test.sh` as consistency checks.
7. Leaves all files and defaults unchanged, and uses the skill's report shape.
