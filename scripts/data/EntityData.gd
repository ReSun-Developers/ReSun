class_name EntityData extends Resource

## Entity type enum
enum EntityType { INFANTRY, VEHICLE, BUILDING, AIRCRAFT, TERRAIN, OVERLAY, SMUDGE }

## Bridge deck kind for bridge overlay entities. RAIL is a HIGH variant: rail
## bridges exist only as high bridges.
enum BridgeKind { NONE, LOW, HIGH, RAIL }

## Identity
@export_group("Identity")
@export var id: String = ""
## Display name shown in UI (e.g., "Minigunner", "Harvester").
@export var display_name: String = ""
## Category of this entity — determines sidebar tab, production queue, and valid behaviors.
@export var entity_type: EntityType = EntityType.TERRAIN
## Original rules.ini section ID for cross-referencing (e.g., "GACNST", "GAPOWR").
@export var legacy_id: String = ""

## Core stats
@export_group("Core Stats")
## Maximum hit points. Entity is destroyed when health reaches 0.
@export var strength: int = 0
## Health percentage (0–100) at which this entity spawns. -1 = use full strength.
@export var spawn_health: int = 0
## Armor type string (e.g., "none", "wood", "light", "heavy", "concrete").
@export var armor: String = "none"
## Cost in credits to produce this entity.
@export var cost: int = 0
## Tech level required to build: the house's current level must be at least
## this. -1 = never buildable (original TS semantics).
@export var tech_level: int = -1
## Sight range in cells — how far this entity can see on the map.
@export var sight: int = 1
## Whether this entity can be selected by dragging a box over it.
@export var is_drag_selectable: bool = true
## Player IDs that can own this entity (e.g., ["GDI", "Nod"]).
@export var owner: PackedStringArray = []
## Score points awarded for killing this entity.
@export var points: int = 0
## Entity IDs to spawn on death (e.g., ["GDI_BUILDING_RUBBLE"] for debris).
@export var death_explosion_ids: PackedStringArray = []

## Combat
@export_group("Combat")
## Weapons this entity uses when attacking.
@export var weapons: Array[WeaponData] = []
## Weapons used when this unit is elite (promoted). Empty = use normal weapons.
@export var elite_weapons: Array[WeaponData] = []
## Per-unit binding of weapons to ArtData sockets, with firing discipline.
## Empty = each weapon is body-mounted (whole body faces the target); the
## single-socket default applies when art_data declares exactly one socket.
@export var weapon_mount_groups: Array[WeaponMountGroupData] = []
## Threat level for AI targeting (higher = prioritized). 0 = no threat.
@export var threat_posed: int = 0

## Movement
@export_group("Movement")
## Movement speed as the TS `Speed` value: leptons per game frame. 0 = immobile.
@export var speed: float = 0.0
## Movement zone — which terrain types this entity can traverse (e.g., "foot", "track", "float").
@export var movement_zone: String = ""
## Locomotor type — determines movement behavior and animation (e.g., "Walk", "Drive", "Fly").
@export var locomotor: String = ""
## Rotation speed in degrees per second when turning.
@export var rotation_speed: float = 180.0
## Whether this entity can crush infantry underfoot.
@export var crusher: bool = false
## Whether this entity can be crushed by larger units.
@export var crushable: bool = false
## Weight class — affects crushing interactions (heavier units crush lighter ones).
@export var weight: float = 1.0

## Vehicle behavior
@export_group("Vehicle Behavior")
## Unit cannot fire while moving.
# ponytail: schema-first, no consumer yet
@export var no_moving_fire: bool = false
## Unit must deploy before firing (e.g., artillery, tick tank).
# ponytail: schema-first, no consumer yet
@export var deploy_to_fire: bool = false
## Speed factor for cloaking transition (0 = instant, higher = slower).
# ponytail: schema-first, no consumer yet
@export var cloaking_speed: float = 0.0
## Whether this unit can be promoted to elite status.
# ponytail: schema-first, no consumer yet
@export var trainable: bool = false
## Whether this unit can pick up crate power-ups.
# ponytail: schema-first, no consumer yet
@export var crate_goodie: bool = false
## Whether this unit tilts visually on sloped terrain.
# ponytail: schema-first, no consumer yet
@export var is_tilter: bool = false
## Turret spins continuously when unit is idle.
# ponytail: schema-first, no consumer yet
@export var turret_spins: bool = false
## Unit has a visible targeting laser beam.
# ponytail: schema-first, no consumer yet
@export var target_laser: bool = false

