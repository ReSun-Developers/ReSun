# Spec Delta

## MODIFIED Requirements

### Requirement: Warhead impact sounds

Each resolved weapon detonation SHALL play at most one warhead impact report, read from `WarheadData.sound_impact` (a comma-separated list of audio ids), at the resolved impact point through `FxSystem.play_impact`, which delegates to `AudioManager.play_random`. The impact report SHALL use random selection with graceful failure: one id SHALL be chosen at random from the entries that resolve to a cached `AudioData`; unknown ids SHALL log a warning and be excluded; an empty `sound_impact` or a list with no known ids SHALL play nothing. The report SHALL be emitted once per detonation, never once per damaged cell victim, whether the detonation hit an entity, a cell overlay, both, or nothing. A resolved warhead with an empty `sound_impact` SHALL still count as one report (no sound) so report parity is observable. Damage whose `damage_type` does not resolve to a `WarheadData` (for example vehicle crush or drowning) SHALL be silent. Impact playback SHALL NOT require the victim to have a `VoiceComponent`.

#### Scenario: Hit plays the warhead impact report

- **WHEN** a projectile or hitscan shot dealing warhead "HE" damages a victim and HE.sound_impact = "EXPNEW06"
- **THEN** "EXPNEW06" plays at the resolved impact point

#### Scenario: Impact picks one report at random

- **WHEN** a warhead with sound_impact = "EXPNEW06,EXPNEW10" damages a victim
- **THEN** exactly one of EXPNEW06 or EXPNEW10 plays at the impact point

#### Scenario: Mixed entity and overlay hit plays one impact report

- **WHEN** a shot damages both a combat entity and a cell overlay at the same impact point and the warhead has a non-empty `sound_impact`
- **THEN** exactly one impact report plays at that point, not one per victim

#### Scenario: Empty impact report is silent

- **WHEN** a warhead with an empty sound_impact damages a victim
- **THEN** no impact sound plays and no error is raised

#### Scenario: Unknown impact id warns and is skipped

- **WHEN** a warhead with sound_impact = "NO_SUCH_ID,EXPNEW10" damages a victim
- **THEN** a warning is logged and EXPNEW10 plays

#### Scenario: Non-warhead damage is silent

- **WHEN** an entity takes damage whose damage_type is not a registered warhead id
- **THEN** no impact sound plays and gameplay continues normally

#### Scenario: Overlay-only hit plays one report

- **WHEN** a detonation damages only a cell overlay and the warhead has a non-empty `sound_impact`
- **THEN** exactly one impact report plays at the impact point

#### Scenario: Empty ground shot plays one report

- **WHEN** a ground shot resolves no entity and no overlay and the warhead has a non-empty `sound_impact`
- **THEN** exactly one impact report plays at the ordered point
