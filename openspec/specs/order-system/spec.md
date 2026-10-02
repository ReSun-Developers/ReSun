# order-system Specification

## Purpose

Resolve player-issued orders and cursors from the current selection: the `OrderResult` data
class, the per-component order-targeter interface, `OrderResolver`, and the order generators
(unit, sell, repair).

## Requirements

### Requirement: OrderResult data class
The system SHALL provide an `OrderResult` class with fields: `cursor` (CursorState.Type), `priority` (int), `target` (Node3D, nullable), `target_pos` (Vector3), `queued` (bool), `execute` (Callable), and `voice_event` (String). The `execute` callback SHALL be a Callable bound to the specific entity instance (closure capturing the component's parent node). `voice_event` SHALL identify the voice event the order acknowledges with, chosen by the component that produced the order; it SHALL default to `move` so non-attack orders acknowledge with the move voice. A component MAY leave it empty to suppress the order voice. Modifiers SHALL be defined as constants: `MOD_FORCE_ATTACK = "force_attack"`, `MOD_FORCE_MOVE = "force_move"`, `MOD_QUEUED = "queued"`.

#### Scenario: OrderResult creation
- **WHEN** a component creates an OrderResult
- **THEN** it MUST populate cursor, priority, and execute fields

#### Scenario: Non-attack order defaults to the move voice event
- **WHEN** a component creates an OrderResult without setting `voice_event`
- **THEN** `voice_event` SHALL be `move`

#### Scenario: Attack order declares the attack voice event
- **WHEN** `CombatComponent` creates an ATTACK OrderResult (including force-fire)
- **THEN** `voice_event` SHALL be `attack`

#### Scenario: OrderResult with an empty voice event
- **WHEN** a component creates an OrderResult with an empty `voice_event` (for example the sell or repair order)
- **THEN** no order voice SHALL play for that order

#### Scenario: OrderResult with null target
- **WHEN** the order targets terrain (no entity)
- **THEN** target SHALL be null and target_pos SHALL contain the world position

#### Scenario: Execute is bound to entity
- **WHEN** execute.call() is invoked
- **THEN** it SHALL operate on the specific entity instance whose component created the OrderResult, not on any other entity

### Requirement: Component order targeter interface
Each order-capable component SHALL implement `get_order_for_target(target: Node3D, target_cell: Vector2i, target_pos: Vector3, modifiers: Dictionary) -> OrderResult`. Returns null if the component cannot handle the target.

#### Scenario: Component can handle target
- **WHEN** a component receives a valid target it can act on
- **THEN** it SHALL return an OrderResult with cursor, priority, and execute callback

#### Scenario: Component cannot handle target
- **WHEN** a component receives a target it cannot act on
- **THEN** it SHALL return null

#### Scenario: Modifier force_attack
- **WHEN** modifiers contains `force_attack: true`
- **THEN** CombatComponent SHALL be able to target allies and terrain

#### Scenario: Modifier force_move
- **WHEN** modifiers contains `force_move: true`
- **THEN** MovementController SHALL return a MOVE OrderResult even when CombatComponent would otherwise match (ALT+click ground near enemies)

#### Scenario: Modifier queued
- **WHEN** modifiers contains `queued: true`
- **THEN** the returned OrderResult SHALL have `queued = true`

### Requirement: OrderResolver returns per-entity orders
The `OrderResolver.resolve_all()` static method SHALL iterate all selected entities' components, collect one OrderResult per entity (the highest-priority from that entity's components), and return `Array[OrderResult]`. Priority convention: higher numeric value = higher priority (e.g., 20 > 10). The `OrderResolver.resolve_single()` static method SHALL return only the single highest-priority OrderResult across all entities (used for cursor resolution).

#### Scenario: Mixed selection, all entities match
- **WHEN** 3 tanks are selected and cursor is over an enemy
- **THEN** resolve_all() SHALL return 3 OrderResults, one per tank

#### Scenario: Mixed selection, partial match
- **WHEN** 2 tanks and 1 harvester are selected and cursor is over an enemy
- **THEN** resolve_all() SHALL return 2 ATTACK OrderResults (tanks) and 0 for harvester (no CombatComponent)

