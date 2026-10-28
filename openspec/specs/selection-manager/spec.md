# selection-manager Specification

## Purpose

`SelectionManager` tracks the player's selected entities and issues group moves, distributing sharers to cells by capacity and non-sharers by offset formation.

## Requirements

### Requirement: SelectionManager tracks selected entities
`SelectionManager` SHALL be an autoload singleton maintaining `selected_entities: Array[SelectComponent]`. It emits `selection_changed(selected_entities)` whenever the selection set changes.

#### Scenario: Select single entity
- **WHEN** `select_entity(entity)` is called without shift
- **THEN** all previously selected entities are deselected, the new entity is selected, and `selection_changed` emits with the new selection

#### Scenario: Shift-click adds to selection
- **WHEN** `select_entity(entity, shift_pressed=true)` is called
- **THEN** the entity is added to the existing selection without deselecting others

#### Scenario: Shift-click removes from selection
- **WHEN** `select_entity(entity, shift_pressed=true)` is called on an already-selected entity
- **THEN** the entity is removed from the selection

#### Scenario: Deselect all
- **WHEN** `deselect_all()` is called
- **THEN** all entities are deselected and `selection_changed` emits with empty array

### Requirement: Hover preview
SelectionManager SHALL manage hover preview state. `set_hover_preview(enabled, entity)` toggles hover visual on the hovered entity and emits `hover_changed(entity)`.

#### Scenario: Hover entity
- **WHEN** `set_hover_preview(true, entity)` is called
- **THEN** `entity.set_is_hovering(true)` is called and `hover_changed` emits

#### Scenario: Unhover entity
- **WHEN** `set_hover_preview(false)` is called
- **THEN** the previously hovered entity's `set_is_hovering(false)` is called

### Requirement: Formation move for vehicles
When multiple vehicles are selected and a move command is issued, `request_move(target)` SHALL maintain formation offsets. Each vehicle moves to a position offset from the target by its relative offset from the selection center, clamped to ±2 cells.

#### Scenario: Two-vehicle formation
- **WHEN** two vehicles are 4 cells apart and move command is issued
- **THEN** each vehicle maintains its relative offset from the group center at the destination

#### Scenario: Formation offset clamped
- **WHEN** a vehicle is more than 2 cells from the selection center
- **THEN** its offset is clamped to ±2 cells at the destination

#### Scenario: Skip formation
- **WHEN** `request_move(target, skip_formation=true)` is called
- **THEN** all vehicles move to the exact target position (no formation offsets)

### Requirement: Infantry cell pre-assignment
When infantry units are selected and a move command is issued, `request_move()` SHALL pre-assign each infantry to a cell using spiral search from the target cell, with max 3 per cell based on `CellReservation` combined capacity (physical idle infantry + in-flight claims). `request_move()` SHALL NOT pre-assign sub-slots; slot assignment SHALL occur at movement start inside `MovementController.set_target_position` via `CellReservation.reserve_sub_slot`.

#### Scenario: Three infantry to same cell
- **WHEN** 3 infantry move to a cell with no existing infantry and no claims
- **THEN** all 3 are assigned to the target cell, and each claims a distinct sub-slot (0, 1, 2) at movement start

#### Scenario: Infantry overflow to adjacent cells
- **WHEN** 4 infantry move to a cell
- **THEN** 3 are assigned to the target cell, the 4th is assigned to the nearest free adjacent cell

#### Scenario: Target cell already has infantry
- **WHEN** 2 infantry move to a cell that already has 1 idle infantry
- **THEN** the 2 new infantry fill the remaining capacity, totaling 3 in the cell

#### Scenario: In-flight claims fill capacity
- **WHEN** a cell has idle infantry plus in-flight claims totaling 3
- **THEN** `_find_infantry_cell()` assigns new infantry to a neighboring cell instead

