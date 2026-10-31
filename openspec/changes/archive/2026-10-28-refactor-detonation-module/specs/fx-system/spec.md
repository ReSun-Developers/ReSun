# Spec Delta

## ADDED Requirements

### Requirement: Warhead impact report

`FxSystem` SHALL expose `play_impact(damage_type: String, position: Vector3)` and emit `impact_played(damage_type, position)` once per resolved warhead report. It SHALL resolve the warhead from the active `GlobalRules` by `damage_type`, play `warhead.impact_fx` through `play` at `position` when non-null, and play `warhead.sound_impact` through `AudioManager.play_random` when non-empty. An empty damage type or a damage type that does not resolve to a warhead SHALL play nothing and SHALL NOT emit the signal. A resolved warhead with neither effect nor sound SHALL still emit the signal (one report, nothing spawned), so callers can observe report parity. Fog gating of the visual effect remains the existing `play` behavior.

#### Scenario: Warhead effect and sound play

- **WHEN** `play_impact` is called with a damage type that resolves to a warhead with an `impact_fx` and a `sound_impact`
- **THEN** one effect is played at the position, one sound is played, and `impact_played` is emitted once

#### Scenario: Report without media still emits

- **WHEN** `play_impact` is called with a resolved warhead that has no `impact_fx` and no `sound_impact`
- **THEN** nothing is spawned or played and `impact_played` is still emitted once

#### Scenario: Unknown damage type is silent

- **WHEN** `play_impact` is called with an empty or unresolvable damage type
- **THEN** nothing is played and `impact_played` is not emitted

#### Scenario: Fog gating is unchanged

- **WHEN** `play_impact` resolves an effect at a cell hidden from the local player while a shroud grid is ready
- **THEN** no effect node is added, matching `play`'s existing fog gate
