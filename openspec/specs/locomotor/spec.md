# locomotor Specification

## Purpose

Locomotor is the movement-behavior registry. Each locomotor defines per-terrain-type speed multipliers (which also drive passability), climb tolerance, behavior flags, and hybrid thresholds. GlobalRules holds the registry; MovementController resolves a unit's locomotor by id and applies terrain speed, hover float, and the jumpjet/subterranean hybrids. The Locomotor always owns movement-behavior decisions.

## Requirements

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

### Requirement: Speed ramp behavior

MovementController SHALL ramp a locomotor's per-tick speed when `accelerate` or `decelerate` is `true`. The ramp SHALL target `move_speed` directly; per-unit factors (vertical split, veteran, slope, terrain, speed jitter) and the neighbor-proximity slowdown SHALL multiply on top of the ramped speed via the step chain, never inside the ramp's target. A decel-only locomotor (`decelerate = true`, `accelerate = false` — TS semantics: no Accelerate = immediate cruise) SHALL start fresh moves at full target speed; an accelerating locomotor SHALL start from standstill. Ramp state SHALL reset only at arrival and `_finish_stop()`, and SHALL carry across mid-move re-targets and stop-order truncations. Jumpjet vertical ascent/descent SHALL use the unit's per-unit `move_speed` directly and SHALL NOT be subject to the accelerate/decelerate ramp.

#### Scenario: Accelerate ramp-up

- **WHEN** a locomotor with `accelerate = true` starts a move from standstill
- **THEN** per-frame displacement rises from below target speed toward full speed, never exceeding it

#### Scenario: Decelerate ramp-down

- **WHEN** a locomotor with `decelerate = true` approaches its final waypoint
- **THEN** per-frame displacement falls below target speed, ending at ~crawl speed at arrival

#### Scenario: No-regression default-off

- **WHEN** `accelerate` and `decelerate` are `false` (default)
- **THEN** per-frame displacement is identical to current constant-speed behavior

#### Scenario: Short-move no overshoot

- **WHEN** a 1–2 cell order runs with both flags `true`
- **THEN** the ramp collapses to a triangular profile and the unit lands exactly on the sub-slot with no overshoot

#### Scenario: Terrain factor scales ramp

- **WHEN** a ramping unit enters a slow-terrain cell
- **THEN** the terrain multiplier scales the ramped speed proportionally

#### Scenario: Decel-only starts at cruise

- **WHEN** a locomotor with `decelerate = true` and `accelerate = false` orders its first move
- **THEN** the ramp starts at full target speed rather than from standstill

#### Scenario: Carry-forward on retarget

- **WHEN** an internal re-target (blocked arrival, repair, scatter) occurs mid-move
- **THEN** current ramped speed carries forward

#### Scenario: Fresh order starts from standstill

- **WHEN** a fresh order starts from IDLE on an accelerating locomotor
- **THEN** the ramp starts at 0

#### Scenario: Ramp targets the per-unit speed

- **WHEN** the same locomotor runs on two units with different `EntityData.speed`
- **THEN** each ramps toward its own converted `move_speed`

### Requirement: Locomotor registry in GlobalRules
GlobalRules SHALL contain a `locomotors: Dictionary` mapping locomotor id strings to `Locomotor` resources, SHALL expose `get_locomotor(id: String) -> Locomotor`, and SHALL support user-defined types. The SHALL-supported set covers TS plus naval and future-proofed types: `Foot`, `Track`, `Wheel`, `Hover`, `Amphibious`, `Fly` (Winged), `Jumpjet`, `Subterranean`, and `Ship`. A submarine SHALL be expressed as a `Ship` entity with stealth (`cloakable`), not as a distinct locomotor.

#### Scenario: Default locomotor set
- **WHEN** GlobalRules is loaded
- **THEN** `locomotors` contains Foot, Track, Wheel, Hover, Amphibious, Fly, Jumpjet, Subterranean, and Ship

#### Scenario: Unknown locomotor lookup
- **WHEN** `get_locomotor("unknown")` is called for an id not in the registry
- **THEN** it returns `null`