#### Scenario: No matching components
- **WHEN** no selected entity has a component that can handle the target
- **THEN** resolve_all() SHALL return an empty array

#### Scenario: Cursor uses single result
- **WHEN** resolve_single() is called for cursor resolution
- **THEN** it SHALL return the single highest-priority OrderResult across all entities, or null

#### Scenario: Tie-breaking
- **WHEN** two components return the same priority
- **THEN** the one with the earlier entity index in selected_entities wins (entity order is deterministic based on selection order)

### Requirement: OrderResolver uses has_method check
The OrderResolver SHALL use `has_method("get_order_for_target")` to detect targeter-capable components before calling the method.

#### Scenario: Component without targeter
- **WHEN** a selected entity has a component that does not implement get_order_for_target()
- **THEN** OrderResolver SHALL skip it without error

### Requirement: OrderSystem autoload
`OrderSystem` SHALL be an autoload singleton that holds the active `OrderGenerator`. It SHALL expose `get_cursor()`, `get_orders()`, `set_generator()`, and `cancel()`. UnitOrderGenerator SHALL be a stateless singleton reused across cancel() calls.

#### Scenario: Default generator
- **WHEN** OrderSystem starts
- **THEN** active_generator SHALL be the UnitOrderGenerator singleton

#### Scenario: Switch generator
- **WHEN** `set_generator(gen)` is called
- **THEN** active_generator SHALL be replaced with gen

#### Scenario: Cancel restores default
- **WHEN** `cancel()` is called
- **THEN** active_generator SHALL be restored to the UnitOrderGenerator singleton (not a new instance)

### Requirement: OrderGenerator base class
`OrderGenerator` SHALL be a base class with virtual methods: `get_cursor(target, target_cell, target_pos, modifiers) -> CursorState.Type`, `get_orders(target, target_cell, target_pos, modifiers) -> Array[OrderResult]`, `cancel()`. The generator SHALL access selection via the SelectionManager autoload.

#### Scenario: Base class defaults
- **WHEN** a subclass does not override a method
- **THEN** get_cursor() SHALL return DEFAULT, get_orders() SHALL return empty array

### Requirement: UnitOrderGenerator
`UnitOrderGenerator` SHALL extend OrderGenerator as a stateless singleton. `get_cursor()` SHALL delegate to `OrderResolver.resolve_single()` using the current selection from SelectionManager. `get_orders()` SHALL delegate to `OrderResolver.resolve_all()`.

#### Scenario: Cursor resolution
- **WHEN** get_cursor() is called with a target
- **THEN** it SHALL return the cursor from the single highest-priority OrderResult, or DEFAULT if none

#### Scenario: Order resolution
- **WHEN** get_orders() is called with a target
- **THEN** it SHALL return the array from resolve_all() — one OrderResult per matching entity

### Requirement: SellOrderGenerator
`SellOrderGenerator` SHALL extend OrderGenerator. It SHALL show SELL cursor on sellable buildings, SELL_BLOCKED elsewhere. A building is sellable if it has FoundationComponent, is not under construction, and has no active production queue. `get_orders()` SHALL return an OrderResult with a sell execute callback.

> **Note:** Sell/repair order generation is building management functionality, not order resolution infrastructure. This requirement is included here for completeness but may be moved to a dedicated sell-repair spec in the future.

#### Scenario: Sellable building under cursor
- **WHEN** target has FoundationComponent, is fully constructed, and has no active production
- **THEN** cursor SHALL be SELL and order SHALL sell the building

#### Scenario: Building under construction
- **WHEN** target has FoundationComponent but is under construction
- **THEN** cursor SHALL be SELL_BLOCKED

#### Scenario: Non-building under cursor
- **WHEN** target does not have FoundationComponent
- **THEN** cursor SHALL be SELL_BLOCKED

#### Scenario: No target
- **WHEN** cursor is over terrain with no entity
- **THEN** cursor SHALL be SELL_BLOCKED

