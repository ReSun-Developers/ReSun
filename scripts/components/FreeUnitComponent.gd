class_name FreeUnitComponent extends Node

@export var free_unit_id: String = ""

const RETRY_INTERVAL: float = 2.0
var _retry_timer: float = 0.0
var _retrying: bool = false


func _ready() -> void:
    if Engine.is_editor_hint():
        return
    if get_parent().get_meta("detached", false):
        return
    var ancestor := get_parent()
    while ancestor:
        if ancestor.has_meta("is_map_editor"):
            return
        ancestor = ancestor.get_parent()
    if free_unit_id.is_empty():
        queue_free()
        return
    call_deferred("_spawn_free_unit")


func _process(delta: float) -> void:
    if not _retrying:
        return
    _retry_timer -= delta
    if _retry_timer <= 0.0:
        _retrying = false
        _spawn_free_unit()


func _spawn_free_unit() -> void:
    var parent := get_parent() as Node3D
    if not parent:
        queue_free()
        return

    var cell := CellUtil.world_to_cell(parent.global_position)
    var foundation := Vector2i(1, 1)
    var found := _find_adjacent_free_cell(cell, foundation)
    if found == Vector2i(-1, -1):
        _retrying = true
        _retry_timer = RETRY_INTERVAL
        return

    var entity_data := EntityFactory.get_entity_data(free_unit_id)
    if not entity_data:
        _retrying = true
        _retry_timer = RETRY_INTERVAL
        return

    var parent_stats := parent.get_node_or_null("StatsComponent") as StatsComponent
    var player_id: int = parent_stats.player_id if parent_stats else 0
    var world_pos := CellUtil.cell_to_world(found)
    var parent_node := parent.get_parent()
    var free_entity := EntityPlacer.place_entity(entity_data, world_pos, player_id, parent_node)
    if not free_entity:
        _retrying = true
        _retry_timer = RETRY_INTERVAL
        return

    var harvest := free_entity.get_node_or_null("HarvestComponent") as HarvestComponent
    if harvest:
        var resource := harvest._find_nearest_resource(free_entity.global_position)
        if resource:
            harvest.set_target_node(resource)

    queue_free()


func _find_adjacent_free_cell(origin: Vector2i, _foundation: Vector2i) -> Vector2i:
    return CellUtil.spiral_first_free(
        origin,
        5,
        func(cell: Vector2i) -> bool:
            var key := CellUtil.cell_key(cell)
            if SpatialHash.instance and SpatialHash.instance.get_building_cells().has(key):
                return true
            if SpatialHash.instance and SpatialHash.instance.is_cell_blocked(cell):
                return true
            if SpatialHash.instance and SpatialHash.instance._reserved.has(key):
                return true
            var cell_type := TerrainSystem.get_cell_type(cell)
            if cell_type != "" and cell_type != "clear":
                return true
            return false
    )
