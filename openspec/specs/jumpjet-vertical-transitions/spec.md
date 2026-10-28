# jumpjet-vertical-transitions Specification

## Purpose

Jumpjet units (hybrid walk/fly infantry like the GDI Jumpjet Infantry) ascend and descend between the ground and a configurable flight altitude instead of snapping. Movement splits `move_speed` between ascending and forward flight when both happen at once, and move orders fly to the destination then land there. Attacks retain the current zone: grounded units attack on land, airborne units attack in the air.

## Requirements

### Requirement: Configurable jumpjet target height
The `Locomotor` resource SHALL provide a `jumpjet_target_height: float` field expressed in terrain height units (each unit = `TerrainSystem.HEIGHT_STEP` world units), defaulting to `6.0`. `MovementController` SHALL use `jumpjet_target_height * HEIGHT_STEP` as the jumpjet's flight altitude, independent of `GlobalRules.hover_height` and `hover_height_override`.

#### Scenario: Default target height
- **WHEN** a Jumpjet Locomotor resource is created without overriding `jumpjet_target_height`
- **THEN** the jumpjet's flight altitude SHALL be `6.0 * HEIGHT_STEP` world units above terrain

#### Scenario: Configurable target height
- **WHEN** a Jumpjet Locomotor resource sets `jumpjet_target_height = 3.0`
- **THEN** the jumpjet's flight altitude SHALL be `3.0 * HEIGHT_STEP` world units above terrain

### Requirement: Vertical state machine
`MovementController` SHALL maintain a vertical state for jumpjet units from the set `{GROUND, ASCENDING, AIR, DESCENDING}`. The unit's Y position SHALL move toward the target altitude (terrain for GROUND/DESCENDING, terrain + flight altitude for AIR/ASCENDING) at `move_speed` per second, not snap. ASCENDING SHALL transition to AIR, and DESCENDING SHALL transition to GROUND, on reaching the target altitude.

#### Scenario: Ascending from ground
- **WHEN** a grounded jumpjet is ordered to fly
- **THEN** it enters ASCENDING and its Y increases toward the flight altitude, then enters AIR

#### Scenario: Descending to ground
- **WHEN** an airborne jumpjet descends to land
- **THEN** it enters DESCENDING and its Y decreases toward terrain height, then enters GROUND

#### Scenario: No snapping on transition
- **WHEN** a jumpjet transitions between GROUND and AIR
- **THEN** its Y never changes by more than `move_speed * delta` in a single frame

### Requirement: Shared speed between ascending and forward flight
When a jumpjet is ascending or descending while also moving forward, `MovementController` SHALL split `move_speed` so each axis receives 50%. A pure vertical transition with no forward movement SHALL use full `move_speed` vertically, and cruising flight (AIR) SHALL use full `move_speed` horizontally.

#### Scenario: Ascending while moving forward
- **WHEN** a jumpjet ascends and flies forward simultaneously
- **THEN** both the vertical and horizontal displacement SHALL be `move_speed * 0.5 * delta` per frame

#### Scenario: Pure vertical transition
- **WHEN** a jumpjet descends to land without moving forward
- **THEN** the vertical displacement SHALL be `move_speed * delta` per frame

#### Scenario: Cruising flight
- **WHEN** a jumpjet flies forward at its flight altitude
- **THEN** the horizontal displacement SHALL be `move_speed * delta` per frame

### Requirement: Move order is walk-first with ground default
A jumpjet's default zone SHALL be GROUND: it spawns and idles on the ground, and move orders (not attack approaches) SHALL walk on the ground like infantry when the target is reachable on foot within `jumpjet_fly_distance`. It SHALL only fly when the walk path is empty or the straight-line distance exceeds `jumpjet_fly_distance`; a fly move SHALL go straight to the destination cell and then land there (descending after reaching the target) rather than descending early and walking the rest. When the destination cell is the same cell the jumpjet already occupies, an empty walk path SHALL NOT trigger flight — the jumpjet settles into its booked sub-slot on the ground instead of taking off.

#### Scenario: Move order to reachable target walks
- **WHEN** a grounded jumpjet is issued a move order to a reachable cell within `jumpjet_fly_distance`
- **THEN** it pathfinds on foot, stays in GROUND, and uses infantry waypoint handling

#### Scenario: Move order to far target flies then lands
- **WHEN** a grounded jumpjet is issued a move order to a cell beyond `jumpjet_fly_distance`
- **THEN** it ascends, flies a straight line to the target cell, then descends and lands there

#### Scenario: Move order to unreachable target flies then lands
- **WHEN** a grounded jumpjet is issued a move order no walk path can reach (e.g. across water)
- **THEN** it flies a straight line to the target cell, then descends and lands there

#### Scenario: Same-cell move settles instead of flying
- **WHEN** a grounded jumpjet is issued a move order to its own current cell (e.g. rallying into a packed spawn)
- **THEN** it does not take off; it stays in GROUND and settles into an infantry sub-slot at that cell

#### Scenario: Airborne move order lands at destination
- **WHEN** an airborne jumpjet is issued a move order
- **THEN** it flies to the target cell, then enters DESCENDING and lands on the ground at that cell

