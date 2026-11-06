# Spec Delta

## MODIFIED Requirements

### Requirement: Component addition rules
The factory SHALL add components based on these rules:
- StatsComponent: ALWAYS
- HealthComponent: if `strength > 0`
- HitboxComponent: if `resource_category == ""` (skipped for resource entities — they use interact hitbox on layer 17)
- SelectComponent: if `entity_type != TERRAIN`
- CombatComponent: if `weapons.size() > 0`
- GuardComponent: if `weapons.size() > 0`
- MovementController: if `speed > 0`
- FoundationComponent: if `(entity_type == BUILDING and blocks_cells)` or `foundation != Vector2i(1,1)`. A non-solid multi-cell building still gets the component through the second branch but registers no cells
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

#### Scenario: 1×1 building gets a FoundationComponent
- **WHEN** EntityData has `entity_type = BUILDING`, `foundation = Vector2i(1, 1)`, and `blocks_cells = true`
- **THEN** the created entity has a FoundationComponent, so its single foundation cell is registered in SpatialHash

#### Scenario: Non-solid 1×1 building registers no cell
- **WHEN** EntityData has `entity_type = BUILDING`, `foundation = Vector2i(1, 1)`, and `blocks_cells = false`
- **THEN** the created entity has no FoundationComponent and registers no building cell, so the cell stays free

#### Scenario: 1×1 non-building gets no FoundationComponent
- **WHEN** EntityData has `entity_type = VEHICLE`, `INFANTRY`, or `AIRCRAFT` and `foundation = Vector2i(1, 1)`
- **THEN** the created entity has no FoundationComponent
