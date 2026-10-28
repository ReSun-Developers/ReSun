# Spec Delta

## MODIFIED Requirements

### Requirement: Air attack holds never book ground sub-slots
Internal re-targets (repair, blocked-arrival settle, wait scatter, nudges) SHALL preserve the move's zone intent via the private `_retarget(target, keep_zone, end_level)` and SHALL NOT emit `movement_started` (they are not new player orders, so an in-progress attack is not cancelled). An airborne attacker holding its air position SHALL never reserve a ground sub-slot or land. A blocked/occupied ground cell below an airborne attack stop SHALL NOT displace the hold — the attacker stops at its in-range stop position regardless of ground occupancy. A jumpjet landing move (not an air hold) arriving at a blocked destination SHALL glide immediately to the nearest free cell instead of entering the `WAIT` freeze-and-scatter cycle.

#### Scenario: Blocked attack stop stays in place
- **WHEN** an airborne attacker's stop position is on a blocked/occupied cell
- **THEN** it stops and holds at that position in the air, reserving no sub-slot, not landing, and not re-targeting away from its stop

#### Scenario: Blocked landing target settles at a free spot
- **WHEN** a jumpjet's landing move arrives at a blocked destination cell
- **THEN** it glides immediately to the nearest free cell and lands there instead of waiting frozen then bouncing

#### Scenario: Internal re-targets do not cancel the attack
- **WHEN** an airborne attacker re-targets (blocked arrival, scatter, nudge) mid-approach
- **THEN** its current attack target is preserved (`movement_started` is not re-emitted)

### Requirement: Zone retention on attack
When `MovementController.approach(target)` is called on a jumpjet, the unit SHALL attack from its current zone: grounded units walk to the target and attack on land, airborne units fly to the target and attack in the air. A unit in ASCENDING or DESCENDING SHALL ascend to the flight altitude before attacking. `CombatComponent._move_toward_target()` SHALL call `approach(target)`. Issuing an attack order while an airborne jumpjet is moving SHALL cancel the in-flight move (via `MovementController.cancel_move_retain_vertical()`) so the attack starts from the air zone instead of finishing the previous move's landing first.

#### Scenario: Grounded jumpjet attacks on land
- **WHEN** a grounded jumpjet is issued an attack order and moves to approach
- **THEN** it takes the walk path and attacks from the ground

#### Scenario: Airborne jumpjet attacks in air
- **WHEN** an airborne jumpjet is issued an attack order and moves to approach
- **THEN** it takes the fly path and attacks from the air at its flight altitude

#### Scenario: Attack interrupts an airborne move
- **WHEN** an airborne jumpjet is mid-flight on a move order (about to land) and receives an attack order
- **THEN** it cancels the landing, stays at the flight altitude, and attacks from the air

#### Scenario: Mid-transition attack ascends first
- **WHEN** a jumpjet in ASCENDING or DESCENDING is issued an attack order
- **THEN** it completes the ascent to the flight altitude before attacking