#### Scenario: Default zone is ground
- **WHEN** a jumpjet spawns or finishes all orders
- **THEN** its vertical zone is GROUND and it stands on the terrain

### Requirement: Ground booking on walk, landing booking on fly
A jumpjet using its walk mode SHALL perform normal infantry booking: reserve an infantry sub-slot at the target cell and use occupancy-aware blocked-cell pathfinding with the jumpjet's `terrain_speeds` and `climb_tolerance`. A jumpjet flying (AIR/ASCENDING/DESCENDING) SHALL NOT reserve cells or sub-slots along its air path, which SHALL be a straight line to the target. A fly move that will land (issued without `keep_zone`) SHALL reserve an infantry sub-slot at its landing cell when the order is issued, and descend onto that sub-slot position rather than the cell center. When the landing cell is already occupied at order time, the landing move SHALL relocate to the nearest free cell before reserving, so it never flies into a blocked cell.

#### Scenario: Walk mode books a sub-slot
- **WHEN** a grounded jumpjet walks to a reachable target
- **THEN** it reserves an infantry sub-slot at the target cell like other infantry

#### Scenario: Air attack flies without booking
- **WHEN** a jumpjet flies to attack (`keep_zone = true`)
- **THEN** it reserves no sub-slots or cells and takes a straight-line air path

#### Scenario: Landing move books a sub-slot
- **WHEN** a jumpjet is issued a move order that will fly then land (airborne move or far/unreachable target)
- **THEN** it reserves an infantry sub-slot at the landing cell and descends onto that sub-slot, not the cell center

#### Scenario: Landing move to an occupied cell relocates before flying
- **WHEN** a jumpjet is issued a landing fly move whose destination cell is already occupied
- **THEN** it books its sub-slot at the nearest free cell instead, and flies there

### Requirement: Landing moves fly to the booked sub-slot; attackers spread dynamically
A landing fly move SHALL fly straight to the exact sub-slot reserved at its landing cell, with no lateral offset — separation between several jumpjets on the same landing order comes from the sub-slot booking itself. An airborne attacker SHALL take the shortest air path to the nearest point at weapon range, then nudge off nearby airborne jumpjets via a bounded dynamic repulsion (`CombatComponent._air_repulsion`, capped at `MIN_AIR_SEPARATION` and a fraction of the weapon range) rather than a fixed ring position. An attacker's stop position SHALL be clamped within its weapon range so it fires on arrival without bouncing back to re-approach. Each attacker keeps its settled hover spot while firing.

#### Scenario: Landing waypoint is the booked sub-slot
- **WHEN** a jumpjet is issued a fly order that will land
- **THEN** its fly waypoint is exactly the booked sub-slot position, with no lateral offset

#### Scenario: Airborne attacker takes the shortest approach
- **WHEN** an airborne jumpjet approaches an attack target
- **THEN** it flies the shortest air path to the nearest point at weapon range on the approach side, not around to the far side

#### Scenario: Airborne attackers nudge apart dynamically
- **WHEN** two or more airborne jumpjets attack the same target
- **THEN** each settles on its own spot near the approach point, pushed away from airborne jumpjets closer than `MIN_AIR_SEPARATION`, and stays within attack range

#### Scenario: Attack stop stays inside weapon range
- **WHEN** an airborne jumpjet's repulsion would push its stop position beyond weapon range
- **THEN** the stop position is clamped back onto the range circle, so the jumpjet fires on arrival instead of bouncing away

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

### Requirement: Attack order retains altitude
A jumpjet completing an attack approach (`keep_zone = true`) SHALL remain hovering at its flight altitude above the destination rather than landing, so it can keep engaging from the air.

#### Scenario: Airborne attack hovers on arrival
- **WHEN** an airborne jumpjet completes an attack approach move
- **THEN** it stays at the flight altitude (AIR) instead of landing

### Requirement: New order while descending ascends back
If a jumpjet receives any new order while in the DESCENDING state, it SHALL interrupt the descent and ascend back to the air zone before processing the new order's movement.

#### Scenario: Descending interrupt
- **WHEN** a descending jumpjet is issued a new move order
- **THEN** it switches to ASCENDING and returns to the flight altitude

### Requirement: Airborne terrain speed exemption
`MovementController._terrain_speed_factor()` SHALL return `1.0` for a jumpjet that is not on the ground, so terrain type does not slow an airborne unit.

#### Scenario: Flying over rough terrain
- **WHEN** an airborne jumpjet passes over a rough cell that would slow its walking speed
- **THEN** its movement speed is unaffected by the terrain multiplier

### Requirement: Jumpjet attacks land and air targets
The GDI Jumpjet Infantry entity SHALL carry a weapon (JumpCannon) so `CombatComponent` can generate attack orders. Its weapon SHALL be able to target both ground and air entities regardless of the jumpjet's altitude.

#### Scenario: Ground target
- **WHEN** a jumpjet unit is selected and an enemy ground entity is the order target
- **THEN** an ATTACK order SHALL be generated

#### Scenario: Air target
- **WHEN** a jumpjet unit is selected and an enemy aircraft entity is the order target
- **THEN** an ATTACK order SHALL be generated
