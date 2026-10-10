class_name BridgeComponent extends Node

## Walkable bridge deck overlay. Joins the parent entity to the "bridge" group so
## SpatialHash keys its (cell, level), and publishes
## {surface_height, bridge_kind, is_end, piece_id, level} to the registry. Rendered
## Y and pathing read the deck via TerrainSystem.get_cell_surface_height.

@export var piece_id: String = ""

var _bridge_kind: EntityData.BridgeKind = EntityData.BridgeKind.NONE
var _bridge_land: String = "road"
var _is_end: bool = false
var _bridge_rise: float = 4.0 * TerrainSystem.HEIGHT_STEP
var _bridge_level: int = 1
var _destroyed: bool = false

@onready var _health: HealthComponent = get_parent().get_node_or_null("HealthComponent")


func configure(data: EntityData) -> void:
    _bridge_kind = data.bridge_kind
    _bridge_land = data.bridge_land
    _is_end = data.bridge_end
    _bridge_rise = data.bridge_rise
    _bridge_level = data.bridge_level
    # RAIL is structurally high-only: it is never authored low, so it shares the
    # HIGH geometry/rise and the HIGH indestructibility rule (no low-rail path).


func _ready() -> void:
    var root := get_parent() as Node3D
    # Detached entities (editor/preview) never join the bridge registry.
    if root and not root.get_meta("detached", false):
        if root.has_meta("bridge_piece_id"):
            piece_id = String(root.get_meta("bridge_piece_id"))
        if not root.is_in_group("bridge"):
            root.add_to_group("bridge")
    # Destructibility split (#250): only LOW normal span pieces hook the revert.
    # LOW end pieces (slope ramps) and every high-bridge cell are indestructible.
    # RAIL is a HIGH variant, so a rail piece is never a destruction target.
    if (
        root
        and not root.get_meta("detached", false)
        and _health
        and _bridge_kind == EntityData.BridgeKind.LOW
        and not _is_end
    ):
        _health.health_zero.connect(_on_destroyed)


## Registry contract: live per-cell deck metadata. Computes the surface height on
## read so it is correct even when the entity's global_position settles after
## `_ready` (spawned overlays set position after add_child).
func get_bridge_cell_data() -> Dictionary:
    if _destroyed:
        return {}
    var root := get_parent() as Node3D
    if root == null:
        return {}
    return {
        "surface_height": get_surface_height(),
        "bridge_kind": _bridge_kind,
        "land": _bridge_land,
        "is_end": _is_end,
        "piece_id": piece_id,
        "level": _bridge_level,
    }


## World Y of the walkable deck at the entity's cell: the cell's lowest terrain
## corner plus the authored `bridge_rise`. The same formula serves every kind, so
## `bridge_rise` is the single authored knob (LOW ~0.5 step, HIGH ~4 steps).
## Reads the autoload directly because TerrainSystem.get_cell_surface_height
## re-enters this registry.
func get_surface_height() -> float:
    var root := get_parent() as Node3D
    var terrain := _resolve_terrain()
    if root == null or terrain == null:
        return 0.0
    var cell := CellUtil.world_to_cell(root.global_position)
    # ponytail: min-corner base keeps a span over flat ground flat and stops a
    # deck cell from inheriting a neighbouring end/cliff's raised corners (the
    # smooth cell-centre sample averaged them in, fragmenting the deck by 2
    # steps). A per-piece authored absolute grade is the upgrade if non-flat
    # spans ever matter.
    var base: float = terrain.get_cell_min_height(cell)
    return base + _bridge_rise


## #250 hook: a destroyed non-end piece drops out of the "bridge" group so the
## next SpatialHash rebuild reverts its cell. Destruction gameplay is #250.
func _on_destroyed() -> void:
    _destroyed = true
    var root := get_parent() as Node3D
    if root:
        root.remove_from_group("bridge")


## Shared-`piece_id` mechanism for the placement API: tags this cell's root meta
## and stamps the component so all cells of one 3-cell piece carry the same id.
func assign_piece_id(id: String) -> void:
    piece_id = id
    var root := get_parent() as Node3D
    if root:
        root.set_meta("bridge_piece_id", id)


func _resolve_terrain() -> Node:
    var tree := get_tree()
    if tree == null:
        return null
    return tree.root.get_node_or_null("TerrainSystem")
