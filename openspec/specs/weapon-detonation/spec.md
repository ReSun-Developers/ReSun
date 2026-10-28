# weapon-detonation Specification

## Purpose
One typed weapon-impact interface shared by instant (hitscan) fire and projectile arrival: given a weapon, its shooter, the shooter's veteran-boosted damage, and either an entity target or a ground point, it resolves the victim, the impact point, warhead damage, cell-overlay damage, and one impact report. It is the test surface for impact behavior without physics ticks or shape casts.

## Requirements

### Requirement: Single typed detonation entry point

The system SHALL expose one detonation entry point, `WeaponDetonation.detonate(weapon, shooter, effective_damage, target, ground_pos, arrival_pos) -> Impact`, used by both the instant-fire path and projectile arrival. `effective_damage` SHALL be the shooter's already veteran-boosted base damage, passed as a typed integer at the call; the module SHALL NOT read shooter combat state through duck typing. `target` SHALL be the entity target, or `null` for a ground shot where `ground_pos` is the ordered point. `arrival_pos` SHALL be the projectile's arrival position, or `Vector3.INF` when the shot has no travel point (instant fire). The returned `Impact` SHALL carry the impact position, the resolved victim, the total applied damage across the entity and overlay passes, and whether an entity and/or cell overlay was hit.

#### Scenario: Instant fire passes typed damage

- **WHEN** an instant-fire weapon is resolved with `effective_damage = 200` while the weapon's own `damage` is `100`
- **THEN** the victim takes damage computed from `200`, not from the weapon's base damage

#### Scenario: Projectile passes its typed damage on arrival

- **WHEN** a projectile is configured by a shooter whose veteran boost makes its effective damage `125` and it detonates on a victim
- **THEN** the detonation uses `125` as the base damage and does not inspect the shooter for a combat component

#### Scenario: Same input, same result

- **WHEN** the same weapon, shooter, effective damage, and victim are detonated once with no arrival point and once with the arrival point at the victim's centre
- **THEN** both calls apply identical victim damage and produce the same impact position

### Requirement: Victim and impact-point resolution

For an entity target, the victim SHALL be that entity. For a ground shot, the victim SHALL be the qualifying occupant of the ordered point's cell resolved through the `SpatialHash` cell-victim query, with the shooter excluded and allied or neutral occupants eligible; when no occupant qualifies, the detonation SHALL still resolve the cell's overlays at the ordered point. A ground shot's impact point SHALL be the ordered point, never the resolved occupant's position.

For a structure entity target (a `BUILDING` whose `StatsComponent.is_structure()` is true and that has a `FoundationComponent`), the impact point SHALL be the nearest foundation-footprint point facing the shooter. For a non-structure entity target the impact point SHALL be the victim's centre, unless a finite arrival point lies within the projectile snap radius of the victim, in which case the arrival point snaps to the victim's centre; a finite arrival point farther than the snap radius SHALL be used as-is. Instant fire has no arrival point and SHALL use the victim's centre. The occupant pass and the overlay pass SHALL both read the same resolved impact point.

#### Scenario: Ground shot resolves the cell occupant at the ordered point

- **WHEN** a ground shot is ordered at an empty cell and an enemy occupies that cell at detonation
- **THEN** that enemy takes the damage and the impact point remains the ordered cell centre

#### Scenario: Ground shot leaves the shooter alone

- **WHEN** a ground shot resolves over the shooter's own cell with no other qualifying occupant
- **THEN** the shooter takes no damage

#### Scenario: Structure impact reads on the nearest footprint point

- **WHEN** a shot hits a structure whose centre is not its nearest wall point
- **THEN** the impact point is `FoundationComponent.nearest_world_point(shooter position)` even when the arrival point is elsewhere

#### Scenario: Close projectile arrival snaps to the victim

- **WHEN** a projectile detonates within the snap radius of its victim
- **THEN** the impact position is the victim's centre

#### Scenario: Distant projectile arrival is kept

- **WHEN** a projectile detonates on a non-structure victim from beyond the snap radius
- **THEN** the impact position is the projectile's arrival position

### Requirement: Warhead damage and overlay pass

Damage SHALL be `GlobalRules.compute_warhead_damage(effective_damage, weapon.warhead, victim armor)`, clamped to the active rules' `[min_damage, max_damage]`; a zero armor multiplier SHALL deal no damage. The same math SHALL apply to cell overlays. Overlay damage SHALL use the warhead's existing gates: a LOW normal bridge span and ice take damage only with `can_damage_walls`, and tiberium only with `can_damage_tiberium`. A non-overlay entity target SHALL take direct entity damage; an overlay entity target SHALL skip direct entity damage and be damaged exactly once by the overlay pass, never by both passes. A non-overlay entity target already damaged by the entity pass SHALL be excluded from the overlay pass.

#### Scenario: Armor multiplier applies

- **WHEN** a weapon with effective damage 100 and warhead "SA" hits a victim with armor "heavy" (SA multiplier 0.25)
- **THEN** the victim takes 25 damage

#### Scenario: Zero multiplier is a no-op

- **WHEN** the warhead's multiplier for the victim's armor is 0.0
- **THEN** the victim takes no damage

#### Scenario: Overlay flag gates damage

- **WHEN** a shot lands on a cell holding a LOW bridge span with a warhead whose `can_damage_walls` is clear
- **THEN** the span takes no damage

#### Scenario: Overlay target is damaged once

- **WHEN** a tiberium overlay is itself the shot's entity target and `can_damage_tiberium` is set
- **THEN** its health decreases by one hit, not two

### Requirement: One impact report per detonation

Each detonation SHALL play at most one warhead impact report (FX and sound) at the resolved impact point, through `FxSystem.play_impact`. A report SHALL play when total applied damage across the entity and overlay passes is positive, and also when the detonation resolved no damageable entity or overlay at all (an empty ground shot still bangs). A detonation that resolved a damageable entity or overlay but applied zero total damage (for example, armor rounding a hit to nothing) SHALL play no report. A warhead with no `impact_fx` or `sound_impact` SHALL still count as one report but spawn nothing. A damage type that does not resolve to a warhead SHALL be silent. Fog gating of the visual effect remains delegated to `FxSystem`.

#### Scenario: Entity hit plays one report

- **WHEN** a detonation damages an entity whose warhead has an impact effect
- **THEN** exactly one impact report plays at the impact point

#### Scenario: Mixed entity and overlay hit plays one report

- **WHEN** one detonation damages both an entity occupant and a cell overlay at the same point
- **THEN** exactly one impact report plays, not one per victim

#### Scenario: Overlay-only hit plays one report

- **WHEN** a detonation damages only a cell overlay
- **THEN** exactly one impact report plays at the impact point

#### Scenario: Empty ground shot still reports

- **WHEN** a ground shot resolves no occupant and no overlay
- **THEN** exactly one impact report plays at the ordered point

#### Scenario: Zero applied damage is silent

- **WHEN** a detonation resolves a damageable entity but the applied damage is zero
- **THEN** no impact report plays

#### Scenario: Non-warhead damage is silent

- **WHEN** the damage type does not resolve to a warhead in the active rules
- **THEN** no impact report plays and no error is raised