### Requirement: Batched move dispatch
SelectionManager SHALL dispatch pending moves in batches of 8 per frame via `_process()`. This prevents frame spikes when moving large groups. Each pending mover SHALL resolve its path via greedy-first movement: the unit's MovementController attempts bounded greedy descent toward its assigned cell (`Pathfinder.try_greedy_step`) and falls back to per-unit `Pathfinder.find_path` only when greedy descent stalls. SelectionManager SHALL NOT compute group-wide frontiers or precompute paths for sharers; every mover's path is resolved per-unit at dispatch time. SelectionManager SHALL keep one batch-lifetime terrain-cost cache (`Pathfinder` per-cell terrain cost memo) alive across the drain frames of a single move order so all units in the order share cost data; the cache SHALL be discarded (or its generation invalidated) when blocked/reservation state changes. SelectionManager SHALL resolve the `TerrainSystem` node reference once per move-order batch and pass it into per-unit path resolution (alongside the shared cost cache) instead of re-resolving the autoload for each unit, so the greedy/A* calls never walk the scene tree per step.

#### Scenario: Large group moved in batches
- **WHEN** 20 units are queued for movement
- **THEN** only 8 units receive their move command per frame, completing over 3 frames

#### Scenario: Sharer-only group uses greedy-first per-unit dispatch
- **WHEN** a selection is entirely infantry cell-sharers with one `LocomotorData` and a move is issued
- **THEN** every unit resolves its path per-unit (greedy first, A* on stall) with no group-wide frontier computation, and all units share one batch-lifetime terrain-cost cache

#### Scenario: Mixed selection keeps per-unit dispatch
- **WHEN** a selection contains a mix of sharers and non-sharers (vehicles, crushers, jumpjets)
- **THEN** every unit resolves its path per-unit (greedy first, A* on stall)

#### Scenario: Cache lifetime spans the order drain
- **WHEN** a move order for 50 units drains across ~6 frames
- **THEN** the terrain-cost cache is reused across the drain frames and invalidated when blocked/reservation state changes

#### Scenario: Terrain resolved once per order batch
- **WHEN** a move order drains N units across multiple frames
- **THEN** the `TerrainSystem` node is resolved at most once per batch and threaded into every unit's path resolution (no per-unit, per-step scene-tree lookup)

### Requirement: Local entity filtering
In multiplayer, `request_move()` SHALL only move entities owned by the local player. Non-local entities are skipped.

#### Scenario: Local entity moves
- **WHEN** an entity has `player_id == PlayerManager.get_local_player_id()`
- **THEN** it receives the move command

#### Scenario: Remote entity skipped
- **WHEN** an entity has a different `player_id`
- **THEN** it does not receive the move command

### Requirement: Deploy transition handling
Entities with DeployComponent that are transitioning (deploying/undeploying) SHALL be skipped during move commands. Their cells are reserved for other units.

#### Scenario: Transitioning entity skipped
- **WHEN** an entity has DeployComponent and `is_transitioning() == true`
- **THEN** it is skipped in `request_move()` and does not receive a move command

### Requirement: Cell reservation during move
Before issuing move commands, SelectionManager SHALL clear all existing reservations, then reserve each selected entity's current cell. If a vehicle's target cell is already reserved, a fallback target is found via spiral search. This requirement covers vehicle cell reservation only; infantry sub-slot claims are handled by `CellReservation`.

#### Scenario: Reserve current cells
- **WHEN** `request_move()` is called
- **THEN** all existing reservations are cleared, and each entity's current cell is reserved

#### Scenario: Fallback on reserved target
- **WHEN** a vehicle's target cell is already reserved
- **THEN** `CellUtil.spiral_first_free()` finds the nearest available cell within radius 8

### Requirement: Rally point setting
`request_set_rally_point(target_position)` SHALL set the rally point on all selected entities that have a RallyPointComponent.

#### Scenario: Set rally point
- **WHEN** `request_set_rally_point(world_pos)` is called with a building selected
- **THEN** `RallyPointComponent.set_rally_point(cell)` is called with the target cell

