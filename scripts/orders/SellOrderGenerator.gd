class_name SellOrderGenerator extends OrderGenerator


func get_cursor(
    target: Node3D,
    _target_cell: Vector2i,
    _target_pos: Vector3,
    _modifiers: Dictionary,
) -> CursorState.Type:
    if not target:
        return CursorState.Type.SELL_BLOCKED
    if not _is_sellable_building(target):
        return CursorState.Type.SELL_BLOCKED
    return CursorState.Type.SELL


func get_orders(
    target: Node3D,
    _target_cell: Vector2i,
    _target_pos: Vector3,
    _modifiers: Dictionary,
) -> Array[OrderResult]:
    if not target or not _is_sellable_building(target):
        return []
    var building := target
    var result := OrderResult.new(
        CursorState.Type.SELL,
        20,
        building,
        Vector3.ZERO,
        false,
        func(): _sell(building),
        "",
    )
    return [result]


func cancel() -> void:
    pass


func _is_sellable_building(entity: Node3D) -> bool:
    if not entity.get_node_or_null("FoundationComponent"):
        return false
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    if stats and stats.entity_type != EntityData.EntityType.BUILDING:
        return false
    var health := entity.get_node_or_null("HealthComponent") as HealthComponent
    if health and health.current_health <= 0:
        return false
    return true


func _sell(building: Node3D) -> void:
    if not is_instance_valid(building):
        return
    var bm := Engine.get_main_loop().root.get_node_or_null("BuildingManager") as BuildingManager
    if bm:
        bm.sell_building(building)
