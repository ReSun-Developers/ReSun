# entity-factory Specification

## Purpose

EntityFactory creates entities from EntityData resources and attaches components by data-driven rules.
## Requirements
### Requirement: EntityFactory creates entities from data
The system SHALL provide an `EntityFactory.gd` autoload singleton that creates entities from EntityData resources. The factory SHALL instantiate a base `Entity.tscn` scene and add components dynamically based on data properties.

#### Scenario: Create infantry entity
- **WHEN** `EntityFactory.create_entity("E1")` is called
- **THEN** the factory looks up EntityData with id "E1", instantiates a base scene, adds StatsComponent, HealthComponent, HitboxComponent, SelectComponent, MovementController, CombatComponent, ArtComponent, and returns the configured entity

#### Scenario: Create terrain entity
- **WHEN** `EntityFactory.create_entity("TREE01")` is called
- **THEN** the factory instantiates a base scene, adds StatsComponent, HealthComponent (if strength > 0), HitboxComponent, FoundationComponent, ArtComponent — but NOT SelectComponent (entity_type = TERRAIN)

#### Scenario: Create building entity
- **WHEN** `EntityFactory.create_entity("GAPOWR")` is called
- **THEN** the factory instantiates a base scene, adds StatsComponent, HealthComponent, HitboxComponent, SelectComponent, FoundationComponent, PowerComponent, ArtComponent, and returns the configured entity

### Requirement: Component addition rules
The factory SHALL add components based on these rules:
- StatsComponent: ALWAYS
- HealthComponent: if `strength > 0`
- HitboxComponent: if `resource_category == ""` (skipped for resource entities — they use interact hitbox on layer 17)
- SelectComponent: if `entity_type != TERRAIN`
- CombatComponent: if `weapons.size() > 0`
- GuardComponent: if `weapons.size() > 0`
- MovementController: if `speed > 0`
- FoundationComponent: if `foundation != Vector2i(1,1)`
- PowerComponent: if `power != 0` or `powered == true`
- RadarComponent: if `radar == true`
- FactoryComponent: if `buildable_queue != ""`
- TransportComponent: if `passengers > 0` or `harvester == true`
- PassengerComponent: if `entity_type == INFANTRY`
- SpecialAbilityComponent: if any ability flag is true
- ArtComponent: if `resource_category != "tiberium"` (skipped for tiberium resource entities)
- ResourceTreeComponent: if `resource_category == "tiberium_tree"`
- ResourceComponent: if `resource_category != ""` and `resource_category != "tiberium_tree"` (trees are spawners, not harvestable nodes)
- HarvestComponent: if `harvester == true`
- DockHostComponent: if `dock_position != Vector3.ZERO`
- DockClientComponent: if `dock != ""`
- DockUnloadComponent: if `dock_unload == true`
- FreeUnitComponent: if `free_unit != ""`
- VoiceComponent: if `voice_data != null`

#### Scenario: Minimal entity (terrain rock)
- **WHEN** EntityData has `entity_type = TERRAIN`, `strength = 0`, `foundation = Vector2i(1,1)`, `speed = 0`, `weapons = []`
- **THEN** entity gets only StatsComponent, HitboxComponent, ArtComponent

#### Scenario: Full entity (Nod Buggy)
- **WHEN** EntityData has `entity_type = VEHICLE`, `strength = 220`, `speed = 10`, `weapons = [raider_cannon]`, `foundation = Vector2i(1,1)`
- **THEN** entity gets StatsComponent, HealthComponent, HitboxComponent, SelectComponent, CombatComponent, GuardComponent, MovementController, ArtComponent

#### Scenario: Harvester entity
- **WHEN** EntityData has `harvester = true`, `dock = "PROC"`, `storage = 1`, `speed = 5.0`
- **THEN** entity gets StatsComponent, HealthComponent, HitboxComponent, SelectComponent, MovementController, TransportComponent, HarvestComponent, DockClientComponent, ArtComponent

