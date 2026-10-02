extends Node

# Force-fire ground orders: Ctrl turns a bare cell into a fire target, and the
# shroud — not the fog — is what refuses one. Covers the order-system
# "Force-fire ground order" requirement and the ground half of "Fog-gated
# target filtering", plus the untouched no-modifier ground path.

const SELECT_COMPONENT_SCENE: PackedScene = preload("res://scenes/components/SelectComponent.tscn")

const GRID := Vector2i(50, 50)
## Inside the visible bounds and the map diamond, so the bounds gate never
## interferes with the order this suite is exercising.
const TARGET_CELL := Vector2i(40, 40)

# `_ts` / `_pm` / `_sm` are injected by the runner; test objects are never
# added to the tree, so _ready() and absolute-path lookups do not run here.
var _ts: Node = null
var _pm: Node = null
var _sm: Node = null
var _saved_insets := Vector4i(0, 0, 0, 0)
var _saved_grid_cells := Vector2i(50, 50)
var _saved_fog := Vector2i(0, 0)


func _make_weapon(range_cells: float = 5.0) -> WeaponData:
    var w := WeaponData.new()
    w.id = "FF_WEAPON"
    w.damage = 10
    w.attack_range = range_cells
    w.rate_of_fire = 1.0
    return w


func _make_unit(armed: bool, player_id: int, movable: bool = true) -> Node3D:
    var entity := Node3D.new()
    entity.name = "FFUnit"
    if armed:
        var combat := CombatComponent.new()
        combat.name = "CombatComponent"
        combat.weapons = [_make_weapon()]
        combat._init_cooldowns()
        entity.add_child(combat)
    if movable:
        var mc := MovementController.new()
        mc.name = "MovementController"
        entity.add_child(mc)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    entity.add_child(stats)
    return entity


func _make_deployable_armed_unit(player_id: int) -> Node3D:
    var entity := _make_unit(true, player_id)
    var deploy := DeployComponent.new()
    deploy.name = "DeployComponent"
    deploy.undeploys_into = "MCV"
    entity.add_child(deploy)
    return entity


func _select(entity: Node3D) -> SelectComponent:
    _sm.deselect_all()
    return _select_add(entity)


func _select_add(entity: Node3D) -> SelectComponent:
    _sm.add_child(entity)
    var sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    sc.name = "SelectComponent"
    entity.add_child(sc)
    _sm.add_entity(sc)
    return sc


func _deselect(entity: Node3D, sc: SelectComponent) -> void:
    if _sm and is_instance_valid(sc):
        _sm.remove_entity(sc)
    if is_instance_valid(entity):
        if entity.is_inside_tree():
            entity.get_parent().remove_child(entity)
        entity.free()


func _setup(shroud: bool = false, fog: bool = false) -> bool:
    if _ts == null or _pm == null or _sm == null:
        TestHelper.fail("TerrainSystem/PlayerManager/SelectionManager not injected")
        return false
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
    _pm._players.clear()
    _pm._local_player_id = 0
    _pm._init_defaults()
    if rules:
        rules.shroud_enabled = shroud
        rules.fog_of_war = fog
    return true


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
    if _sm:
        _sm.deselect_all()


func _force() -> Dictionary:
    return {OrderResult.MOD_FORCE_ATTACK: true}


func _target_pos() -> Vector3:
    return CellUtil.cell_to_world(TARGET_CELL)


# ========================================
# Order generation under the modifier
# ========================================


func test_ctrl_ground_issues_attack_order_and_cursor():
    if not _setup():
        return
    var unit := _make_unit(true, 0)
    var sc := _select(unit)
    var pos := _target_pos()
    var orders := OrderSystem.get_orders(null, Vector2i.ZERO, pos, _force())
    var cursor := OrderSystem.get_cursor(null, Vector2i.ZERO, pos, _force())
    var ok: bool = (
        orders.size() == 1
        and orders[0].cursor == CursorState.Type.ATTACK
        and orders[0].priority > 5
        and orders[0].target_pos == pos
        and orders[0].get("voice_event") == VoiceData.EVENT_ATTACK
        and cursor == CursorState.Type.ATTACK
    )
    _deselect(unit, sc)
    _teardown()
    TestHelper.assert_true(ok, "Ctrl on empty ground -> ATTACK order + ATTACK cursor")


