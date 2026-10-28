extends Node

# OrderSystem visible-bounds gate tests — player orders are clamped/rejected
# outside the visible playable diamond, while AI/automatic movement is not
# restricted. Mirrors the fog-gate test setup in test_shroud_system.gd.

const SELECT_COMPONENT_SCENE: PackedScene = preload("res://scenes/components/SelectComponent.tscn")

const GRID := Vector2i(50, 50)

var _ts: Node = null
var _pm: Node = null
var _sm: Node = null
var _saved_insets := Vector4i(0, 0, 0, 0)
var _saved_grid_cells := Vector2i(50, 50)
var _saved_fog := Vector2i(0, 0)


func _ready() -> void:
    _ts = get_node_or_null("/root/TerrainSystem")
    _pm = get_node_or_null("/root/PlayerManager")
    _sm = get_node_or_null("/root/SelectionManager")


func _make_weapon(damage: int = 10, range_cells: float = 5.0) -> WeaponData:
    var w := WeaponData.new()
    w.id = "TEST_WEAPON"
    w.damage = damage
    w.attack_range = range_cells
    w.rate_of_fire = 1.0
    return w


func _make_combat_entity(player_id: int) -> Node3D:
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


func _make_harvester_entity(player_id: int) -> Node3D:
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
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    entity.add_child(stats)
    return entity


func _make_refinery_target(player_id: int) -> Node3D:
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


func _make_target(player_id: int) -> Node3D:
    var entity := Node3D.new()
    entity.name = "TargetEntity"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    entity.add_child(stats)
    return entity


func _select_entity(entity: Node3D) -> SelectComponent:
    if _sm == null:
        return null
    _sm.deselect_all()
    _sm.add_child(entity)
    var sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    sc.name = "SelectComponent"
    entity.add_child(sc)
    _sm.add_entity(sc)
    return sc


func _free_unit(entity: Node3D, sc: SelectComponent) -> void:
    if _sm and is_instance_valid(sc):
        _sm.remove_entity(sc)
    if is_instance_valid(entity):
        entity.free()


func _setup() -> void:
    if _ts:
        _ts.init_grid(GRID.x, GRID.y)
    _saved_insets = Vector4i(
        BoundsSystem.left_inset,
        BoundsSystem.right_inset,
        BoundsSystem.top_inset,
        BoundsSystem.bottom_inset,
    )
    _saved_grid_cells = BoundsSystem.grid_cells
    var rules := GlobalRules.get_current()
    _saved_fog = Vector2i(
        1 if rules and rules.fog_of_war else 0, 1 if rules and rules.shroud_enabled else 0
    )
    BoundsSystem.grid_cells = GRID
    BoundsSystem.left_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.x
    BoundsSystem.right_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.y
    BoundsSystem.top_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.z
    BoundsSystem.bottom_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.w
    if _pm:
        _pm._players.clear()
        _pm._local_player_id = 0
        _pm._init_defaults()
    if SpatialHash.instance:
        SpatialHash.instance._grid.clear()
    if rules:
        rules.fog_of_war = false
        rules.shroud_enabled = false


func _teardown() -> void:
    BoundsSystem.left_inset = _saved_insets.x
    BoundsSystem.right_inset = _saved_insets.y
    BoundsSystem.top_inset = _saved_insets.z
    BoundsSystem.bottom_inset = _saved_insets.w
    BoundsSystem.grid_cells = _saved_grid_cells
    var rules := GlobalRules.get_current()
    if rules:
        rules.fog_of_war = _saved_fog.x == 1
        rules.shroud_enabled = _saved_fog.y == 1


## First cell inside the map diamond but outside the visible bounds.
func _map_cell_outside_visible() -> Vector2i:
    var extent: Vector2i = CellUtil.get_diamond_extent(GRID)
    for x in extent.x:
        for z in extent.y:
            var cell := Vector2i(x, z)
            if BoundsSystem.is_in_map_bounds(cell) and not BoundsSystem.is_in_play_area(cell):
                return cell
    return Vector2i(0, 0)


