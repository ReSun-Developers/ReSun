class_name FoundationComponent extends Node

@export var foundation: Vector2i = Vector2i(1, 1)
@export var height: float = 1.0
@export var bib_cells: Array[Vector2i] = []

var _registered_cells: Array[Vector2i] = []
var _registered_bib_cells: Array[Vector2i] = []


func _ready() -> void:
    if Engine.is_editor_hint():
        return
    var entity := get_parent() as Node3D
    if not entity:
        return
    if entity.has_meta("detached") or entity.process_mode == Node.PROCESS_MODE_DISABLED:
        return
    # Only buildings register building cells — vehicles/infantry should not.
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    if stats and stats.entity_type != EntityData.EntityType.BUILDING:
        return
    if not SpatialHash.instance:
        return
    var origin_cell := CellUtil.world_to_cell_origin(entity.global_position, foundation)
    _registered_cells = get_foundation_cells(origin_cell)
    _registered_bib_cells = get_bib_cells(origin_cell)
    # Bib cells are the walkable pad in front of the building (e.g. the refinery
    # dock) — dockers must path onto them, so they are NOT blocked building
    # cells. Register only the non-bib foundation cells as blocked, matching
    # BuildingManager.place_building.
    var non_bib_cells: Array[Vector2i] = _registered_cells.duplicate()
    for bib in _registered_bib_cells:
        non_bib_cells.erase(bib)
    SpatialHash.instance.register_building_cells(non_bib_cells, entity)
    if not _registered_bib_cells.is_empty():
        SpatialHash.instance.register_bib_cells(_registered_bib_cells)


func _exit_tree() -> void:
    if not SpatialHash.instance:
        return
    if not _registered_cells.is_empty():
        SpatialHash.instance.unregister_building_cells(_registered_cells)
    if not _registered_bib_cells.is_empty():
        SpatialHash.instance.unregister_bib_cells(_registered_bib_cells)


func configure(data: EntityData) -> void:
    foundation = data.foundation
    height = data.height
    bib_cells = data.bib_cells


func validate(data: EntityData) -> PackedStringArray:
    var errors: PackedStringArray = []
    if data.foundation == Vector2i(0, 0):
        errors.append("FoundationComponent: '%s' has zero foundation" % data.id)
    return errors


func get_cell_count() -> int:
    return foundation.x * foundation.y


func get_foundation_cells(origin_cell: Vector2i) -> Array[Vector2i]:
    return FoundationComponent.footprint_cells(foundation, origin_cell)


func get_occupied_cells(origin_cell: Vector2i) -> Array[Vector2i]:
    return FoundationComponent.occupied_cells(foundation, bib_cells, origin_cell)


func get_bib_cells(origin_cell: Vector2i) -> Array[Vector2i]:
    var cells: Array[Vector2i] = []
    for offset in bib_cells:
        if offset.x >= 0 and offset.x < foundation.x and offset.y >= 0 and offset.y < foundation.y:
            cells.append(origin_cell + offset)
    return cells


## World-space point on the foundation footprint nearest to `from`. The footprint
## is the axis-aligned XZ rectangle centered on the owning entity, so this is a
## per-axis clamp — no cell walk. Rotation is ignored, matching foundation cell
## registration; a rotation-aware query would replace this method alone.
func nearest_world_point(from: Vector3) -> Vector3:
    var entity := get_parent() as Node3D
    if entity == null:
        return from
    var center := entity.global_position
    var half := Vector3(foundation.x, 0.0, foundation.y) * CellUtil.CELL_SIZE * 0.5
    return Vector3(
        clampf(from.x, center.x - half.x, center.x + half.x),
        center.y,
        clampf(from.z, center.z - half.z, center.z + half.z),
    )


func is_buildable(origin_cell: Vector2i) -> bool:
    return FoundationComponent.footprint_buildable(foundation, origin_cell)


# ========================================
# Canonical footprint math (static, callable from raw EntityData footprint
# during preview/validation before an entity instance exists)
# ========================================


static func footprint_cells(footprint: Vector2i, origin_cell: Vector2i) -> Array[Vector2i]:
    var cells: Array[Vector2i] = []
    for dx in footprint.x:
        for dz in footprint.y:
            cells.append(origin_cell + Vector2i(dx, dz))
    return cells


static func occupied_cells(
    footprint: Vector2i, bibs: Array[Vector2i], origin_cell: Vector2i
) -> Array[Vector2i]:
    var cells: Array[Vector2i] = []
    for dx in footprint.x:
        for dz in footprint.y:
            var offset := Vector2i(dx, dz)
            if not bibs.has(offset):
                cells.append(origin_cell + offset)
    return cells


static func is_cell_buildable(cell: Vector2i) -> bool:
    var sh := SpatialHash.instance
    if sh:
        if sh.get_building_cells().has(CellUtil.cell_key(cell)):
            return false
        if sh.is_cell_blocked(cell):
            return false
        if sh.is_any_entity_on_cell(cell):
            return false
        if sh.is_bib_cell(cell):
            return false
        if sh.has_resource_cell(cell):
            return false
    var cell_type := TerrainSystem.get_cell_type(cell)
    return cell_type == "" or cell_type == "clear"


static func footprint_buildable(footprint: Vector2i, origin_cell: Vector2i) -> bool:
    var min_h := INF
    var max_h := -INF
    for dx in footprint.x:
        for dz in footprint.y:
            var cell := origin_cell + Vector2i(dx, dz)
            if not FoundationComponent.is_cell_buildable(cell):
                return false
            var h := TerrainSystem.get_cell_max_height(cell)
            min_h = minf(min_h, h)
            max_h = maxf(max_h, h)
    if min_h != INF and (max_h - min_h) > TerrainSystem.HEIGHT_STEP:
        return false
    return true