func test_plain_ground_still_moves():
    if not _setup():
        return
    var unit := _make_unit(true, 0)
    var sc := _select(unit)
    var pos := _target_pos()
    var orders := OrderSystem.get_orders(null, Vector2i.ZERO, pos, {})
    var cursor := OrderSystem.get_cursor(null, Vector2i.ZERO, pos, {})
    var ok: bool = (
        orders.size() == 1
        and orders[0].cursor == CursorState.Type.MOVE
        and orders[0].target_pos == pos
        and cursor == CursorState.Type.MOVE
    )
    _deselect(unit, sc)
    _teardown()
    TestHelper.assert_true(ok, "plain click on the same ground -> MOVE order + MOVE cursor")


func test_unarmed_selection_ctrl_ground_moves():
    if not _setup():
        return
    var unit := _make_unit(false, 0)
    var sc := _select(unit)
    var orders := OrderSystem.get_orders(null, Vector2i.ZERO, _target_pos(), _force())
    var cursor := OrderSystem.get_cursor(null, Vector2i.ZERO, _target_pos(), _force())
    var ok: bool = (
        orders.size() == 1
        and orders[0].cursor == CursorState.Type.MOVE
        and cursor == CursorState.Type.MOVE
    )
    _deselect(unit, sc)
    _teardown()
    TestHelper.assert_true(ok, "unarmed selection under Ctrl still moves")


func test_deployed_armed_selection_ctrl_ground_wins_undeploy():
    if not _setup():
        return
    var unit := _make_deployable_armed_unit(0)
    var sc := _select(unit)
    var orders := OrderSystem.get_orders(null, Vector2i.ZERO, _target_pos(), _force())
    var cursor := OrderSystem.get_cursor(null, Vector2i.ZERO, _target_pos(), _force())
    var ok: bool = (
        orders.size() == 1
        and orders[0].cursor == CursorState.Type.ATTACK
        and orders[0].priority == 30
        and cursor == CursorState.Type.ATTACK
    )
    _deselect(unit, sc)
    _teardown()
    TestHelper.assert_true(ok, "priority-30 attack outranks the undeploy order")


# ========================================
# Shroud gate: fog does not block, shroud does
# ========================================


func test_force_fire_blocked_in_unexplored_cell():
    if not _setup(true, true):
        return
    var unit := _make_unit(true, 0)
    var sc := _select(unit)
    var pos := _target_pos()
    var cell := CellUtil.world_to_cell(pos)
    var unexplored: bool = not ShroudSystem.is_explored(0, cell)
    var orders := OrderSystem.get_orders(null, Vector2i.ZERO, pos, _force())
    var cursor := OrderSystem.get_cursor(null, Vector2i.ZERO, pos, _force())
    var degraded: bool = (
        orders.size() == 1
        and orders[0].cursor == CursorState.Type.MOVE
        and cursor == CursorState.Type.MOVE
    )
    _deselect(unit, sc)
    _teardown()
    TestHelper.assert_true(unexplored, "fixture: target cell is unexplored")
    TestHelper.assert_true(degraded, "force-fire into shroud degrades to a move")


func test_force_fire_allowed_in_explored_fogged_cell():
    if not _setup(true, true):
        return
    var unit := _make_unit(true, 0)
    var sc := _select(unit)
    var pos := _target_pos()
    var cell := CellUtil.world_to_cell(pos)
    ShroudSystem.explore_area(0, cell, 3)
    var explored_but_dark: bool = (
        ShroudSystem.is_explored(0, cell) and not ShroudSystem.is_cell_visible_to_local(cell)
    )
    var orders := OrderSystem.get_orders(null, Vector2i.ZERO, pos, _force())
    var cursor := OrderSystem.get_cursor(null, Vector2i.ZERO, pos, _force())
    var issued: bool = (
        orders.size() == 1
        and orders[0].cursor == CursorState.Type.ATTACK
        and cursor == CursorState.Type.ATTACK
    )
    _deselect(unit, sc)
    _teardown()
    TestHelper.assert_true(explored_but_dark, "fixture: explored but not visible (fogged)")
    TestHelper.assert_true(issued, "force-fire into fog is still issued")


