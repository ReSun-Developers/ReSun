# Design

## Context

See `proposal.md` — Why. Two seams exist for building occupancy:

- `EntityFactory._add_foundation_component` decides whether a `FoundationComponent` exists.
- `FoundationComponent._ready` registers non-bib foundation cells in `SpatialHash` and `_exit_tree` unregisters them; it already filters on `StatsComponent.entity_type == BUILDING`.

`SpatialHash` deliberately does not turn structures into idle-unit blockers during `rebuild` (only entries with a `MovementController` reach `_blocked_cells`), so the component lifecycle is the occupancy writer. Structures are still indexed in `_grid` at their centre cell, which is why a 1×1 structure already resolves as a ground-shot victim; only the footprint registry (`_building_cells`) is missing for them. `EntityFactory.spawn` sets position before `add_child`, which is why `_ready` derives the correct origin cell.

## Goals / Non-Goals

**Goals:**
- One-seam fix so every solid BUILDING gets the component and therefore occupancy.
- Preserve walkable, non-solid buildings (pavement, invisible light emitters).
- No change to `SpatialHash` registration/query/pathfinding behaviour or to `FoundationComponent` lifecycle.
- Preserve the existing non-building footprint case (smudges with 2×2 foundations use the component for minimap/fog geometry).

**Non-Goals:**
- #519 cursor-side changes (it starts working as a consequence of the invariant, but no cursor code changes here).
- #528 (`EntityData`-assembled fixtures).
- Reworking `SpatialHash.rebuild` to index structures from the entity group.
- Making overlay walls (`GDI_WALL_OVERLAY`) block; overlays are a separate occupancy gap.

## Decisions

### D1 — Attach `FoundationComponent` for every solid BUILDING (chosen)

Change `_add_foundation_component` from:

```gdscript
if data.foundation != Vector2i(1, 1):
```

to:

```gdscript
if (
    data.entity_type == EntityData.EntityType.BUILDING and data.blocks_cells
    or data.foundation != Vector2i(1, 1)
):
```