### Requirement: RepairOrderGenerator
`RepairOrderGenerator` SHALL extend OrderGenerator. It SHALL show REPAIR cursor on damaged buildings, REPAIR_BLOCKED on healthy buildings or non-buildings. `get_orders()` SHALL return an OrderResult with a repair execute callback.

#### Scenario: Damaged building under cursor
- **WHEN** target has FoundationComponent and health < max_health
- **THEN** cursor SHALL be REPAIR and order SHALL repair the building

#### Scenario: Healthy building under cursor
- **WHEN** target has FoundationComponent and health >= max_health
- **THEN** cursor SHALL be REPAIR_BLOCKED

#### Scenario: Non-building under cursor
- **WHEN** target does not have FoundationComponent
- **THEN** cursor SHALL be REPAIR_BLOCKED

### Requirement: Left-click routes friendly unselected targets through orders first
When a left-click hits a selectable entity that is friendly/neutral and not currently selected, and the player has a selection, `MouseHandler` SHALL consult `OrderSystem.get_orders(target, target_cell, target_pos, modifiers)` before selecting. If the order list is non-empty, the orders SHALL execute and selection SHALL be skipped. Only when no orders are produced SHALL the entity be selected.

#### Scenario: Click refinery with harvester selected issues dock order
- **WHEN** a harvester is selected and the player left-clicks a friendly unselected refinery (DockHostComponent target)
- **THEN** the ENTER dock order SHALL execute (`set_target_refinery`)
- **AND** the refinery SHALL NOT be selected

#### Scenario: Click tiberium with harvester selected issues harvest order
- **WHEN** a harvester is selected and the player left-clicks a friendly unselected tiberium pod (ResourceComponent target)
- **THEN** the HARVEST order SHALL execute (`set_target_node`)
- **AND** the tiberium SHALL NOT be selected

#### Scenario: Click friendly unit with no order selects it
- **WHEN** units are selected and the player left-clicks a friendly unselected unit that produces no orders
- **THEN** the unit SHALL be selected (orders empty → fallback to selection)

#### Scenario: Empty selection still selects
- **WHEN** nothing is selected and the player left-clicks a friendly unselected entity
- **THEN** the entity SHALL be selected

#### Scenario: Shift+click forced selection unaffected
- **WHEN** the player shift+clicks a friendly unselected entity
- **THEN** selection behavior SHALL be unchanged (queued selection, no order execution)

#### Scenario: Enemy routing unchanged
- **WHEN** the target is an enemy and the selection can produce an order
- **THEN** the order SHALL execute as before (no behavior change to the enemy branch)

### Requirement: Order confirmation voices
After order resolution in `MouseHandler`, the system SHALL play one confirmation voice per order event from the NW-most selected local unit that has a `VoiceComponent` with a variant for the event, using the voice event carried by the resolved `OrderResult.voice_event` (the highest-priority resolved order). The voice event SHALL be chosen by the order-producing component, not derived from the cursor: `MOVE`, `HARVEST`, `ENTER`, and `DEPLOY` orders SHALL carry `move`; `ATTACK` orders SHALL carry `attack`; an empty `voice_event` SHALL produce no voice. Playback SHALL be a single `AudioManager.play_voice` call (camera-centered), never one per selected unit. A selected unit whose voice set lacks a variant for the event SHALL be skipped so the confirmation never lands on a speaker that would be silent.

#### Scenario: Move order plays move voice
- **WHEN** a player issues a `MOVE` order with a local unit selected
- **THEN** one `move` voice variant SHALL play

#### Scenario: Harvest order plays move voice
- **WHEN** a player issues a `HARVEST` order with a local harvester selected
- **THEN** one `move` voice variant SHALL play and no `attack` variant

#### Scenario: Attack-class order plays attack voice
- **WHEN** a player issues an `ATTACK` order with a local combat unit selected
- **THEN** one `attack` voice variant SHALL play

#### Scenario: Unmapped cursor is silent
- **WHEN** the resolved order carries an empty `voice_event` (no voice event mapped for the order)
- **THEN** no order voice SHALL play

