---
name: storage-audit
version: 1.0.0
description: Inventory where disk space and project data are stored, track growth privately, and plan safe cleanup. Use when storage is filling, locating app or agent data, preventing duplicated datasets in new workspaces, or reviewing cleanup candidates.
---

# Storage audit

Audit first. Cleanup is a separate, explicitly authorized action. Keep machine-specific inventories outside Git.

<!-- [impl->req~storage-audit.inventory~1] -->
## Start with the existing owners

1. Read the dotfiles repository's `AGENTS.md` and [`docs/STORAGE.md`](../../../docs/STORAGE.md).
2. Run the read-only [`scripts/storage-report.sh`](../../../scripts/storage-report.sh) from the dotfiles repository. Do not replace it with another whole-disk scanner.
3. Establish the volume's free space with `df -h "$HOME"`. If Finder, `df`, and directory totals disagree, report the discrepancy and inspect APFS snapshots/volumes with read-only `diskutil apfs list` and `tmutil listlocalsnapshots /`. Do not thin snapshots automatically.
4. Treat nested directory totals as overlapping. A `du` total is not proof of physically duplicated bytes: APFS clones, snapshots, hard links, symlinks, inaccessible files, and sparse VM images can change what it means.

## Make a private growth record

For each requested audit, save the report outside the repository so private paths do not enter dotfiles or project history:

```bash
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/storage-audit"
umask 077
mkdir -p "$state_dir"
report="$state_dir/inventory-$(date -u +%Y%m%dT%H%M%SZ).txt"
bash "$HOME/github/dotfiles/scripts/storage-report.sh" > "$report" 2>&1
```

Check the previous snapshot and summarize changes by path. Keep snapshots small: record paths, sizes, purpose, owner/configuration source, canonical-versus-copy status, recreation/backup status, and last checked date. Do not record file contents, credentials, cookies, audio, transcripts, database rows, or secrets. Do not put reports under `~/github`, a Firstmate home, Treehouse, or this repository. Do not automatically delete old snapshots.

If the dotfiles checkout is not at `~/github/dotfiles`, resolve the script relative to this skill's repository instead. If the scan is interrupted or reports permission errors, mark it incomplete rather than presenting partial totals as a complete inventory. Never use `sudo` or change permissions to make a scan pass.

## Find where large data is owned and written

- Start with the roots in `docs/STORAGE.md`, then drill into only the largest or relevant roots with `du -h -d 1 "PATH"`.
- Read the owning project's README, path resolver, configuration, and data/download scripts. Search for path variables such as `DATA_DIR`, `CACHE_DIR`, `HF_HOME`, `TORCH_HOME`, and project-specific environment variables. Do not assume ignored files or runtime data live beside tracked source.
- Distinguish source corpora, model weights, generated feature caches, build output, environments, app runtime databases/audio, Git object stores, and agent/task evidence. Use the owner and purpose, not a directory name alone, to classify a path.
- For Firstmate, keep each home's agent state and writable runtime isolated. For repeated training data on one machine, prefer one canonical dataset root and have project clones reference it. Share raw data read-only; share generated caches only when their input/model/config identity is clear and concurrent writes are safe. Keep run outputs, databases, logs, and checkpoints per home or run.
- In Invoz, inspect `scripts/data_paths.py` before setting paths. `INVOZ_DATA_DIR` currently directs datasets, runtime, and experiments together; do not point multiple homes at the same value merely to share datasets.
- Check symlinks and volume boundaries before interpreting totals. Do not launch a full file-by-file scan from `/` or `$HOME` as the first step. Inspect only targeted paths after the top-level summary identifies them.

Report findings in a table with `Path`, `Size`, `Contents/purpose`, `Owner or path configuration`, `Canonical/copy`, `Recreate/backup`, and `Cleanup status`. Separate measured facts from inference and list unscanned or inaccessible locations.

<!-- [impl->req~storage-audit.cleanup-approval~1] -->
## Cleanup gate

Never delete during an audit-only request. Before a cleanup, identify each exact target, current size, owning process/application, whether it is open, whether it is unique user data, how it can be restored or regenerated, and the expected space recovery. Show the plan and get approval for the exact targets. Then use the owning application's supported cleanup or retirement workflow, remove only approved paths, verify the target and free-space change, and save a new snapshot.

Default preservation rules:

- Keep source corpora, unique recordings, user/runtime databases, credentials, project source, uncommitted work, and backups unless the owner explicitly approves deleting the exact data and a recovery plan is understood.
- Never delete an entire `.git` directory. For Git garbage, verify refs/reflogs and active Git processes, explain what becomes unrecoverable, and use Git maintenance only with specific approval.
- Retire Firstmate homes through their provisioning/retirement contract, not raw directory deletion. Return or retire Treehouse worktrees through Treehouse, not `rm -rf`.
- Close the owning Chrome instance before removing profile cache directories. Do not delete the whole profile when only a cache is approved; cookies, sign-in state, local storage, and history are separate data.
- Use each package manager's documented cache or garbage-collection command. Do not bulk-delete `~/.cache`, `~/Library`, `.local`, model stores, or all folders named `cache`.
- Do not upload local data to Google Drive or another cloud as part of auditing or cleanup without explicit authorization and a license/privacy review.

Disk reports can show a path's size, not whether its content is valuable. When ownership, duplication, active use, licensing, or recoverability is uncertain, report the uncertainty and ask before changing it.
