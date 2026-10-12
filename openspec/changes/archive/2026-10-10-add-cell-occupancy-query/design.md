# Design

## Context

See `proposal.md` (Why) for the drift. The relevant current state:

- `SpatialHash` (`scripts/core/SpatialHash.gd`) exposes the per-cell queries and the registries
  `_building_cells`/`_bib_cells`/`_resource_cells` (all `cell_key`, ground only) and
  `_blocked_cells`/`_reserved`/`_shared_cell_counts`/`_grid` (all level-scoped via
  `cell_level_key`). There is no composite query.
- `rebuild()` (`SpatialHash.gd:155-163`) counts only **IDLE** sharers into `_shared_cell_counts`
  and only **IDLE non-sharers** into `_blocked_cells`; a moving sharer is in `_grid` but in
  neither registry.
- `TerrainSystem.get_cell_type(cell)` (`scripts/core/TerrainSystem.gd:311`) returns `""` for
  **both** a clear cell and an out-of-extent cell; the `""`/`"clear"` buildability convention is
  re-inlined in `FoundationComponent`, `DeployComponent`, `FreeUnitComponent`, and
  `ProductionManager`.
- `SpatialHash._reserved` is **not** destination-only: `SelectionManager.request_move` frees all
  reservations then `force_reserve`s each selected unit's **own origin cell**
  (`scripts/core/SelectionManager.gd:239,256-258`), and `DockHostComponent` holds a dock-pad
  reservation for the whole dock/unload, while `HarvestComponent` holds a tiberium cell until
  harvest. Only `MovementController` releases on arrival.
- `ExitComponent._is_cell_available` and `FactoryComponent._is_cell_available` are byte-identical
  and check building/bib/blocked/shared-capacity but **no terrain**; only
  `ProductionManager._find_exit_cell` checks terrain. `FactoryComponent._find_free_near` returns
  the building's own cell when nothing is free and never refuses.

## Goals / Non-Goals

**Goals:**
- One composite query answers "what occupies this cell", and one place encodes each consumer
  intent (build / unit exit / resource placement).
- Preserve every consumer's public surface; delete duplicated private predicates and private
  registry reads.
- Converge the divergent checks that are genuine drift, with each correction tested.