#### Scenario: Submarine is a ship with stealth
- **WHEN** a naval unit intended as a submarine is defined
- **THEN** it uses `locomotor = "Ship"` and enables `cloakable` rather than a dedicated Submarine locomotor

### Requirement: Locomotor terrain speed validation
GlobalRules SHALL validate that every terrain speed key in every Locomotor references a registered LandType, and SHALL expose a validator.

#### Scenario: Valid terrain keys pass
- **WHEN** all Locomotor `terrain_speeds` keys exist in `land_types`
- **THEN** validation returns no errors

#### Scenario: Dangling terrain key fails
- **WHEN** a Locomotor's `terrain_speeds` references a land type id not in the registry
- **THEN** validation returns an error naming the Locomotor and the missing land type

### Requirement: Terrain speed factor in MovementController
MovementController SHALL multiply its per-frame step by the terrain speed multiplier of the unit's current cell for its locomotor. This is applied on top of move_speed, veteran, jitter, repulsion, and slope factors.

#### Scenario: Wheeled on rough moves slower
- **WHEN** a wheeled unit (`rough = 0.5`) moves over a rough cell
- **THEN** its effective speed is 50% of its move_speed

#### Scenario: Unit on road moves faster
- **WHEN** a unit (`road = 1.25`) moves over a road cell
- **THEN** its effective speed is 125% of its move_speed

#### Scenario: Unknown terrain speed defaults to full
- **WHEN** a unit's current cell has a land type absent from its `terrain_speeds` and passability was already allowed
- **THEN** the terrain speed factor is 1.0