## Foundation
@export_group("Foundation")
## Footprint in cells (width × depth) — determines placement grid and collision.
@export var foundation: Vector2i = Vector2i(1, 1)
## Whether this building's foundation cells are solid (block placement and pathing).
## False for walkable buildings such as pavement and invisible light emitters.
@export var blocks_cells: bool = true
## Visual height in world units — affects bounding box and selection overlay.
@export var height: float = 1.0
## Cells that form the building's bib (the raised foundation edge).
@export var bib_cells: Array[Vector2i] = []
## 3D hitbox size in world units for projectile collision.
@export var hitbox_size: Vector3 = Vector3.ZERO

## Aircraft behavior
@export_group("Aircraft Behavior")
## Altitude at which this aircraft flies (in world units).
# ponytail: schema-first, no consumer yet
@export var flight_level: float = 0.0
## Whether this aircraft can land on helipads or ground.
# ponytail: schema-first, no consumer yet
@export var landable: bool = false
## Whether this aircraft can carry other units (e.g., carryall).
# ponytail: schema-first, no consumer yet
@export var carryall: bool = false

## Dock — building-side configuration for the dock system.
@export_group("Dock")
## Local offset from the building's top-left cell to the dock cell.
@export var dock_position: Vector3 = Vector3.ZERO
## Rotation in degrees the docker entity snaps to when docking (e.g. -90 for west-facing).
@export var dock_rotation: float = 0.0
## Whether this building has a dock for unloading cargo.
@export var dock_unload: bool = false
## Resource categories this dock accepts (e.g. ["tiberium"]). Empty = accepts all.
@export var accepted_resource_categories: PackedStringArray = []

## Power
@export_group("Power")
## Power output in watts (positive = generating, negative = consuming).
@export var power: int = 0
## Whether this building requires power to function (shutdown when low power).
@export var powered: bool = false

## Sensor & Cloak
@export_group("Sensor & Cloak")
## Whether this building provides radar/minimap functionality.
@export var radar: bool = false
## Whether this building has a sensor array (detects cloaked units).
# ponytail: schema-first, no consumer yet
@export var sensors: bool = false
## Whether this building generates a cloak field for nearby friendly units.
# ponytail: schema-first, no consumer yet
@export var cloak_generator: bool = false
## Radius in cells of the cloak generator field.
# ponytail: schema-first, no consumer yet
@export var cloak_radius_cells: int = 0

## Building Capabilities
@export_group("Building Capabilities")
## Whether this building is a construction yard (can deploy from MCV).
# ponytail: schema-first, no consumer yet
@export var construction_yard: bool = false
## Whether this building is a weapons factory (produces vehicles).
# ponytail: schema-first, no consumer yet
@export var weapons_factory: bool = false
## Whether this building is a refinery (processes harvested resources).
# ponytail: schema-first, no consumer yet
@export var refinery: bool = false
## Whether this building is a helipad (lands and reloads aircraft).
# ponytail: schema-first, no consumer yet
@export var helipad: bool = false
## Per-category storage capacity this building grants (e.g. {"tiberium": 2000}).
# Summed per player by EconomyManager.get_storage_capacity.
@export var storage_capacity: Dictionary = {}
## Whether units can reload ammunition at this building.
# ponytail: schema-first, no consumer yet
@export var unit_reload: bool = false
## Upgrade IDs available at this building (e.g., ["WEAP_UPGRADE"]).
# ponytail: schema-first, no consumer yet
@export var upgrades: PackedStringArray = []

## Factory — which production queue this entity belongs to (used for queue routing).
@export_group("Factory")
## Set on entities that ARE produced (e.g. buildings → "BuildingType").
@export var buildable_queue: String = ""
## Production type — what this building produces (used to find the producing building).
## Set on production buildings only (e.g. Construction Yard → "BuildingType").
@export var factory: String = ""
## Entity ID of the free unit spawned when this building is placed (e.g., "GDI_HARVESTER").
@export var free_unit: String = ""