func _orders(
    target: Node3D, cell: Vector2i, pos: Vector3, modifiers: Dictionary
) -> Array[OrderResult]:
    return OrderSystem.get_orders(target, cell, pos, modifiers)


func _cursor(target: Node3D, cell: Vector2i, pos: Vector3, modifiers: Dictionary) -> int:
    return OrderSystem.get_cursor(target, cell, pos, modifiers)


# ========================================
# Ground orders: clamp, not reject
# ========================================


func test_ground_move_outside_clamps_to_visible_bounds():
    if not _sm:
        TestHelper.fail("SelectionManager not injected")
        return
    _setup()
    var local_id: int = _pm.get_local_player_id() if _pm else 0
    var unit := _make_combat_entity(local_id)
    var sc := _select_entity(unit)
    if sc == null:
        TestHelper.fail("select failed")
        _free_unit(unit, null)
        _teardown()
        return
    var out_cell := _map_cell_outside_visible()
    var outside_pos := CellUtil.cell_to_world(out_cell)
    var orders := _orders(null, Vector2i.ZERO, outside_pos, {})
    var cell_was_out: bool = not BoundsSystem.is_in_play_area(out_cell)
    var dest_cell := CellUtil.world_to_cell(orders[0].target_pos) if orders else Vector2i(-1, -1)
    var clamped_ok: bool = (
        orders.size() == 1
        and orders[0].cursor == CursorState.Type.MOVE
        and BoundsSystem.is_in_play_area_with_margin(dest_cell, BoundsSystem.ORDER_EDGE_INSET)
    )
    _free_unit(unit, sc)
    _teardown()
    (
        TestHelper
        . assert_true(
            cell_was_out and clamped_ok,
            (
                "ground move outside clamps into visible bounds (out=%s orders=%s)"
                % [cell_was_out, orders.size()]
            ),
        )
    )


func test_ground_move_outside_keeps_move_cursor():
    if not _sm:
        TestHelper.fail("SelectionManager not injected")
        return
    _setup()
    var local_id: int = _pm.get_local_player_id() if _pm else 0
    var unit := _make_combat_entity(local_id)
    var sc := _select_entity(unit)
    if sc == null:
        TestHelper.fail("select started")
        _teardown()
        return
    var out := _map_cell_outside_visible()
    var outside_pos := CellUtil.cell_to_world(out)
    var cursor := _cursor(null, Vector2i.ZERO, outside_pos, {})
    _free_unit(unit, sc)
    _teardown()
    TestHelper.assert_eq(cursor, CursorState.Type.MOVE, "boundary ground cursor stays MOVE")


func test_ground_move_inside_unclamped():
    if not _sm:
        TestHelper.fail("SelectionManager not injected")
        return
    _setup()
    var local_id: int = _pm.get_local_player_id() if _pm else 0
    var unit := _make_combat_entity(local_id)
    var sc := _select_entity(unit)
    if sc == null:
        _teardown()
        return
    var inside_cell := Vector2i(40, 40)
    var inside_pos := CellUtil.cell_to_world(inside_cell)
    var orders := _orders(null, Vector2i.ZERO, inside_pos, {})
    var unchanged: bool = orders.size() == 1 and orders[0].target_pos == inside_pos
    _free_unit(unit, sc)
    _teardown()
    TestHelper.assert_true(unchanged, "ground move inside keeps unclamped target_pos")


# ========================================
# Entity orders: reject out of bounds
# ========================================


