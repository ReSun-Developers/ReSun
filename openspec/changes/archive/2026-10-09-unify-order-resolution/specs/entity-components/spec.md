## MODIFIED Requirements

### Requirement: Components declare order targeters
Each component that can issue player-initiated orders SHALL implement
`get_order_for_target(target: Node3D, target_cell: Vector2i, target_pos: Vector3, modifiers: Dictionary) ->
OrderResult`. The method SHALL return null if the component cannot act on the given target. The returned
`OrderResult` SHALL carry the cursor for that order; a component SHALL NOT expose a separate cursor-only
method (`get_cursor_for_target`) — cursor behavior is provided solely by the targeter. Components without
this method SHALL be silently skipped during order resolution.

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