#### Scenario: Refinery entity
- **WHEN** EntityData has `dock_position = Vector3(6, 0, 2)`, `dock_unload = true`, `accepted_resource_categories = ["tiberium"]`, `free_unit = "HARV"`
- **THEN** entity gets StatsComponent, HealthComponent, HitboxComponent, SelectComponent, FoundationComponent, DockHostComponent, DockUnloadComponent, FreeUnitComponent, ArtComponent

#### Scenario: Resource crystal entity
- **WHEN** EntityData has `resource_category = "tiberium"`, `resource_type_id = "tiberium_green"`, `strength = 300`
- **THEN** entity gets StatsComponent, HealthComponent, ResourceComponent, ArtComponent (no SelectComponent — entity_type = TERRAIN)

#### Scenario: Resource tree entity
- **WHEN** EntityData has `spawned_entity_id = "TIB"`, `radius_cells = 8`, `node_count = 12`
- **THEN** entity gets StatsComponent, FoundationComponent, ResourceTreeComponent, ArtComponent (no HealthComponent if strength = 0, no SelectComponent)

#### Scenario: Voiced unit entity
- **WHEN** EntityData has a `voice_data` reference (e.g. a VoiceData .tres)
- **THEN** entity gets a VoiceComponent holding that reference, in addition to its normal components

#### Scenario: Infantry entity
- **WHEN** EntityData has `entity_type = INFANTRY`
- **THEN** entity gets a PassengerComponent configured from its EntityData (including `pip_color`), in addition to its normal components

#### Scenario: Vehicle entity gets no PassengerComponent
- **WHEN** EntityData has `entity_type = VEHICLE`
- **THEN** entity gets no PassengerComponent

### Requirement: Component wiring
The factory SHALL wire component references programmatically after instantiation. HitboxComponent and SelectComponent SHALL receive a reference to HealthComponent.

#### Scenario: Health component reference wiring
- **WHEN** an entity has both HealthComponent and HitboxComponent
- **THEN** HitboxComponent.health_component is set to the HealthComponent node

### Requirement: EntityFactory caching
The factory SHALL cache loaded EntityData resources by id for fast lookup. The factory SHALL provide `get_all_by_type(entity_type: EntityType) -> Array[EntityData]` to query cached entities by category.

#### Scenario: Repeated entity creation
- **WHEN** `create_entity("E1")` is called 10 times
- **THEN** EntityData is loaded once and cached, not re-loaded from disk each time

#### Scenario: Query entities by type
- **WHEN** `get_all_by_type(EntityData.EntityType.BUILDING)` is called
- **THEN** the factory returns an Array[EntityData] containing all cached entities where `entity_type == BUILDING`

#### Scenario: Query returns empty for no matches
- **WHEN** `get_all_by_type(EntityData.EntityType.AIRCRAFT)` is called and no aircraft entities are cached
- **THEN** the factory returns an empty array

#### Scenario: Query includes all subdirectories
- **WHEN** EntityData files exist in `games/ts/entities/structures/gdi/` and `games/ts/entities/structures/nod/`
- **THEN** `get_all_by_type(BUILDING)` returns entities from both directories

#### Scenario: Invalid entity id
- **WHEN** `create_entity("INVALID_ID")` is called and no matching EntityData exists
- **THEN** the factory returns null and logs an error

#### Scenario: Base scene missing
- **WHEN** `Entity.tscn` is not found at the expected path
- **THEN** the factory logs an error and returns null

### Requirement: Death cleanup with die voice
On `HealthComponent.health_zero`, EntityFactory SHALL free the entity. If the entity has a `VoiceComponent` with a non-empty `VoiceData.die` set, EntityFactory SHALL play a random die variant via `AudioManager.play_voice` before freeing. Entities without a die voice set play nothing.

#### Scenario: Death plays die voice
- **WHEN** a unit with a non-empty `VoiceData.die` reaches zero health
- **THEN** a random die variant SHALL play and the entity SHALL be freed