func test_attack_out_of_bounds_rejected():
    if not _sm:
        TestHelper.fail("SelectionManager not injected")
        return
    _setup()
    var local_id: int = _pm.get_local_player_id() if _pm else 0
    var unit := _make_combat_entity(local_id)
    var sc := _select_entity(unit)
    if sc == null:
        _teardown()
        return
    var target := _make_target(local_id + 1)
    var out := _map_cell_outside_visible()
    var orders := _orders(target, out, CellUtil.cell_to_world(out), {})
    var cursor := _cursor(target, out, CellUtil.cell_to_world(out), {})
    target.free()
    _free_unit(unit, sc)
    _teardown()
    (
        TestHelper
        . assert_true(
            orders.is_empty() and cursor == CursorState.Type.GENERIC_BLOCKED,
            "attack on out-of-bounds entity -> empty orders + BLOCKED cursor",
        )
    )


func test_attack_in_bounds_unchanged():
    if not _sm:
        TestHelper.fail("SelectionManager not injected")
        return
    _setup()
    var local_id: int = _pm.get_local_player_id() if _pm else 0
    var unit := _make_combat_entity(local_id)
    var sc := _select_entity(unit)
    if sc == null:
        _teardown()
        return
    var target := _make_target(local_id + 1)
    var center := Vector2i(40, 40)
    var orders := _orders(target, center, CellUtil.cell_to_world(center), {})
    var cursor := _cursor(target, center, CellUtil.cell_to_world(center), {})
    target.free()
    _free_unit(unit, sc)
    _teardown()
    (
        TestHelper
        . assert_true(
            orders.size() == 1 and cursor == CursorState.Type.ATTACK,
            (
                "in-bounds enemy still attackable (orders=%d order_cursor=%s cursor=%d)"
                % [orders.size(), orders[0].cursor if orders.size() else "none", cursor]
            ),
        )
    )


func test_harvest_dock_out_of_bounds_rejected():
    if not _sm:
        TestHelper.fail("SelectionManager not injected")
        return
    _setup()
    var local_id: int = _pm.get_local_player_id() if _pm else 0
    var harvester := _make_harvester_entity(local_id)
    var sc := _select_entity(harvester)
    if sc == null:
        _teardown()
        return
    var refinery := _make_refinery_target(local_id)
    var out := _map_cell_outside_visible()
    refinery.global_position = CellUtil.cell_to_world(out)
    add_child(refinery)
    var orders := _orders(refinery, out, refinery.global_position, {})
    refinery.free()
    _free_unit(harvester, sc)
    _teardown()
    TestHelper.assert_true(orders.is_empty(), "harvest/dock on out-of-bounds entity rejected")


func test_rally_point_outside_clamps_to_edge():
    if not _sm:
        TestHelper.fail("SelectionManager not injected")
        return
    _setup()
    var md := Node3D.new()
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = 0
    md.add_child(stats)
    var rally := RallyPointComponent.new()
    rally.name = "RallyPointComponent"
    md.add_child(rally)
    var sc := _select_entity(md)
    if sc == null:
        _teardown()
        return
    var out := _map_cell_outside_visible()
    var outside_pos := CellUtil.cell_to_world(out)
    _sm.request_set_rally_point(outside_pos)
    var cell_in: bool = BoundsSystem.is_in_play_area(rally.rally_point)
    _free_unit(md, sc)
    _teardown()
    TestHelper.assert_true(cell_in, "rally point outside clamps to visible edge")


# ========================================
# Automatic / AI movement unaffected
# ========================================


func test_auto_harvester_move_outside_bounds_unaffected():
    # The harvester auto-cycle calls MovementController.move_to
    # directly (never OrderSystem), so an out-of-bounds field is accepted and
    # the destination is NOT clamped to the visible edge.
    if not _sm:
        TestHelper.fail("SelectionManager not injected")
        return
    _setup()
    var out := _map_cell_outside_visible()
    var outside_pos := CellUtil.cell_to_world(out)
    # Detached controller mirroring _make_mc in test_move_target_line.gd, so the
    # MoveController never runs _physics_process during the assertion.
    var parent := Node3D.new()
    (Engine.get_main_loop() as SceneTree).root.add_child(parent)
    parent.global_position = CellUtil.cell_to_world(Vector2i(25, 25))
    var mc := MovementController.new()
    mc._parent = parent
    mc._retarget(outside_pos)
    var dest_cell := CellUtil.world_to_cell(mc.get_target_position())
    var dest_unclamped: bool = dest_cell == out
    parent.free()
    mc.free()
    _teardown()
    (
        TestHelper
        . assert_true(
            dest_unclamped,
            "auto harvester move outside is not clamped (dest=%s out=%s)" % [dest_cell, out],
        )
    )


