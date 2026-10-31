# Spec Delta

## MODIFIED Requirements

### Requirement: Projectile node lifecycle

The system SHALL provide a `Projectile.tscn` scene with a `ProjectileController` script. `CombatComponent` SHALL instantiate it when firing a weapon whose projectile id resolves, configure it with the projectile data, weapon, shooter, target, ordered ground point, and the shooter's veteran-boosted effective damage, and parent it to the match World root (falling back to the shooter's parent when no World root exists). The projectile SHALL free itself after detonation, after flying its maximum range, or after reaching the last known position of a target that died in flight. It SHALL emit `impacted(position: Vector3)` at the detonation point returned by the detonation module.

#### Scenario: Spawn and self-free on detonation

- **WHEN** a projectile detonates on a valid target
- **THEN** damage is applied through `WeaponDetonation` to `HealthComponent`, `impacted` is emitted with the detonation position, and the node frees itself

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
A projectile SHALL NOT expose a `get_damage_info()` dictionary or any duck-typed damage accessor. Its configuration SHALL accept the shooter's veteran-boosted effective damage as a typed integer, falling back to the weapon's base damage when the caller supplies none. On arrival the projectile SHALL call `WeaponDetonation.detonate` with its weapon, shooter, stored effective damage, victim (or null for a ground shot), ordered ground point, and arrival position. The module SHALL own the warhead armor multiplier, `[min_damage, max_damage]` clamping, victim/impact resolution, the cell-overlay pass, and the impact report.

#### Scenario: Payload contract keys
- **WHEN** a projectile is configured for detonation
- **THEN** it carries the weapon's warhead id, the shooter reference, the typed effective damage, and the ordered ground point/arrival position, with no damage-info dictionary exposed

#### Scenario: Effective damage is stored at fire time
- **WHEN** a projectile is configured with an effective damage of 125 for a weapon whose base damage is 100
- **THEN** its detonation uses 125 as the base damage

#### Scenario: Armor multiplier applied by projectile
- **WHEN** a projectile carrying weapon damage 100 with warhead "SA" detonates on a target with armor "heavy" (SA multiplier 0.25)
- **THEN** the victim's HealthComponent receives 25 damage

#### Scenario: Damage clamps
- **WHEN** the computed damage falls below `min_damage` or exceeds `max_damage`
- **THEN** the applied damage is clamped to the respective bound

#### Scenario: Zero armor multiplier
- **WHEN** the warhead's multiplier for the victim's armor is 0.0
- **THEN** the victim takes no damage

### Requirement: Invisible projectiles teleport-detonate
When the resolved `ProjectileData` has `is_invisible = true`, the projectile SHALL skip flight entirely: it SHALL be positioned at the target's coordinate and detonate through `WeaponDetonation` at dispatch — the same tick the legacy hitscan path applied damage — with no travel time and no visible node.

#### Scenario: Invisible projectile behavior-preserving
- **WHEN** a weapon with `projectile = "Invisible"` fires at an enemy in range
- **THEN** the victim takes the same damage on the same tick as the legacy hitscan path produced, and no projectile mesh is rendered

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
- **THEN** the projectile's max range covers the footprint centre and it detonates through `WeaponDetonation`, dealing damage

#### Scenario: Non-structure max range unchanged
- **WHEN** a projectile is fired at a non-structure target beyond weapon range
- **THEN** max range remains the weapon range and the projectile fizzles without damage
