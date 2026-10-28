# Spec Delta

## MODIFIED Requirements

### Requirement: Movement integration
CombatComponent SHALL connect to `MovementController.arrived` signal on first attack engagement. When `arrived` fires, the next `_physics_process` tick SHALL re-evaluate range and fire if in range. The approach destination SHALL be computed from the target's effective target point (nearest foundation-footprint point for a building, `global_position` otherwise), and the post-relocation in-range re-check SHALL measure to that same point.

#### Scenario: Unit moves toward target
- **WHEN** target is out of range and MC is idle, or the current move was just superseded by a fresh attack order
- **THEN** CombatComponent SHALL compute a stop position at `weapon.attack_range * CELL_SIZE` distance from the target's effective target point, on the attacker's side of that point, and call `mc.approach(stop_pos)`

#### Scenario: Attacker stops at range from the nearest wall, not the center
- **WHEN** the target is a large building and the attacker approaches from outside its footprint
- **THEN** CombatComponent SHALL issue a stop position `attack_range * CELL_SIZE` from the nearest footprint point, not from the footprint center, so the attacker does not close into the footprint center

#### Scenario: Multiple units spread around target
- **WHEN** 3 units attack the same target from different angles
- **THEN** each unit SHALL compute a unique stop position at its own angle around the target's effective target point, spreading naturally around the target perimeter

#### Scenario: Unit already moving on an approach
- **WHEN** MC is already moving (`is_moving() == true`) on a previously issued combat approach
- **THEN** the per-frame `_physics_process` re-check SHALL NOT issue another move command

#### Scenario: Arrival triggers re-check
- **WHEN** MovementController emits `arrived` signal
- **THEN** CombatComponent SHALL re-check range on next `_physics_process` tick

#### Scenario: Stop relocation keeps the target in range
- **WHEN** the computed stop position is relocated to the nearest passable cell and that relocation pushes it outside `attack_range * CELL_SIZE` of the effective target point
- **THEN** CombatComponent SHALL pull the stop position back inside the range circle around the effective target point, or back off as a failed path if that is impossible

### Requirement: Player move cancels attack
CombatComponent SHALL clear its attack target and stop attacking when the player issues a move command. Combat-initiated moves (closing distance to target) SHALL NOT clear the attack target.

#### Scenario: Player move clears attack
- **WHEN** CombatComponent has an active target and MovementController emits `movement_started` from a player-initiated move
- **THEN** CombatComponent SHALL clear `_target`, set `_attack_active = false`, and stop firing

#### Scenario: Combat move preserves attack
- **WHEN** CombatComponent issues a move to close distance to target (sets `_combat_move = true` before calling `mc.approach()`)
- **THEN** MovementController emits `movement_started`, CombatComponent SHALL detect `_combat_move`, skip clearing attack state, and continue attacking after arrival

### Requirement: movement_started signal on MovementController
MovementController SHALL emit `signal movement_started` at the beginning of each public move intent (`move_to`, `player_move`, `exit_move`, `approach`, `board`), before any pathfinding or movement begins. The private re-target SHALL NOT emit it.

#### Scenario: Signal emitted on move
- **WHEN** a public move intent is called with a valid position
- **THEN** `movement_started` SHALL be emitted before movement begins

#### Scenario: Signal suppressed on re-target
- **WHEN** the controller re-targets itself internally
- **THEN** `movement_started` SHALL NOT be emitted