## Exit — where units spawn and exit from this building.
@export_group("Exit")
## Local-space offset where unit appears inside building (Vector3.ZERO = no exit).
@export var spawn_offset: Vector3 = Vector3.ZERO
## Local-space offset where unit exits to (e.g., Vector3(0, 0, 2) = south side).
@export var exit_offset: Vector3 = Vector3.ZERO
## Rotation in degrees the unit faces after exit.
@export var exit_facing: int = 0
## Seconds to wait after spawn before unit starts moving (door animation time).
@export var exit_delay: float = 0.0
## Whether this building supports rally points for units after exit.
@export var has_rally_point: bool = false

## Transport — unit-side cargo and docking configuration.
@export_group("Transport")
## Number of infantry passengers this unit can carry.
@export var passengers: int = 0
## Dock type ID this unit docks with (e.g. "GDI_REFINERY").
@export var dock: String = ""
## Whether this unit is a harvester (auto-seeks resources and docks when full).
@export var harvester: bool = false
## Resource categories this harvester collects. Empty = every category.
@export var harvestable_categories: PackedStringArray = []
## Maximum resource bales this unit can carry (raw units, not credit value).
@export var storage: int = 0
## Animation scale key for pip overlays on the sidebar.
@export var pip_scale: String = ""
## Seat pip color drawn for this entity while it rides as a passenger in a transport.
@export var pip_color: Color = Color.WHITE

## Resource entity — configuration for harvestable resource entities.
@export_group("Resource Entity")
## Category string (e.g. "tiberium", "spice"). Empty = not a resource entity.
@export var resource_category: String = ""
## ResourceType ID for this crystal (e.g. "tiberium_green", "tiberium_blue").
@export var resource_type_id: String = ""
## Regrowth rate override — negative means use the ResourceType's grow_rate.
@export var resource_regrowth_rate: float = -1.0
## Renders through the procedural ResourceComponent instead of an ArtComponent.
@export var procedural_resource_visual: bool = false
## Breakable surface (e.g. ice): drowns occupants when destroyed. Behavior only
## runs when the game enables the `breakable_ice` feature.
@export var breakable_surface: bool = false

## Resource tree spawner — configuration for entities that spawn resource crystals.
@export_group("Resource Tree Spawner")
## True when this entity seeds resource crystals around itself.
@export var resource_spawner: bool = false
## Entity ID of the crystal to spawn (e.g. "TIBERIUM_RIPARIUS").
@export var spawned_entity_id: String = ""
## Spawn radius in cells around this entity.
@export var radius_cells: int = 0
## Maximum number of crystal nodes to spawn within the radius.
@export var node_count: int = 0
## Initial spawn density (0.0–1.0) — fraction of max nodes placed on spawn.
@export var spawn_strength: float = 0.5
## Maximum spawn density (0.0–1.0) — cap for regrowth.
@export var max_spawn_strength: float = 1.0

## Bridge overlay — a walkable deck surface spanning one or more cells.
@export_group("Bridge")
## Deck kind: NONE = not a bridge, LOW = surface-level deck, HIGH = elevated deck,
## RAIL = elevated rail deck (HIGH variant).
@export var bridge_kind: BridgeKind = BridgeKind.NONE
## Land the covered deck lane resolves: `road` for road/low/high lanes and rail
## outer lanes, `railroad` for a rail middle lane.
@export var bridge_land: String = "road"
## Shared identifier for the cells of one bridge piece; empty for a standalone cell.
@export var bridge_piece_id: String = ""
## True when this overlay is an indestructible bridge end piece (destruction is #250).
@export var bridge_end: bool = false
## HIGH bridge deck rise above the cell terrain height, in world units. Defaults
## to four height steps (4 * TerrainSystem.HEIGHT_STEP = 3.26).
@export var bridge_rise: float = 4.0 * TerrainSystem.HEIGHT_STEP
## Deck surface level: 1 = first deck above ground. Defaults to 0 (ground), which
## is inert for a non-bridge entity and invalid for a bridge. Higher levels stack
## extra-high decks, bounded by MAX_HEIGHT.
@export var bridge_level: int = 0