### Requirement: Resource terrain speed per ground locomotor
Every ground `Locomotor` SHALL declare a `"resource"` entry in `terrain_speeds` using the TS tiberium percentages: `Foot` and `Jumpjet` at `0.9`, `Track` and `Subterranean` at `0.7`, `Wheel` and `Amphibious` at `0.5`. `Hover` SHALL declare `"resource": 1.0`. `Ship` SHALL declare no `"resource"` entry (impassable, TS Float = 0%). `Fly` SHALL declare none (airborne). The existing `is_passable` and `get_speed_multiplier` methods SHALL consume these entries unchanged. The `resource` entry SHALL drive both pathing cost (via the pathfinder's per-locomotor multiplier) and movement speed (via `MovementController`).

#### Scenario: Wheeled unit slows in a crystal field
- **WHEN** a wheeled unit (`resource = 0.5`) enters a resource-occupied cell
- **THEN** its terrain speed multiplier is `0.5`

#### Scenario: Hover is unaffected by crystal fields
- **WHEN** a hover unit (`resource = 1.0`) enters a resource-occupied cell
- **THEN** its terrain speed multiplier is `1.0`

#### Scenario: Ship cannot cross crystal fields
- **WHEN** `is_passable("resource")` is called on a Ship locomotor
- **THEN** it returns `false`

#### Scenario: Validation accepts the resource key
- **WHEN** `GlobalRules.validate_locomotor_keys()` runs after the `resource` land type is registered
- **THEN** it returns no errors for the `resource` terrain speed keys

### Requirement: Hover locomotion
MovementController SHALL treat a `Hover` locomotor as ignoring slope coefficients (uphill/downhill never apply) and floating at a hover height above terrain: the unit's Y is set to terrain height + hover height (from `hover_height_override` or `GlobalRules.hover_height`) instead of snapping to terrain.

#### Scenario: Hover ignores slope
- **WHEN** a hover unit moves over graded terrain
- **THEN** no uphill/downhill coefficient is applied to its speed

#### Scenario: Hover floats above terrain
- **WHEN** a hover unit with `hover_height = 2.0` is idle or moving over a flat cell
- **THEN** its Y position is terrain height + 2.0

#### Scenario: Ground unit snaps to terrain
- **WHEN** a track unit moves over the same cell
- **THEN** its Y position equals the terrain height

### Requirement: Amphibious locomotion
MovementController SHALL treat an `Amphibious` locomotor as ground locomotion that is also passable on water. Water passability SHALL be handled by Pathfinder via the locomotor's `terrain_speeds`.

#### Scenario: Amphibious APC enters water
- **WHEN** an amphibious unit (`water = 0.6`) pathfinds onto a water cell
- **THEN** the path includes the water cell and the unit moves onto it at 60% speed

#### Scenario: Amphibious moves like a ground unit
- **WHEN** an amphibious unit moves over clear ground
- **THEN** slope coefficients apply as for a tracked unit

### Requirement: Jumpjet hybrid locomotion
MovementController SHALL give a `Jumpjet` locomotor walk-first behavior: it pathfinds by foot first, and falls back to flying a straight line to the target when the walk path is empty OR when the straight-line distance exceeds `jumpjet_fly_distance`. Aircraft (`is_fly`) SHALL NOT use walk pathing.

#### Scenario: Reachable target walks
- **WHEN** a jumpjet unit is ordered to a walk-reachable target within `jumpjet_fly_distance`
- **THEN** it pathfinds on foot and moves along the ground path

#### Scenario: Unreachable target flies
- **WHEN** a jumpjet unit is ordered to a target no walk path can reach (e.g. across water)
- **THEN** it flies a straight-line path to the target

#### Scenario: Distant target flies
- **WHEN** a jumpjet unit is ordered to a walk-reachable target farther than `jumpjet_fly_distance`
- **THEN** it flies a straight-line path to the target

#### Scenario: Aircraft never walks
- **WHEN** a fly unit is ordered anywhere
- **THEN** it always uses flight movement, never ground pathfinding

### Requirement: Subterranean hybrid locomotion
MovementController SHALL give a `Subterranean` locomotor surface-first behavior: it pathfinds on the surface like Track, and digs underground to travel a straight line to the target when the surface path is empty OR the straight-line distance exceeds `subterranean_dig_distance`. An underground movement layer is not implemented; the dug phase SHALL move the unit directly to the target cell and re-emerge.

#### Scenario: Nearby target stays on surface
- **WHEN** a subterranean unit is ordered to a surface-reachable target within `subterranean_dig_distance`
- **THEN** it travels on the surface like a tracked unit

#### Scenario: Distant target digs
- **WHEN** a subterranean unit is ordered to a target farther than `subterranean_dig_distance`
- **THEN** it moves directly to the target (digging under intervening obstacles) and re-emerges

#### Scenario: Blocked surface target digs
- **WHEN** a subterranean unit is ordered to a target no surface path can reach
- **THEN** it digs directly to the target

### Requirement: Slope probe uses waypoint cell
MovementController SHALL compute the slope coefficient by sampling terrain height at the next waypoint cell center rather than a fixed 1.0 unit ahead of the current position.

#### Scenario: Uphill segment applies tracked coefficient
- **WHEN** a tracked unit moves along a segment whose next waypoint cell is higher than its current cell
- **THEN** the uphill coefficient is applied for that segment

#### Scenario: Downhill segment applies tracked coefficient
- **WHEN** a tracked unit moves along a segment whose next waypoint cell is lower than its current cell
- **THEN** the downhill coefficient is applied for that segment

#### Scenario: Flat segment has no coefficient
- **WHEN** the current and next waypoint cells have equal height
- **THEN** no slope coefficient is applied

### Requirement: Locomotor drives MovementController behavior
MovementController SHALL derive occupancy participation and infantry-style movement feel from the unit's resolved Locomotor and SHALL NOT read `EntityData.EntityType` for movement decisions. `shares_cell` SHALL gate sub-slot booking, exact sub-slot landing, repulsion bypass between sharers, and non-sharer blocking of sharer cells. `stand_upright` SHALL gate the facing normal (`Vector3.UP` vs terrain normal), `instant_turn` SHALL gate the direct IDLE→MOVING transition (skipping ROTATING), and `organic_path` SHALL gate path smoothing and spline-end easing.

#### Scenario: Foot infantry behaves unchanged
- **WHEN** an infantry unit resolves `locomotor = "Foot"`
- **THEN** it shares cells, stands upright, turns instantly, and walks organic paths

#### Scenario: Non-infantry shares a cell
- **WHEN** an entity whose locomotor has `shares_cell = true` targets a cell containing another `shares_cell = true` unit below capacity
- **THEN** it books a free sub-slot and counts toward the cell's capacity

### Requirement: Slope coefficients live on the Locomotor resource
`Locomotor` SHALL expose `uphill_factor: float` and `downhill_factor: float` (defaults 1.0 = no slope effect). `MovementController` SHALL read the slope coefficients from the unit's resolved `Locomotor` resource and SHALL NOT branch on locomotor id strings. When the resolved factors are both 1.0 the slope coefficient is 1.0.

#### Scenario: Tracked uphill
- **WHEN** a unit's Locomotor has `uphill_factor = 0.5` and it moves uphill
- **THEN** its speed is multiplied by 0.5

#### Scenario: Unknown locomotor id
- **WHEN** a unit uses a locomotor whose resource defines no slope factors
- **THEN** the slope coefficient is 1.0 (no error, no id-string match)

#### Scenario: Hover ignores slope
- **WHEN** a hover locomotor moves uphill
- **THEN** the slope coefficient is 1.0

### Requirement: Per-locomotor slope factors configured in data
The Tiberian Sun tracked and wheeled locomotors SHALL carry their slope factors in their `.tres` resources, preserving current behavior without a GlobalRules dependency.

#### Scenario: TS tracked values preserved
- **WHEN** `games/ts/locomotors/Track.tres` is loaded
- **THEN** `uphill_factor` is 0.5 and `downhill_factor` is 1.1

#### Scenario: TS wheeled values preserved
- **WHEN** `games/ts/locomotors/Wheel.tres` is loaded
- **THEN** `uphill_factor` is 0.5 and `downhill_factor` is 1.2

### Requirement: Large height steps cost from the road row
A locomotor SHALL cost a transition of two or more height levels (including a four-level bridge step) from the deck's resolved land row rather than the destination ground land type, so a unit keeps road-like speed climbing onto a deck over water: the Road row for a road deck, the Railroad row for a rail-bridge middle lane. On a deck the terrain figure SHALL be skipped entirely. Any rail-specific movement restriction SHALL be applied by the movement system from the rail bridge kind.

#### Scenario: Large step uses road multiplier
- **WHEN** a unit transitions a step of two or more levels onto a road deck
- **THEN** the cost uses the unit locomotor's road multiplier

#### Scenario: Deck skips the terrain figure
- **WHEN** a unit whose destination ground land type has zero speed crosses onto a deck
- **THEN** the deck transition is allowed at the deck land row's cost

#### Scenario: Rail high deck
- **WHEN** a rail bridge is crossed
- **THEN** its middle lane is treated as a railroad deck for cost and passability

### Requirement: MovementController base speed derives from EntityData

`MovementController` SHALL set its base `move_speed` from the entity's `EntityData.speed` via `GlobalRules.speed_to_units_per_second()`, not from a fixed default. Because `configure()` runs before the controller enters the tree (and thus before `_ready()` resolves `GlobalRules`), the controller SHALL retain the raw `EntityData.speed` and apply the conversion as soon as rules are available, so the converted value is in force before the first move. The exported `move_speed` default SHALL serve only as a fallback for controllers constructed directly without `configure()` (tests, editor previews).

#### Scenario: Configured controller uses the converted speed

- **WHEN** a MovementController is configured from an EntityData with `speed = 6.0` at `logic_fps = 30`
- **THEN** its `move_speed` is `3.6` world units per second

#### Scenario: Conversion applied when rules resolve later

- **WHEN** `configure()` runs before GlobalRules is resolvable and the entity is then added to the tree
- **THEN** `move_speed` reflects the converted `EntityData.speed` before the first movement step

#### Scenario: Bare controller keeps its export default

- **WHEN** a MovementController is created and `_handle_moving_movement` runs without `configure()` having been called
- **THEN** `move_speed` remains the scene/export default and existing mechanics tests are unaffected

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
