# Spec Delta

## MODIFIED Requirements

### Requirement: Bounded player-order gating
`OrderSystem` SHALL restrict player-issued orders to targets inside the visible (inset) playable bounds as defined by `BoundsSystem`. The visible bounds SHALL be enforced via the playable-diamond cell test (`BoundsSystem.is_in_play_area`) for entity targets and the world-space clamp (`BoundsSystem.clamp_to_visible_diamond`) for ground positions. This gate SHALL apply to `get_cursor()` and `get_orders()` resolution only, and SHALL NEVER restrict movement, targeting, or behavior that is not issued by the human player through `OrderSystem`: AI-driven movement, the harvester auto-cycle, dock/exit navigation, combat pursuit, and any future map-trigger movement that calls a MovementController move intent (`move_to` / `exit_move` / `approach` / `board`) or `SelectionManager.request_move` directly SHALL remain fully functional inside and outside the visible bounds.

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
