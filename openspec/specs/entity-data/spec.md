# entity-data Specification

## Purpose

EntityData is the single resource class describing every entity type (infantry, vehicle, building, aircraft, terrain). It carries identity, stats, combat, movement, docking, and build-requirement fields with sensible defaults, names the unit's Locomotor, and drives how EntityFactory composes an entity.

## Requirements

### Requirement: EntityData resource class

The system SHALL provide a single `EntityData.gd` resource class containing ALL properties for ALL entity types (infantry, vehicle, building, aircraft, terrain). Properties SHALL have sensible defaults (0, false, "") so unused fields can be ignored, except the two selectability flags (`is_selectable`, `is_drag_selectable`), which default to `true` because selectable is the behavior of nearly every entity. The class SHALL include a `buildable: bool` field (default `false`) to indicate whether an entity can be placed by the player via the build menu. The class SHALL include a `deploys_into: String` field (default `""`) to specify the entity id this entity can deploy into. The class SHALL include an `undeploys_into: String` field (default `""`) to specify the entity id this entity can undeploy into. The class SHALL include `is_selectable: bool` (default `true`) as the data source for click, hover, and box selection, and `is_drag_selectable: bool` (default `true`) as the data source for box-select group eligibility.

#### Scenario: Create infantry entity data

- **WHEN** an EntityData resource is created with `entity_type = INFANTRY`, `strength = 125`, `speed = 5.0`, `weapons = [WeaponData("minigun")]`
- **THEN** the resource contains all fields with defaults for unused properties (e.g., `foundation = Vector2i(1,1)`, `power = 0`, `radar = false`, `buildable = false`, `deploys_into = ""`, `undeploys_into = ""`)

#### Scenario: Create building entity data

- **WHEN** an EntityData resource is created with `entity_type = BUILDING`, `foundation = Vector2i(2,2)`, `power = 100`, `capturable = true`, `buildable = true`
- **THEN** the resource contains all fields with defaults for unused properties (e.g., `speed = 0.0`, `weapons = []`, `deploys_into = ""`, `undeploys_into = ""`)

#### Scenario: Create terrain entity data

- **WHEN** an EntityData resource is created with `entity_type = TERRAIN`, `strength = 200`, `foundation = Vector2i(1,1)`
- **THEN** the resource contains all fields with defaults for unused properties (e.g., `speed = 0.0`, `weapons = []`, `capturable = false`, `buildable = false`, `deploys_into = ""`, `undeploys_into = ""`)

#### Scenario: Buildable field defaults to false

- **WHEN** an EntityData resource is created without explicitly setting `buildable`
- **THEN** `buildable` is `false`

#### Scenario: DeploysInto field defaults to empty

- **WHEN** an EntityData resource is created without explicitly setting `deploys_into`
- **THEN** `deploys_into` is `""`

#### Scenario: UndeploysInto field defaults to empty

- **WHEN** an EntityData resource is created without explicitly setting `undeploys_into`
- **THEN** `undeploys_into` is `""`

#### Scenario: Selectability defaults to true

- **WHEN** an EntityData resource is created without setting `is_selectable` or `is_drag_selectable`
- **THEN** both fields are `true`

#### Scenario: Explicit opt-out persists

- **WHEN** an EntityData resource is saved with `is_selectable = false`
- **THEN** loading that resource returns `is_selectable = false`

### Requirement: EntityData dock configuration
EntityData SHALL include `dock_position: Vector3` and `dock_rotation: float` for buildings with docking capability. EntityData SHALL include `dock_unload: bool` to indicate whether the building has a DockUnloadComponent.

#### Scenario: Refinery with dock
- **WHEN** an EntityData is created with `dock_position = Vector3(6, 0, 2)`, `dock_rotation = -90.0`, `dock_unload = true`
- **THEN** the building has a dock 6 units right and 2 units forward, facing west, with unload capability

