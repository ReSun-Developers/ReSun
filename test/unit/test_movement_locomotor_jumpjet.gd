extends Node

const MovementFactory := preload("res://test/movement_test_factory.gd")

# MovementController jumpjet vertical state machine, booking, and attack holds

var _ts: Node = null


func _reset_terrain() -> void:
    if _ts:
        _ts.init_grid(50, 50)
        _ts.clear()


func _jumpjet() -> Locomotor:
    var jj := Locomotor.new()
    jj.terrain_speeds = {"clear": 1.0, "rough": 0.89}
    jj.is_jumpjet = true
    jj.jumpjet_fly_distance = 0.0
    jj.shares_cell = true
    jj.stand_upright = true
    jj.instant_turn = true
    jj.organic_path = true
    return jj


func _make_mc(entity_type: int) -> Array:
    return _make_mc_with(_jumpjet(), entity_type)


func _make_mc_with(loco: Locomotor, entity_type: int) -> Array:
    var mc := MovementFactory.make_movement_controller(loco, entity_type)
    return [mc.get_parent(), mc]


## Creates an idle non-infantry entity occupying a cell, so the cell counts as
## occupied-by-idle for occupancy checks. The caller adds it to the tree and
## triggers `SpatialHash.instance.rebuild()` so it registers in the grid.


func _place_idle_vehicle(cell: Vector2i) -> Node3D:
    var blocker := Node3D.new()
    blocker.name = "BlockerVehicle"
    blocker.global_position = CellUtil.cell_to_world(cell)
    blocker.add_to_group("entities")
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.entity_type = EntityData.EntityType.VEHICLE
    stats.player_id = 1
    blocker.add_child(stats)
    var mc := MovementController.new()
    mc.name = "MovementController"
    blocker.add_child(mc)
    return blocker


func test_jumpjet_move_order_walks_when_reachable():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    var target := CellUtil.cell_to_world(Vector2i(52, 50))
    mc.move_to(target)
    var hybrid: bool = mc._hybrid_active
    var waypoints: int = mc._waypoints.size()
    var zone: int = mc._vertical_state
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(hybrid, false, "reachable move order walks on the ground")
    TestHelper.assert_true(waypoints >= 2, "clear walk path is a straight segment")
    TestHelper.assert_eq(zone, MovementController.VerticalState.GROUND, "default zone stays GROUND")


