# Spec Delta

## MODIFIED Requirements

### Requirement: Killer recorded on lethal damage
`HealthComponent.take_damage(damage, damage_type, source)` SHALL accept an optional attacking `Node3D` and SHALL return the applied damage. Every damage path SHALL supply the attacker where one is known: hitscan fire, projectile detonation, and crush. The removed collision-hitbox damage path no longer applies damage; projectiles supply their shooter through the detonation module instead. On reaching zero health the component SHALL emit a `killed(killer)` signal carrying the last recorded attacker (or null when the fatal damage had no source). The existing no-argument `health_zero` signal SHALL remain and SHALL still fire on every death.

#### Scenario: Fatal hit records its source
- **WHEN** entity A deals the damage that brings entity B to zero health
- **THEN** B's `killed` signal fires with A

#### Scenario: Killerless death
- **WHEN** an entity is killed with no `source` (sell, sink, scripted kill)
- **THEN** `killed` fires with null and `health_zero` still fires

#### Scenario: Non-lethal damage emits no kill
- **WHEN** an entity takes damage but remains above zero health
- **THEN** `killed` does not fire

#### Scenario: Further damage to a dead entity is ignored
- **WHEN** an entity already at zero health takes additional damage before it is freed
- **THEN** `killed` and `health_zero` SHALL NOT fire again and the recorded killer is unchanged

#### Scenario: Existing health_zero listeners unaffected
- **WHEN** an entity dies
- **THEN** every listener connected to `health_zero` runs exactly as before