#### Scenario: Building without dock
- **WHEN** an EntityData is created without setting `dock_position`
- **THEN** `dock_position` is `Vector3.ZERO` and no DockHostComponent is attached

### Requirement: Infantry entity data includes weapons
Infantry entity .tres files SHALL populate the `weapons` array with references to WeaponData .tres files. EntityFactory SHALL create a CombatComponent when `data.weapons` is non-empty.

#### Scenario: GDI Light Infantry has weapon
- **WHEN** `gdi_light_infantry.tres` is loaded
- **THEN** `weapons` SHALL contain a reference to `m1carbine.tres`

#### Scenario: Nod Light Infantry has weapon
- **WHEN** `nod_light_infantry.tres` is loaded
- **THEN** `weapons` SHALL contain a reference to `m1carbine.tres`

#### Scenario: EntityFactory creates CombatComponent
- **WHEN** an entity is created with non-empty `weapons` array
- **THEN** EntityFactory SHALL instantiate CombatComponent and call `configure(data)`

### Requirement: EntityData accepted resource categories
EntityData SHALL include `accepted_resource_categories: PackedStringArray` for buildings that accept resource cargo (refineries). This field SHALL be passed to DockUnloadComponent at creation time. Empty array = accept all cargo types, non-empty array = exclusive whitelist of accepted resource categories.

#### Scenario: Refinery accepts all tiberium
- **WHEN** an EntityData has `accepted_resource_categories = ["tiberium"]`
- **THEN** DockUnloadComponent accepts cargo whose category matches "tiberium"

#### Scenario: Refinery accepts specific types
- **WHEN** an EntityData has `accepted_resource_categories = ["tiberium_green", "tiberium_blue"]`
- **THEN** DockUnloadComponent only accepts cargo with those specific type IDs

#### Scenario: Empty accepts all
- **WHEN** an EntityData has `accepted_resource_categories = []`
- **THEN** DockUnloadComponent accepts any cargo type

### Requirement: EntityData locomotor references the registry
`EntityData.locomotor: String` SHALL name a Locomotor registered in `GlobalRules.locomotors`. The MovementController SHALL resolve the unit's locomotor resource from this id at runtime. An id not in the registry SHALL fall back to no-locomotor behavior (current movement) and SHALL be reported loudly at runtime and by validation.

#### Scenario: Known locomotor resolved
- **WHEN** an EntityData has `locomotor = "Wheel"` and "Wheel" is registered
- **THEN** MovementController resolves the Wheel Locomotor and applies its terrain speeds, climb tolerance, and flags

#### Scenario: Unknown locomotor falls back loudly
- **WHEN** an EntityData has `locomotor = "NotAThing"` not in the registry
- **THEN** the unit moves with current default behavior (no terrain filtering), `push_error` is emitted, and validation reports an error

### Requirement: EntityData movement_zone is a pathfinding domain class
`EntityData.movement_zone: String` SHALL be interpreted as the TS-style pathfinding domain class (e.g. Normal, Infantry, Crusher, Destroyer, AmphibiousCrusher, InfantryDestroyer, Fly, Subterannean) and SHALL be metadata only. It SHALL NOT gate terrain passability — passability SHALL be driven by `locomotor`. Validation SHALL reject a `movement_zone` that contradicts its unit's locomotor (e.g. `Track` with zone `Subterannean`).

#### Scenario: Zone is informational for passability
- **WHEN** two units share `locomotor = "Wheel"` but differ in `movement_zone`
- **THEN** both units have identical terrain passability

#### Scenario: Contradictory zone rejected
- **WHEN** validation runs on an EntityData with `locomotor = "Track"` and `movement_zone = "Subterannean"`
- **THEN** an error is returned naming the entity id

### Requirement: EntityData weight drives ice damage, not speed

`EntityData.weight: float` SHALL represent mass used to damage ice entities when a unit enters their cell. Weight SHALL NOT scale movement speed — speed is set by `EntityData.speed` and terrain/locomotor factors.