func test_jumpjet_move_order_flies_when_far():
    _reset_terrain()
    var jj := _jumpjet()
    jj.jumpjet_fly_distance = 1.0
    var pair: Array = _make_mc_with(jj, EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    var target := CellUtil.cell_to_world(Vector2i(54, 50))
    mc.move_to(target)
    var hybrid: bool = mc._hybrid_active
    var waypoints: int = mc._waypoints.size()
    var land: bool = mc._land_on_arrival
    var booked: bool = mc.has_sub_slot()
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(hybrid, true, "far move order flies to target")
    TestHelper.assert_eq(waypoints, 2, "fly is a single straight segment")
    TestHelper.assert_eq(land, true, "fly move order lands on arrival")
    TestHelper.assert_eq(booked, true, "far landing move reserves a sub-slot")


func test_jumpjet_airborne_move_flies_then_lands():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc._vertical_state = MovementController.VerticalState.AIR
    var target := CellUtil.cell_to_world(Vector2i(52, 50))
    mc.move_to(target)
    var hybrid: bool = mc._hybrid_active
    var land: bool = mc._land_on_arrival
    var booked: bool = mc.has_sub_slot()
    var dest: Vector3 = mc._waypoints[mc._waypoints.size() - 1]
    var sub_pos: Vector3 = mc.get_sub_slot_position()
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(hybrid, true, "airborne jumpjet stays airborne on move")
    TestHelper.assert_eq(land, true, "airborne move order lands on arrival")
    TestHelper.assert_eq(booked, true, "landing move reserves a sub-slot")
    TestHelper.assert_true(
        dest.distance_to(sub_pos) < 0.7, "landing waypoint stays within the sub-slot cell"
    )


func test_jumpjet_walk_books_sub_slot():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc._vertical_state = MovementController.VerticalState.GROUND
    var target := CellUtil.cell_to_world(Vector2i(52, 50))
    mc.move_to(target)
    var booked: bool = mc.has_sub_slot()
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(booked, true, "grounded walk reserves an infantry sub-slot")


func test_jumpjet_move_order_same_cell_stays_grounded():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    entity.global_position = CellUtil.cell_to_world(Vector2i(52, 50))
    var target := CellUtil.cell_to_world(Vector2i(52, 50))
    mc.move_to(target)
    var hybrid: bool = mc._hybrid_active
    var zone: int = mc._vertical_state
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(hybrid, false, "same-cell move does not fly")
    TestHelper.assert_eq(zone, MovementController.VerticalState.GROUND, "stays grounded")


func test_jumpjet_landing_waypoint_is_exact_sub_slot():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc._vertical_state = MovementController.VerticalState.AIR
    var target := CellUtil.cell_to_world(Vector2i(52, 50))
    mc.move_to(target)
    var dest: Vector3 = mc._waypoints[mc._waypoints.size() - 1]
    var sub_pos: Vector3 = mc.get_sub_slot_position()
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()
    (
        TestHelper
        . assert_true(
            dest.is_equal_approx(sub_pos),
            "landing waypoint is exactly the booked sub-slot, no lateral offset",
        )
    )


func test_jumpjet_landing_move_relocates_occupied_cell():
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var blocker := _place_idle_vehicle(Vector2i(52, 50))
    root.add_child(blocker)
    SpatialHash.instance.rebuild()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc._vertical_state = MovementController.VerticalState.AIR
    var target := CellUtil.cell_to_world(Vector2i(52, 50))
    mc.move_to(target)
    var dest: Vector3 = mc._waypoints[mc._waypoints.size() - 1]
    var dest_cell: Vector2i = CellUtil.world_to_cell(dest)
    var booked: bool = mc.has_sub_slot()
    root.remove_child(blocker)
    blocker.free()
    SpatialHash.instance.rebuild()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_true(
        dest_cell != Vector2i(52, 50), "landing fly move relocates off an occupied cell"
    )
    TestHelper.assert_eq(booked, true, "relocated landing books a sub-slot at the free cell")


func test_jumpjet_airborne_hold_ignores_occupied_cell():
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var blocker := _place_idle_vehicle(Vector2i(52, 50))
    root.add_child(blocker)
    SpatialHash.instance.rebuild()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    root.add_child(entity)
    entity.global_position = Vector3.ZERO
    mc._vertical_state = MovementController.VerticalState.AIR
    mc._land_on_arrival = false
    mc._state = MovementController.State.MOVING
    var stop_pos := CellUtil.cell_to_world(Vector2i(52, 50))
    mc._waypoints = [Vector3.ZERO, stop_pos]
    mc._spline_t = 1.0
    mc._handle_moving_movement(0.016)
    var dest: Vector3 = mc._waypoints[mc._waypoints.size() - 1]
    root.remove_child(entity)
    root.remove_child(blocker)
    entity.free()
    blocker.free()
    SpatialHash.instance.rebuild()
    _reset_terrain()
    (
        TestHelper
        . assert_true(
            dest.is_equal_approx(stop_pos),
            "airborne attack hold stays at its stop even on an occupied cell",
        )
    )
    TestHelper.assert_eq(mc._vertical_state, MovementController.VerticalState.AIR, "hold stays air")
    TestHelper.assert_eq(mc.has_sub_slot(), false, "airborne hold books no sub-slot")


func test_jumpjet_attack_move_has_no_spread():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc._vertical_state = MovementController.VerticalState.AIR
    var target := CellUtil.cell_to_world(Vector2i(52, 50))
    mc.approach(target)
    var dest: Vector3 = mc._waypoints[mc._waypoints.size() - 1]
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_true(
        dest.is_equal_approx(target), "attack waypoint keeps the stop position exactly"
    )


func test_jumpjet_cancel_move_retains_air():
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    root.add_child(entity)
    mc._state = MovementController.State.MOVING
    mc._vertical_state = MovementController.VerticalState.AIR
    mc._land_on_arrival = true
    mc.cancel_move_retain_vertical()
    var state: int = mc.get_state()
    var zone: int = mc._vertical_state
    var land: bool = mc._land_on_arrival
    root.remove_child(entity)
    entity.free()
    _reset_terrain()
    TestHelper.assert_eq(state, MovementController.State.IDLE, "cancel halts the move")
    TestHelper.assert_eq(zone, MovementController.VerticalState.AIR, "air zone retained")
    TestHelper.assert_eq(land, false, "pending landing cancelled")


func test_jumpjet_cancel_move_ignores_grounded():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc._state = MovementController.State.MOVING
    mc._vertical_state = MovementController.VerticalState.GROUND
    mc.cancel_move_retain_vertical()
    var state: int = mc.get_state()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(state, MovementController.State.MOVING, "grounded move left alone")


func test_jumpjet_attack_after_cancel_flies():
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    root.add_child(entity)
    mc._state = MovementController.State.MOVING
    mc._vertical_state = MovementController.VerticalState.AIR
    mc._land_on_arrival = true
    mc.cancel_move_retain_vertical()
    var target := CellUtil.cell_to_world(Vector2i(52, 50))
    mc.approach(target)
    var hybrid: bool = mc._hybrid_active
    var zone: int = mc._vertical_state
    var land: bool = mc._land_on_arrival
    root.remove_child(entity)
    entity.free()
    _reset_terrain()
    TestHelper.assert_eq(hybrid, true, "post-cancel attack takes the fly path")
    TestHelper.assert_eq(zone, MovementController.VerticalState.AIR, "attacks from the air")
    TestHelper.assert_eq(land, false, "attack does not land")


func test_jumpjet_wait_retarget_keeps_air_zone():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc._vertical_state = MovementController.VerticalState.AIR
    mc._land_on_arrival = false
    mc._state = MovementController.State.WAIT
    mc._wait_threshold = 0.01
    mc._wait_time = 0.02
    mc._waypoints = [Vector3.ZERO, CellUtil.cell_to_world(Vector2i(52, 50))]
    mc._handle_wait(0.01)
    var zone: int = mc._vertical_state
    var booked: bool = mc.has_sub_slot()
    var land: bool = mc._land_on_arrival
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(zone, MovementController.VerticalState.AIR, "attack hold stays airborne")
    TestHelper.assert_eq(booked, false, "attack hold reserves no ground sub-slot")
    TestHelper.assert_eq(land, false, "attack hold does not land")


func test_jumpjet_wait_retarget_landing_lands():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc._vertical_state = MovementController.VerticalState.AIR
    mc._land_on_arrival = true
    mc._state = MovementController.State.WAIT
    mc._wait_threshold = 0.01
    mc._wait_time = 0.02
    mc._waypoints = [Vector3.ZERO, CellUtil.cell_to_world(Vector2i(52, 50))]
    mc._handle_wait(0.01)
    var booked: bool = mc.has_sub_slot()
    var land: bool = mc._land_on_arrival
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(land, true, "landing move still lands on re-target")
    TestHelper.assert_eq(booked, true, "landing move books a sub-slot on re-target")


func test_jumpjet_blocked_arrival_retargets_immediately():
    _reset_terrain()
    SpatialHash.instance.register_building_cells([Vector2i(52, 50)])
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc._vertical_state = MovementController.VerticalState.AIR
    mc._land_on_arrival = true
    mc._state = MovementController.State.MOVING
    mc._waypoints = [Vector3.ZERO, CellUtil.cell_to_world(Vector2i(52, 50))]
    mc._spline_t = 1.0
    mc._handle_moving_movement(0.016)
    var state: int = mc.get_state()
    var land: bool = mc._land_on_arrival
    SpatialHash.instance._building_cells.clear()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_true(
        state != MovementController.State.WAIT, "jumpjet skips WAIT on blocked arrival"
    )
    TestHelper.assert_eq(land, true, "blocked arrival re-target keeps landing intent")


func test_jumpjet_distant_flies():
    _reset_terrain()
    var jj := _jumpjet()
    jj.jumpjet_fly_distance = 1.0
    var pair: Array = _make_mc_with(jj, EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    var target := CellUtil.cell_to_world(Vector2i(54, 50))
    mc.move_to(target)
    var hybrid: bool = mc._hybrid_active
    var waypoints: int = mc._waypoints.size()
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(hybrid, true, "distant target triggers flight")
    TestHelper.assert_eq(waypoints, 2, "flight is a single straight segment")


func test_jumpjet_target_height_default():
    var jj := _jumpjet()
    var air_height: float = jj.jumpjet_target_height * _ts.HEIGHT_STEP
    (
        TestHelper
        . assert_true(
            is_equal_approx(air_height, 6.0 * _ts.HEIGHT_STEP),
            "default target height = 6 terrain height units",
        )
    )


func test_jumpjet_target_height_override():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    var rules := GlobalRules.new()
    var jj := _jumpjet()
    jj.id = "Jumpjet"
    jj.jumpjet_target_height = 3.0
    rules.locomotors["Jumpjet"] = jj
    mc._rules = rules
    mc.locomotor = "Jumpjet"
    mc._resolve_locomotor()
    var air_height: float = mc._jumpjet_air_height
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_true(
        is_equal_approx(air_height, 3.0 * _ts.HEIGHT_STEP), "configured height honored"
    )


func test_jumpjet_ascending_reaches_air():
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    root.add_child(entity)
    entity.global_position = Vector3.ZERO
    mc.move_speed = 10.0
    mc._jumpjet_air_height = 4.075
    mc._vertical_state = MovementController.VerticalState.ASCENDING
    var start_y: float = entity.global_position.y
    mc._update_vertical(0.1)
    var mid_y: float = entity.global_position.y
    mc._update_vertical(1.0)
    var end_y: float = entity.global_position.y
    var state: int = mc._vertical_state
    root.remove_child(entity)
    entity.free()
    _reset_terrain()
    TestHelper.assert_true(is_equal_approx(mid_y - start_y, 1.0), "ascends at move_speed * delta")
    TestHelper.assert_true(is_equal_approx(end_y, 4.075), "reaches air height")
    TestHelper.assert_eq(state, MovementController.VerticalState.AIR, "state -> AIR")


func test_jumpjet_descending_reaches_ground():
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    root.add_child(entity)
    entity.global_position = Vector3(0.0, 4.075, 0.0)
    mc.move_speed = 10.0
    mc._vertical_state = MovementController.VerticalState.DESCENDING
    mc._update_vertical(0.1)
    var mid_y: float = entity.global_position.y
    mc._update_vertical(1.0)
    var end_y: float = entity.global_position.y
    var state: int = mc._vertical_state
    root.remove_child(entity)
    entity.free()
    _reset_terrain()
    TestHelper.assert_true(is_equal_approx(4.075 - mid_y, 1.0), "descends at move_speed * delta")
    TestHelper.assert_true(end_y < 0.01, "reaches ground")
    TestHelper.assert_eq(state, MovementController.VerticalState.GROUND, "state -> GROUND")


func test_jumpjet_split_speed_ascend_and_forward():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc.move_speed = 10.0
    mc._state = MovementController.State.MOVING
    mc._vertical_state = MovementController.VerticalState.ASCENDING
    var factor: float = mc._vertical_split_factor()
    mc._state = MovementController.State.IDLE
    mc._vertical_state = MovementController.VerticalState.ASCENDING
    var idle_factor: float = mc._vertical_split_factor()
    mc._vertical_state = MovementController.VerticalState.AIR
    mc._state = MovementController.State.MOVING
    var air_factor: float = mc._vertical_split_factor()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(factor, 0.5, "ascending while moving splits speed in half")
    TestHelper.assert_eq(idle_factor, 1.0, "pure vertical transition keeps full speed")
    TestHelper.assert_eq(air_factor, 1.0, "cruising flight keeps full speed")


func test_jumpjet_fly_order_arrival_hovers():
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    root.add_child(entity)
    entity.global_position = Vector3(0.0, 4.075, 0.0)
    mc._jumpjet_air_height = 4.075
    mc._vertical_state = MovementController.VerticalState.AIR
    mc._snap_to_terrain(0.016)
    var y: float = entity.global_position.y
    root.remove_child(entity)
    entity.free()
    _reset_terrain()
    TestHelper.assert_true(is_equal_approx(y, 4.075), "airborne jumpjet hovers at air height")


func test_jumpjet_ground_snap_to_terrain():
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    root.add_child(entity)
    entity.global_position = Vector3(0.0, 4.075, 0.0)
    mc._jumpjet_air_height = 4.075
    mc._vertical_state = MovementController.VerticalState.GROUND
    mc._snap_to_terrain(0.016)
    var y: float = entity.global_position.y
    root.remove_child(entity)
    entity.free()
    _reset_terrain()
    TestHelper.assert_true(y < 0.01, "grounded jumpjet sits on terrain")


func test_jumpjet_new_order_while_descending_ascends():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc._vertical_state = MovementController.VerticalState.DESCENDING
    var target := CellUtil.cell_to_world(Vector2i(52, 50))
    mc.move_to(target)
    var state: int = mc._vertical_state
    var hybrid: bool = mc._hybrid_active
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(
        state, MovementController.VerticalState.ASCENDING, "descending order -> ascend"
    )
    TestHelper.assert_eq(hybrid, true, "interrupt takes the fly path")


func test_jumpjet_keep_zone_airborne_flies():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc._vertical_state = MovementController.VerticalState.AIR
    var target := CellUtil.cell_to_world(Vector2i(52, 50))
    mc.approach(target)
    var hybrid: bool = mc._hybrid_active
    var state: int = mc._vertical_state
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(hybrid, true, "airborne keep_zone attack flies")
    TestHelper.assert_eq(state, MovementController.VerticalState.AIR, "air zone retained")


func test_jumpjet_keep_zone_grounded_walks():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc._vertical_state = MovementController.VerticalState.GROUND
    var target := CellUtil.cell_to_world(Vector2i(52, 50))
    mc.approach(target)
    var hybrid: bool = mc._hybrid_active
    var state: int = mc._vertical_state
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(hybrid, false, "grounded keep_zone attack walks")
    TestHelper.assert_eq(state, MovementController.VerticalState.GROUND, "ground zone retained")


func test_jumpjet_keep_zone_descending_ascends():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc._vertical_state = MovementController.VerticalState.DESCENDING
    var target := CellUtil.cell_to_world(Vector2i(52, 50))
    mc.approach(target)
    var state: int = mc._vertical_state
    var hybrid: bool = mc._hybrid_active
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(
        state, MovementController.VerticalState.ASCENDING, "mid-transition attack ascends"
    )
    TestHelper.assert_eq(hybrid, true, "mid-transition attack flies")


func test_jumpjet_airborne_terrain_factor_is_one():
    if _ts == null:
        TestHelper.fail("TerrainSystem not injected")
        return
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var mc: MovementController = pair[1]
    mc._vertical_state = MovementController.VerticalState.AIR
    _ts.set_land_type(Vector2i(50, 50), "rough")
    var factor: float = mc._terrain_speed_factor()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(factor, 1.0, "airborne jumpjet ignores terrain speed")


func test_jumpjet_short_approach_no_overshoot():
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var pair: Array = _make_mc(EntityData.EntityType.INFANTRY)
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    root.add_child(entity)
    var start := Vector3(0.0, 4.075, 0.0)
    var final_pos := Vector3(4.0, 0.0, 0.0)
    entity.global_position = start
    mc._vertical_state = MovementController.VerticalState.AIR
    mc._land_on_arrival = false
    mc._state = MovementController.State.MOVING
    mc._waypoints = [start, final_pos]
    mc._spline_t = 0.0
    mc._last_position = start
    var prev_dist: float = start.distance_to(final_pos)
    var overshot := false
    var arrived := false
    for i in range(600):
        mc._handle_moving_movement(0.016)
        var dist := (
            Vector2(entity.global_position.x - final_pos.x, entity.global_position.z - final_pos.z)
            . length()
        )
        if dist > prev_dist + 0.05:
            overshot = true
        prev_dist = dist
        if mc.get_state() == MovementController.State.IDLE:
            arrived = true
            break
    root.remove_child(entity)
    entity.free()
    _reset_terrain()
    TestHelper.assert_true(not overshot, "airborne approach never overshoots past the stop")
    TestHelper.assert_true(arrived, "airborne approach reaches IDLE")
    TestHelper.assert_true(prev_dist < 0.01, "airborne approach converges on the stop")
