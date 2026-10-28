# Spec Delta

## MODIFIED Requirements

### Requirement: Locomotor resource class

The system SHALL provide a `Locomotor.gd` resource class defining a movement type. Properties SHALL include `id: String`, `terrain_speeds: Dictionary` (land type id → speed multiplier float, where `0.0` or an absent key = impassable, `1.0` = full speed, `1.2` = speed bonus), `climb_tolerance: int` (height levels a unit can ascend/descend in one cell transition), `crushes: PackedStringArray` (documentation of crushable categories), `zones: PackedStringArray` (movement-zone domain classes compatible with this locomotor; default `[]`), behavior flags `is_hover`, `is_fly`, `is_jumpjet`, `is_subterranean`, `shares_cell`, `stand_upright`, `instant_turn`, `organic_path: bool`, `accelerate: bool`, `decelerate: bool`, plus hybrid thresholds `jumpjet_fly_distance: float` and `subterranean_dig_distance: float` (0 = use the alternate mode only when the primary path is impossible). Amphibious and ship passability SHALL be driven by `terrain_speeds` water entries, not by dedicated flags. `shares_cell`, `accelerate`, and `decelerate` SHALL default `false`. `stand_upright`, `instant_turn`, and `organic_path` SHALL default `false` and SHALL encode infantry-style movement feel: upright facing, instant rotation, and organic path smoothing/easing respectively. `zones` SHALL default to an empty array, which accepts no non-empty movement zone.

#### Scenario: Create foot locomotor
- **WHEN** a Locomotor resource is created with `id = "Foot"`, `terrain_speeds = {"clear": 1.0, "rough": 0.89, "road": 1.11, "water": 0.0}`, `climb_tolerance = 1`
- **THEN** the resource defines a ground-walking locomotor that cannot enter water

#### Scenario: Create fly locomotor
- **WHEN** a Locomotor resource is created with `id = "Fly"`, `terrain_speeds = {}`, `climb_tolerance = 99`, `is_fly = true`
- **THEN** the resource defines an air-only locomotor that ignores terrain and height

#### Scenario: Create ship locomotor
- **WHEN** a Locomotor resource is created with `id = "Ship"`, `terrain_speeds = {"water": 1.0}`
- **THEN** the resource defines a water-only naval locomotor for which all land surfaces are impassable

#### Scenario: Foot shares cells
- **WHEN** a Locomotor with `id = "Foot"` is loaded
- **THEN** `shares_cell`, `stand_upright`, `instant_turn`, and `organic_path` are `true`

#### Scenario: Non-sharing vehicle defaults to false
- **WHEN** a Locomotor resource is created without `shares_cell`
- **THEN** `shares_cell`, `accelerate`, and `decelerate` default to `false` and the unit never books sub-slots or counts toward cell capacity

#### Scenario: Zones default to empty
- **WHEN** a Locomotor resource is created without `zones`
- **THEN** `zones` is an empty array and the locomotor accepts no non-empty movement zone

## ADDED Requirements

### Requirement: Movement zone compatibility lives on the Locomotor resource

`Locomotor.zones` SHALL list the movement-zone domain classes compatible with that locomotor. An empty `movement_zone` SHALL be compatible with every locomotor. Zone compatibility SHALL be evaluated from the resolved Locomotor resource, not from a static `EntityData` table. The nine TS locomotor resources SHALL declare these zones:

- `Foot`: Infantry, InfantryDestroyer
- `Track`: Normal, Crusher, Destroyer, AmphibiousCrusher, AmphibiousDestroyer, InfantryDestroyer
- `Wheel`: Normal, Destroyer, Crusher, InfantryDestroyer
- `Hover`: Normal, Destroyer, AmphibiousCrusher, AmphibiousDestroyer, InfantryDestroyer, Crusher
- `Amphibious`: AmphibiousCrusher, AmphibiousDestroyer, Destroyer, InfantryDestroyer, Normal
- `Fly`: Fly
- `Jumpjet`: Fly
- `Subterranean`: Subterannean
- `Ship`: Subterannean, Fly, Destroyer, AmphibiousCrusher, AmphibiousDestroyer

#### Scenario: Foot accepts infantry zones
- **WHEN** the `Foot` locomotor's `zones` are checked against `Infantry`
- **THEN** the zone is compatible

#### Scenario: Track rejects a subterranean zone
- **WHEN** the `Track` locomotor's `zones` are checked against `Subterannean`
- **THEN** the zone is incompatible

#### Scenario: Fly accepts only its own zone
- **WHEN** the `Fly` locomotor's `zones` are checked against `Fly` and against `Normal`
- **THEN** `Fly` is compatible and `Normal` is incompatible

#### Scenario: Every TS locomotor declares its zone list
- **WHEN** the nine TS locomotor resources are loaded
- **THEN** each exposes the zone list above and none relies on an `EntityData` fallback table