### Requirement: Visual selection synchronization
SelectionManager SHALL synchronize its internal selection list with the visual `is_selected` state on SelectComponents. The primary path SHALL be event-driven: `SelectComponent.set_is_selected()` emits a selection-state signal and SelectionManager reconciles that entity immediately. A low-frequency reconcile (at most 10 Hz) SHALL remain as a safety net for external direct writes to `is_selected`. The list SHALL NOT be rescanning the "selectable" group every frame.

#### Scenario: Visual selection out of sync (event-driven)
- **WHEN** a SelectComponent sets `is_selected = true` via `set_is_selected()` and is not in `selected_entities`
- **THEN** it is added to `selected_entities` on the same frame

#### Scenario: List contains visually unselected (event-driven)
- **WHEN** a SelectComponent sets `is_selected = false` via `set_is_selected()` while in `selected_entities`
- **THEN** it is removed from `selected_entities` on the same frame

#### Scenario: External mutation reconciled at low frequency
- **WHEN** a SelectComponent's `is_selected` is written directly (not via `set_is_selected()`)
- **THEN** `selected_entities` is reconciled within 100 ms

### Requirement: Sharers distribute by capacity
The system SHALL separate sharers from non-sharers when processing a group move command. Units whose MovementController `shares_cell()` returns true SHALL be distributed to cells near the target with at most `CellSubPositions.get_slot_count()` per cell, using `CellReservation` combined capacity. Each sharer SHALL be assigned a sub-slot at movement start inside `MovementController.set_target_position`; SelectionManager SHALL NOT pre-assign slots. Non-sharers SHALL use the existing offset-based vehicle formation.

#### Scenario: Group move with mixed units
- **WHEN** a player issues a move command with 6 sharers and 2 non-sharers selected
- **THEN** sharers are spread across cells near the target (≤ capacity per cell) using combined capacity, and non-sharers use existing offset logic

#### Scenario: Sharer cell search
- **WHEN** `_find_sharer_cell()` is called with a target cell at capacity
- **THEN** it spirals outward to find the nearest cell below capacity

### Requirement: Select voice playback
On a single-entity selection via `select_entity(entity)`, SelectionManager SHALL play a random variant from the entity's `VoiceData.select` event when the entity has a `VoiceComponent` with `voice_data` and is a local unit. Group and box selection events SHALL play exactly ONE select voice from the NW-most unit — never one per unit. Voice playback SHALL go through `AudioManager.play_voice` (camera-centered radio chatter).

#### Scenario: Selecting a local unit plays its select voice
- **WHEN** `select_entity(entity)` is called on a local unit with a non-empty `VoiceData.select`
- **THEN** one random `select` variant SHALL be played via AudioManager

#### Scenario: Selecting an enemy unit is silent
- **WHEN** `select_entity(entity)` is called on an enemy unit (non-local player_id)
- **THEN** no voice SHALL play

#### Scenario: Group select plays one voice
- **WHEN** `play_select_voice_for_entities(entities)` is called for a multi-unit selection event
- **THEN** exactly one select voice plays, from the NW-most unit

#### Scenario: Add-entity alone is silent
- **WHEN** `add_entity(entity)` is called directly (not via `select_entity` or the group path)
- **THEN** no voice SHALL play — voices are deferred to the selection event

### Requirement: NW-most voice picker
`get_northwest_most(entities)` SHALL deterministically pick the single speaking unit as the one closest to the top of the screen (smallest projected screen Y), tie-broken by the largest screen X (right-most). Without a camera it SHALL fall back to world-space ordering (smallest +Z, then largest +X).

#### Scenario: Top-most unit picked
- **WHEN** a camera exists and three units are candidates
- **THEN** the unit with the smallest projected screen Y is returned

#### Scenario: World-space fallback ordering
- **WHEN** no camera is present (headless/test context)
- **THEN** the unit with smallest +Z (then largest +X) is returned

### Requirement: Selection is exclusive across ownership

