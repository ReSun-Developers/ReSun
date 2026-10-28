# Spec Delta

## MODIFIED Requirements

### Requirement: OrderResult data class
The system SHALL provide an `OrderResult` class with fields: `cursor` (CursorState.Type), `priority` (int), `target` (Node3D, nullable), `target_pos` (Vector3), `queued` (bool), `execute` (Callable), and `voice_event` (String). The `execute` callback SHALL be a Callable bound to the specific entity instance (closure capturing the component's parent node). `voice_event` SHALL identify the voice event the order acknowledges with, chosen by the component that produced the order; it SHALL default to `move` so non-attack orders acknowledge with the move voice. A component MAY leave it empty to suppress the order voice. Modifiers SHALL be defined as constants: `MOD_FORCE_ATTACK = "force_attack"`, `MOD_FORCE_MOVE = "force_move"`, `MOD_QUEUED = "queued"`, `MOD_GUARD_AREA = "guard_area"`.

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

## ADDED Requirements

### Requirement: Guard-area order resolution
`OrderSystem.build_modifiers()` SHALL set `MOD_GUARD_AREA` when both Ctrl and Alt are held, unless the current selection owns a `RallyPointComponent` (Alt then sets a rally point and the guard-area flag SHALL stay clear). `UnitOrderGenerator.resolve()` SHALL resolve a guard-area order before the force-move short-circuit whenever `MOD_GUARD_AREA` is held and the local selection contains at least one movable armed entity with a `GuardComponent`. The produced order SHALL be a `GUARD`-cursor order at a priority above the synthesized ground MOVE, SHALL carry the clicked target position and, for ground clicks, the surface level, and its execution SHALL move the selection to that position and place every selected local entity that actually receives that move and owns a `GuardComponent` into the guard-area stance. The resolution cursor SHALL be `CursorState.Type.GUARD`.

When the guard-area modifier is held but the local selection contains no guard-capable movable entity, resolution SHALL fall through to the existing force-move behavior. A non-local (enemy) selection SHALL never produce a guard-area order or cursor. The existing bounds gate SHALL still reject an out-of-bounds entity target as `GENERIC_BLOCKED` before the generator runs.

#### Scenario: Ctrl+Alt+Click issues guard area
- **WHEN** a local selection containing a movable armed unit Ctrl+Alt+clicks ground
- **THEN** `cursor` SHALL be `GUARD` and `orders` SHALL contain one `GUARD` order
- **AND** the order's priority SHALL be above the synthesized ground MOVE

#### Scenario: Ctrl+Alt+Click over an enemy issues guard area, not an attack
- **WHEN** a local guard-capable selection Ctrl+Alt+clicks an enemy entity
- **THEN** the resolution SHALL produce the `GUARD` order at that entity's position rather than an ATTACK order

#### Scenario: Guard order moves the selection and enters the stance
- **WHEN** the guard-area order executes for a local guard-capable selection
- **THEN** every selected local entity that receives the move SHALL be ordered to the target position
- **AND** each of those entities owning a `GuardComponent` SHALL enter the guard-area stance

#### Scenario: Ctrl+Alt+Click with no guard-capable unit falls back to force-move
- **WHEN** a local selection of movable unarmed units Ctrl+Alt+clicks ground
- **THEN** `cursor` SHALL be `MOVE` and the order SHALL be the force-move order

#### Scenario: Ctrl+Alt with a non-local selection is never a guard order
- **WHEN** only an enemy unit is selected and Ctrl+Alt+clicks ground
- **THEN** `orders` SHALL be empty and `cursor` SHALL NOT be `GUARD`

#### Scenario: Ctrl+Alt on an out-of-bounds entity is blocked
- **WHEN** a local guard-capable selection Ctrl+Alt+clicks an entity outside the visible bounds
- **THEN** `cursor` SHALL be `GENERIC_BLOCKED` and no guard-area order SHALL be produced

#### Scenario: Ctrl alone still force-fires
- **WHEN** a local armed selection Ctrl+clicks empty ground
- **THEN** `cursor` SHALL be `ATTACK` and the order SHALL be the force-fire order, unchanged by guard area

#### Scenario: Alt alone still force-moves
- **WHEN** a local selection Alt+clicks over an enemy or ground
- **THEN** `cursor` SHALL be `MOVE` and the order SHALL be the force-move order

#### Scenario: Alt on a rally receiver still sets a rally point
- **WHEN** a local selected building owns a `RallyPointComponent` and the player Alt+clicks ground
- **THEN** the click SHALL set the rally point instead of issuing any unit order, including guard area
- **AND** the guard-area modifier SHALL be clear for that selection