Rationale:
- `FoundationComponent._ready` already guards on BUILDING and already handles 1×1 (`footprint_cells` yields one cell, no bibs). The component is the existing registration seam; nothing new is needed.
- `BuildingManager._register_building_entity` falls back to `data.foundation` when the component is absent, `DockHostComponent._get_foundation` falls back to `Vector2i(1, 1)`, and `ShroudSystem.is_entity_revealed_to_local`, `FogRenderer._entity_fog_state`, and `Minimap._overlay_footprint` fall back to `Vector2i(1, 1)`; for 1×1 buildings the attached component carries the same values, so those consumers are behaviour-neutral.
- The `FoundationComponent`-based sell/repair gate (#519) becomes correct for 1×1 buildings with no cursor edit.
- Keeps the non-building branch (`foundation != 1×1`) so SMUDGE overlays keep their multi-cell minimap/fog footprint.

Alternative rejected — register cells at `EntityFactory.spawn`: it would duplicate registration for every >1×1 building, require a second unregistration path (the spawn seam has no teardown hook), and leave the `FoundationComponent`-based consumers (#519, `DockHostComponent`, minimap) still wrong for 1×1. Strictly more code and more failure modes.

Alternative rejected — index structures in `SpatialHash.rebuild` from the `entities` group: it changes the level-0/per-level contract and duplicates the component's unregistration responsibility.

### D2 — `EntityData.blocks_cells` distinguishes solid from walkable buildings

A blanket "every BUILDING blocks" would make `GDI_PAVEMENT` (documented as "speeds vehicles") and the six invisible light emitters solid. Add `@export var blocks_cells: bool = true` to `EntityData` and `FoundationComponent`; `FoundationComponent.configure` copies it and `_ready` returns early when false. Set `blocks_cells = false` on `gdi_pavement.tres` and `civ_invisible_{red,purple,yellow,blue,green}_light.tres` plus `civ_invisible_light_post.tres`.

Default `true` means no other content changes; only the seven non-solid buildings opt out. This is smaller and safer than re-typing them as OVERLAY (which would also make them undamageable and change selection).

### D3 — Root cause, not per-consumer guards

The report lists five consequences. Four read `SpatialHash._building_cells` (or the component's presence). Fixing the single writer covers them; adding guards in each consumer would be several diffs with the same bug left in the seam. The ground-shot path is the exception: it already resolves via `_grid`, so it is asserted for coverage but does not drive the regression.

### D4 — Resolve the `GDI_WALL` duplicate id

`structures/gdi/gdi_wall.tres` (`BUILDING`, buildable sandbags, prerequisite of `GDI_GATE_A/B`) and `overlay/gdi_wall.tres` (`OVERLAY`, neutral concrete wall) share `id = "GDI_WALL"`; the overlay is scanned later and overwrites the structure in `EntityFactory._entity_cache`. Rename the overlay ids to `GDI_WALL_OVERLAY`/`NOD_WALL_OVERLAY`. No shipped map, scene, or prerequisite references the overlay ids, so the structure keeps the id the gates already depend on. Without this, the issue's wall case cannot be fixed or tested through the factory.

### D5 — Test at the observable seam

Regression tests spawn real 1×1 structures (`GDI_SILO`, `GDI_WALL`) through `EntityFactory.spawn` on a `TerrainSystem` grid, then assert consumer-visible outcomes: `get_cell_occupancy().building`, `is_cell_free_for_build`, `get_blocked_cells`/`Pathfinder.find_path`, `is_cell_free_for_unit_exit`, and ground-shot victim resolution. The rejection pair asserts the same cell is free before the spawn. A second case spawns `GDI_PAVEMENT` and asserts its cell stays free, locking the `blocks_cells` exception. The suite snapshots/restores `BuildingManager._buildings`, `PrerequisiteSystem._player_buildings`, and `SpatialHash._building_cells` because `spawn` fires the `spawned` event. `test_order_system_modes._make_building` migrates to `EntityFactory.create_entity("GDI_SILO")` with player id and health set directly, so the fixture can no longer diverge from factory output.

### D6 — Scope cuts

- #519 is not edited; it is fixed by the invariant (recorded as a consequence, not a deliverable).
- #528 is untouched.
- No new specs; three existing capabilities are amended.

## Risks / Trade-offs

- [1×1 structures now participate in the projectile range extension for structures] → Intended: a 1×1 structure's footprint centre is its own cell, and the half-diagonal allowance only matters at the edge of weapon range.
- [1×1 structures now report a clamped `nearest_world_point` for impact position and range] → Intended and matches every other structure; the clamp is inside the single cell. `CombatComponent._effective_target_pos` and `GuardComponent` acquisition/visibility both switch from the cell centre to the cell edge for 1×1 buildings.
- [Attaching the component to 1×1 buildings changes the sell/repair gate] → Intended; it is the #519 fix and is covered by the migrated order-mode fixture.
- [Smudge/overlay behaviour could change if the condition is rewritten carelessly] → The condition keeps the `foundation != 1×1` branch; covered by existing minimap/fog tests.
- [A non-solid building with a footprint larger than 1×1 would still get the component through the non-building branch] → `FoundationComponent._ready` also checks `blocks_cells`, so it would not register. No such content exists today.

## Migration Plan

- Data-only: `blocks_cells` defaults to `true`, so existing `EntityData` resources keep their behaviour without edits; only the seven non-solid buildings opt out.
- The `GDI_WALL`/`NOD_WALL` overlay ids are renamed to `*_OVERLAY`. No shipped map, scene, or prerequisite references the overlay ids (grep-verified). A map that did place a `GDI_WALL`/`NOD_WALL` overlay now resolves to the wall structure (same art, now solid); re-save that placement as `GDI_WALL_OVERLAY`/`NOD_WALL_OVERLAY` to keep overlay semantics. Rollback is the reverse: revert the overlay ids, the `blocks_cells` data edits, and the factory condition.
