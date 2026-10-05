## Purpose

CombatComponent resolves enemy targets into attack orders, tracks the current target, enforces per-weapon cooldowns, measures engagement range, applies hitscan damage through warhead armor multipliers, and coordinates movement toward out-of-range targets.
## Requirements
### Requirement: CombatComponent tracks attack target
CombatComponent SHALL maintain a `_target: Node3D` reference set via `set_target(entity, hold_ground := false)`. The optional `hold_ground` flag SHALL default to `false` so existing player-order and test call sites are unchanged. When `hold_ground` is true, CombatComponent SHALL treat the engagement as stand-and-shoot: it SHALL NOT issue chase/approach moves, and when the target's horizontal distance exceeds the longest weapon range on a `_physics_process` tick it SHALL clear the target and stop attacking. The target SHALL persist across `_physics_process` ticks until explicitly cleared via `clear_target()`, the target becomes invalid, or (hold-ground only) the target leaves weapon range.

#### Scenario: Set target
- **WHEN** `set_target(entity)` is called with a valid enemy entity
- **THEN** `_target` SHALL reference that entity

#### Scenario: Target becomes invalid
- **WHEN** `_target` is no longer a valid instance (freed node)
- **THEN** CombatComponent SHALL clear `_target` and stop attacking

#### Scenario: Target dies (health reaches zero)
- **WHEN** the target's HealthComponent emits `health_zero`
- **THEN** CombatComponent SHALL clear `_target` and stop attacking

#### Scenario: Hold-ground target leaves range
- **WHEN** the active target was set with `hold_ground = true` and its horizontal distance exceeds `max(weapon.attack_range) * CellUtil.CELL_SIZE`
- **THEN** CombatComponent SHALL clear `_target` and SHALL NOT call `_move_toward_target`

#### Scenario: Default hold_ground preserves chase
- **WHEN** `set_target(entity)` is called without the second argument (or with `false`) and the target is out of range
- **THEN** CombatComponent SHALL behave exactly as before this change (stop current move, approach toward the target)

### Requirement: Fire rate cooldown per weapon
CombatComponent SHALL maintain one cooldown timer per weapon mount group (a body-mounted weapon with no mount group is its own group). After a group fires, its timer SHALL be set to `weapon.rate_of_fire / 30.0` seconds, treating `rate_of_fire` as the original Tiberian Sun `ROF=` rearm-delay frames at the engine's 30 fps logic rate. A group SHALL NOT fire while its cooldown timer is positive. Groups evaluate independently, so a unit with several weapons or several turret mounts fires each on its own schedule.

#### Scenario: Fire rate timing
- **WHEN** a group whose weapon has `rate_of_fire = 20` fires
- **THEN** the next shot from that group is delayed by 0.667 seconds (20/30)

#### Scenario: Cooldown ticks down
- **WHEN** `_physics_process(delta)` runs with a positive group cooldown
- **THEN** the cooldown decreases by `delta`

#### Scenario: Independent group schedules
- **WHEN** a unit has two mount groups with different weapons
- **THEN** each group fires on its own cooldown without waiting for the other

