# Spec Delta

## MODIFIED Requirements

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