**Non-Goals:**
- Rebuilding movement passability or per-locomotor terrain cost (#469/#370). Exit terrain keeps a
  coarse `cell_type` proxy; this change does not introduce locomotor-aware exit checks.
- Changing the reservation model (`SelectionManager`/`MovementController`/`DockHost`/
  `HarvestComponent`). See D6 — folding reservations into BUILD is deliberately deferred.
- Moving systems under a World root (#473), sentinel constants (#470), or the shared-slot
  capacity model / `CellReservation`.
- Changing `DeployComponent`'s scatter behavior or the human-vs-AI placement rules.

## Decisions

### D1 — One typed result struct, computed once per cell

`SpatialHash` exposes `get_cell_occupancy(cell: Vector2i, level: int = 0, exclude: Node3D = null)
-> SpatialHash.CellOccupancy`. `CellOccupancy` is an **inner class** of `SpatialHash`
(`class CellOccupancy extends RefCounted:` — GDScript allows one `class_name` per file, so it is
not a second top-level `class_name`; referenced externally as `SpatialHash.CellOccupancy`).
Fields:

```
cell: Vector2i            level: int
building: bool            # _building_cells (ground)
bib: bool                 # _bib_cells (ground)
resource: bool            # _resource_cells (ground)
terrain_buildable: bool   # TerrainSystem.is_cell_buildable (ground; false out of bounds)
units: Array[Node3D]      # grid entries with a MovementController at `level`, minus `exclude`
blocked: bool             # any unit in `units` with state IDLE and not shares
moving: bool              # any unit in `units` with state != IDLE
shared_count: int         # count of units in `units` with state IDLE and shares
reserved: bool            # _reserved at `level` (NOT filtered by `exclude`)
```

`blocked`, `moving`, and `shared_count` partition `units` by `(state, shares)`, so a caller can
distinguish "an idle sharer below capacity" (exit may allow) from "a moving unit" (exit refuses)
— a single `units.is_empty()` cannot, which is why the fields are split. `units` holds the
`Node3D` roots (not raw entry dicts), so callers never touch the grid entry schema.

Buildings and resource overlays are **not** in `units`: buildings have no `MovementController`
and overlays are excluded from the `"entities"` group — they are the permanent facts instead.

### D2 — Three intent projections (corrected)

Built on the snapshot, encoding each shared semantics once:

```
is_cell_free_for_build(cell, level = 0, exclude = null) -> bool
    terrain_buildable and not (building or bib or resource) and units.is_empty()

is_cell_free_for_unit_exit(cell, level = 0, exclude = null) -> bool
    not (building or bib)
    and not blocked and not moving
    and shared_count < CellSubPositions.get_slot_count()

is_cell_free_for_resource(cell, level = 0) -> bool
    terrain_buildable and not (building or bib)
```

- **build** ≈ TS `Is_Clear_To_Build`: any unit body (idle, moving, sharer) refuses.
- **exit** ≈ TS `Can_Enter_Cell == MOVE_OK`: a moving unit and an idle non-sharer refuse; idle
  sharers are allowed **up to capacity**. This preserves current behavior
  (`is_cell_full_for_shared`) instead of the earlier `units.is_empty()` mistake, which would have
  rejected a cell holding a single friendly infantry. Non-`"clear"` terrain is **not** refused
  here: walkability is a locomotor concern, not buildability (a slope is walkable), so gating on
  `terrain_buildable` would regress the old Exit/Factory behavior that had no terrain check.
- **resource** ≈ TS `Can_Tiberium_Germinate`: units are ignored; only permanent obstructions and
  non-buildable terrain refuse.

### D3 — Terrain buildability: one predicate on `TerrainSystem`, false out of bounds

Add `TerrainSystem.is_cell_buildable(cell) -> bool` returning `type in {"", "clear"}` **after**
an in-bounds guard (a cell outside the grid extent returns false, because `get_cell_type`
returns `""` for out-of-extent cells, which would otherwise read as buildable). `SpatialHash`
already reads `TerrainSystem` statically (`MAX_HEIGHT`, `invalidate_height_snapshot`). This is
not a sentinel-constant change (#470): the two-literal comparison is relocated, not replaced.

### D4 — Momentary facts derive from `_grid`; permanent facts stay ground-only

`units`/`blocked`/`moving`/`shared_count` derive from `_grid` entries at `level` (respecting
`exclude`), so a single exclusion filter reproduces `DeployComponent._is_only_source_blocking` /
`_is_only_source_on_cell`. `building`/`bib`/`resource`/`terrain_buildable` are ground-only; at
`level > 0` the permanent facts are `false` and `terrain_buildable` follows the cell. All current
consumers are ground (level 0); build/exit projections are documented as ground-scoped.

### D5 — Convergence corrections (original-TS parity)

| Intent | Before | After | TS anchor |
|---|---|---|---|
| BUILD | any unit (incl. sharers) blocks | unchanged | `Is_Clear_To_Build` reads `Flag.Composite` |
| EXIT (Exit/Factory) | blocks idle non-sharer + idle-sharer capacity; **no terrain**, no moving | same, **plus** a moving unit blocks (terrain still not gated) | `Find_Exit_Cell` demands `MOVE_OK`; a moving occupant is `MOVE_MOVING_BLOCK` |
| EXIT (ProductionManager) | blocks building + idle non-sharer + terrain | unified onto the exit intent (drops the coarse terrain check) | as above |
| EXIT resource | resource not checked | unchanged (correct): tiberium is driveable, so exit is allowed | TS selects exits by movement, tiberium is passable |
| RESOURCE target | idle unit blocks; no terrain gate | ignore units; add terrain gate | `Can_Tiberium_Germinate` has no occupant test; gates on `Ground[].Build` |
| RESOURCE source | (none) | a unit on a tiberium cell stops it spreading | `Can_Tiberium_Spread` rejects `Cell_Occupier() != NULL` |

The exit intent deliberately does **not** gate terrain. The old `ExitComponent`/
`FactoryComponent` paths had no terrain check, and `get_cell_type` only ever returns `"clear"` or
`"slope"` — a slope is walkable, so gating exit on buildability would strand a factory whose only
free cell is a slope. Locomotor-aware exit passability (water, per-locomotor reach) is deferred to
#469/#370; the `ProductionManager` fallback's coarse `cell_type` check is dropped as part of the
convergence (it also refused walkable slopes).

### D6 — Reservations are NOT folded into BUILD (reversal; see follow-up)

The original plan folded `SpatialHash._reserved` into the build intent for TS parity, on the
assumption that ReSun reserves only a unit's destination. That assumption is **false**
(`SelectionManager.request_move` force-reserves each selected unit's origin cell until the next
move order; `DockHostComponent` holds a dock pad; `HarvestComponent` holds a tiberium cell).
Folding it in would make a freshly-vacated, visibly empty cell unbuildable until the player
issues another order — a routine-action regression and stricter than TS, which reserves the
destination only.

Therefore: the snapshot still exposes `reserved` (a cheap fact), but **no intent uses it**.
A follow-up change SHALL reconcile reservation lifetime (release origins at move start, scope
reservations to destinations) and only then fold `reserved` into BUILD. Tracked as a follow-up,
not this change.

### D7 — Test seeding

- Permanent facts seed through the public registrars (`register_building_cells`,
  `register_bib_cells`, `register_resource_cell`, `force_reserve`).
- Momentary facts seed by spawning real entities and calling `SpatialHash.rebuild()`, so tests
  exercise the gameplay path. Tests MUST tear down (unregister cells, `clear_reservations`,
  free spawned nodes, re-`init_grid`) because `test/run_tests.gd` runs all suites in one process
  and the registries persist.
- Terrain seeds through `TerrainSystem.set_cell_type(cell, type)`. Tests MUST seed an
  **in-bounds** cell and assert the round-trip (`get_cell_type(cell) == type`) before asserting
  buildability, so a "slope/water refused" test cannot pass vacuously via an out-of-bounds cell.
- Happy-path tests need no terrain seed only when the cell is in-bounds (`get_cell_type` `""` →
  buildable); out-of-bounds cells are now non-buildable.

## Risks / Trade-offs

- **EXIT moving-unit block stalls production.** New: a moving unit on the candidate holds the
  cell. `FactoryComponent._find_free_near` currently returns the building's own cell when nothing
  is free (pre-existing, unchanged this change); `ProductionManager`'s fallback retains to
  ready-to-spawn. Mitigation: tests cover the crowded-exit cases; the pre-existing "spawn on own
  cell" gap is called out for a follow-up. Terrain is deliberately not gated (see D5), so the
  exit pool is not shrunk by slopes.
- **Resource source-side rule changes spread dynamics** (tiberium grows under units but a covered
  patch stops seeding neighbors). Scoped to resource-to-resource spread, not tree seeding.
- **Query allocation on hot-ish paths.** The build-mode preview resolves per cell per frame; the
  query returns a fresh `RefCounted` per call. Bounded by the white window + footprint. If
  profiling shows it matters, add a bool fast-path per intent without changing callers.
- **Reservation regression avoided** by D6; the reserved-fact is inert until the follow-up.