#### Scenario: Voiceless death is silent
- **WHEN** an entity without a VoiceComponent, or with an empty `die` set, reaches zero health
- **THEN** no sound SHALL play and the entity SHALL be freed

### Requirement: Factory content branches keyed on data flags
`EntityFactory` and `EntityPlacer` SHALL select resource-spawner, procedural-resource and breakable-surface behavior from `EntityData` boolean flags, and SHALL NOT compare against Tiberian Sun category or id strings such as `"tiberium"`, `"tiberium_tree"` or an `"ICE"` legacy-id prefix.

#### Scenario: Spawner by flag
- **WHEN** an entity's data has `resource_spawner = true`
- **THEN** the factory adds the resource-tree component and the `resource_trees` group without matching a category string

#### Scenario: Procedural resource by flag
- **WHEN** an entity's data flags a procedural resource visual
- **THEN** the factory omits the ArtComponent without matching `"tiberium"`

#### Scenario: Breakable surface by flag
- **WHEN** an entity's data has `breakable_surface = true` and the game enables `breakable_ice`
- **THEN** the factory attaches the breakable-surface component without inspecting `legacy_id`

### Requirement: Ice component gated by feature flag
`EntityFactory` SHALL attach the breakable-surface component only when `GameContext.has_feature("breakable_ice")` is true. When the flag is off the entity SHALL spawn normally with no ice group membership.

#### Scenario: Ice disabled
- **WHEN** an entity with `breakable_surface = true` spawns in a game without `breakable_ice`
- **THEN** it has no IceComponent and is not in the `ice` group

### Requirement: Bridge component attached to bridge overlay entities
`EntityFactory` SHALL attach a `BridgeComponent` to an entity whose `EntityData` declares a bridge kind. The component SHALL join the `"bridge"` group so the live registry resolves the entity's `(cell, level)` surface, and SHALL expose the entity's bridge kind (low/high/rail), end flag, piece identifier, deck level, and walkable surface height. Non-bridge entities SHALL NOT receive the component. The attach branch SHALL pass the entity's deck level and kind into the component.

#### Scenario: Bridge entity gets component
- **WHEN** a bridge overlay entity is created
- **THEN** it has a `BridgeComponent` and is a member of the `"bridge"` group

#### Scenario: Non-bridge entity unaffected
- **WHEN** a non-bridge entity is created
- **THEN** it has no `BridgeComponent` and is not in the `"bridge"` group

#### Scenario: Component publishes deck surface data
- **WHEN** a high bridge entity's component resolves its surface
- **THEN** it reports the deck level, kind, and the surface height (ground plus `bridge_rise`)

#### Scenario: Rail bridge attaches as high
- **WHEN** a rail bridge entity is created
- **THEN** its component reports the rail kind on a high deck level

### Requirement: Warhead impact FX

On each damaging hit, `EntityFactory` SHALL resolve the hit's warhead from the `HealthComponent.damage_taken` `damage_type` through `GlobalRules` and play `warhead.impact_fx` through `FxSystem.play` at the victim's `global_position`. A `null` `impact_fx`, an empty `damage_type`, or an unresolvable warhead SHALL play nothing. Because the trigger is the shared damage signal, this SHALL cover both the projectile and the fallback hitscan damage paths without a separate projectile hook. The per-victim report SHALL apply only to combat entities; cell overlays (bridge span, ice, tiberium) SHALL be excluded from this trigger, because their damage is applied by the warhead-gated cell pass, which plays the shot's single report once at the impact point. One resolved shot SHALL therefore play the impact effect at most once, never once per damaged cell victim. Fog gating is delegated to `FxSystem` (see the `fx-system` capability).

#### Scenario: Damaging hit plays impact FX

- **WHEN** an entity takes damage whose warhead has a non-null `impact_fx`
- **THEN** the effect is played at the victim's position