### Requirement: Range checking
CombatComponent SHALL check if the target is within firing range before firing. Range SHALL be calculated as `weapon.attack_range * CellUtil.CELL_SIZE` world units, measured on the horizontal (XZ) plane — the Y (altitude) component SHALL be ignored so hovering or elevated attackers are not pushed out of range by vertical separation. The measured distance SHALL be from the attacker to the target's **effective target point**: when the target is a structure (`StatsComponent.is_structure()` is true) and has a `FoundationComponent`, the effective target point SHALL be the nearest point on the target's foundation footprint to the attacker (the clamped projection of the attacker's position onto the footprint rectangle); otherwise it SHALL be the target's `global_position`. For weapons mounted on a `yaw_free` turret socket, being in range additionally requires turret alignment per the `turrets` capability (in-range but turret not aligned holds fire for that tick while the turret slews). For weapons that are body-mounted or mounted on a `yaw_free = false` socket, being in range additionally requires body alignment per the `combat-facing` capability.

#### Scenario: Target in range
- **WHEN** the target's horizontal distance (ignoring Y) is less than or equal to `attack_range * CELL_SIZE`
- **THEN** CombatComponent MAY fire (subject to cooldown and, for the mounting, turret or body alignment)

#### Scenario: Target out of range
- **WHEN** the target's horizontal distance (ignoring Y) exceeds `attack_range * CELL_SIZE`
- **THEN** CombatComponent SHALL issue a move command toward the target position instead of firing

#### Scenario: Building edge in range fires while center is out of range
- **WHEN** the target is a building whose foundation-footprint center is beyond `attack_range * CELL_SIZE` but whose nearest footprint edge is within it
- **THEN** CombatComponent SHALL treat the building as in range and MAY fire (subject to cooldown and alignment), matching Tiberian Sun's rule that a building is engaged while any foundation cell is in range

#### Scenario: Building center in range still fires
- **WHEN** the target is a building whose foundation-footprint center is within `attack_range * CELL_SIZE`
- **THEN** CombatComponent SHALL treat the building as in range (its nearest footprint point is at least as close as the center)

#### Scenario: Single-cell building measured as a point
- **WHEN** the target is a 1x1 building (no `FoundationComponent`; footprint center equals the cell center)
- **THEN** CombatComponent SHALL measure to the target's `global_position`, unchanged from before this change

#### Scenario: Non-building target unchanged
- **WHEN** the target is a unit without a `FoundationComponent`
- **THEN** CombatComponent SHALL measure to the target's `global_position` exactly as before this change

#### Scenario: Multi-cell non-structure measured as a point
- **WHEN** the target is not a structure but carries a `FoundationComponent` (possible because `EntityFactory` attaches one for any `foundation != 1x1`)
- **THEN** CombatComponent SHALL measure to the target's `global_position`, matching `GuardComponent`'s classifier

#### Scenario: Vertical separation ignored
- **WHEN** a unit hovers or flies at `4.08` world units above a target that is within `attack_range * CELL_SIZE` horizontally
- **THEN** CombatComponent SHALL treat the target as in range and fire

#### Scenario: Airborne attacker engages ground target
- **WHEN** a jumpjet hovering at its flight altitude attacks a ground target within horizontal range
- **THEN** the target is in range regardless of the altitude difference

#### Scenario: In range but turret not aligned holds fire
- **WHEN** a `yaw_free` mount has an in-range target outside its turret angle tolerance
- **THEN** CombatComponent SHALL NOT fire that tick and the turret yaws toward the target instead

#### Scenario: In range but body not facing holds fire
- **WHEN** a body-mounted or fixed-socket weapon has an in-range target outside the body facing tolerance with no live move leg
- **THEN** CombatComponent SHALL NOT fire that tick and the body yaws toward the target instead

### Requirement: Weapon dispatch and damage
When firing, CombatComponent SHALL first resolve `weapon.projectile` through the GlobalRules projectile registry. If the id resolves to a `ProjectileData`, CombatComponent SHALL instantiate `Projectile.tscn`, configure it with the projectile data, weapon, shooter, and target, spawn it at the firing mount's muzzle transform, parent it to the match World root, and SHALL NOT apply direct damage. The muzzle transform SHALL be the firing socket's world transform composed with the socket yaw and extended by the socket `barrel_length` for turret-mounted weapons, or the entity transform offset by `WeaponData.fire_offset` for body-mounted weapons (see the `turrets` capability). If the id is empty or unresolvable, CombatComponent SHALL apply damage directly (legacy hitscan): the weapon's base damage multiplied by the warhead armor multiplier for the target's armor type, clamped to GlobalRules `[min_damage, max_damage]`, then call `target.get_node("HealthComponent").take_damage(final_damage, weapon.warhead)`.

#### Scenario: Resolvable projectile spawns instead of direct damage
- **WHEN** a weapon with `projectile = "Invisible"` fires at an enemy in range
- **THEN** a projectile node is spawned and configured, and the target's HealthComponent is not modified by CombatComponent directly

#### Scenario: Spawn at socket muzzle
- **WHEN** a turret-mounted weapon fires
- **THEN** the projectile's initial position is the firing socket's world transform extended by `barrel_length`, rotated by the current socket yaw

#### Scenario: Spawn at body muzzle
- **WHEN** a body-mounted weapon fires
- **THEN** the projectile's initial position is the entity transform offset by `WeaponData.fire_offset`

#### Scenario: Unresolvable projectile falls back to hitscan
- **WHEN** a weapon's projectile id does not resolve in the registry (or is empty)
- **THEN** damage is applied directly with the full legacy math

#### Scenario: Fallback damage applied with armor
- **WHEN** a weapon with `damage = 100` and warhead "SA" fires via the fallback at a target with `armor = "heavy"` (SA multiplier 0.25)
- **THEN** the target's HealthComponent receives `take_damage(25, "SA")`

#### Scenario: Armor-piercing vs heavy
- **WHEN** a weapon with `damage = 100` and warhead "AP" fires at a target with `armor = "heavy"` (AP multiplier 1.00)
- **THEN** the target's HealthComponent SHALL receive `take_damage(100, "AP")`

#### Scenario: Fallback minimum damage floor
- **WHEN** the fallback-computed damage would be below `min_damage` (1)
- **THEN** the applied damage is clamped to 1

#### Scenario: Fallback maximum damage cap
- **WHEN** the fallback-computed damage would exceed `max_damage` (1000)
- **THEN** the applied damage is clamped to 1000

#### Scenario: Fallback zero-damage armor pairing
- **WHEN** a warhead's multiplier for the target's armor is 0.0
- **THEN** the target's HealthComponent receives `take_damage(0, warhead)` and takes no damage

#### Scenario: Fallback unknown warhead or armor
- **WHEN** the weapon's warhead id or the target's armor id is not in the GlobalRules registries
- **THEN** fallback damage is applied with full multiplier 1.0

#### Scenario: Fallback target has no HealthComponent
- **WHEN** the target entity has no HealthComponent child
- **THEN** CombatComponent skips the damage call without error

### Requirement: weapon_fired signal
CombatComponent SHALL emit `weapon_fired(weapon: WeaponData, target: Node3D)` after each successful weapon dispatch, whether the weapon spawned a projectile or applied fallback hitscan damage. For an entity engagement `target` SHALL be that entity; for a ground engagement `target` SHALL be `null`. Listeners MUST tolerate a null target.

#### Scenario: Signal emitted on fire
- **WHEN** CombatComponent fires a weapon
- **THEN** `weapon_fired` is emitted with the weapon data and target reference

#### Scenario: Signal emitted on projectile dispatch
- **WHEN** a weapon dispatches a projectile instead of applying fallback damage
- **THEN** `weapon_fired` is still emitted exactly once

#### Scenario: Signal emitted with a null target on ground engagement
- **WHEN** CombatComponent fires while engaged with a ground position rather than an entity
- **THEN** `weapon_fired` is emitted once with the weapon data and a null target, without error

### Requirement: Movement integration
CombatComponent SHALL connect to `MovementController.arrived` signal on first attack engagement. When `arrived` fires, the next `_physics_process` tick SHALL re-evaluate range and fire if in range. The approach destination SHALL be computed from the target's effective target point (nearest foundation-footprint point for a building, `global_position` otherwise), and the post-relocation in-range re-check SHALL measure to that same point.

#### Scenario: Unit moves toward target
- **WHEN** target is out of range and MC is idle, or the current move was just superseded by a fresh attack order
- **THEN** CombatComponent SHALL compute a stop position at `weapon.attack_range * CELL_SIZE` distance from the target's effective target point, on the attacker's side of that point, and call `mc.set_target_position(stop_pos)`

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
- **WHEN** CombatComponent issues a move to close distance to target (sets `_combat_move = true` before calling `mc.set_target_position()`)
- **THEN** MovementController emits `movement_started`, CombatComponent SHALL detect `_combat_move`, skip clearing attack state, and continue attacking after arrival

### Requirement: Attack cancels player move
Issuing an attack order SHALL cancel a ground unit's in-progress player move and engage the target. A ground unit SHALL halt via `MovementController.stop()` (a no-op when already idle); an airborne jumpjet SHALL keep its air zone via `cancel_move_retain_vertical()`. When the target is out of range, the old move destination SHALL be dropped immediately and a new approach path issued in the same frame, so the unit starts moving toward the target without finishing the old move.

#### Scenario: Moving ground unit attacks in-range target
- **WHEN** a ground unit is moving on a player move order and receives an attack order on a target already within weapon range
- **THEN** the unit SHALL stop (settle to its sub-slot) and fire from its current position instead of continuing along the old move path

#### Scenario: Moving ground unit attacks out-of-range target
- **WHEN** a ground unit is moving on a player move order and receives an attack order on a target outside weapon range
- **THEN** the old move destination SHALL be abandoned and the unit SHALL move along a fresh approach path to within weapon range of the target, starting in the same frame as the attack order

#### Scenario: Idle unit receives attack order
- **WHEN** an idle unit receives an attack order
- **THEN** `MovementController.stop()` is a no-op and behavior SHALL be unchanged (fire if in range, approach otherwise)

#### Scenario: Airborne jumpjet attack interrupts move
- **WHEN** an airborne jumpjet moving on a player move order receives an attack order
- **THEN** the in-flight move SHALL be cancelled via `cancel_move_retain_vertical()` and the jumpjet SHALL attack from its air zone (no change to existing airborne behavior)

### Requirement: movement_started signal on MovementController
MovementController SHALL emit `signal movement_started` at the beginning of `set_target_position()`, before any pathfinding or movement begins.

#### Scenario: Signal emitted on move
- **WHEN** `set_target_position()` is called with a valid position
- **THEN** `movement_started` SHALL be emitted before movement begins

### Requirement: is_moving getter on MovementController
MovementController SHALL expose `func is_moving() -> bool` that returns `true` when `_state != State.IDLE`.

#### Scenario: Unit is idle
- **WHEN** MovementController `_state` is `IDLE`
- **THEN** `is_moving()` SHALL return `false`

#### Scenario: Unit is moving
- **WHEN** MovementController `_state` is `MOVING` or `ROTATING`
- **THEN** `is_moving()` SHALL return `true`

### Requirement: Weapon fire sound
On each shot in `_fire_weapon`, CombatComponent SHALL delegate the comma-separated `WeaponData.sound_report` list to `AudioManager.play_report`, which plays one audio id at the firing unit's world position, selecting the first entry whose live copy count is below the rotation threshold (stacking-driven selection; see the audio-system spec for the full selection requirement). An empty `sound_report` SHALL play nothing. A missing or unknown id SHALL log a warning and fall through to the next entry (graceful failure).

#### Scenario: Fire plays a report sound
- **WHEN** a weapon with `sound_report = "INFGUN3,GOSTGUN1"` fires while unstacked
- **THEN** the first listed entry SHALL play at the firing unit's position

#### Scenario: Empty report is silent
- **WHEN** a weapon with an empty `sound_report` fires
- **THEN** no sound SHALL play

#### Scenario: Missing id is skipped
- **WHEN** a listed report id is not in the audio cache
- **THEN** a warning SHALL be logged and selection SHALL fall through to the next entry (silent only when no entry resolves)

### Requirement: Powered-down structures do not fire
CombatComponent SHALL NOT acquire targets or fire while its entity's `PowerComponent` reports offline (`is_online == false`). The check SHALL be a local gate in the combat processing tick and SHALL NOT interfere with existing target-state handling: the current target SHALL be retained so power restoration resumes engagement. Entities without a `PowerComponent` SHALL be unaffected.

#### Scenario: Offline structure holds fire
- **WHEN** a `powered = true` defense structure is offline and an enemy is in range
- **THEN** CombatComponent fires no weapon and issues no approach move

#### Scenario: Power restoration resumes engagement
- **WHEN** the structure comes back online while a target is still set
- **THEN** CombatComponent resumes normal range/cooldown evaluation against that target

#### Scenario: Units without PowerComponent unaffected
- **WHEN** a combat entity has no `PowerComponent`
- **THEN** firing behavior is identical to the pre-change behavior

### Requirement: Weapon rate of fire time base from rules
`CombatComponent` SHALL convert a weapon's `rate_of_fire` (logic ticks) to seconds using `GlobalRules.logic_fps`, rather than a compile-time frame-rate constant. The weapon cooldown SHALL be `rate_of_fire / logic_fps` seconds.

#### Scenario: ROF conversion
- **WHEN** the active rules set `logic_fps = 30.0` and the weapon has `rate_of_fire = 30`
- **THEN** the firing cooldown is 1.0 second

#### Scenario: No rules fallback
- **WHEN** no GlobalRules are active
- **THEN** the conversion falls back to 30 logic ticks per second without error

### Requirement: Veteran ROF shortens reload delay
When setting a weapon group's cooldown after firing, `CombatComponent` SHALL divide the base cooldown by `GlobalRules.get_veteran_rof_multiplier(veteran_level)`. A rookie (`veteran_level = 0`) SHALL use the base cooldown unchanged. The bonus SHALL apply from the next shot after a promotion.

#### Scenario: Veteran reloads faster
- **WHEN** a veteran unit with `veteran_rof = 0.20` and a 1.0 s base cooldown fires
- **THEN** the cooldown is set to 1.0 / 1.20 s

#### Scenario: Rookie uses base cooldown
- **WHEN** a rookie unit fires
- **THEN** the cooldown equals the base rate-of-fire conversion

#### Scenario: Bonus applies after promotion
- **WHEN** a unit is promoted mid-engagement
- **THEN** its subsequent cooldowns use the veteran ROF multiplier

### Requirement: Weapon muzzle FX
On each successful weapon dispatch, `CombatComponent` SHALL play `WeaponData.muzzle_fx` through `FxSystem.play` at the weapon's world muzzle transform. The muzzle transform SHALL be the same one used for projectile spawn: the firing socket's world transform composed with socket yaw and extended by `barrel_length` for turret-mounted weapons, or the entity transform composed with `WeaponData.fire_offset` (entity-local, so the offset rotates with the body) for body-mounted weapons. A `null` `muzzle_fx` SHALL play nothing. The effect SHALL play exactly once per shot, whether the weapon spawned a projectile or applied fallback hitscan damage. Fog gating is delegated to `FxSystem` (see the `fx-system` capability).

#### Scenario: Turret-mounted muzzle FX at the socket
- **WHEN** a turret-mounted weapon with a non-null `muzzle_fx` fires
- **THEN** the effect is played at the firing socket's muzzle world transform

#### Scenario: Body-mounted muzzle FX at the body muzzle
- **WHEN** a body-mounted weapon with a non-null `muzzle_fx` fires
- **THEN** the effect is played at the entity transform composed with `WeaponData.fire_offset`

#### Scenario: Body muzzle follows the body orientation
- **WHEN** a rotated body-mounted weapon with a non-null `fire_offset` fires
- **THEN** the muzzle is the entity transform applied to the local offset, so the offset follows the body's facing rather than a fixed world axis

#### Scenario: No muzzle FX is silent
- **WHEN** a weapon whose `muzzle_fx` is `null` fires
- **THEN** no effect node is spawned

#### Scenario: Muzzle FX plays once per shot
- **WHEN** a weapon with a non-null `muzzle_fx` fires
- **THEN** exactly one effect is played for that shot

#### Scenario: Muzzle FX on both dispatch paths
- **WHEN** a weapon with a non-null `muzzle_fx` fires via projectile spawn, and another fires via fallback hitscan damage
- **THEN** both shots play the muzzle effect exactly once

### Requirement: Force-fire order generation
When `OrderResult.MOD_FORCE_ATTACK` is held and the entity has at least one weapon, `CombatComponent.get_order_for_target()` SHALL return an ATTACK `OrderResult` regardless of the target's ownership or presence: an allied entity, an own entity, a neutral entity (`player_id < 0`), an entity with no `StatsComponent`, and an absent entity target (ground) are all accepted. Without the modifier, an ATTACK `OrderResult` SHALL be produced only for a hostile entity (`player_id >= 0` and `PlayerManager.is_enemy`). An entity with no weapons SHALL produce no order under either case.

#### Scenario: Ground target under force-fire
- **WHEN** an armed entity resolves a null target with `MOD_FORCE_ATTACK` held
- **THEN** `CombatComponent` SHALL return an ATTACK `OrderResult` carrying the requested ground position

#### Scenario: Ground target without force-fire
- **WHEN** an armed entity resolves a null target without `MOD_FORCE_ATTACK`
- **THEN** `CombatComponent` SHALL return no order

#### Scenario: Allied entity under force-fire
- **WHEN** an armed entity resolves an allied or own entity with `MOD_FORCE_ATTACK` held
- **THEN** `CombatComponent` SHALL return an ATTACK `OrderResult` on that entity

#### Scenario: Allied entity without force-fire
- **WHEN** an armed entity resolves an allied or own entity without `MOD_FORCE_ATTACK`
- **THEN** `CombatComponent` SHALL return no order

#### Scenario: Neutral entity under force-fire
- **WHEN** an armed entity resolves a neutral entity (`player_id < 0`) with `MOD_FORCE_ATTACK` held
- **THEN** `CombatComponent` SHALL return an ATTACK `OrderResult` on that entity

#### Scenario: Hostile entity without force-fire is unchanged
- **WHEN** an armed entity resolves a hostile entity without `MOD_FORCE_ATTACK`
- **THEN** `CombatComponent` SHALL return an ATTACK `OrderResult`, exactly as before this change

#### Scenario: Unarmed entity never force-fires
- **WHEN** an entity with an empty `weapons` array resolves any target with `MOD_FORCE_ATTACK` held
- **THEN** `CombatComponent` SHALL return no order

### Requirement: Ground engagement
`CombatComponent` SHALL support an engagement keyed to a world position with no entity target, entered via a ground-target setter alongside `set_target()`. The position SHALL be the source of truth for range, body facing, turret slew, and approach: `_effective_target_pos()` SHALL return the ordered position when no entity target is held, and the entity's foundation-nearest point otherwise. The engagement SHALL be entered in the same state as an entity engagement (stop current move, approach if out of range) and SHALL fire on every cooldown while in range, repeating without being re-issued. It SHALL NOT self-terminate: a position never becomes invalid and never reaches zero health, so the only exits are a player move, the Stop command, or the shooter's death. `is_engaged()` SHALL report true for both an entity engagement and a ground engagement.

#### Scenario: Ground engagement fires in range
- **WHEN** an entity with a ground engagement is within weapon range, facing is aligned and cooldown has elapsed
- **THEN** the entity SHALL fire at the ordered position

#### Scenario: Ground engagement repeats without re-issue
- **WHEN** a ground engagement stays in range across several cooldown periods with no further player input
- **THEN** the entity SHALL fire again on each elapsed cooldown, the engagement still being active

#### Scenario: Ground engagement approaches when out of range
- **WHEN** a ground engagement is ordered at a position beyond weapon range
- **THEN** the entity SHALL issue an approach move and fire once the ordered position enters range

#### Scenario: Ground engagement survives arbitrary ticks
- **WHEN** no player order has been issued for many `_physics_process` ticks during a ground engagement
- **THEN** the engagement SHALL remain active and `is_engaged()` SHALL remain true

#### Scenario: Player move ends the ground engagement
- **WHEN** a ground engagement is active and `MovementController` emits `movement_started` from a player-initiated move
- **THEN** `CombatComponent` SHALL clear the engagement and stop firing, per the existing player-move-cancels-attack requirement

#### Scenario: Stop ends the ground engagement
- **WHEN** a ground engagement is active and the player issues the Stop command
- **THEN** `CombatComponent` SHALL clear the engagement, the entity SHALL become idle, and `GuardComponent` SHALL be free to acquire on its next scan

#### Scenario: is_engaged is true without an entity target
- **WHEN** a ground engagement is active and `_target` is null
- **THEN** `is_engaged()` SHALL return true while `get_target()` returns null

### Requirement: Cell occupant damage without an entity target
When a shot resolves with **no** entity target — a ground engagement's hitscan fallback or projectile detonation — the system SHALL resolve the occupant of the impact cell: the entity nearest the impact point in three dimensions that has a `HealthComponent` and whose `entity_type` is `INFANTRY`, `VEHICLE`, `AIRCRAFT` or `BUILDING`. Candidates SHALL come from the impact cell's `SpatialHash` grid entries, falling back to the building-footprint registry when the cell holds none — a building is indexed in the grid only at its centre cell, so an edge cell of a large structure must still resolve its occupant. The shooter SHALL be excluded. Allied and neutral occupants SHALL be eligible — only the shooter is exempt. When no such occupant exists, no entity damage SHALL be applied. Shots that do have an entity target SHALL apply damage exactly as before this change: the target's `HealthComponent`, or a skip when it has none.

A ground shot with no victim SHALL resolve both the occupant and the cell overlays at one point — the ordered position — so a projectile that overshoots by a frame can never damage an entity in one cell and a bridge, ice sheet or tiberium in the next.

#### Scenario: Enemy walks into the cell after the order
- **WHEN** a force-fire shot is ordered at an empty cell and an enemy occupies that cell before impact
- **THEN** that enemy SHALL take the weapon's damage

#### Scenario: Ally in the cell takes the hit
- **WHEN** a force-fire shot resolves over a cell occupied by an allied entity
- **THEN** the allied entity SHALL take the weapon's damage

#### Scenario: Shooter is exempt
- **WHEN** a force-fire shot resolves over the cell the shooter itself occupies and no other qualifying occupant is present
- **THEN** the shooter SHALL take no damage

#### Scenario: Empty cell applies no entity damage
- **WHEN** a force-fire shot resolves over a cell with no qualifying occupant
- **THEN** no entity SHALL take damage from the shot

#### Scenario: Edge cell of a large building resolves its occupant
- **WHEN** a force-fire shot resolves over a footprint cell of a building whose centre lies in a different cell
- **THEN** that building SHALL take the weapon's damage

#### Scenario: Terrain and overlay entities are never occupants
- **WHEN** a force-fire shot resolves over a cell occupied only by a bridge or ice entity
- **THEN** the occupant pass SHALL apply no entity damage; bridge and ice are handled by the cell-overlay pass

#### Scenario: Entity-targeted shots are unchanged
- **WHEN** a shot resolves with an entity target that has no `HealthComponent`
- **THEN** the damage call SHALL be skipped without error and no occupant SHALL be substituted

### Requirement: Cell overlay damage
Whenever a shot resolves at a position — entity target or ground — the system SHALL apply the warhead's cell-overlay damage to overlays standing in the impact cell, each gated on its own flag:

- a **bridge span** SHALL take damage only when `WarheadData.can_damage_walls` is set and the span is a destructible LOW normal piece; end pieces and every high-bridge cell SHALL take no damage from any warhead;
- **ice** SHALL take damage only when `WarheadData.can_damage_walls` is set and the game declares the `breakable_ice` feature; without the feature ice SHALL take no warhead damage;
- **tiberium** SHALL take damage only when `WarheadData.can_damage_tiberium` is set.

Overlays failing their gate SHALL take no damage. An overlay that is itself the shot's entity target SHALL be damaged exactly once.

#### Scenario: Tiberium damaged under its warhead flag
- **WHEN** a shot resolves over a tiberium cell with a warhead whose `can_damage_tiberium` is set
- **THEN** the tiberium SHALL take damage

#### Scenario: Tiberium untouched without its warhead flag
- **WHEN** a shot resolves over a tiberium cell with a warhead whose `can_damage_tiberium` is clear
- **THEN** the tiberium SHALL take no damage

#### Scenario: Bridge collateral under an entity-targeted shot
- **WHEN** a shot with an entity target detonates over a cell holding a destructible LOW bridge span, with a warhead whose `can_damage_walls` is set
- **THEN** the span SHALL take damage in addition to the entity target

#### Scenario: Ice untouched when the feature is off
- **WHEN** a shot resolves over an ice cell with a warhead whose `can_damage_walls` is set but the game does not declare `breakable_ice`
- **THEN** the ice SHALL take no damage

#### Scenario: Overlay damaged exactly once when it is the target
- **WHEN** an overlay entity is itself the shot's entity target and its warhead gate passes
- **THEN** its health SHALL decrease by a single hit, not two

