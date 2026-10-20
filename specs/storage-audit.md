# Storage audit

## Scope

Kind: product

Capability: `storage-audit`

Owns: guided disk inventories, private growth records, and approval-gated cleanup.

Does not own: where individual applications store data or how those applications retire their own data.

## Context

The Pi procedure is the [storage-audit skill](../.agents/skills/storage-audit/SKILL.md). It uses the [storage report](../scripts/storage-report.sh) and the [storage guide](../docs/STORAGE.md).

## Requirements

### Guided inventory and history

`req~storage-audit.inventory~1`

WHEN a user requests a storage audit in Pi, the storage-audit skill SHALL guide a read-only inventory, save dated reports in private local state, and identify incomplete measurements.

Needs: impl, utest, doc

### Approval-gated cleanup

`req~storage-audit.cleanup-approval~1`

WHEN a user requests storage cleanup, the skill SHALL identify exact targets, assess ownership and recovery, and obtain approval for those targets before using supported cleanup workflows.

Needs: impl, utest