## Special abilities
@export_group("Special Abilities")
## Can cloak (become invisible until attacking).
@export var cloakable: bool = false
## Regenerates health slowly over time.
@export var self_healing: bool = false
## Can destroy buildings with C4 charges.
@export var c4: bool = false
## Can capture enemy buildings (engineer class).
@export var engineer: bool = false
## Can disguise as enemy units.
@export var disguise: bool = false
## Can infiltrate enemy buildings for intel.
@export var agent: bool = false
## Can steal credits from enemy buildings.
@export var thief: bool = false
## Immune to resource entity damage (tiberium, veins).
@export var immune_to_resource_damage: bool = false
## Immune to tiberium vein damage.
@export var immune_to_veins: bool = false
## Can be captured by engineers (neutral buildings).
@export var capturable: bool = false

@export_group("Building Properties")
## Max empty-cell gap (Chebyshev) allowed between this building's footprint and
## existing friendly footprints when placing. <= 0 = no requirement.
@export var adjacent: int = 0
## Whether the building is crewed (affects survival on destruction).
@export var crewed: bool = false
## Whether the building explodes on death (affects debris and damage).
@export var explodes: bool = false
## Whether this building can be toggled on/off to save power.
# ponytail: schema-first, no consumer yet
@export var toggle_power: bool = false

## Build menu
@export_group("Build Menu")
## Whether this entity appears in the build sidebar.
@export var buildable: bool = false
## Multiplier on the cost-derived build duration (TS formula). 1.0 = default,
## 0.5 = half duration, 2.0 = double. Leave unset unless tuning an entity.
@export var build_time_mult: float = 1.0
## Max count per player (0 = unlimited).
@export var build_limit: int = 0

## Prerequisites
@export_group("Prerequisites")
## Entity IDs that must exist before this entity can be built (any-of).
@export var prerequisite: PackedStringArray = []
## Entity IDs that must ALL exist before this entity can be built (all-of).
@export var prerequisite_necessary: PackedStringArray = []

## Deploy — vehicle↔building transformation configuration.
@export_group("Deploy")
## Entity id to create when this entity deploys (e.g., "GDI_CONSTRUCTION_YARD" for MCV).
@export var deploys_into: String = ""
## Entity id to create when this entity undeploys (e.g., "GDI_MCV" for ConYard).
@export var undeploys_into: String = ""
## Rotation in degrees the source entity rotates to before deploying (0 = default/north).
@export var deploy_rotation: float = 0.0
## Rotation in degrees the source entity rotates to before undeploying (0 = default/north).
@export var undeploy_rotation: float = 0.0

## Art reference
@export_group("Art")
@export var art_data: ArtData = null

## Voice set reference — drives select/order voice playback (optional).
@export var voice_data: VoiceData = null

## Death sound report(s) — comma-separated audio ids played on death when this
## entity has no die voice set (see voice_data). One known id is chosen at
## random. Independent of voice_data; an entity may define either, both, or
## neither. Empty plays nothing.
@export var sound_die: String = ""

## Default build-speed factor when GlobalRules is unavailable (e.g. isolated tests).
const DEFAULT_BUILD_SPEED: float = 0.4

## Movement zones compatible with each locomotor type. Zone is metadata (TS
## pathfinding domain class); passability is driven by the locomotor alone.
const LOCOMOTOR_ZONES: Dictionary = {
    "Foot": ["Infantry", "InfantryDestroyer"],
    "Track":
    [
        "Normal",
        "Crusher",
        "Destroyer",
        "AmphibiousCrusher",
        "AmphibiousDestroyer",
        "InfantryDestroyer",
    ],
    "Wheel": ["Normal", "Destroyer", "Crusher", "InfantryDestroyer"],
    "Hover":
    [
        "Normal",
        "Destroyer",
        "AmphibiousCrusher",
        "AmphibiousDestroyer",
        "InfantryDestroyer",
        "Crusher",
    ],
    "Amphibious":
    [
        "AmphibiousCrusher",
        "AmphibiousDestroyer",
        "Destroyer",
        "InfantryDestroyer",
        "Normal",
    ],
    "Fly": ["Fly"],
    "Jumpjet": ["Fly"],
    "Subterranean": ["Subterannean"],
    "Ship": ["Subterannean", "Fly", "Destroyer", "AmphibiousCrusher", "AmphibiousDestroyer"],
}