#### Scenario: Projectile hit path

- **WHEN** a projectile detonates on a victim through the hitbox pipeline and the warhead has an `impact_fx`
- **THEN** the impact effect is played at the victim

#### Scenario: Hitscan hit path

- **WHEN** a weapon applies fallback hitscan damage and the warhead has an `impact_fx`
- **THEN** the impact effect is played at the victim

#### Scenario: Mixed entity and overlay hit plays one impact effect

- **WHEN** a shot damages both a combat entity and a cell overlay at the same impact point and the warhead has an `impact_fx`
- **THEN** exactly one impact effect plays at that point, not one per victim

#### Scenario: No impact FX is silent

- **WHEN** the resolved warhead's `impact_fx` is `null`
- **THEN** no effect node is spawned

#### Scenario: Non-warhead damage is silent

- **WHEN** an entity takes damage with an empty `damage_type` (crush, drowning)
- **THEN** no impact effect is played

#### Scenario: Unknown warhead is silent

- **WHEN** `damage_type` does not resolve to a warhead in the GlobalRules registry
- **THEN** no impact effect is played and no error is raised

### Requirement: Single entity spawn seam

`EntityFactory` SHALL provide `spawn(entity_id, placement)` as the single seam through which entities enter the world. The seam SHALL own assembly and insertion: it resolves the entity data (applying `placement.overrides`), assigns `placement.player_id` and `placement.world_pos` before the entity joins the scene tree, attaches it under `placement.parent` (defaulting to the match world's entity container, then the current scene), and — for a non-detached spawn — emits a spawn event. Callers SHALL retain placement policy — cost deduction, placement validation, terrain flattening, build-up animation, map rotation and deck height, health overrides, and their post-insertion steps — and SHALL NOT re-implement insertion.

#### Scenario: Entity enters the world through one call
- **WHEN** `spawn("GAPOWR", {world_pos, player_id})` is called
- **THEN** a fully assembled entity is attached under the world entity container with the given position and player

#### Scenario: Player is assigned before tree insertion
- **WHEN** a spawned entity has a MovementController
- **THEN** its player id is set before it enters the tree, so the movement crush filter reads the real id on `_ready`

#### Scenario: Position is assigned before tree insertion
- **WHEN** a spawned building has a FoundationComponent
- **THEN** its world position is set before it enters the tree, so foundation registration derives the correct origin cell

#### Scenario: Spawn event is emitted once for a world entity
- **WHEN** a non-detached entity is spawned
- **THEN** exactly one spawn event is emitted carrying the entity, its data, and its player id

#### Scenario: Caller keeps its post-insertion steps
- **WHEN** a caller performs post-insertion work (movement sub-slot assignment, map rotation/health overrides, state snapshot, terrain flattening, build-up)
- **THEN** that work still runs after the entity is inserted

### Requirement: Detached spawn for previews and editor content

`spawn(entity_id, placement)` SHALL support `placement.detached = true`, which inserts an entity into the scene for rendering but excludes it from world registration: no occupancy cells are registered, no `entities`, `selectable`, or `drag_selectable` groups are added, no player is registered, and no spawn event is emitted. Detachment SHALL be applied through the seam as a single shared marker that registration, guard and free-unit activation, fog, and unit-mesh exclusion all read, and it SHALL replace the previous per-caller preview flag.

#### Scenario: Detached preview registers nothing
- **WHEN** a building is spawned with `detached = true`
- **THEN** it is visible in the scene but registers no occupancy cells, joins no groups, and emits no spawn event

#### Scenario: Runtime spawn is registered
- **WHEN** the same building is spawned without `detached`
- **THEN** it registers occupancy and emits a spawn event

#### Scenario: Detached unit is excluded from gameplay and rendering systems
- **WHEN** a detached unit is spawned
- **THEN** guard acquisition, free-unit spawning, fog rendering, and the unit multimesh renderer treat it as absent, and occupancy is not registered