#### Scenario: One voice per order, not per unit
- **WHEN** a multi-unit selection issues one order
- **THEN** exactly one confirmation voice plays (from the NW-most local unit)

#### Scenario: Deploy and stop hotkeys acknowledge with the move voice
- **WHEN** the player presses Ctrl+D (deploy) or Ctrl+S (stop) with a local unit selected and the command applies
- **THEN** one `move` voice variant plays from the NW-most selected unit that can voice it

#### Scenario: Voiceless or non-local selection is silent
- **WHEN** the NW-most local unit has no `VoiceComponent`, or the selection is entirely non-local
- **THEN** no order voice SHALL play

#### Scenario: Speaker is chosen among units that can voice the event
- **WHEN** a mixed selection issues an order whose event is missing from the NW-most unit's voice set but present on another selected local unit
- **THEN** the confirmation plays from the NW-most selected unit that has a variant for the event

### Requirement: Fog-gated target filtering
`OrderSystem` SHALL treat a target entity as absent when its cell is not visible to the local player. Visibility is the shroud/fog **cover state**, not the `fog_of_war` rule directly: `ShroudSystem.is_shroud_enabled()` decides whether never-explored cells stay hidden, `ShroudSystem.is_fog_enabled()` decides whether explored cells may go dark, and `ShroudSystem.is_cell_visible_to_local()` combines them. When fog of war is enabled, for cursor resolution and order generation: an entity (unit, building, or resource such as tiberium) in a cell not visible to the local player (including allied-union visibility) SHALL behave as a null target, falling through to the move path. Attack targeting against an **entity** SHALL NOT be issued at cells not visible to the local player.

A **force-fire ground** order SHALL be gated on the shroud instead of the fog: `OrderSystem` SHALL issue it only when the clicked cell has been explored by the local player (`ShroudSystem.is_explored`), and SHALL strip `OrderResult.MOD_FORCE_ATTACK` when it has not, so the input degrades to a plain move. Fog — explored but not currently visible — SHALL NOT block a force-fire ground order. This shroud gate SHALL be enabled by `ShroudSystem.is_shroud_enabled()` and SHALL NOT be conditioned on `GlobalRules.fog_of_war`.

The entity gate SHALL apply to hover preview and entity selection. With both covers off — `shroud_enabled` false and `fog_of_war` false — no entity filtering occurs and all entities resolve as before. With the shroud on, never-explored cells stay hidden whether or not `fog_of_war` is set; the shroud gate for force-fire ground orders is likewise governed by `is_shroud_enabled()` alone.

#### Scenario: Shrouded enemy falls through to move
- **WHEN** fog of war is enabled and an enemy entity sits in a cell not visible to the local player
- **THEN** hovering it produces the move cursor and clicking it issues a move order, never an attack

#### Scenario: Revealed enemy is attackable
- **WHEN** the enemy's cell becomes visible to the local player
- **THEN** normal attack cursors and orders apply

#### Scenario: Force-fire into shroud gated
- **WHEN** fog of war is enabled and force-fire targets a cell the local player has never explored
- **THEN** the force-fire attack is not issued and the input falls through to a move order

#### Scenario: Force-fire into fog is allowed
- **WHEN** fog of war is enabled and force-fire targets a cell that the local player has explored but that is not currently visible to them
- **THEN** the force-fire attack SHALL be issued at that cell

#### Scenario: Shroud gate does not depend on fog of war
- **WHEN** `fog_of_war` is false, the shroud is enabled, and force-fire targets an unexplored cell
- **THEN** the force-fire attack is not issued and the input falls through to a move order

#### Scenario: Shrouded resource not harvestable
- **WHEN** a tiberium crystal sits in a cell not visible to the local player
- **THEN** it is not targetable for harvest and is excluded from hover targeting

#### Scenario: Shrouded entity not selectable
- **WHEN** an entity is in a cell not visible to the local player
- **THEN** it cannot be selected by click or box selection and does not appear in hover preview

