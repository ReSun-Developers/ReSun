# veterancy Specification

## Purpose
TBD - created by archiving change add-veterancy-and-tech-gating. Update Purpose after archive.

## Requirements

### Requirement: Experience and rank
`StatsComponent` SHALL carry a per-instance `experience: float` figure, initialised to `0` at creation. Rank SHALL be derived from `experience` using the engine-fixed thresholds: below rookie `< 0`, rookie `[0, 1)`, veteran `[1, 2)`, elite `>= 2`. `veteran_level` SHALL remain the stored integer rank (`0` rookie, `1` veteran, `2` elite) that existing consumers read, and SHALL be recomputed whenever `experience` changes. Experience SHALL NOT decay and SHALL NOT reset on ownership change.

#### Scenario: New entity is rookie
- **WHEN** any entity is created
- **THEN** its `experience` is 0 and `veteran_level` is 0

#### Scenario: Experience crossing the veteran threshold
- **WHEN** an entity's `experience` rises from 0.9 to 1.2
- **THEN** its `veteran_level` becomes 1

#### Scenario: Experience crossing the elite threshold
- **WHEN** an entity's `experience` rises from 1.9 to 2.0
- **THEN** its `veteran_level` becomes 2

#### Scenario: Rank is not reset by capture
- **WHEN** an entity with `veteran_level = 1` changes owner
- **THEN** its `experience` and `veteran_level` are unchanged

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

### Requirement: VeterancySystem credits kills
The system SHALL provide a `VeterancySystem` autoload that registers every `HealthComponent` in the scene tree via tree add/remove signals and listens for its `killed(killer)` event. On a kill it SHALL resolve the killer's and victim's `StatsComponent` and add `victim_cost / (killer_cost * veteran_ratio)` to the killer's `experience`, then clamp the result to `veteran_cap`. Both costs SHALL be the entities' `EntityData.cost` (not `points`). The system SHALL NOT credit a kill when: the killer is null or invalid, its `StatsComponent` is missing, the killer's type is not `Trainable`, the victim's owner considers the killer allied, `veteran_ratio <= 0`, or the victim's or killer's `cost <= 0`.

#### Scenario: Cheaper unit earns more from a valuable kill
- **WHEN** a 100-cost trainable unit destroys a 1000-cost enemy with `veteran_ratio = 10`
- **THEN** the killer gains 1.0 experience (1000 / (100 * 10)) and becomes veteran

#### Scenario: Expensive unit earns less from a cheap kill
- **WHEN** a 1000-cost trainable unit destroys a 100-cost enemy with `veteran_ratio = 10`
- **THEN** the killer gains 0.01 experience and remains rookie

#### Scenario: Experience is capped
- **WHEN** a killer's total would exceed `veteran_cap = 2`
- **THEN** its experience is clamped to 2

#### Scenario: Untrainable killer earns nothing
- **WHEN** a building with `trainable = false` lands the fatal hit
- **THEN** no experience is credited

#### Scenario: Allied killer earns nothing
- **WHEN** the victim's owner considers the killer allied
- **THEN** no experience is credited

#### Scenario: Zero ratio guards against division by zero
- **WHEN** `veteran_ratio` is 0 or the killer's cost is 0
- **THEN** no experience is credited and no error is raised

#### Scenario: Fatal blow, not mere participation, is credited
- **WHEN** unit A damages a target and unit B lands the fatal hit
- **THEN** only B gains experience

#### Scenario: A corpse cannot credit a second kill
- **WHEN** a dead victim takes further damage before it is freed (queued projectile, splash, second crusher)
- **THEN** no additional experience is credited for that victim

### Requirement: Non-combat promotion sources
Entities SHALL be created at a rank assigned by the active rules without accumulating experience. When `GlobalRules.initial_veteran` is true, entities spawned at match start SHALL be created elite. Assigning a rank this way SHALL NOT consult `veteran_cap` and SHALL NOT require the type to be `Trainable`.

#### Scenario: InitialVeteran creates elites
- **WHEN** `GlobalRules.initial_veteran` is true and a starting unit is spawned
- **THEN** the unit has `veteran_level = 2`

#### Scenario: Default start is rookie
- **WHEN** `GlobalRules.initial_veteran` is false and a unit is spawned
- **THEN** the unit has `veteran_level = 0`

### Requirement: Rank change notification
`StatsComponent` SHALL emit `veterancy_changed(level)` whenever its derived rank changes, including when a rank is assigned by a non-combat source. Consumers SHALL NOT poll for rank.

#### Scenario: Promotion emits once
- **WHEN** a unit's rank moves from rookie to veteran
- **THEN** `veterancy_changed` fires once with `level = 1`

#### Scenario: Rank assigned at spawn emits
- **WHEN** an entity is created at elite rank
- **THEN** `veterancy_changed` fires with `level = 2`

### Requirement: Rank insignia display
`SelectionOverlay` SHALL draw a rank insignia for a selected entity whose `veteran_level` is at least 1, distinct from cargo and passenger pips. The insignia SHALL be drawn only for entities owned by the local player or by an allied player; enemy ranks SHALL remain hidden.

#### Scenario: Veteran shows one insignia
- **WHEN** the local player selects a veteran unit
- **THEN** the overlay draws one rank insignia

#### Scenario: Elite shows a distinct insignia
- **WHEN** the local player selects an elite unit
- **THEN** the overlay draws the elite insignia, visually distinct from the veteran insignia

#### Scenario: Rookie shows none
- **WHEN** the local player selects a rookie unit
- **THEN** no rank insignia is drawn

#### Scenario: Enemy rank hidden
- **WHEN** the local player selects an enemy veteran unit (or views it)
- **THEN** no rank insignia is drawn for it