#### Scenario: Heavy unit damages ice

- **WHEN** a unit with `weight = 3.0` enters a cell occupied by an ice entity
- **THEN** the ice entity receives weight-proportional damage

#### Scenario: Weight does not affect speed

- **WHEN** two units with the same `speed = 6.0` but different `weight` move over flat clear terrain
- **THEN** both move at the same rate, `GlobalRules.speed_to_units_per_second(6.0)`, independent of weight

### Requirement: Submarine is a Ship with stealth
A naval unit intended as a submarine SHALL use `locomotor = "Ship"` and enable `cloakable` (with TS-style submerge behavior: cloaked in water, decloaks to attack). No dedicated Submarine locomotor SHALL exist.

#### Scenario: Submarine data
- **WHEN** a submarine unit is defined
- **THEN** its EntityData has `locomotor = "Ship"`, a naval `movement_zone` domain, and `cloakable = true`

### Requirement: Default build time derives from GlobalRules build speed
`EntityData.get_build_time()` SHALL return the explicit `build_time` when it is positive. Otherwise it SHALL compute the build time from `cost` and the game-wide build-speed factor, which SHALL be sourced from `GlobalRules.build_speed` rather than a duplicated constant. When GlobalRules is unavailable, it SHALL fall back to the default factor `0.8`.

#### Scenario: Explicit build time takes precedence
- **WHEN** `build_time` is set to a positive value
- **THEN** `get_build_time()` returns that value unchanged

#### Scenario: Computed from GlobalRules build speed
- **WHEN** `build_time` is unset and GlobalRules is available
- **THEN** `get_build_time()` computes `cost * GlobalRules.build_speed * 60 / 1000`

#### Scenario: Fallback when GlobalRules unavailable
- **WHEN** `build_time` is unset and GlobalRules cannot be resolved
- **THEN** `get_build_time()` computes the time using the default factor `0.8`

### Requirement: EntityData voice set reference
EntityData SHALL include an optional `voice_data: VoiceData` export (default null) in the Art group. When set, EntityFactory SHALL attach a VoiceComponent holding the reference; when null, no VoiceComponent is created.

#### Scenario: Voice data set attaches component
- **WHEN** an EntityData has `voice_data` referencing a VoiceData resource
- **THEN** EntityFactory SHALL attach a VoiceComponent holding that reference

#### Scenario: Voice data unset omits component
- **WHEN** an EntityData has `voice_data = null`
- **THEN** no VoiceComponent SHALL be attached

### Requirement: EntityData pip color for passenger seat pips
EntityData SHALL expose a `pip_color: Color` export (default white) with a `##` doc comment, defining the color of the seat pip drawn for this entity while it rides as a passenger in a transport. Transports and harvesters SHALL NOT require the field (cargo pips are unaffected).

#### Scenario: Infantry entity sets pip_color
- **WHEN** an infantry EntityData sets `pip_color` to a non-default color and that entity boards a transport
- **THEN** the transport's selection overlay draws that entity's seat pip in the configured color

#### Scenario: Default pip_color
- **WHEN** an EntityData leaves `pip_color` unset
- **THEN** the value defaults to white and seat pips for that entity draw white

### Requirement: EntityData death sound reference
`EntityData` SHALL include an optional `sound_die: String` export (default `""`) holding a comma-separated list of audio ids played on death when the entity has no die voice set. The field SHALL be independent of `voice_data`; an entity may define either, both, or neither. An empty `sound_die` SHALL be valid and play nothing.

#### Scenario: EntityData exposes sound_die
- **WHEN** an EntityData resource is authored with `sound_die = "EXPNEW05"`
- **THEN** the resource exposes the value for the death handler

#### Scenario: Default is silent
- **WHEN** an EntityData resource omits `sound_die`
- **THEN** the field defaults to `""` and the entity plays no death sound unless it has a die voice