#### Scenario: Filter disabled with both covers off
- **WHEN** `shroud_enabled` is false and `fog_of_war` is false
- **THEN** all entities are interactable regardless of their exploration state

#### Scenario: Fog off alone does not reveal the unexplored
- **WHEN** `fog_of_war` is false, `shroud_enabled` is true, and an enemy sits in a never-explored cell
- **THEN** it behaves as a null target, falling through to the move path

### Requirement: Bounded player-order gating
`OrderSystem` SHALL restrict player-issued orders to targets inside the visible (inset) playable bounds as defined by `BoundsSystem`. The visible bounds SHALL be enforced via the playable-diamond cell test (`BoundsSystem.is_in_play_area`) for entity targets and the world-space clamp (`BoundsSystem.clamp_to_visible_diamond`) for ground positions. This gate SHALL apply to `get_cursor()` and `get_orders()` resolution only, and SHALL NEVER restrict movement, targeting, or behavior that is not issued by the human player through `OrderSystem`: AI-driven movement, the harvester auto-cycle, dock/exit navigation, combat pursuit, and any future map-trigger movement that calls `MovementController.set_target_position` or `SelectionManager.request_move` directly SHALL remain fully functional inside and outside the visible bounds.

#### Scenario: Ground move outside visible bounds clamps to edge
- **WHEN** the player selects a movable unit and right-clicks empty ground outside the visible bounds
- **THEN** the order SHALL be issued with `target_pos` clamped to the nearest point within the visible bounds
- **AND** the cursor SHALL remain MOVE

#### Scenario: Ground move inside visible bounds unchanged
- **WHEN** the player right-clicks empty ground inside the visible bounds
- **THEN** `target_pos` SHALL be used unclamped and the cursor SHALL be MOVE

#### Scenario: Attack / force-fire on out-of-bounds entity rejected
- **WHEN** the player selects a combat unit and attacks (or force-fires) an entity whose cell is outside the visible bounds
- **THEN** no order SHALL be produced
- **AND** the order-system cursor SHALL be BLOCKED

#### Scenario: Harvest / dock order on out-of-bounds entity rejected
- **WHEN** the player selects a harvester and issues a harvest or dock order on an entity outside the visible bounds
- **THEN** no order SHALL be produced
- **AND** the order-system cursor SHALL be BLOCKED

#### Scenario: Rally point outside clamps to edge
- **WHEN** the player alt+clicks to set a rally point outside the visible bounds
- **THEN** the rally point SHALL be placed at the nearest in-bounds point

#### Scenario: out-of-bounds target falls through to human move path only
- **WHEN** an out-of-bounds entity target is rejected
- **THEN** it SHALL NOT be turned into an attack/harvest/dock order (rejected, never remapped to a move order)

#### Scenario: AI and automatic movement unaffected outside bounds
- **WHEN** an unit is moved, harvested, docked, or pursued by AI / component-driven logic to a position outside the visible bounds
- **THEN** that movement SHALL proceed normally, unrestricted by the visible bounds

#### Scenario: boundary order valid at an already-in-bounds entity
- **WHEN** the player issues an order on an entity whose cell is inside the visible bounds
- **THEN** normal order resolution SHALL apply (no change from current behavior)

### Requirement: Action-mode state API
`OrderSystem` SHALL expose action-mode state derived from the active generator's type: `is_sell_mode()` returns true iff `active_generator` is a `SellOrderGenerator`, `is_repair_mode()` returns true iff it is a `RepairOrderGenerator`, and `is_action_mode()` returns true iff `active_generator` is neither the `UnitOrderGenerator` singleton nor a unit-order generator. No parallel mode booleans SHALL be kept in UI scripts; gameplay guards (MouseHandler order routing, PauseMenu ESC handling) SHALL query OrderSystem, not the Sidebar.

#### Scenario: Sell mode armed
- **WHEN** the sell button arms `SellOrderGenerator` via `set_generator()`
- **THEN** `is_sell_mode()` and `is_action_mode()` return true and `is_repair_mode()` returns false

