## ADDED Requirements

### Requirement: OrderResolution and unified resolution
`OrderSystem` SHALL expose `resolve(target, target_cell, target_pos, modifiers) -> OrderResolution`, the
single decision for one player input. An `OrderResolution` SHALL carry `cursor` (`CursorState.Type`) and
`orders` (`Array[OrderResult]`). When the resolution produces orders, `cursor` SHALL be the highest-priority
order's cursor; when it produces none, `cursor` SHALL be a selection affordance (`SELECT`, `MOVE`,
`GENERIC_BLOCKED`, or `DEFAULT`). Cursor and orders MUST NOT be decided by separate branches.

#### Scenario: Armed selection over an enemy
- **WHEN** a local armed selection resolves against an enemy entity
- **THEN** `cursor` SHALL be `ATTACK` and `orders` SHALL contain the per-entity ATTACK orders

#### Scenario: Empty selection over a selectable entity
- **WHEN** nothing is selected and the input targets an unselected selectable entity
- **THEN** `cursor` SHALL be `SELECT` and `orders` SHALL be empty

#### Scenario: Already-selected immovable entity
- **WHEN** an already-selected immovable entity with no applicable order is targeted
- **THEN** `cursor` SHALL be `GENERIC_BLOCKED` and `orders` SHALL be empty

#### Scenario: Force-fire ground
- **WHEN** `force_attack` is held with a local armed selection and the target is bare ground
- **THEN** `cursor` SHALL be `ATTACK` and `orders` SHALL contain the ATTACK orders

#### Scenario: Cursor projects the order, not a parallel tree
- **WHEN** `get_cursor()` and `get_orders()` are called for the same input
- **THEN** the cursor SHALL equal `resolve().cursor` and the orders SHALL equal `resolve().orders`

### Requirement: Order dispatch
`OrderSystem` SHALL expose `issue(orders: Array[OrderResult]) -> bool`. For a non-empty list it SHALL play one
confirmation voice from the highest-priority order's `voice_event`, invoke each order's `execute`, and
acknowledge the selection's target lines, returning true. For an empty list it SHALL do nothing and return
false. Player order entry points (world click, ground click, minimap) SHALL dispatch through this operation
rather than reproducing the voice/execute/acknowledge sequence.

#### Scenario: One voice and one execution per batch
- **WHEN** `issue()` receives a multi-order batch
- **THEN** exactly one confirmation voice SHALL play and every order's `execute` SHALL run

#### Scenario: Empty batch is a no-op
- **WHEN** `issue()` receives an empty array
- **THEN** no voice SHALL play, nothing SHALL execute, and it SHALL return false

## MODIFIED Requirements

### Requirement: OrderSystem autoload
`OrderSystem` SHALL be an autoload singleton that holds the active `OrderGenerator`. It SHALL expose
`resolve()`, `get_cursor()`, `get_orders()`, `issue()`, `set_generator()`, and `cancel()`. `get_cursor()`
SHALL return `resolve().cursor` and `get_orders()` SHALL return `resolve().orders`. `UnitOrderGenerator`
SHALL be a stateless singleton reused across cancel() calls.

#### Scenario: Default generator
- **WHEN** OrderSystem starts
- **THEN** active_generator SHALL be the UnitOrderGenerator singleton

#### Scenario: Switch generator
- **WHEN** `set_generator(gen)` is called
- **THEN** active_generator SHALL be replaced with gen

#### Scenario: Cancel restores default
- **WHEN** `cancel()` is called
- **THEN** active_generator SHALL be restored to the UnitOrderGenerator singleton (not a new instance)

#### Scenario: Views project the resolution
- **WHEN** `get_cursor()` or `get_orders()` is called
- **THEN** it SHALL return the corresponding field of `resolve()` for the same input

### Requirement: UnitOrderGenerator
`UnitOrderGenerator` SHALL extend `OrderGenerator` as a stateless singleton and SHALL perform one resolution
decision per input. `resolve()` SHALL return the unified cursor and orders for the current selection from
`SelectionManager`, delegating per-entity order collection to `OrderResolver.resolve_all()` and cursor
selection to the highest-priority result. `get_cursor()` and `get_orders()` SHALL project `resolve()` and
MUST NOT re-derive its branches.

#### Scenario: Cursor resolution
- **WHEN** `resolve()` is called with a target
- **THEN** the cursor SHALL be the highest-priority order's cursor, or the selection affordance when no order is produced

#### Scenario: Order resolution
- **WHEN** `resolve()` is called with a target
- **THEN** orders SHALL contain one OrderResult per matching entity
