extends Node

# UnitOrderGenerator tests — cursor resolution and order generation for units
# Tests the full flow: selected entities -> target -> cursor/orders

const SELECT_COMPONENT_SCENE: PackedScene = preload("res://scenes/components/SelectComponent.tscn")

var _sm: Node = null
var _pm: Node = null


func _make_weapon(damage: int = 10, range_cells: float = 5.0) -> WeaponData:
    var w := WeaponData.new()
    w.id = "TEST_WEAPON"
    w.damage = damage
    w.attack_range = range_cells
    w.rate_of_fire = 1.0
    return w


func _make_combat_entity(player_id: int = -1) -> Node3D:
    var entity := Node3D.new()
    entity.name = "CombatEntity"
    var combat := CombatComponent.new()
    combat.name = "CombatComponent"
    combat.weapons = [_make_weapon()]
    entity.add_child(combat)
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    entity.add_child(stats)
    return entity


func _make_non_combat_entity(player_id: int = -1) -> Node3D:
    var entity := Node3D.new()
    entity.name = "NonCombatEntity"
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    entity.add_child(stats)
    return entity


func _make_deploy_entity(can_undeploy: bool = false, player_id: int = -1) -> Node3D:
    var entity := Node3D.new()
    entity.name = "DeployEntity"
    var deploy := DeployComponent.new()
    deploy.name = "DeployComponent"
    entity.add_child(deploy)
    if can_undeploy:
        deploy.undeploys_into = "MCV"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    entity.add_child(stats)
    return entity


func _make_target(player_id: int, add_selectable: bool = false) -> Node3D:
    var entity := Node3D.new()
    entity.name = "TargetEntity"
    if add_selectable:
        entity.add_to_group("selectable")
        var sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
        entity.add_child(sc)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    entity.add_child(stats)
    return entity


func _setup_selection(entities: Array[Node3D]) -> void:
    if _sm == null:
        return
    _sm.deselect_all()
    for entity in entities:
        _sm.add_child(entity)
        var sc := entity.get_node_or_null("SelectComponent") as SelectComponent
        if not sc:
            sc = SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
            sc.name = "SelectComponent"
            entity.add_child(sc)
        _sm.add_entity(sc)


func _teardown_selection(entities: Array[Node3D]) -> void:
    if _sm:
        _sm.deselect_all()
    for entity in entities:
        if is_instance_valid(entity):
            entity.free()


func _get_generator() -> UnitOrderGenerator:
    return UnitOrderGenerator.get_instance()


# --- get_cursor: no target cases ---


func test_cursor_no_selection_returns_default():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var gen := _get_generator()
    var cursor := gen.get_cursor(null, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "no selection -> DEFAULT")


