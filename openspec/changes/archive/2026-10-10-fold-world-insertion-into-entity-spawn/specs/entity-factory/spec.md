# Spec Delta

## ADDED Requirements

### Requirement: Single entity spawn seam

`EntityFactory` SHALL provide `spawn(entity_id, placement)` as the single seam through which entities enter the world. The seam SHALL own assembly and insertion: it resolves the entity data (applying `placement.overrides`), assigns `placement.player_id` and `placement.world_pos` before the entity joins the scene tree, attaches it under `placement.parent` (defaulting to the match world's entity container, then the current scene), and — for a non-detached spawn — emits a spawn event. Callers SHALL retain placement policy — cost deduction, placement validation, terrain flattening, build-up animation, map rotation and deck height, health overrides, and their post-insertion steps — and SHALL NOT re-implement insertion.

#### Scenario: Entity enters the world through one call
- **WHEN** `spawn("GAPOWR", {world_pos, player_id})` is called
- **THEN** a fully assembled entity is attached under the world entity container with the given position and player

#### Scenario: Player is assigned before tree insertion
- **WHEN** a spawned entity has a MovementController
- **THEN** its player id is set before it enters the tree, so the movement crush filter reads the real id on `_ready`

#### Scenario: Position is assigned before tree insertion
- **WHEN** a spawned building has a FoundationComponent
- **THEN** its world position is set before it enters the tree, so foundation registration derives the correct origin cell

#### Scenario: Spawn event is emitted once for a world entity
- **WHEN** a non-detached entity is spawned
- **THEN** exactly one spawn event is emitted carrying the entity, its data, and its player id

#### Scenario: Caller keeps its post-insertion steps
- **WHEN** a caller performs post-insertion work (movement sub-slot assignment, map rotation/health overrides, state snapshot, terrain flattening, build-up)
- **THEN** that work still runs after the entity is inserted

### Requirement: Detached spawn for previews and editor content

`spawn(entity_id, placement)` SHALL support `placement.detached = true`, which inserts an entity into the scene for rendering but excludes it from world registration: no occupancy cells are registered, no `entities`, `selectable`, or `drag_selectable` groups are added, no player is registered, and no spawn event is emitted. Detachment SHALL be applied through the seam as a single shared marker that registration, guard and free-unit activation, fog, and unit-mesh exclusion all read, and it SHALL replace the previous per-caller preview flag.

#### Scenario: Detached preview registers nothing
- **WHEN** a building is spawned with `detached = true`
- **THEN** it is visible in the scene but registers no occupancy cells, joins no groups, and emits no spawn event

#### Scenario: Runtime spawn is registered
- **WHEN** the same building is spawned without `detached`
- **THEN** it registers occupancy and emits a spawn event

#### Scenario: Detached unit is excluded from gameplay and rendering systems
- **WHEN** a detached unit is spawned
- **THEN** guard acquisition, free-unit spawning, fog rendering, and the unit multimesh renderer treat it as absent, and occupancy is not registered