func test_force_fire_outside_diamond_judges_clicked_cell_not_clamp():
    # The shroud gate must judge the clicked cell, not the bounds-clamped edge:
    # a Ctrl+click outside the order diamond into shroud stays a move even when
    # the clamped edge cell is explored.
    if not _setup(true, false):
        return
    var unit := _make_unit(true, 0)
    var sc := _select(unit)
    var far := CellUtil.cell_to_world(Vector2i(-100, -100))
    var clamped := BoundsSystem.clamp_to_visible_diamond(far, BoundsSystem.ORDER_EDGE_INSET)
    var edge_cell := CellUtil.world_to_cell(clamped)
    ShroudSystem.explore_area(0, edge_cell, 1)
    var edge_explored: bool = ShroudSystem.is_explored(0, edge_cell)
    var clicked_shrouded: bool = not ShroudSystem.is_explored(0, CellUtil.world_to_cell(far))
    var orders := OrderSystem.get_orders(null, Vector2i.ZERO, far, _force())
    var cursor := OrderSystem.get_cursor(null, Vector2i.ZERO, far, _force())
    var degraded: bool = (
        orders.size() == 1
        and orders[0].cursor == CursorState.Type.MOVE
        and cursor == CursorState.Type.MOVE
    )
    _deselect(unit, sc)
    _teardown()
    TestHelper.assert_true(edge_explored, "fixture: clamped edge cell is explored")
    TestHelper.assert_true(clicked_shrouded, "fixture: clicked cell is shroud-covered")
    TestHelper.assert_true(degraded, "out-of-diamond force-fire into shroud degrades to a move")


func test_shroud_gate_does_not_depend_on_fog_of_war():
    # shroud on, fog off: the gate must still refuse an unexplored cell.
    if not _setup(true, false):
        return
    var unit := _make_unit(true, 0)
    var sc := _select(unit)
    var pos := _target_pos()
    var orders := OrderSystem.get_orders(null, Vector2i.ZERO, pos, _force())
    var degraded: bool = orders.size() == 1 and orders[0].cursor == CursorState.Type.MOVE
    _deselect(unit, sc)
    _teardown()
    TestHelper.assert_true(degraded, "shroud gate applies with fog_of_war disabled")


func test_mixed_selection_armed_fire_unarmed_hold():
    if not _setup():
        return
    var armed := _make_unit(true, 0)
    var unarmed := _make_unit(false, 0)
    _sm.deselect_all()
    var sc_armed := _select_add(armed)
    var sc_unarmed := _select_add(unarmed)
    var orders := OrderSystem.get_orders(null, Vector2i.ZERO, _target_pos(), _force())
    var cursor := OrderSystem.get_cursor(null, Vector2i.ZERO, _target_pos(), _force())
    var ok: bool = (
        orders.size() == 1
        and orders[0].cursor == CursorState.Type.ATTACK
        and cursor == CursorState.Type.ATTACK
    )
    _deselect(armed, sc_armed)
    _deselect(unarmed, sc_unarmed)
    _teardown()
    TestHelper.assert_true(ok, "armed unit fires while the unarmed unit holds")


func test_entity_filtering_survives_fog_off_while_shrouded():
    # `fog_of_war` alone does not disable the entity gate: with the shroud on,
    # a never-explored cell still hides what stands in it.
    if not _setup(true, false):
        return
    var unit := _make_unit(true, 0)
    var sc := _select(unit)
    var enemy := Node3D.new()
    enemy.name = "ShroudedEnemy"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = 1
    enemy.add_child(stats)
    enemy.position = _target_pos()
    var orders := OrderSystem.get_orders(enemy, TARGET_CELL, _target_pos(), {})
    var cursor := OrderSystem.get_cursor(enemy, TARGET_CELL, _target_pos(), {})
    var filtered: bool = (
        orders.size() == 1
        and orders[0].cursor == CursorState.Type.MOVE
        and cursor == CursorState.Type.MOVE
    )
    enemy.free()
    _deselect(unit, sc)
    _teardown()
    TestHelper.assert_true(filtered, "fog off alone does not reveal a shrouded enemy")
