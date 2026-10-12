# resource-growth-system Specification

## Purpose

ResourceGrowthSystem grows and spreads harvestable resources from trees and existing cells.

## Requirements

### Requirement: ResourceGrowthSystem
The system SHALL provide a `ResourceGrowthSystem.gd` autoload that manages resource growth and spawning via two independent timers (tree timer and resource timer) with batched entity processing and cached entity lists. The system is registered in `project.godot` as `TiberiumGrowthSystem` autoload (name preserved for backward compatibility).

#### Scenario: MapEditor guard
- **WHEN** `ResourceGrowthSystem._physics_process()` runs in the Redot editor
- **THEN** it returns immediately without processing any growth (MapEditor is completely static)

#### Scenario: Entity list caching
- **WHEN** the system needs to iterate trees or resource entities
- **THEN** it uses cached lists rebuilt every `REBUILD_INTERVAL` seconds (5s) or when a timer fires

#### Scenario: Tree timer — spawn zone
- **WHEN** the tree timer fires and a tree has `node_count > 0`
- **THEN** the system iterates all cells within `tree_spawn_radius` of the tree (circular area, e.g. 3 = 7x7)
- **AND** for each cell: if resource exists → grow it; if empty → spawn new resource with `spawn_strength` health

#### Scenario: Tree timer — growth zone (contiguous spread)
- **WHEN** the tree timer fires
- **THEN** the system iterates all resource entities within `radius_cells` of the tree
- **AND** for each resource entity: tries to spread to its 8 adjacent neighbors
- **AND** if neighbor has resource → grow it; if empty → spawn new resource, increment entity's `spread_count`

#### Scenario: Tree timer batched processing
- **WHEN** there are more trees than `growth_batch_trees`
- **THEN** only `growth_batch_trees` trees are processed per tick, cycling through all trees over multiple ticks

#### Scenario: Resource timer fires
- **WHEN** the resource timer counts down to zero
- **THEN** the system processes up to `growth_batch_crystals` resource entities from the cached list

#### Scenario: Resource self-growth
- **WHEN** the resource timer fires and a resource entity has health < max_health
- **THEN** the entity's health increases by 5% of `max_health` per tick

#### Scenario: Resource spread count limit
- **WHEN** a resource entity has `spread_count >= spread_max`
- **THEN** the tree timer does not attempt to spread from this entity

#### Scenario: Randomized timer intervals
- **WHEN** a timer fires
- **THEN** the next interval is `base_interval + randf_range(-60, 60)` seconds (prevents mass growth events in single frame)

#### Scenario: Batched resource processing
- **WHEN** there are 100k resource entities on the map and `growth_batch_crystals = 500`
- **THEN** only 500 resource entities are processed per tick, cycling through all entities over multiple ticks

#### Scenario: Tree freed during timer
- **WHEN** a tree entity is freed while the growth timer is active
- **THEN** the system skips the freed entity (is_instance_valid guard)

#### Scenario: Concurrent growth on same cell
- **WHEN** two trees attempt to spawn on the same empty cell in the same tick
- **THEN** only one resource is spawned (second spawn finds cell occupied)

### Requirement: ResourceComponent spread tracking
ResourceComponent SHALL include a `spread_count: int = 0` field tracking how many times this resource entity has spread to new cells.

#### Scenario: Spread count incremented
- **WHEN** ResourceGrowthSystem spawns new resource from an existing entity's spread attempt
- **THEN** the source entity's `spread_count` increments by 1

#### Scenario: Spread count limit enforced
- **WHEN** a resource entity has `spread_count >= spread_max` (from GlobalRules)
- **THEN** ResourceGrowthSystem does not attempt to spread from this entity

### Requirement: ResourceTreeComponent configure method
ResourceTreeComponent SHALL implement a `configure(data: EntityData)` method that copies tree-spawner fields from EntityData into the component's exports.

#### Scenario: Configure from EntityData
- **WHEN** EntityFactory calls `configure(data)` on a ResourceTreeComponent with `spawned_entity_id = "TIB"`, `radius_cells = 8`, `node_count = 12`, `spawn_strength = 0.5`
- **THEN** the component stores these values for use by ResourceGrowthSystem

#### Scenario: No upfront spawn
- **WHEN** a ResourceTreeComponent enters the scene tree
- **THEN** it does NOT spawn resources automatically (map editor pre-populates; ResourceGrowthSystem handles growth)

### Requirement: Growth and spread amounts use the bale scale
`ResourceGrowthSystem` SHALL convert bale amounts to health through the target cell's bale capacity (`ResourceType.bales_per_cell`) when spawning resources via trees or spread. A spawn or spread amount of X bales SHALL create a cell at `X / bales_per_cell` of max health (clamped to at least 1 health).

#### Scenario: Spread seeds at the intended bale amount
- **WHEN** a tree with `spread_amount = 0.5` bales spawns a tiberium cell (`bales_per_cell = 11`)
- **THEN** the spawned cell's health ratio SHALL be approximately `0.5 / 11`, not 0.5