func test_cursor_no_target_movable_returns_move():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var gen := _get_generator()
    var cursor := gen.get_cursor(null, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(cursor, CursorState.Type.MOVE, "no target + movable -> MOVE")
    _teardown_selection([entity])


func test_cursor_no_target_undeployable_returns_move():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_deploy_entity(true, local_id)
    _setup_selection([entity])
    var gen := _get_generator()
    var cursor := gen.get_cursor(null, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(cursor, CursorState.Type.MOVE, "no target + undeployable -> MOVE")
    _teardown_selection([entity])


# --- get_cursor: target cases ---


func test_cursor_enemy_with_combat_unit():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var target := _make_target(local_id + 1)
    var gen := _get_generator()
    var cursor := gen.get_cursor(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(cursor, CursorState.Type.ATTACK, "combat unit + enemy -> ATTACK")
    _teardown_selection([entity])
    target.free()


func test_cursor_enemy_with_non_combat_unit():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_non_combat_entity(local_id)
    _setup_selection([entity])
    var target := _make_target(local_id + 1, true)
    var gen := _get_generator()
    var cursor := gen.get_cursor(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(
        cursor, CursorState.Type.SELECT, "non-combat unit + enemy -> SELECT (not ATTACK)"
    )
    _teardown_selection([entity])
    target.free()


func test_cursor_friendly_selectable_entity():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var target := _make_target(local_id, true)
    var gen := _get_generator()
    var cursor := gen.get_cursor(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(cursor, CursorState.Type.SELECT, "friendly selectable -> SELECT")
    _teardown_selection([entity])
    target.free()


func test_cursor_already_selected_with_movement():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var gen := _get_generator()
    var cursor := gen.get_cursor(entity, Vector2i.ZERO, entity.global_position, {})
    TestHelper.assert_eq(
        cursor, CursorState.Type.MOVE, "already selected + has MovementController -> MOVE"
    )
    _teardown_selection([entity])


func test_cursor_already_selected_without_movement():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_non_combat_entity(local_id)
    var mc := entity.get_node_or_null("MovementController")
    if mc:
        mc.free()
    _setup_selection([entity])
    var gen := _get_generator()
    var cursor := gen.get_cursor(entity, Vector2i.ZERO, entity.global_position, {})
    TestHelper.assert_eq(
        cursor,
        CursorState.Type.GENERIC_BLOCKED,
        "already selected + no MovementController -> GENERIC_BLOCKED"
    )
    _teardown_selection([entity])


# --- get_cursor: edge cases ---


func test_cursor_enemy_non_selectable_returns_move():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_non_combat_entity(local_id)
    _setup_selection([entity])
    var target := _make_target(local_id + 1, false)
    var gen := _get_generator()
    var cursor := gen.get_cursor(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(cursor, CursorState.Type.MOVE, "enemy non-selectable + movable -> MOVE")
    _teardown_selection([entity])
    target.free()


func test_cursor_undeployable_unit_no_target():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_deploy_entity(true, local_id)
    _setup_selection([entity])
    var gen := _get_generator()
    var cursor := gen.get_cursor(null, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(cursor, CursorState.Type.MOVE, "undeployable + no target -> MOVE")
    _teardown_selection([entity])


# --- get_orders: no target cases ---


func test_orders_no_selection_returns_empty():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var gen := _get_generator()
    var orders := gen.get_orders(null, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(orders.size(), 0, "no selection -> empty orders")


func test_orders_no_target_movable_returns_move_order():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var gen := _get_generator()
    var target_pos := Vector3(10.0, 0.0, 20.0)
    var orders := gen.get_orders(null, Vector2i.ZERO, target_pos, {})
    TestHelper.assert_eq(orders.size(), 1, "no target + movable -> 1 move order")
    TestHelper.assert_eq(orders[0].cursor, CursorState.Type.MOVE, "move order cursor -> MOVE")
    _teardown_selection([entity])


func test_orders_no_target_undeployable_resolves():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_deploy_entity(true, local_id)
    _setup_selection([entity])
    var gen := _get_generator()
    var orders := gen.get_orders(null, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(orders.size() >= 0, "no target + undeployable -> no crash")
    _teardown_selection([entity])


# --- get_orders: target cases ---


func test_orders_enemy_with_combat_unit():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var target := _make_target(local_id + 1)
    var gen := _get_generator()
    var orders := gen.get_orders(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(orders.size(), 1, "combat + enemy -> 1 attack order")
    TestHelper.assert_eq(orders[0].cursor, CursorState.Type.ATTACK, "attack order cursor -> ATTACK")
    _teardown_selection([entity])
    target.free()


func test_orders_enemy_with_non_combat_unit():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_non_combat_entity(local_id)
    _setup_selection([entity])
    var target := _make_target(local_id + 1)
    var gen := _get_generator()
    var orders := gen.get_orders(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(orders.size(), 0, "non-combat + enemy -> empty orders")
    _teardown_selection([entity])
    target.free()


func test_non_combat_empty_orders_allows_enemy_selection():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var center := Vector2i(BoundsSystem.grid_cells.x / 2, BoundsSystem.grid_cells.y / 2)
    var in_play := CellUtil.cell_to_world(center)
    var rules := GlobalRules.get_current()
    var saved_fog: bool = rules.fog_of_war
    var saved_shroud: bool = rules.shroud_enabled
    rules.fog_of_war = false
    rules.shroud_enabled = false
    var entity := _make_non_combat_entity(local_id)
    _setup_selection([entity])
    entity.global_position = in_play
    var target := _make_target(local_id + 1, true)
    target.global_position = in_play
    var target_sc := target.get_node_or_null("SelectComponent") as SelectComponent
    var gen := _get_generator()
    var orders := gen.get_orders(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(orders.size(), 0, "non-combat + enemy -> empty orders")
    if orders.is_empty() and target_sc:
        _sm.select_entity(target_sc)
        var local_sc := entity.get_node_or_null("SelectComponent") as SelectComponent
        TestHelper.assert_true(
            _sm.is_entity_selected(target_sc),
            "enemy selected after empty orders (MouseHandler fallthrough)"
        )
        TestHelper.assert_true(
            not _sm.is_entity_selected(local_sc),
            "enemy selection cleared the local unit (no mixed selection)"
        )
        _sm.deselect_all()
    _teardown_selection([entity])
    target.free()
    rules.fog_of_war = saved_fog
    rules.shroud_enabled = saved_shroud


func test_orders_already_selected_self():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var gen := _get_generator()
    var orders := gen.get_orders(entity, Vector2i.ZERO, entity.global_position, {})
    TestHelper.assert_eq(orders.size(), 1, "already selected entity -> 1 move-to-self order")
    _teardown_selection([entity])


# --- get_orders: queued modifier ---


func test_orders_queued_modifier():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var target := _make_target(local_id + 1)
    var gen := _get_generator()
    var modifiers := {OrderResult.MOD_QUEUED: true}
    var orders := gen.get_orders(target, Vector2i.ZERO, Vector3.ZERO, modifiers)
    TestHelper.assert_eq(orders.size(), 1, "queued + enemy -> 1 order")
    TestHelper.assert_true(orders[0].queued, "queued modifier -> order.queued = true")
    _teardown_selection([entity])
    target.free()


# --- get_orders: multiple selected entities ---


func test_orders_multiple_combat_entities_vs_enemy():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity1 := _make_combat_entity(local_id)
    var entity2 := _make_combat_entity(local_id)
    _setup_selection([entity1, entity2])
    var target := _make_target(local_id + 1)
    var gen := _get_generator()
    var orders := gen.get_orders(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(orders.size(), 2, "2 combat entities vs enemy -> 2 attack orders")
    _teardown_selection([entity1, entity2])
    target.free()


func test_orders_mixed_selection_vs_enemy():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var combat := _make_combat_entity(local_id)
    var non_combat := _make_non_combat_entity(local_id)
    _setup_selection([combat, non_combat])
    var target := _make_target(local_id + 1)
    var gen := _get_generator()
    var orders := gen.get_orders(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(orders.size(), 1, "mixed selection vs enemy -> 1 order (only combat)")
    _teardown_selection([combat, non_combat])
    target.free()


# --- helper function tests ---


func test_is_local_entity_true_for_local():
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    var gen := _get_generator()
    var result := gen._is_local_entity(entity)
    TestHelper.assert_true(result, "_is_local_entity returns true for local player")
    entity.free()


## Harvester with HarvestComponent + DockClient + Transport, ready to dock.
func _make_harvester_entity(player_id: int = -1) -> Node3D:
    var entity := Node3D.new()
    entity.name = "HarvesterEntity"
    var transport := TransportComponent.new()
    transport.name = "TransportComponent"
    transport.dock = "GDI_REFINERY"
    transport.storage = 700
    transport.cargo = {"tiberium_green": 700.0}
    entity.add_child(transport)
    var harvest := HarvestComponent.new()
    harvest.name = "HarvestComponent"
    entity.add_child(harvest)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    entity.add_child(stats)
    return entity


func _make_refinery_target(player_id: int = -1) -> Node3D:
    var entity := Node3D.new()
    entity.name = "RefineryTarget"
    var dock := DockHostComponent.new()
    dock.name = "DockHostComponent"
    entity.add_child(dock)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    entity.add_child(stats)
    return entity


func test_orders_harvester_friendly_refinery_returns_enter():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var harvester := _make_harvester_entity(local_id)
    _setup_selection([harvester])
    var refinery := _make_refinery_target(local_id)
    var gen := _get_generator()
    var orders := gen.get_orders(refinery, Vector2i.ZERO, refinery.global_position, {})
    TestHelper.assert_eq(orders.size(), 1, "harvester + friendly refinery -> 1 order")
    TestHelper.assert_eq(
        orders[0].cursor, CursorState.Type.ENTER, "friendly refinery click -> ENTER (dock)"
    )
    _teardown_selection([harvester])
    refinery.free()


func test_orders_harvester_enemy_refinery_no_enter_order():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var harvester := _make_harvester_entity(local_id)
    _setup_selection([harvester])
    var enemy_refinery := _make_refinery_target(local_id + 1)
    var gen := _get_generator()
    var orders := gen.get_orders(enemy_refinery, Vector2i.ZERO, enemy_refinery.global_position, {})
    for order in orders:
        TestHelper.assert_true(
            order.cursor != CursorState.Type.ENTER, "enemy refinery must not produce ENTER order"
        )
    _teardown_selection([harvester])
    enemy_refinery.free()


func test_orders_friendly_unit_no_order_returns_empty():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var friendly := _make_non_combat_entity(local_id)
    friendly.add_to_group("selectable")
    var gen := _get_generator()
    var orders := gen.get_orders(friendly, Vector2i.ZERO, friendly.global_position, {})
    TestHelper.assert_eq(
        orders.size(), 0, "combat unit + friendly non-combat unit -> no orders (select fallback)"
    )
    _teardown_selection([entity])
    friendly.free()


func test_is_local_entity_false_for_enemy():
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id + 1)
    var gen := _get_generator()
    var result := gen._is_local_entity(entity)
    TestHelper.assert_true(not result, "_is_local_entity returns false for enemy")
    entity.free()


func test_is_local_entity_true_for_no_stats():
    var entity := Node3D.new()
    entity.name = "NoStatsEntity"
    var gen := _get_generator()
    var result := gen._is_local_entity(entity)
    TestHelper.assert_true(
        result, "_is_local_entity returns true for entity without StatsComponent"
    )
    entity.free()


func test_is_local_entity_true_for_negative_player_id():
    var entity := _make_combat_entity(-1)
    var gen := _get_generator()
    var result := gen._is_local_entity(entity)
    TestHelper.assert_true(result, "_is_local_entity returns true for player_id=-1")
    entity.free()


func test_has_movable_true_with_movement_controller():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var gen := _get_generator()
    var result := gen._has_movable(_sm)
    TestHelper.assert_true(result, "_has_movable returns true when entity has MovementController")
    _teardown_selection([entity])


func test_has_movable_false_without_movement_controller():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := Node3D.new()
    entity.name = "StationaryEntity"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = local_id
    entity.add_child(stats)
    _setup_selection([entity])
    var gen := _get_generator()
    var result := gen._has_movable(_sm)
    TestHelper.assert_true(not result, "_has_movable returns false when no MovementController")
    _teardown_selection([entity])


# --- enemy (non-local) selection: viewing only, never commandable (#166) ---


func _make_armed_building(player_id: int) -> Node3D:
    var entity := Node3D.new()
    entity.name = "ArmedBuilding"
    var combat := CombatComponent.new()
    combat.name = "CombatComponent"
    combat.weapons = [_make_weapon()]
    entity.add_child(combat)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    stats.entity_type = EntityData.EntityType.BUILDING
    entity.add_child(stats)
    return entity


func _make_resource_target() -> Node3D:
    var entity := Node3D.new()
    entity.name = "ResourceTarget"
    var res := ResourceComponent.new()
    res.name = "ResourceComponent"
    entity.add_child(res)
    return entity


func test_cursor_enemy_selection_default_over_ground():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var enemy := _make_combat_entity(local_id + 1)
    _setup_selection([enemy])
    var gen := _get_generator()
    var cursor := gen.get_cursor(null, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "enemy selection + ground -> DEFAULT")
    _teardown_selection([enemy])


func test_cursor_enemy_selection_select_over_selectable():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var enemy := _make_combat_entity(local_id + 1)
    _setup_selection([enemy])
    var target := _make_target(local_id + 1, true)
    var gen := _get_generator()
    var cursor := gen.get_cursor(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(
        cursor, CursorState.Type.SELECT, "enemy selection + unselected selectable -> SELECT"
    )
    _teardown_selection([enemy])
    target.free()


func test_cursor_enemy_selection_default_over_self():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var enemy := _make_combat_entity(local_id + 1)
    enemy.add_to_group("selectable")
    _setup_selection([enemy])
    var gen := _get_generator()
    var cursor := gen.get_cursor(enemy, Vector2i.ZERO, enemy.global_position, {})
    TestHelper.assert_eq(
        cursor, CursorState.Type.DEFAULT, "enemy selection + the selected enemy itself -> DEFAULT"
    )
    _teardown_selection([enemy])


func test_orders_enemy_selection_empty_for_ground():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var enemy := _make_combat_entity(local_id + 1)
    _setup_selection([enemy])
    var gen := _get_generator()
    var orders := gen.get_orders(null, Vector2i.ZERO, Vector3(10.0, 0.0, 20.0), {})
    TestHelper.assert_eq(orders.size(), 0, "enemy selection + ground -> no move order")
    _teardown_selection([enemy])


func test_orders_enemy_harvester_no_harvest_or_dock():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var harvester := _make_harvester_entity(local_id + 1)
    _setup_selection([harvester])
    var gen := _get_generator()
    var resource := _make_resource_target()
    var orders := gen.get_orders(resource, Vector2i.ZERO, resource.global_position, {})
    TestHelper.assert_eq(orders.size(), 0, "enemy harvester + tiberium -> no HARVEST order")
    var cursor := gen.get_cursor(resource, Vector2i.ZERO, resource.global_position, {})
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "enemy harvester cursor -> DEFAULT")
    var refinery := _make_refinery_target(local_id + 1)
    orders = gen.get_orders(refinery, Vector2i.ZERO, refinery.global_position, {})
    TestHelper.assert_eq(orders.size(), 0, "enemy harvester + enemy refinery -> no ENTER order")
    _teardown_selection([harvester])
    resource.free()
    refinery.free()


func test_enemy_armed_building_not_commandable():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var building := _make_armed_building(local_id + 1)
    _setup_selection([building])
    var target := _make_target(local_id + 2)
    var gen := _get_generator()
    var cursor := gen.get_cursor(target, Vector2i.ZERO, Vector3.ZERO, {})
    var orders := gen.get_orders(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "enemy armed building cursor -> DEFAULT")
    TestHelper.assert_eq(orders.size(), 0, "enemy armed building -> no ATTACK order")
    _teardown_selection([building])
    target.free()


func test_enemy_undeployable_building_not_commandable():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var building := _make_deploy_entity(true, local_id + 1)
    _setup_selection([building])
    var gen := _get_generator()
    var cursor := gen.get_cursor(null, Vector2i.ZERO, Vector3.ZERO, {})
    var orders := gen.get_orders(null, Vector2i.ZERO, Vector3(5.0, 0.0, 5.0), {})
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "enemy undeployable building -> DEFAULT")
    TestHelper.assert_eq(orders.size(), 0, "enemy undeployable building -> no undeploy order")
    _teardown_selection([building])


func test_local_armed_building_remains_commandable():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var building := _make_armed_building(local_id)
    _setup_selection([building])
    var target := _make_target(local_id + 1)
    var gen := _get_generator()
    var cursor := gen.get_cursor(target, Vector2i.ZERO, Vector3.ZERO, {})
    var orders := gen.get_orders(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(cursor, CursorState.Type.ATTACK, "local armed building + enemy -> ATTACK")
    TestHelper.assert_eq(orders.size(), 1, "local armed building + enemy -> 1 attack order")
    _teardown_selection([building])
    target.free()


func test_local_undeployable_building_remains_commandable():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var building := _make_deploy_entity(true, local_id)
    _setup_selection([building])
    var gen := _get_generator()
    var cursor := gen.get_cursor(null, Vector2i.ZERO, Vector3.ZERO, {})
    var orders := gen.get_orders(null, Vector2i.ZERO, Vector3(5.0, 0.0, 5.0), {})
    TestHelper.assert_eq(cursor, CursorState.Type.MOVE, "local undeployable building -> MOVE")
    TestHelper.assert_true(
        orders.size() >= 1, "local undeployable building still produces an undeploy order"
    )
    _teardown_selection([building])


# --- resolve(): unified cursor + orders ---


func test_resolve_projects_cursor_and_orders():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var target := _make_target(local_id + 1)
    var gen := _get_generator()
    var resolution := gen.resolve(target, Vector2i.ZERO, Vector3.ZERO, {})
    (
        TestHelper
        . assert_eq(
            gen.get_cursor(target, Vector2i.ZERO, Vector3.ZERO, {}),
            resolution.cursor,
            "get_cursor projects resolve().cursor",
        )
    )
    (
        TestHelper
        . assert_eq(
            gen.get_orders(target, Vector2i.ZERO, Vector3.ZERO, {}).size(),
            resolution.orders.size(),
            "get_orders projects resolve().orders",
        )
    )
    TestHelper.assert_eq(
        resolution.cursor, CursorState.Type.ATTACK, "combat vs enemy -> ATTACK cursor"
    )
    _teardown_selection([entity])
    target.free()


func test_resolve_empty_selection_select_affordance():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var target := _make_target(0, true)
    var gen := _get_generator()
    var resolution := gen.resolve(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(
        resolution.cursor, CursorState.Type.SELECT, "empty selection + selectable -> SELECT"
    )
    TestHelper.assert_eq(resolution.orders.size(), 0, "empty selection -> no orders")
    target.free()


func test_resolve_force_fire_ground_attacks():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var gen := _get_generator()
    var modifiers := {OrderResult.MOD_FORCE_ATTACK: true}
    var resolution := gen.resolve(null, Vector2i.ZERO, Vector3(5.0, 0.0, 5.0), modifiers)
    TestHelper.assert_eq(resolution.cursor, CursorState.Type.ATTACK, "force-fire ground -> ATTACK")
    TestHelper.assert_eq(resolution.orders.size(), 1, "force-fire ground -> 1 attack order")
    _teardown_selection([entity])


func test_resolve_force_move_over_enemy_yields_move():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var target := _make_target(local_id + 1)
    var gen := _get_generator()
    var modifiers := {OrderResult.MOD_FORCE_MOVE: true}
    var resolution := gen.resolve(target, Vector2i.ZERO, target.global_position, modifiers)
    TestHelper.assert_eq(
        resolution.cursor, CursorState.Type.MOVE, "ALT force-move over enemy -> MOVE cursor"
    )
    TestHelper.assert_eq(resolution.orders.size(), 1, "ALT force-move over enemy -> 1 MOVE order")
    TestHelper.assert_eq(
        resolution.orders[0].cursor, CursorState.Type.MOVE, "the order is a MOVE, not an ATTACK"
    )
    _teardown_selection([entity])
    target.free()


func test_resolve_force_move_ground_yields_move():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var gen := _get_generator()
    var modifiers := {OrderResult.MOD_FORCE_MOVE: true}
    var resolution := gen.resolve(null, Vector2i.ZERO, Vector3(7.0, 0.0, 3.0), modifiers)
    TestHelper.assert_eq(resolution.cursor, CursorState.Type.MOVE, "force-move ground -> MOVE")
    TestHelper.assert_eq(resolution.orders.size(), 1, "force-move ground -> 1 move order")
    _teardown_selection([entity])


func test_resolve_ctrl_alt_falls_back_to_force_move():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(local_id)
    _setup_selection([entity])
    var target := _make_target(local_id + 1)
    var gen := _get_generator()
    # Ctrl+Alt+Click is Guard Area in the original (not implemented); the held
    # Alt currently yields force-move rather than firing.
    var modifiers := {OrderResult.MOD_FORCE_ATTACK: true, OrderResult.MOD_FORCE_MOVE: true}
    var resolution := gen.resolve(target, Vector2i.ZERO, target.global_position, modifiers)
    TestHelper.assert_eq(
        resolution.cursor, CursorState.Type.MOVE, "Ctrl+Alt -> MOVE fallback, not ATTACK"
    )
    _teardown_selection([entity])
    target.free()


# --- OrderSystem.issue(): dispatch ---


func test_issue_empty_is_noop():
    var orders: Array[OrderResult] = []
    TestHelper.assert_true(not OrderSystem.issue(orders), "empty batch -> false")


func test_issue_executes_every_order():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var ran := [0]
    var orders: Array[OrderResult] = []
    for _i in 3:
        orders.append(
            OrderResult.new(
                CursorState.Type.MOVE,
                5,
                null,
                Vector3.ZERO,
                false,
                func() -> void: ran[0] += 1,
            )
        )
    TestHelper.assert_true(OrderSystem.issue(orders), "non-empty batch -> true")
    TestHelper.assert_eq(ran[0], 3, "every order in the batch executed")
