# Spec Delta

## MODIFIED Requirements

### Requirement: Tech level gates the build list

`PrerequisiteSystem.can_build(player_id, entity_data)` SHALL reject a type with `tech_level == -1` outright, and SHALL reject any type whose positive `tech_level` exceeds the requesting player's current tech level. This follows original TS (`house.cpp`): `-1` is permanently unbuildable, while a positive level at or below the house's level is buildable. The gate SHALL apply to both the sidebar build list and production order checks, since both route through `can_build`. `can_build` SHALL resolve through the shared per-player build-gate query, and therefore SHALL also reject any type whose `buildable` menu flag is false — a type outside the build menu is never buildable, regardless of tech level and pending prerequisites. The debug `no_prereqs` override SHALL continue to bypass the gate for all types.

> Note: an omitted `EntityData.tech_level` defaults to `-1` and is therefore unbuildable, matching OpenTS's stored default of `255`. Player-buildable types must carry a positive level.

#### Scenario: Type at or below the current level is buildable
- **WHEN** a player at tech level 5 requests a build-menu type with `tech_level = 5`
- **THEN** `can_build` returns true

#### Scenario: Type above the current level is rejected
- **WHEN** a player at tech level 3 requests a type with `tech_level = 7`
- **THEN** `can_build` returns false

#### Scenario: Negative level is permanently unbuildable
- **WHEN** a player at any tech level requests a type with `tech_level = -1`
- **THEN** `can_build` returns false

#### Scenario: Type outside the build menu is rejected
- **WHEN** a player requests a type whose `buildable` menu flag is false and `no_prereqs` is off
- **THEN** `can_build` returns false

#### Scenario: Gate applies to orders, not just the sidebar
- **WHEN** a type above the player's level is queued directly through production
- **THEN** the order is refused

#### Scenario: Debug override bypasses the gate
- **WHEN** the debug `no_prereqs` override is active
- **THEN** `can_build` returns true regardless of tech level or menu flag