#### Scenario: Growth is unchanged in ratio terms
- **WHEN** a resource cell grows by `grow_rate` of its max health
- **THEN** its remaining bales SHALL increase by `grow_rate x bales_per_cell`

#### Scenario: Regrown cell reaches full bale capacity
- **WHEN** a partially grown cell heals to full health
- **THEN** `ResourceComponent.get_amount()` SHALL equal `bales_per_cell`

#### Scenario: Map-editor brush scales by bales
- **WHEN** the map editor adds or removes 50% strength on an existing resource cell
- **THEN** its remaining bales SHALL change by `0.5 x bales_per_cell`

### Requirement: Tree regrowth is feature-gated
The tree-seeded resource growth model SHALL run only when the active game declares the `resource_tree_regrowth` feature and the existing `GlobalRules.resource_grows`/`resource_spreads` booleans. With the feature off, no trees are scanned and no crystals are spawned from trees, without errors.

#### Scenario: Feature on
- **WHEN** the active game declares `resource_tree_regrowth = true`, `resource_grows = true`
- **THEN** tree timers tick and spawn crystals within `tree_spawn_radius`

#### Scenario: Feature off
- **WHEN** the active game does not declare `resource_tree_regrowth`
- **THEN** tree processing is skipped and no crystals are spawned, and self-growth/spread of existing crystals is governed by the growth booleans

### Requirement: Generic resource identifiers
`ResourceGrowthSystem` SHALL use generic resource identifiers (`res_*`) rather than Tiberian Sun abbreviations (`tib_*`) in its internal code.

#### Scenario: No tib_ identifiers
- **WHEN** `ResourceGrowthSystem.gd` is linted
- **THEN** it contains no `tib_` identifier

### Requirement: Runtime resource spawns follow the match World root

Resource entities grown or spread at runtime SHALL resolve their spawn parent through the match World root at spawn time, rather than reusing a parent reference cached earlier. This ensures a resource spawned after a match boundary is parented under the current match rather than a released one, and is released with the match that owns it.

#### Scenario: Growth after a match boundary

- **WHEN** a second match starts and its trees grow new resource cells
- **THEN** the new cells are descendants of the new match's World root and growth continues without a warning about a missing parent

#### Scenario: Grown resources are released with the match

- **WHEN** a match that grew resource cells at runtime is replaced
- **THEN** those grown cells are no longer in the scene tree

### Requirement: Tiberium target cells ignore units and respect terrain

When tiberium germinates or spreads onto a cell, the target-cell test SHALL refuse the cell only
for permanent obstructions and terrain: a building, a bib cell, or non-buildable terrain. It
SHALL NOT refuse a cell because a unit is standing on it. This matches the original TS engine,
whose target test (`CellClass::Can_Tiberium_Germinate`) consults buildings, terrain objects, and
`Ground[Land_Type()].Build`, but has no occupant check — tiberium spreads and thickens under
units. The test SHALL route through the shared resource-intent occupancy query
(`SpatialHash.is_cell_free_for_resource`). The existing separate rule that a cell already
containing a resource grows that resource instead of spawning a new one is unchanged and is
evaluated by the caller, not by the occupancy intent.

#### Scenario: Tiberium spreads under an idle unit
- **WHEN** a spread or tree-seed target cell has buildable terrain, no building or bib, and an idle unit standing on it
- **THEN** the cell is accepted and tiberium appears there

#### Scenario: Tiberium grows under a unit
- **WHEN** an existing resource cell with a unit standing on it receives growth
- **THEN** its amount increases as normal

#### Scenario: Water and slope cells reject tiberium
- **WHEN** a candidate target cell's terrain type is neither `""` nor `"clear"`
- **THEN** the cell is refused

#### Scenario: Building and bib cells reject tiberium
- **WHEN** a candidate target cell is a building footprint or a bib cell
- **THEN** the cell is refused

### Requirement: Tiberium spread source must be unoccupied

Tiberium SHALL NOT spread from a source cell that is occupied by any unit. This matches the
original TS engine, where `CellClass::Can_Tiberium_Spread` returns false when `Cell_Occupier()`
is non-null — a patch covered by a unit stops seeding neighbors until that unit leaves, while
the covered patch itself may still grow. The spread driver SHALL consult the shared composite
snapshot's `units` fact for the source cell before attempting any spread. This rule SHALL apply
only to resource-to-resource spread; tree seeding (`_spawn_in_radius`) SHALL NOT be gated by it.

#### Scenario: A unit on a tiberium cell stops it spreading
- **WHEN** a tiberium cell has a unit standing on it and its neighbors are free
- **THEN** no spread originates from that cell while the unit remains

#### Scenario: Removing the unit resumes spread
- **WHEN** the unit leaves the tiberium source cell
- **THEN** that cell may spread to its neighbors again

#### Scenario: Growth of the covered patch is unaffected
- **WHEN** a unit stands on a tiberium cell
- **THEN** the covered patch still grows (thickens) as usual

#### Scenario: Tree seeding is not gated by an occupied source
- **WHEN** a tree's own cell is occupied by a unit
- **THEN** tree seeding within its radius is unaffected by the source-occupied rule
