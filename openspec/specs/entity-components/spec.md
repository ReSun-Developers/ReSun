## Purpose

Reusable entity behavior components and the contracts they expose to the rest of the engine.
## Requirements
### Requirement: Components declare order targeters
Each component that can issue player-initiated orders SHALL implement `get_order_for_target(target: Node3D, target_cell: Vector2i, target_pos: Vector3, modifiers: Dictionary) -> OrderResult`. The method SHALL return null if the component cannot act on the given target. The returned `OrderResult` SHALL carry the cursor for that order; a component SHALL NOT expose a separate cursor-only method (`get_cursor_for_target`) — cursor behavior is provided solely by the targeter. Components without this method SHALL be silently skipped during order resolution.

#### Scenario: Component with no targeter
- **WHEN** a component does not implement `get_order_for_target()`
- **THEN** OrderResolver SHALL skip it without error

#### Scenario: Component returns null
- **WHEN** `get_order_for_target()` returns null
- **THEN** OrderResolver SHALL skip it and try other components

#### Scenario: Component returns OrderResult
- **WHEN** `get_order_for_target()` returns a non-null OrderResult
- **THEN** OrderResolver SHALL consider it for priority comparison

#### Scenario: No separate cursor method
- **WHEN** an order-capable component is inspected
- **THEN** it SHALL provide cursor information only through `get_order_for_target()` and SHALL NOT define `get_cursor_for_target()`

### Requirement: CombatComponent fires weapons at targets
CombatComponent SHALL implement a `_physics_process(delta)` loop that: (1) validates target, (2) checks range, (3) issues move if out of range, (4) fires hitscan damage when in range and cooldown elapsed.

#### Scenario: Full engagement cycle
- **WHEN** an attack order is issued on a valid enemy target
- **THEN** CombatComponent SHALL move toward target if out of range, fire when in range, and continue firing on cooldown until target dies or is cleared

#### Scenario: No-op when no target
- **WHEN** `_target` is null
- **THEN** `_physics_process` SHALL do nothing (no errors, no moves, no fires)

### Requirement: CombatComponent exposes weapon_fired signal
CombatComponent SHALL declare `signal weapon_fired(weapon: WeaponData, target: Node3D)` that emits after each hitscan damage application.

#### Scenario: Signal wiring
- **WHEN** any node connects to `weapon_fired`
- **THEN** the signal SHALL fire with the WeaponData and target Node3D on each shot

### Requirement: StatsComponent trainable and rank state
`StatsComponent` SHALL expose `trainable: bool` and the rank fields described by the `veterancy` capability (`experience`, derived `veteran_level`, `veterancy_changed`). `trainable` SHALL default from entity type when `EntityData.configure` runs: infantry, vehicles and aircraft are trainable; buildings are not. A building MAY opt in by setting `EntityData.trainable = true`. This default follows OpenTS (`Trainable=yes` for unit types, `no` for buildings).

#### Scenario: Unit types are trainable by default
- **WHEN** an infantry, vehicle or aircraft entity is created without an explicit `trainable` flag
- **THEN** its `StatsComponent.trainable` is true

#### Scenario: Buildings are not trainable by default
- **WHEN** a building entity is created without an explicit `trainable` flag
- **THEN** its `StatsComponent.trainable` is false

#### Scenario: Non-unit, non-building types are not trainable
- **WHEN** a terrain, overlay or smudge entity is created
- **THEN** its `StatsComponent.trainable` is false

#### Scenario: Defensive building opts in
- **WHEN** a building's `EntityData.trainable` is true
- **THEN** its `StatsComponent.trainable` is true

### Requirement: StatsComponent entity-type helpers
`StatsComponent` SHALL expose `is_unit()`, `is_infantry()`, `is_vehicle()`, `is_structure()` and `is_aircraft()` predicates resolving against `entity_type`. `is_unit()` SHALL be true for infantry, vehicles and aircraft. A static `is_unit_type(entity_type: int)` SHALL provide the same mobile-unit test for data-only call sites that have no `StatsComponent` instance. Existing call sites that inline the mobile-unit comparison SHALL use the shared unit predicate instead.

#### Scenario: Unit predicate covers mobile types
- **WHEN** `is_unit()` is called on an infantry, vehicle or aircraft entity
- **THEN** it returns true

#### Scenario: Unit predicate excludes buildings and terrain
- **WHEN** `is_unit()` is called on a building or terrain entity
- **THEN** it returns false

#### Scenario: Airframe predicate is specific
- **WHEN** `is_aircraft()` is called on an infantry entity
- **THEN** it returns false

