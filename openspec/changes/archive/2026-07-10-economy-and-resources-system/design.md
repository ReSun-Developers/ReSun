## Context

The codebase has harvester entity data (`HARV` with `storage=28`, `dock="PROC"`), a `TransportComponent` shell (cargo container, no behavior), and `GlobalRules` placeholders (`tiberium_grows`, `growth_rate`). No runtime economy exists: credits are never tracked, harvesters are decorative, and `BuildingManager.place_building()` spawns entities for free. The project needs a full economy backbone — credit tracking, Tiberium harvesting, and docking — before gameplay becomes functional.

Constraints: GDScript only, Redot 26.2 LTS, existing autoload pattern (6 registered in `project.godot`), existing component pattern (script-attached `Node` with `configure(data)`).

## Goals / Non-Goals

**Goals:**
- Per-player credit tracking via `PlayerData` resource + `EconomyManager` autoload
- Depletable Tiberium crystal nodes as `TERRAIN`-type entity instances
- Harvester behavior: find nearest node → fill cargo → find nearest refinery → dock → dump credits
- Refinery docking with one-at-a-time queue, bib-cell soft blocking for harvester pathing
- Stub deduction in `BuildingManager.place_building()` (placeholder for future build queue system)
- EntityData, GlobalRules field extensions for economy data

**Non-Goals:**
- Build menu / construction queue system (separate issue)
- Factory/barracks production queue system (separate issue)
- ServiceDepot repair deduction (separate issue)
- Passive income / credit farms (Tiberian Sun has none)
- Tiberium growth/spread simulation (structurally present but no tick system yet)
- UI HUD for credit display (separate issue)
- Multiplayer per-player treasury routing (structural foundation only)

## Decisions

### D1: EconomyManager as thin ledger
**Decision**: `EconomyManager` exposes only `add()`, `deduct()`, `can_afford()`, `get_balance()` with no income tick or passive generation.
**Rationale**: Tiberian Sun has zero passive income. Every credit comes from the harvest loop. A thick manager with tick rates would be dead code. Thin ledger is testable and composable — income behavior lives in `HarvestComponent` and `DockComponent` where it belongs.
**Alternatives considered**: Thick manager with per-second income tick (rejected — misaligned with TS game design).

### D2: PlayerData as Resource, not singleton state
**Decision**: `PlayerData` is an `@export`-rich `Resource` with `player_id` and `credits`. `EconomyManager` holds a `Dictionary[int, PlayerData]`.
**Rationale**: Resources serialize to `.tres` for save/load. The dictionary pattern extends naturally to multiplayer (one entry per connected player). A singleton with hardcoded credit variables would require a refactor later.
**Alternatives considered**: Global `credits` int on EconomyManager (rejected — multiplayer unfriendly, no serialization path).

### D3: New separate components (TiberiumComponent, HarvestComponent, DockComponent) over extending existing ones
**Decision**: Three new script-attached Node components. HarvestComponent references TransportComponent for storage. TransportComponent stays a pure data container.
**Rationale**: Single-responsibility. TransportComponent already has `harvester`, `storage`, `dock` fields — adding harvest behavior would make it a hybrid. Separation keeps each component testable and follows the existing codebase pattern (12 existing components, all single-purpose).
**Alternatives considered**: Merge harvest logic into TransportComponent (rejected — violates single responsibility), merge Tiberium state into TerrainSystem cell data (rejected — couples economy to terrain grid).

