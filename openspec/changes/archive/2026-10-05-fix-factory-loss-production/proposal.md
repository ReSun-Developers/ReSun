# Proposal

## Why

Selling or destroying the final factory for a production type leaves its queue
running even though no building remains to service it. The queue continues to
charge and advance, and completed units waiting for a busy factory can remain
orphaned indefinitely.

## What Changes

- Keep the raw matching-factory count instead of hiding zero behind the
  historical one-factory speed baseline.
- Cancel unsupported active and paused queues through the existing refund path.
- Cancel and fully refund completed units waiting to spawn when their final
  matching factory disappears.
- Preserve completed buildings already waiting for placement.
- Synchronize factory ownership before announcing a newly entered factory.

## Impact

- `scripts/production/ProductionManager.gd`
- `scripts/components/FactoryComponent.gd`
- `test/unit/test_production_manager.gd`
- `openspec/specs/production-manager/spec.md`

