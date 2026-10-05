## Purpose

Runtime projectile nodes close the gap between weapon dispatch and damage application: when a weapon's projectile id resolves through the GlobalRules registry, a `ProjectileController` node flies (or teleport-detonates) from the muzzle to the target and delivers its damage payload through the `HitboxComponent` → `HealthComponent` pipeline, replacing instant hitscan application for resolvable ids while preserving the legacy damage math. Flight behavior is data-driven from `ProjectileData` flags, mirroring how `MovementController` resolves locomotors.

## Requirements

### Requirement: Projectile node lifecycle

The system SHALL provide a `Projectile.tscn` scene with a `ProjectileController` script. `CombatComponent` SHALL instantiate it when firing a weapon whose projectile id resolves, configure it with the projectile data, weapon, shooter, and target, and parent it to the match World root (falling back to the shooter's parent when no World root exists). The projectile SHALL free itself after detonation, after flying its maximum range, or after reaching the last known position of a target that died in flight. It SHALL emit `impacted(position: Vector3)` at the detonation point.

#### Scenario: Spawn and self-free on detonation

- **WHEN** a projectile detonates on a valid target
- **THEN** damage flows through `HitboxComponent` to `HealthComponent`, `impacted` is emitted with the detonation position, and the node frees itself

#### Scenario: Target dies in flight

- **WHEN** the projectile's target dies before impact
- **THEN** the projectile continues to the target's last known position, detonates or frees there, and never crashes on a freed reference

#### Scenario: Projectile is parented under the match World root

- **WHEN** a weapon fires a resolvable projectile during a match
- **THEN** the projectile node is a descendant of the match World root

#### Scenario: Map change cleans up

- **WHEN** a match is replaced while projectiles are in flight
- **THEN** the projectiles are released with the outgoing match's World root and no orphan nodes remain

### Requirement: Projectile damage payload
A projectile SHALL implement `get_damage_info()` returning `{amount: int, type: String, source: Node3D, position: Vector3}`. `type` SHALL be the firing weapon's warhead id, `source` SHALL be the shooter node, and `position` SHALL be the detonation position. `amount` SHALL be computed at detonation as the weapon's base damage multiplied by the warhead armor multiplier for the victim's armor type, clamped to GlobalRules `[min_damage, max_damage]`, mirroring the existing hitscan damage math.

#### Scenario: Payload contract keys
- **WHEN** `get_damage_info()` is called on a live projectile
- **THEN** the returned dictionary contains non-negative `amount`, a non-empty `type` matching the weapon's warhead, a valid `source` reference, and a `position`

#### Scenario: Armor multiplier applied by projectile
- **WHEN** a projectile carrying weapon damage 100 with warhead "SA" detonates on a target with armor "heavy" (SA multiplier 0.25)
- **THEN** the payload `amount` is 25 and the victim's HealthComponent receives 25 damage

#### Scenario: Damage clamps
- **WHEN** the computed damage falls below `min_damage` or exceeds `max_damage`
- **THEN** the applied damage is clamped to the respective bound

#### Scenario: Zero armor multiplier
- **WHEN** the warhead's multiplier for the victim's armor is 0.0
- **THEN** the victim takes no damage

### Requirement: Invisible projectiles teleport-detonate
When the resolved `ProjectileData` has `is_invisible = true`, the projectile SHALL skip flight entirely: it SHALL be positioned at the target's coordinate and detonate through the `HitboxComponent` pipeline at dispatch — the same tick the legacy hitscan path applied damage — with no travel time and no visible node.

#### Scenario: Invisible projectile behavior-preserving
- **WHEN** a weapon with `projectile = "Invisible"` fires at an enemy in range
- **THEN** the victim takes the same damage on the same tick as the legacy hitscan path produced, and no projectile mesh is rendered

### Requirement: Visible projectile flight
When the resolved `ProjectileData` has `is_invisible = false`, the projectile SHALL travel from its spawn position toward the target along a straight line at its resolved speed. When `is_guided = true`, it SHALL additionally steer toward the target's current position each physics frame, limited by `homing_turn_rate`.

#### Scenario: Straight flight reaches a stationary target
- **WHEN** a visible non-guided projectile is fired at a stationary enemy within range
- **THEN** the projectile travels the intervening distance at the resolved speed and detonates on contact

#### Scenario: Homing converges on a moving target
- **WHEN** a guided projectile's target moves laterally during flight
- **THEN** the projectile's heading turns toward the target at no more than `homing_turn_rate` and still detonates on or near the target

#### Scenario: Visual orientation and tint
- **WHEN** a visible projectile flies
- **THEN** its visual faces its heading when `rotates_to_face = true` and is tinted with `tint_color`

### Requirement: Projectile speed resolution
Flight speed SHALL resolve by precedence: `ProjectileData.speed_override` when nonzero, otherwise `WeaponData.speed` when nonzero, otherwise `GlobalRules.default_projectile_speed`. Speed is in world units per second.

#### Scenario: Speed override wins
- **WHEN** a projectile sets `speed_override = 30.0` and its weapon sets `speed = 10.0`
- **THEN** the projectile flies at 30.0 world units per second

#### Scenario: Weapon speed used when no override
- **WHEN** `speed_override` is 0 and the weapon sets `speed = 12.0`
- **THEN** the projectile flies at 12.0 world units per second

#### Scenario: Global default used last
- **WHEN** neither `speed_override` nor `WeaponData.speed` is nonzero
- **THEN** the projectile flies at `GlobalRules.default_projectile_speed`

### Requirement: Arming delay
A projectile SHALL NOT detonate during the first `arm_delay` physics frames of its life, regardless of contact or proximity.

#### Scenario: Armed projectile detonates on contact
- **WHEN** a projectile past its `arm_delay` contacts an enemy hitbox
- **THEN** it detonates

#### Scenario: Unarmed projectile passes through
- **WHEN** a projectile within its `arm_delay` overlaps an enemy hitbox
- **THEN** it does not detonate and continues flying

### Requirement: Detonation triggers
A visible, armed projectile SHALL detonate when any of the following occurs first: contact with a valid hitbox along its motion; close proximity to its target while armed; overshoot, meaning the distance to the target stops decreasing between frames; or exhaustion of its maximum range. Max range SHALL be derived from the firing weapon's `attack_range`. When the target is a structure (has a `FoundationComponent` and its `StatsComponent.is_structure()` is true), max range SHALL additionally include the target foundation's half-diagonal in world units, because the projectile flies to the footprint centre while the attacker stops at weapon range from the nearest footprint edge; without this the shot fizzles before reaching the wall. Non-structure targets SHALL keep max range equal to the weapon range. When the projectile exhausts range or flies past the map's playable bounds without hitting, it SHALL free itself without dealing damage.

#### Scenario: Contact detonation
- **WHEN** an armed projectile's motion segment intersects an enemy hitbox
- **THEN** it detonates at the intersection

#### Scenario: Overshoot detonation
- **WHEN** a guided projectile's target dodges and the projectile's distance to the target stops decreasing
- **THEN** the projectile detonates instead of circling or flying forever

#### Scenario: Max range fizzle
- **WHEN** a projectile has flown farther than its weapon's attack range without contact
- **THEN** it frees itself without dealing damage and without emitting `impacted`

#### Scenario: Physical shot reaches a large structure fired from nearest-edge range
- **WHEN** a visible non-invisible projectile is fired at a 4x4 structure whose centre is `range + half_extent` away (the attacker stopped at weapon range from the nearest edge)
- **THEN** the projectile's max range covers the footprint centre and it detonates through the hitbox pipeline, dealing damage

#### Scenario: Non-structure max range unchanged
- **WHEN** a projectile is fired at a non-structure target beyond weapon range
- **THEN** max range remains the weapon range and the projectile fizzles without damage

### Requirement: Snap-to-victim detonation
When an armed projectile detonates by close proximity or contact within a short distance of its target, the detonation position SHALL snap onto the victim's center so the blast visually strikes the victim.

#### Scenario: Close detonation snaps
- **WHEN** an armed projectile comes within close proximity of its target and detonates
- **THEN** `impacted` is emitted with the victim's center position rather than the raw proximity point

### Requirement: Friendly-fire exclusion
A projectile SHALL never detonate on, trigger on, or damage its shooter. It SHALL likewise ignore hitboxes belonging to the shooter's allies, passing through them harmlessly. Enemy, neutral, and civilian hitboxes SHALL trigger detonation normally.

#### Scenario: Shooter immune at point-blank
- **WHEN** a projectile spawns inside its own shooter's hitbox
- **THEN** it does not detonate and does not damage the shooter

#### Scenario: Ally pass-through
- **WHEN** a projectile's motion crosses an allied unit's hitbox
- **THEN** the projectile continues flying and the ally takes no damage

#### Scenario: Neutral and enemy contact
- **WHEN** a projectile's motion crosses an enemy or civilian hitbox
- **THEN** it detonates

### Requirement: Tunneling-immune detection
A projectile SHALL detect hits by casting a shape along each physics frame's full motion segment (from previous position to next position), not by relying on `area_entered` overlap events. The closest valid hit along the segment SHALL win.

#### Scenario: Fast projectile cannot skip a hitbox
- **WHEN** a projectile moves more than one cell width in a single physics frame across an enemy hitbox
- **THEN** the motion-segment cast still registers the hit and the projectile detonates on that hitbox

### Requirement: Default projectile speed exceeds the fastest unit speed

`GlobalRules.default_projectile_speed` SHALL sit on the same 2× TS time base as movement and SHALL be strictly greater than the world speed of the fastest unit in the active game, so a projectile fired from behind a receding target can still close. The default SHALL be 24 world units per second. Per-weapon and per-projectile TS speeds remain the fidelity path and may author values above it.

#### Scenario: Default outruns the fastest unit

- **WHEN** `GlobalRules.default_projectile_speed` is resolved at the default 24 u/s and the fastest unit is the Orca Fighter (TS Speed 20 → 12.0 u/s)
- **THEN** the default projectile speed is strictly greater than the unit's world speed

#### Scenario: Pursuing shot catches a receding target

- **WHEN** a non-guided projectile at the default speed is fired from behind a target receding at the fastest unit speed
- **THEN** the projectile closes the gap and detonates on the target rather than fizzling at maximum range
