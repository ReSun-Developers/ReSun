class_name RepairOrderGenerator extends OrderGenerator


func get_cursor(
    target: Node3D,
    _target_cell: Vector2i,
    _target_pos: Vector3,
    _modifiers: Dictionary,
) -> CursorState.Type:
    if not target:
        return CursorState.Type.REPAIR_BLOCKED
    if not _is_damaged_building(target):
        return CursorState.Type.REPAIR_BLOCKED
    return CursorState.Type.REPAIR


func get_orders(
    target: Node3D,
    _target_cell: Vector2i,
    _target_pos: Vector3,
    _modifiers: Dictionary,
) -> Array[OrderResult]:
    if not target or not _is_damaged_building(target):
        return []
    var building := target
    var result := OrderResult.new(
        CursorState.Type.REPAIR,
        20,
        building,
        Vector3.ZERO,
        false,
        func(): _repair(building),
        "",
    )
    return [result]


func cancel() -> void:
    pass


func _is_damaged_building(entity: Node3D) -> bool:
    if not entity.get_node_or_null("FoundationComponent"):
        return false
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    if stats and stats.entity_type != EntityData.EntityType.BUILDING:
        return false
    var health := entity.get_node_or_null("HealthComponent") as HealthComponent
    if not health:
        return false
    if health.current_health <= 0:
        return false
    if health.current_health >= health.max_health:
        return false
    return true


func _repair(building: Node3D) -> void:
    if not is_instance_valid(building):
        return
    var bm := Engine.get_main_loop().root.get_node_or_null("BuildingManager") as BuildingManager
    if bm:
        bm.repair_building(building)