#### Scenario: Repair mode armed
- **WHEN** the repair button arms `RepairOrderGenerator` via `set_generator()`
- **THEN** `is_repair_mode()` and `is_action_mode()` return true and `is_sell_mode()` returns false

#### Scenario: Cancel resets to unit orders
- **WHEN** `cancel()` is called while an action mode is active
- **THEN** the active generator cancels, `active_generator` resets to the `UnitOrderGenerator` singleton, and all three queries return false

#### Scenario: Guards do not read the Sidebar
- **WHEN** MouseHandler or the PauseMenu ESC guard need sell/repair mode state
- **THEN** they call `OrderSystem.is_sell_mode()`/`is_repair_mode()`/`is_action_mode()`; no gameplay script calls `Sidebar.is_sell_mode()`, `Sidebar.is_repair_mode()`, or `Sidebar.exit_action_mode()`

### Requirement: Generator change notification
`OrderSystem` SHALL emit a `generator_changed` signal after `set_generator()` installs a generator and after `cancel()` resets to the `UnitOrderGenerator` singleton, so UI (e.g. the Sidebar sell/repair buttons) can sync its visual state from the signal instead of being told imperatively.

#### Scenario: Set generator notifies
- **WHEN** `set_generator(SellOrderGenerator.new())` is called
- **THEN** `generator_changed` emits after the generator is installed

#### Scenario: Cancel notifies
- **WHEN** `cancel()` is called while a sell order mode is active
- **THEN** `generator_changed` emits after the reset, and the sell button unpresses itself from the signal — no imperative un-press call from gameplay code is required

### Requirement: Non-local selected entities are never commandable

`UnitOrderGenerator` SHALL exclude non-local (enemy) selected entities from order generation.
Ownership SHALL be determined from the selected entity's `StatsComponent.player_id` (missing
component or `player_id < 0` counts as local); the filter SHALL key on ownership only and MUST
NOT key on entity kind or component set, so local order-capable buildings (armed structures,
undeployable structures) remain fully commandable.

When the selection resolves to no local entity, `get_orders()` SHALL return an empty array and
`get_cursor()` SHALL return `CursorState.Type.SELECT` when the hovered target is a selectable
entity that is not already selected (so the player can click to re-select another entity),
otherwise `CursorState.Type.DEFAULT`. No command cursor (`MOVE`, `ATTACK`, `HARVEST`, `ENTER`,
`DEPLOY`) SHALL ever be produced for a non-local selection. Targets rejected by an earlier gate
— the bounds gate (`OrderSystem._order_bounds`) returns `GENERIC_BLOCKED`, the fog gate falls a
shrouded target through to the move path — keep that gate's outcome.

#### Scenario: Enemy selection shows DEFAULT cursor over ground
- **WHEN** only an enemy unit is selected and the cursor hovers empty ground
- **THEN** `get_cursor()` SHALL return `DEFAULT`

#### Scenario: Enemy selection shows SELECT cursor over an unselected selectable target
- **WHEN** only an enemy unit is selected and the cursor hovers a selectable entity that is not in the selection
- **THEN** `get_cursor()` SHALL return `SELECT`

#### Scenario: Enemy selection shows DEFAULT cursor over itself
- **WHEN** only an enemy unit is selected and the cursor hovers that same enemy
- **THEN** `get_cursor()` SHALL return `DEFAULT`

#### Scenario: Enemy selection returns no move order
- **WHEN** only an enemy unit is selected and a ground position is clicked
- **THEN** `get_orders()` SHALL return an empty array

#### Scenario: Enemy harvester receives no harvest or dock order
- **WHEN** only an enemy harvester is selected and a tiberium resource or an enemy refinery is clicked
- **THEN** `get_orders()` SHALL return an empty array
- **AND** `get_cursor()` SHALL return `DEFAULT` (never `HARVEST` or `ENTER`)

#### Scenario: Enemy armed or undeployable building receives no order
- **WHEN** only an enemy building with a `CombatComponent` or an undeploy-capable `DeployComponent` is selected and the cursor hovers empty ground
- **THEN** `get_orders()` SHALL return an empty array
- **AND** `get_cursor()` SHALL return `DEFAULT`