`SelectionManager` SHALL never hold a selection that mixes local and non-local entities.
Enemy (non-local) entities SHALL remain selectable for viewing, governed by the normal
selectability gates (visible bounds and shroud/reveal) and by the select modifier; ownership
SHALL NOT by itself make an entity unselectable. When an entity is added to the selection and
either the current selection's head is non-local or the incoming entity is non-local, the
existing selection SHALL be cleared first. Only local entities may coexist in one selection.
Consequently a non-local selection SHALL always contain a single entity.

Ownership SHALL be determined from `StatsComponent.player_id` (missing component or
`player_id < 0` counts as local), matching `SelectionManager._is_local_entity_node`.

#### Scenario: Shift-click an enemy while own units are selected clears them
- **WHEN** local units are selected and the player shift-clicks an enemy entity
- **THEN** the local units SHALL be deselected
- **AND** the enemy SHALL be the sole selected entity

#### Scenario: Shift-click a local unit while an enemy is selected clears it
- **WHEN** an enemy is selected and the player shift-clicks a local unit
- **THEN** the enemy SHALL be deselected
- **AND** the local unit SHALL be the sole selected entity

#### Scenario: A second enemy replaces the first
- **WHEN** an enemy is selected and the player shift-clicks a different enemy
- **THEN** the previously selected enemy SHALL be deselected
- **AND** only the newly clicked enemy SHALL remain selected

#### Scenario: Shift-click a local unit still adds
- **WHEN** a local unit is selected and the player shift-clicks another local unit
- **THEN** both local units SHALL be selected (no clearing)

#### Scenario: Plain click selects a lone enemy
- **WHEN** nothing is selected and the player clicks a selectable enemy
- **THEN** the enemy SHALL be selected

#### Scenario: Box-select while an enemy is selected clears it
- **WHEN** an enemy is selected and the player shift-drags a box over local units
- **THEN** the enemy SHALL be deselected
- **AND** only the local units SHALL be selected

### Requirement: Marquee drag ends on release regardless of UI hover
A marquee (selection box) drag SHALL end whenever the left mouse button is released, regardless of where the cursor is at that moment. This includes releases over the sidebar, the gameplay minimap, and the debug menu. On release the drag state SHALL clear and the selection box SHALL hide, so moving back into the gameplay view does not leave a latched drag.

A release over UI SHALL NOT resolve as a world single-click: it MUST NOT select a world entity behind the UI and MUST NOT issue an order. A release with no preceding press that reached gameplay input (for example, a press over UI followed by a release over the map) SHALL likewise select nothing and issue no order. When the drag exceeded the movement threshold before the cursor entered UI, the release SHALL still resolve the box selection from the rectangle formed in the gameplay view.

#### Scenario: Release over the sidebar ends the drag
- **WHEN** the player starts a marquee drag in the gameplay view and releases the left button with the cursor over the sidebar
- **THEN** the drag state clears and the selection box hides
- **AND** moving the cursor back into the gameplay view shows no lingering drag

#### Scenario: Release over the minimap ends the drag
- **WHEN** the player starts a marquee drag in the gameplay view and releases the left button with the cursor over the gameplay minimap
- **THEN** the drag state clears and the selection box hides

#### Scenario: Box selection resolves when released over UI
- **WHEN** the player drags a marquee past the movement threshold and releases over UI
- **THEN** the entities inside the rectangle formed in the gameplay view are selected

#### Scenario: Sub-threshold release over UI does not click through
- **WHEN** the player presses in the gameplay view and releases over UI without exceeding the drag threshold
- **THEN** no world entity is selected and no order is issued

#### Scenario: Release without a preceding press does not click through
- **WHEN** the player presses over UI and releases over the gameplay view
- **THEN** no world entity is selected and no order is issued

#### Scenario: Normal release over the gameplay view is unchanged
- **WHEN** the player drags a marquee and releases over the gameplay view
- **THEN** the box selection resolves and the selection box hides, as before