func test_ai_start_and_end_outside_bounds_unclamped():
    # AI-contract regression: automatic movement with BOTH start and end
    # outside the visible diamond must land exactly where told. This freezes
    # the unbounded default on move_to — a refactor that flips
    # it would silently break harvester/dock/combat auto cycles in the void.
    if not _sm:
        TestHelper.fail("SelectionManager not injected")
        return
    _setup()
    var out_a := _map_cell_outside_visible()
    var out_b := Vector2i(-1, -1)
    # A second map-bounds cell that is inside the map but outside play area,
    # distinct from out_a.
    var extent: Vector2i = CellUtil.get_diamond_extent(GRID)
    for x in range(extent.x - 1, -1, -1):
        var found := false
        for z in extent.y:
            var c := Vector2i(x, z)
            if (
                BoundsSystem.is_in_map_bounds(c)
                and not BoundsSystem.is_in_play_area(c)
                and c != out_a
            ):
                out_b = c
                found = true
                break
        if found:
            break
    var setup_ok: bool = (
        BoundsSystem.is_in_map_bounds(out_a)
        and BoundsSystem.is_in_map_bounds(out_b)
        and not BoundsSystem.is_in_play_area(out_a)
        and not BoundsSystem.is_in_play_area(out_b)
        and out_a != out_b
    )
    var parent := Node3D.new()
    (Engine.get_main_loop() as SceneTree).root.add_child(parent)
    parent.global_position = CellUtil.cell_to_world(out_a)
    var mc := MovementController.new()
    mc._parent = parent
    mc._retarget(CellUtil.cell_to_world(out_b))
    var dest_cell := CellUtil.world_to_cell(mc.get_target_position())
    parent.free()
    mc.free()
    _teardown()
    (
        TestHelper
        . assert_true(
            setup_ok and dest_cell == out_b,
            (
                "AI move outside->outside lands exactly at target (dest=%s want=%s)"
                % [dest_cell, out_b]
            ),
        )
    )


func test_group_sharer_ordered_to_edge_keeps_cell_in_order_area():
    # Ordering a single infantry (shares_cell) to a boundary-adjacent target
    # must keep the assigned cell inside the inset order area: the target cell
    # gets reserved by the sharer, forcing _find_sharer_cell to spiral; its
    # radius-4 elliptic scan bounds the result to the visible inset region.
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _setup()
    var local_id: int = _pm.get_local_player_id() if _pm else 0
    var entity := Node3D.new()
    entity.name = "EdgeSharer"
    var stats := StatsComponent.new()
    stats.player_id = local_id
    entity.add_child(stats)
    var mc := MovementController.new()
    mc._shares_cell = true
    entity.add_child(mc)
    entity.global_position = CellUtil.cell_to_world(Vector2i(40, 40))
    _select_entity(entity)
    var edge_world := BoundsSystem.clamp_to_visible_diamond(
        CellUtil.cell_to_world(Vector2i(25, 25)), BoundsSystem.ORDER_EDGE_INSET
    )
    _sm.request_move(edge_world)
    var assigned: Vector2i = _sm._find_sharer_cell(edge_world)
    var cell_in: bool = BoundsSystem.is_in_play_area_with_margin(
        assigned, BoundsSystem.ORDER_EDGE_INSET
    )
    _free_unit(entity, null)
    _sm.deselect_all()
    _teardown()
    (
        TestHelper
        . assert_true(
            cell_in,
            "single sharer at clamped edge stays inside order area (assigned=%s)" % [assigned],
        )
    )
