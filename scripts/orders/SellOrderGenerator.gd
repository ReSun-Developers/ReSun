class_name SellOrderGenerator extends OrderGenerator


func resolve(
    target: Node3D,
    _target_cell: Vector2i,
    _target_pos: Vector3,
    _modifiers: Dictionary,
) -> OrderResolution:
    if not target or not _is_sellable_building(target):
        return OrderResolution.new(CursorState.Type.SELL_BLOCKED, [])
    var building := target
    var result := OrderResult.new(
        CursorState.Type.SELL,
        20,
        building,
        Vector3.ZERO,
        false,
        func() -> void: _sell(building),
        "",
    )
    return OrderResolution.new(CursorState.Type.SELL, [result])


func cancel() -> void:
    pass


func _is_sellable_building(entity: Node3D) -> bool:
    if not entity.get_node_or_null("FoundationComponent"):
        return false
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    if not stats or stats.entity_type != EntityData.EntityType.BUILDING:
        return false
    # Only the acting (local) player may sell their own buildings.
    if stats.player_id != PlayerManager.get_local_player_id():
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
