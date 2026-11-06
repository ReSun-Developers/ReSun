# Spec Delta

## MODIFIED Requirements

### Requirement: EntityData movement_zone is a pathfinding domain class

`EntityData.movement_zone: String` SHALL be interpreted as the TS-style pathfinding domain class (e.g. Normal, Infantry, Crusher, Destroyer, AmphibiousCrusher, InfantryDestroyer, Fly, Subterannean) and SHALL be metadata only. It SHALL NOT gate terrain passability — passability SHALL be driven by `locomotor`. Validation SHALL resolve the unit's Locomotor from the active GlobalRules registry and SHALL reject a `movement_zone` that is not listed in that locomotor's `zones` (e.g. `Track` with zone `Subterannean`). An empty `movement_zone` SHALL be accepted. A non-empty `movement_zone` with an empty `locomotor` SHALL be rejected. When GlobalRules is unavailable, or the unit's non-empty locomotor id cannot be resolved to a Locomotor resource, zone compatibility SHALL NOT be evaluated and validation SHALL NOT use a built-in fallback table; an unresolved non-empty id SHALL still be reported as an unknown locomotor.

#### Scenario: Zone is informational for passability
- **WHEN** two units share `locomotor = "Wheel"` but differ in `movement_zone`
- **THEN** both units have identical terrain passability

#### Scenario: Contradictory zone rejected
- **WHEN** validation runs on an EntityData with `locomotor = "Track"` and `movement_zone = "Subterannean"`
- **THEN** an error is returned naming the entity id

#### Scenario: Zone checked against the resolved locomotor
- **WHEN** the registry contains a locomotor whose `zones` exclude `Subterannean` and an EntityData uses that locomotor with `movement_zone = "Subterannean"`, while another registered locomotor accepts it
- **THEN** validation rejects the zone because the unit's own locomotor does not list it

#### Scenario: Empty zone accepted
- **WHEN** an EntityData has a known locomotor and an empty `movement_zone`
- **THEN** validation reports no zone contradiction

#### Scenario: Zone without a locomotor rejected
- **WHEN** an EntityData has an empty `locomotor` and a non-empty `movement_zone`
- **THEN** validation reports a zone contradiction

#### Scenario: Unresolved locomotor id
- **WHEN** GlobalRules is available but the EntityData's non-empty `locomotor` id is not registered, and `movement_zone` is non-empty
- **THEN** validation reports an unknown locomotor and does not report a zone contradiction

#### Scenario: Validation before GlobalRules is available
- **WHEN** validation runs before GlobalRules is available with a non-empty `movement_zone`
- **THEN** zone compatibility is not checked and no contradiction error is produced
