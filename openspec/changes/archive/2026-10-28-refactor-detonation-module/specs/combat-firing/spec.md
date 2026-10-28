# Spec Delta

## MODIFIED Requirements

### Requirement: Weapon dispatch and damage
When firing, CombatComponent SHALL first resolve `weapon.projectile` through the GlobalRules projectile registry. If the id resolves to a `ProjectileData`, CombatComponent SHALL instantiate `Projectile.tscn`, configure it with the projectile data, weapon, shooter, target, the ordered ground point, and the shooter's veteran-boosted effective damage, spawn it at the firing mount's muzzle transform, parent it to the match World root, and SHALL NOT apply direct damage. The muzzle transform SHALL be the firing socket's world transform composed with the socket yaw and extended by the socket `barrel_length` for turret-mounted weapons, or the entity transform offset by `WeaponData.fire_offset` for body-mounted weapons (see the `turrets` capability). If the id is empty or unresolvable, CombatComponent SHALL apply the shot through the shared `WeaponDetonation` module with the weapon, shooter, the shooter's veteran-boosted effective damage, the entity target (or null), and the ordered ground point; it SHALL NOT call `HealthComponent.take_damage` itself. The module owns victim resolution, the impact point, warhead armor math and clamping, the cell-overlay pass, and the single impact report (see the `weapon-detonation` capability).

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
- **THEN** the shot is applied through `WeaponDetonation` with the same damage math as projectile arrival

#### Scenario: Fallback damage applied with armor
- **WHEN** a weapon with `damage = 100` and warhead "SA" fires via the fallback at a target with `armor = "heavy"` (SA multiplier 0.25)
- **THEN** the target takes 25 damage of warhead type "SA"

#### Scenario: Armor-piercing vs heavy
- **WHEN** a weapon with `damage = 100` and warhead "AP" fires at a target with `armor = "heavy"` (AP multiplier 1.00)
- **THEN** the target takes 100 damage of warhead type "AP"

#### Scenario: Fallback minimum damage floor
- **WHEN** the fallback-computed damage would be below `min_damage` (1)
- **THEN** the applied damage is clamped to 1

#### Scenario: Fallback maximum damage cap
- **WHEN** the fallback-computed damage would exceed `max_damage` (1000)
- **THEN** the applied damage is clamped to 1000

#### Scenario: Fallback zero-damage armor pairing
- **WHEN** a warhead's multiplier for the target's armor is 0.0
- **THEN** the target takes no damage

#### Scenario: Fallback unknown warhead or armor
- **WHEN** the weapon's warhead id or the target's armor id is not in the GlobalRules registries
- **THEN** fallback damage is applied with full multiplier 1.0

#### Scenario: Fallback target has no HealthComponent
- **WHEN** the target entity has no HealthComponent child
- **THEN** the detonation applies no entity damage without error and still resolves the cell overlays

#### Scenario: Veteran boost is passed as typed damage
- **WHEN** a veteran shooter fires a fallback shot
- **THEN** the detonation uses the shooter's `get_effective_damage(weapon)` value, not the weapon's base damage