## Returns true when the given movement zone is compatible with the locomotor.
static func is_movement_zone_compatible(locomotor_id: String, zone: String) -> bool:
    if zone.is_empty():
        return true
    var zones: Array = LOCOMOTOR_ZONES.get(locomotor_id, [])
    return zones.has(zone)


## Returns effective build time in seconds, calculated from cost using the TS
## formula and scaled by the per-entity build_time_mult. An explicit build_speed
## overrides the game-wide factor from GlobalRules (falling back to
## DEFAULT_BUILD_SPEED when rules are unavailable).
func get_build_time(build_speed: float = -1.0) -> float:
    if build_speed < 0.0:
        build_speed = DEFAULT_BUILD_SPEED
        var rules := EntityFactory.get_global_rules() as GlobalRules
        if rules:
            build_speed = rules.build_speed
    # TS formula: (cost / 1000) * BuildSpeed * 60, scaled by per-entity multiplier.
    return cost * build_speed * 60.0 / 1000.0 * build_time_mult


func validate() -> PackedStringArray:
    var errors: PackedStringArray = []
    if id.is_empty():
        errors.append("EntityData: id is empty")
    if (
        strength <= 0
        and entity_type != EntityType.TERRAIN
        and entity_type != EntityType.OVERLAY
        and entity_type != EntityType.SMUDGE
    ):
        errors.append("%s: strength must be > 0" % id)
    if cost < 0:
        errors.append("%s: cost must be >= 0" % id)
    if owner.is_empty():
        errors.append("%s: owner is empty" % id)
    for weapon in weapons:
        if weapon and weapon.id.is_empty():
            errors.append("%s: weapon has empty id" % id)
    if buildable and strength <= 0:
        errors.append("%s: buildable building must have strength > 0" % id)
    var rules := GlobalRules.get_current()
    if rules:
        if not locomotor.is_empty() and rules.get_locomotor(locomotor) == null:
            errors.append("%s: unknown locomotor %s" % [id, locomotor])
        if (
            not movement_zone.is_empty()
            and not is_movement_zone_compatible(locomotor, movement_zone)
        ):
            errors.append(
                "%s: movement_zone %s contradicts locomotor %s" % [id, movement_zone, locomotor]
            )
    var seen_weapon_indices: Dictionary = {}
    for group in weapon_mount_groups:
        if group == null:
            errors.append("%s: null weapon mount group" % id)
            continue
        if group.weapon_index < 0 or group.weapon_index >= weapons.size():
            errors.append("%s: mount group weapon_index %d out of range" % [id, group.weapon_index])
        elif seen_weapon_indices.has(group.weapon_index):
            errors.append(
                "%s: duplicate mount group for weapon_index %d" % [id, group.weapon_index]
            )
        seen_weapon_indices[group.weapon_index] = true
        if group.socket_ids.is_empty():
            errors.append("%s: mount group has no socket ids" % id)
        for socket_id in group.socket_ids:
            if socket_id.is_empty():
                errors.append("%s: mount group has empty socket id" % id)
            elif art_data == null or art_data.get_socket(socket_id) == null:
                errors.append("%s: mount group references unknown socket %s" % [id, socket_id])
    return errors


## Resolves the effective weapon mount groups for this entity. When no groups
## are declared and art_data declares exactly one socket, every weapon binds to
## that socket (one group per weapon so each keeps its own cooldown). Returns an
## empty array when no groups apply — every weapon is then body-mounted.
func resolved_mount_groups() -> Array[WeaponMountGroupData]:
    if not weapon_mount_groups.is_empty():
        return weapon_mount_groups
    if art_data == null or art_data.sockets.size() != 1:
        return []
    var sole := art_data.sockets[0]
    if sole == null or sole.id.is_empty():
        return []
    var groups: Array[WeaponMountGroupData] = []
    for i in weapons.size():
        var group := WeaponMountGroupData.new()
        group.weapon_index = i
        group.socket_ids = PackedStringArray([sole.id])
        groups.append(group)
    return groups


func has_special_abilities() -> bool:
    return (
        cloakable
        or self_healing
        or c4
        or engineer
        or disguise
        or agent
        or thief
        or immune_to_resource_damage
        or immune_to_veins
        or capturable
    )