### D4: Bib cells on FoundationComponent, soft-blocked in SpatialHash
**Decision**: `FoundationComponent` gains `bib_cells: PackedVector2i`. When a building is placed, bib cells are registered separately in `SpatialHash` as soft-blocked (passable only for entities with an active dock interaction).
**Rationale**: Bib cells are a foundation-adjacent concept (they're always within the footprint rect). Storing them on FoundationComponent keeps placement validation and occupancy data colocated. Soft-blocking allows `HarvestComponent` to path through them while blocking enemy units.
**Alternatives considered**: Separate BibComponent (rejected — thin wrapper with no independent behavior), hard-blocked cells with manual exclusion in pathfinding (rejected — fragile).

### D5: Dock queue as Array on DockComponent, nearest-first
**Decision**: `DockComponent.queue: Array[HarvestComponent]` with one-at-a-time processing. Harvesters prefer the nearest non-occupied refinery; if the nearest is occupied they queue there rather than traveling to a farther one.
**Rationale**: Matches original TS behavior exactly. Nearest-first with queuing prevents harvesters from ping-ponging between distant refineries. Array-based queue is trivially simple — no priority, no timeout, FIFO.
**Alternatives considered**: Global harvester dispatch service (rejected — over-engineered for a 2-queue maximum in typical gameplay).

### D6: Stub deduction in place_building(), full deduction in future build queue
**Decision**: `BuildingManager.place_building()` calls `EconomyManager.deduct()` as a stub for testing. The real deduction timing (on queue entry, not placement) will be implemented in the build queue issue.
**Rationale**: Without at least one wired deduction path, `EconomyManager` is untestable in gameplay. The stub is temporary — 3 lines that get replaced when the build queue system lands.
**Alternatives considered**: No stub until build queue exists (rejected — no way to test the economy end-to-end).

### D7: Credit label in BuildMenu, signal-driven
**Decision**: A `Label` node added to `BuildMenu.tscn` above the GridContainer. Connected to `EconomyManager.credits_changed` in `_ready()`. No `_process()` polling.
**Rationale**: The build menu is always visible during gameplay, so adding a label inside it avoids a separate overlay scene. Signal-driven update is the established codebase pattern.
**Alternatives considered**: Separate HUD overlay (rejected — more complexity for a single label), polling in _process (rejected — credit changes are event-driven).

### D8: TiberiumTree as persistent EntityFactory entity, not transient Node3D
**Decision**: `TiberiumTree` is a `TERRAIN` entity created via `EntityFactory` with `TiberiumTreeComponent` + `FoundationComponent(1x1)`. It is placed in map scenes. On `_ready()` with `call_deferred()` it spawns crystal entity instances via `EntityFactory.create_entity()`. The tree persists even when all crystals are depleted.
**Rationale**: A persistent entity matches the original TS behavior where the tiberium tree (TIBTRE01-03 terrain object) stays on the map permanently. Using EntityFactory gives it proper lifecycle, foundation registration in SpatialHash, and consistency with how all other map objects are created. `call_deferred()` ensures the terrain system is loaded before spawning.
**Alternatives considered**: Transient Node3D that self-destructs (rejected — tree must persist for regrowth/spread), manual code in map scripts (rejected — map designers should configure via inspector).

### D9: Crystal pseudo-foundation checked in BuildingManager, not SpatialHash
**Decision**: Tiberium crystal entities have a 1x1 foundation registered in `SpatialHash` but marked as "pseudo" — `BuildingManager.can_place()` explicitly checks for `TiberiumComponent` in footprint cells. Unit pathing ignores them.
**Rationale**: Tiberium crystals must block building placement but allow unit movement through. SpatialHash currently has a binary blocked/unblocked model for cells. Adding a third state would complicate its interface and impact pathfinding performance. A targeted check in `BuildingManager.can_place()` is the smallest diff that works. Entities with `TiberiumComponent` register their foundation cells as building-blocked only, not entity-blocked.
**Alternatives considered**: Three-way cell state in SpatialHash (rejected — more complexity, wider blast radius), dedicated "resource cells" layer (rejected — YAGNI until a second resource type exists).

## Risks / Trade-offs

- **Bib cell pathing** → `SpatialHash` currently has no concept of "passable with conditions." Adding soft-blocking will either add complexity to `get_blocked_cells()` or require a separate lookup. Mitigation: Start with bib cells as fully traversable (ignored in block checks), add condition gates when dock queue is active.
- **Harvester auto-target perf** → Scanning all cells for TiberiumComponent entities every state transition could be costly on large maps. Mitigation: Limit scan radius to a fixed range (e.g. 20 cells). Cache nearest node per harvester and re-check only when depleted or out of range.
- **TransportComponent duplication** → `HarvestComponent` references `TransportComponent` for `storage` and `dock`. If the transport is destroyed mid-harvest, the harvest component must handle the null gracefully. Mitigation: `is_instance_valid()` check before every cargo operation.