### Requirement: EntityData breakable surface flag
`EntityData` SHALL expose `breakable_surface: bool` (default false). Entities flagged breakable SHALL receive the ice (breakable-surface) component, replacing detection by a legacy-id prefix.

#### Scenario: Flagged entity
- **WHEN** an entity's data has `breakable_surface = true` and the game enables `breakable_ice`
- **THEN** the entity receives the breakable-surface component

#### Scenario: Unflagged TS ice-like id
- **WHEN** an entity id ends in an ice-like suffix but `breakable_surface` is false
- **THEN** no breakable-surface component is attached

### Requirement: EntityData resource spawner flag
`EntityData` SHALL expose `resource_spawner: bool` (default false) identifying entities that seed resource crystals, replacing the `"tiberium_tree"` category string branch.

#### Scenario: Spawner flagged
- **WHEN** an entity's data has `resource_spawner = true`
- **THEN** it joins the `resource_trees` group and receives the resource-tree component

#### Scenario: Non-spawner
- **WHEN** an entity's data has `resource_spawner = false`
- **THEN** it does not join `resource_trees` and does not receive the resource-tree component

### Requirement: EntityData procedural resource visual flag
`EntityData` SHALL expose a flag indicating a resource entity that renders via the procedural resource component and therefore needs no art component, replacing the `"tiberium"` category check.

#### Scenario: Procedural resource
- **WHEN** an entity's data flags a procedural resource visual
- **THEN** no ArtComponent is added and the ResourceComponent renders it

#### Scenario: Ordinary resource entity
- **WHEN** an entity's data does not flag a procedural visual
- **THEN** an ArtComponent is added when the data has art

### Requirement: EntityData harvestable categories
`EntityData` SHALL expose `harvestable_categories: PackedStringArray`; `HarvestComponent` SHALL configure its `harvestable_types` from this field. An empty list SHALL mean the harvester accepts every resource category.

#### Scenario: Restricted harvester
- **WHEN** harvester data sets `harvestable_categories = ["ore"]`
- **THEN** the harvester ignores resource cells whose category is not `"ore"`

#### Scenario: Unrestricted harvester
- **WHEN** harvester data leaves `harvestable_categories` empty
- **THEN** the harvester accepts every resource category

### Requirement: Neutral resource defaults
`ResourceComponent.resource_type_id` and `ResourceTreeComponent.resource_type_id` SHALL default to `""` and SHALL be set only through `configure` from entity data, not to a TS resource id.

#### Scenario: Unconfigured resource
- **WHEN** a resource component is created without data
- **THEN** `resource_type_id` is `""` and no tiberium-tinted fallback colour is applied

### Requirement: Bridge overlay data fields
`EntityData` SHALL expose bridge overlay fields used to resolve a deck surface: a bridge kind (`bridge_kind`, default none) distinguishing `low`, `high`, and `rail`; a deck land (`bridge_land`, default `"road"`) giving the land the covered lane resolves (`road` for road/low/high lanes and rail outer lanes, `railroad` for a rail middle lane); an end-piece flag (`bridge_end`, default false); a deck grade/rise (`bridge_rise`, default four height steps) used by the high deck height; and a deck level (`bridge_level`, default 0) used to place the surface in the cell's stack. A `bridge_kind` other than none SHALL mark the entity as a bridge overlay for component attachment and registry resolution. A `bridge_level` at or above `TerrainSystem.MAX_HEIGHT` SHALL be invalid.

#### Scenario: Defaults are inert
- **WHEN** an `EntityData` is created without bridge fields
- **THEN** `bridge_kind` is none, `bridge_land` is `"road"`, `bridge_end` is false, `bridge_level` is 0, and the entity is not treated as a bridge

#### Scenario: Low bridge declared
- **WHEN** an `EntityData` sets the low bridge kind
- **THEN** it is treated as a low bridge overlay at its level with road deck land

