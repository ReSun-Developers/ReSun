## Context

The current sidebar (`Sidebar.gd`, 131 lines) is a flat GridContainer showing only buildings from `BuildingManager.building_types`. There is no tab system, no unit production queue, and no prerequisite checking. The `EntityData.prerequisite` and `prerequisite_necessary` fields exist but are unused. `FactoryComponent` is a thin data stub with no queue logic.

The game uses Redot 26.2 LTS with standard `_process(delta)` timing. `Engine.time_scale` scales delta automatically, so game speed settings will work without special handling. `Camera01.gd` handles zoom via scroll wheel (`zoom_in`/`zoom_out` actions), which must not fire when hovering over the sidebar.

## Goals / Non-Goals

**Goals:**
- 4-tab sidebar (Buildings, Infantry, Vehicles, Special) with scrollable 5×3 cameo grid
- Full prerequisite system: OR/AND logic, build limits, dynamic appearance/disappearance
- Production queue with timer, pause/resume/cancel, production speed bonuses
- Angular progress shader on cameos during production
- Unit spawning at factory exit with scatter when blocked
- Cost deduction on queue start, full refund on cancel

**Non-Goals:**
- Rally point setting UI (future — units spawn at factory exit point)
- Per-building queue selection (merged queues per factory type)
- Production speed visualization beyond the angular progress
- Drag-and-drop queue reordering
- Multiplayer sync of production state

## Decisions

### 1. Queue key = player_id + queue_type (not per-building)

**Decision**: Queues are keyed by `"%d:%s" % [player_id, queue_type]`. All barracks contribute to one infantry queue; all war factories contribute to one vehicle queue. The `queue_type` comes from `EntityData.buildable_queue` (OpenRA-style separation: `Buildable.Queue` on entity, `Production.Produces` on building).

**Rationale**: Matches TS behavior where units merge into a single queue per production category. The primary building determines spawn location. Multiple factories give a speed bonus (`1.0 + (count - 1) * 0.25`). Separating `buildable_queue` (what queue this entity belongs to) from `factory` (what this building produces) prevents conflation of the two concepts.

**Alternative considered**: Per-building queues — rejected because TS doesn't work this way and it would complicate the UI.

### 2. PrerequisiteSystem as separate autoload (not part of BuildingManager)

**Decision**: New `PrerequisiteSystem` autoload tracks player buildings and checks prerequisites.

**Rationale**: BuildingManager already has 560+ lines and focuses on placement logic. Prerequisite checking is a cross-cutting concern that other systems (sidebar, future tech tree) will use. Separation keeps both modules focused.

**Alternative considered**: Extend BuildingManager — rejected because it would mix placement concerns with query logic.

### 3. build_time in game seconds via Engine.time_scale

**Decision**: `EntityData.build_time` is in game seconds. ProductionManager uses `delta` from `_process()` directly. `Engine.time_scale` scales it automatically.

**Rationale**: No custom time system needed. When game speed settings are added later, they just set `Engine.time_scale` and all timers scale.

**Alternative considered**: Custom tick-based timing — rejected as over-engineering when Redot's built-in time scaling works.

### 4. Angular progress via canvas_item shader (not Polygon2D)

**Decision**: Radial wipe shader on a `ColorRect` child of each cameo button.

**Rationale**: Single draw call per cameo, GPU-accelerated, clean hard edge. `Polygon2D` would need vertex updates per frame and multiple draw calls.

### 5. Scroll consumption via _gui_input on ScrollContainer

**Decision**: `ScrollContainer._gui_input()` checks for mouse wheel events and calls `get_viewport().set_input_as_handled()`.

**Rationale**: Prevents `Camera01.gd` from receiving the scroll event. Standard Redot pattern for UI consuming input.

### 6. Cameo state machine: Available / Building / Paused / Dark / Hidden

**Decision**: Five visual states per cameo, managed by Sidebar.gd based on PrerequisiteSystem and ProductionManager signals.

**Rationale**: Covers all TS sidebar states. Hidden = prerequisites not met. Dark = build limit reached. Building = angular progress overlay. Paused = frozen progress.

### 7. buildable_queue vs factory separation (OpenRA pattern)

**Decision**: `EntityData.buildable_queue` determines which queue an entity belongs to (for routing in `start_production`). `EntityData.factory` is only set on production buildings (what they produce). `_spawn_unit` uses `buildable_queue` to find the producing factory via `_find_primary_factory`.

**Rationale**: OpenRA uses `Buildable.Queue` on the entity being produced and `Production.Produces` on the producing building — both reference the same string. This prevents the ambiguity where `factory = "BuildingType"` on the Construction Yard means "it produces buildings" but also would need to mean "I belong to the Building queue" for buildings being produced.

**Alternative considered**: Single `factory` field for both — rejected because it conflates "what produces this" with "what queue this belongs to", causing infantry to spawn from the wrong building.

## Risks / Trade-offs

- **[Risk] ProductionManager gets complex** → Mitigate by keeping queue operations simple (add/remove/pause/resume) and delegating spawn logic to a helper function.
- **[Risk] PrerequisiteSystem performance with many entities** → Mitigate by caching `can_build` results and only recomputing on `prerequisites_changed` signal.
- **[Risk] Scroll consumption blocks other UI** → Mitigate by only consuming when mouse is actually over the sidebar (check in `_gui_input`).
- **[Trade-off] No rally point UI** → Units spawn at factory exit point. Acceptable for initial implementation; rally point system is a separate future change.
- **[Trade-off] No queue persistence** → Queues are in-memory only. Acceptable since this is a single-session RTS, not a save-heavy game.
