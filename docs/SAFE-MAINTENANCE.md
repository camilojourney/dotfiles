# Safe maintenance

`scripts/safe-maintenance.sh` is the shared, profile-aware planner for the
laptop (`camilo`) and Mini (`camilo-remote`). It is preview-only by default:

```sh
scripts/safe-maintenance.sh --profile camilo --action setup
scripts/safe-maintenance.sh --profile camilo-remote --action update
scripts/safe-maintenance.sh --profile camilo-remote --action cleanup
```

The profile may be omitted only when `HOME` ends in `/Users/camiloslaptop` or
`/Users/mini`. A profile and target home must agree; outside paths and symlink
escapes are refused. The Mini scope is Pythia, Trader, Pilaster, and verified
dependencies. The laptop profile remains unchanged.

Setup/update planning does not run Nix, Homebrew, `darwin-rebuild`, or services.
Cleanup prints the exact proposed categories, but no cleanup category currently
has a reviewed generated-file allowlist or retention policy. Consequently
`--apply` is intentionally unavailable and exits without changing anything.
Protected data includes source and unpublished work, databases and history,
research/private data, credentials and keys, backups, and required services.

This is build-ready and backup-ready planning only. It is not live-apply,
reset-ready, deployment, Gateway login, trading upgrade, or deletion authority.
Explicit review and approval are required before adding an allowlist or enabling
any destructive/security-sensitive action.