#### Scenario: High bridge rise and level declared
- **WHEN** an `EntityData` sets the high bridge kind with a rise and a level
- **THEN** its deck surface is placed at that level, `bridge_rise` above the ground

#### Scenario: Rail kind declares railroad lane
- **WHEN** an `EntityData` sets the rail bridge kind with `bridge_land = "railroad"`
- **THEN** its covered cell resolves `railroad` at its level

#### Scenario: Level bound enforced
- **WHEN** an `EntityData` declares a bridge level at or above `MAX_HEIGHT`
- **THEN** the level is rejected as invalid

### Requirement: ArtData animation clip schema

`ArtData` SHALL expose `animations: Array[AnimClipData]` (default empty), replacing `active_anims`. Each `AnimClipData` SHALL be a `Resource` with a `role: Role` enum (default `ACTIVE`), `model_path: String` (default `""`), `clip_name: String` (default `""`, meaning the player's first animation), `damaged_model_path: String` (default `""`), `speed_scale: float` (default `1.0`), `loop: bool` (default `true`), `offset: Vector3` (default `Vector3.ZERO`), and `requires_power: bool` (default `true`). The `Role` enum SHALL include at least `ACTIVE`, `DOOR`, `UNDER_DOOR`, `PRODUCTION`, `PRE_PRODUCTION`, `BUILDUP`, `DEPLOY`, `SPECIAL`, `CHARGE`, `POWER_UP`, and `GATE`. `ArtData.validate()` SHALL report an animation entry whose `model_path` is empty.

#### Scenario: Defaults on a new entry
- **WHEN** an `AnimClipData` is created with no fields set
- **THEN** `role` is `ACTIVE`, `model_path` is empty, `speed_scale` is `1.0`, `loop` is true, `offset` is `Vector3.ZERO`, and `requires_power` is true

#### Scenario: Multiple clips on one building
- **WHEN** an `ArtData` sets `animations` to a rotating-antenna `ACTIVE` entry and a `DOOR` entry
- **THEN** both entries are retained in order and expose their own `model_path` and `offset`

#### Scenario: Validation flags empty model path
- **WHEN** `ArtData.validate()` runs with an animation entry whose `model_path` is empty
- **THEN** the returned errors include an entry identifying the missing animation model path

### Requirement: Theater variant opt-in flag

`ArtData.new_theater` SHALL enable suffix-based theater art resolution for the base model path and every animation clip path. When false, only the authored paths are used.

#### Scenario: Opt-in enables resolution
- **WHEN** `new_theater` is true and a theater-specific file exists
- **THEN** resolution may select the theater-specific file

#### Scenario: Opt-out keeps generic
- **WHEN** `new_theater` is false
- **THEN** only the authored generic path is used regardless of theater

### Requirement: EntityData speed is TS leptons per frame and drives movement

`EntityData.speed: float` SHALL be interpreted as the original Tiberian Sun `Speed` value in leptons per game frame (`0.0` = immobile). `MovementController` SHALL set its base `move_speed` from this value through the `GlobalRules` lepton-to-world-units conversion, so two units with different `speed` traverse the same path at different real rates. The field SHALL NOT be documented as "cells per tick".

#### Scenario: Different speeds move at different rates

- **WHEN** two units with `speed = 6.0` and `speed = 10.0` move over flat clear terrain with a non-ramping locomotor on the unit's default cell land type
- **THEN** their world units per second are in the ratio 6:10 and each equals `GlobalRules.speed_to_units_per_second(speed)`

#### Scenario: Immobile entity has no controller

- **WHEN** an EntityData has `speed = 0.0`
- **THEN** no MovementController is attached and the entity never moves

#### Scenario: Speed documentation

- **WHEN** a developer reads the `EntityData.speed` declaration
- **THEN** the comment describes it as leptons per frame (TS `Speed`), not cells per tick