#### Scenario: Local armed building remains commandable
- **WHEN** a local building with a `CombatComponent` is selected and an enemy entity is clicked
- **THEN** `get_orders()` SHALL return a non-empty list containing the `ATTACK` order
- **AND** `get_cursor()` SHALL return `ATTACK`

#### Scenario: Local undeployable building remains commandable
- **WHEN** a local building with an undeploy-capable `DeployComponent` is selected and ground is clicked
- **THEN** `get_orders()` SHALL return a non-empty list containing the undeploy order

### Requirement: Unselected target click falls through to selection when no order applies

`MouseHandler` SHALL route a left-click on an unselected entity through `OrderSystem` first
(unless the select modifier is held). When the current selection produces no order, the entity
SHALL be selected instead of the click being swallowed. The same rule SHALL apply to enemy and
friendly/neutral targets; an unselected entity MUST NOT be selected when an order is produced
(e.g. an armed unit clicking an enemy attacks rather than selecting it).

#### Scenario: Armed unit clicking an enemy attacks, not selects
- **WHEN** an armed unit is selected and an unselected enemy is clicked
- **THEN** the `ATTACK` order SHALL execute
- **AND** the enemy SHALL NOT be selected

#### Scenario: Non-attacking selection clicking an enemy selects it
- **WHEN** a non-combat unit is selected and an unselected enemy is clicked (no order produced)
- **THEN** the enemy SHALL be selected (replacing the previous selection)

#### Scenario: Enemy selection clicking another enemy replaces it
- **WHEN** one enemy is selected and a different unselected enemy is clicked
- **THEN** the clicked enemy SHALL become the sole selection

#### Scenario: Enemy selection clicking a friendly entity replaces it
- **WHEN** an enemy is selected and an unselected friendly entity is clicked
- **THEN** the friendly entity SHALL be selected (the enemy is cleared)

### Requirement: Force-fire ground order
When a click resolves no entity target and `OrderResult.MOD_FORCE_ATTACK` is held, `UnitOrderGenerator` SHALL resolve component orders for the selection instead of synthesising a move, and SHALL emit the single highest-priority result per entity. For an armed combat unit the result SHALL be an ATTACK order at the requested ground position, at a priority above movement (5) and deploy (15) orders. When the modifier is not held, the ground path SHALL be byte-for-byte the existing behaviour: an undeploy-capable selection resolves component orders first, a movable selection receives a synthesized MOVE, and an unarmed selection receives a MOVE. The order cursor SHALL mirror the emitted order rather than being decided independently.

#### Scenario: Force-fire on empty ground attacks
- **WHEN** an armed local selection Ctrl+clicks empty explored ground
- **THEN** an ATTACK order SHALL be produced at that ground position and the cursor SHALL be ATTACK

#### Scenario: Plain click on the same ground still moves
- **WHEN** the same armed local selection left-clicks the same empty ground without Ctrl
- **THEN** a MOVE order SHALL be produced at that position and the cursor SHALL be MOVE

#### Scenario: Force-fire on ground an unarmed selection still moves
- **WHEN** a local selection with no weapons Ctrl+clicks empty ground
- **THEN** no ATTACK order SHALL be produced and the selection SHALL receive a MOVE order

#### Scenario: Force-fire ground respects the visible-bounds clamp
- **WHEN** an armed local selection Ctrl+clicks empty ground outside the visible bounds
- **THEN** the ATTACK order SHALL be issued at the position clamped by `BoundsSystem.clamp_to_visible_diamond`, matching the existing ground-move clamp

#### Scenario: Undeployable selection yields to force-fire
- **WHEN** a deployed, armed local selection Ctrl+clicks empty ground
- **THEN** the ATTACK order (priority 30) SHALL win over the undeploy order (priority 5)

#### Scenario: Mixed selection — armed fire, unarmed hold
- **WHEN** a local selection mixing armed and unarmed units Ctrl+clicks empty ground
- **THEN** the armed units SHALL each receive an ATTACK order and the unarmed units SHALL receive no order at all — they neither fire nor move
