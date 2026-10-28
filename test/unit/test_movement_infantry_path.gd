extends Node

# Regression tests for #173 — infantry pathfinding start must not detour
# sideways. The unit spawns at a sub-slot offset, so a first waypoint snapped to
# a cell center (or sub-slot) can point off the straight line to the destination.
# The initial segment must be projected onto the start→destination line.

var _ts: Node = null


func _reset_terrain() -> void:
    if _ts:
        _ts.init_grid(50, 50)
        _ts.clear()


func _make_mc() -> Array:
    var entity := Node3D.new()
    var stats := StatsComponent.new()
    stats.entity_type = EntityData.EntityType.INFANTRY
    stats.player_id = 0
    stats.weight = 3.0
    entity.add_child(stats)
    var mc := MovementController.new()
    entity.add_child(mc)
    mc._parent = entity
    mc._shares_cell = true
    mc._organic_path = true
    mc._instant_turn = true
    var loco := Locomotor.new()
    loco.terrain_speeds = {"clear": 1.0}
    loco.shares_cell = true
    loco.organic_path = true
    mc._locomotor_data = loco
    return [entity, mc]


func test_first_segment_points_at_destination():
    _reset_terrain()
    var pair: Array = _make_mc()
    var mc: MovementController = pair[1]
    # Idle infantry sits at a sub-slot, offset from its cell center.
    var start_cell := Vector2i(50, 50)
    var positions: Array[Vector3] = CellSubPositions.get_sub_positions(start_cell)
    mc._parent.global_position = CellUtil.cell_to_world(start_cell) + positions[0]
    var target := CellUtil.cell_to_world(Vector2i(58, 50))
    mc.move_to(target)

    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()

    TestHelper.assert_true(mc._waypoints.size() >= 2, "path has a start and a destination waypoint")
    var start_pos: Vector3 = mc._waypoints[0]
    var final_pos: Vector3 = mc._waypoints[mc._waypoints.size() - 1]
    var to_dest := (final_pos - start_pos).normalized()
    to_dest.y = 0.0
    var first_seg := (mc._waypoints[1] - start_pos).normalized()
    first_seg.y = 0.0
    var angle_deg: float = rad_to_deg(first_seg.angle_to(to_dest))
    TestHelper.assert_true(
        angle_deg < 5.0,
        "first movement segment is aligned with the straight line to the destination"
    )


func test_clear_path_collapses_to_straight_segment():
    _reset_terrain()
    var pair: Array = _make_mc()
    var mc: MovementController = pair[1]
    var start_cell := Vector2i(50, 50)
    var positions: Array[Vector3] = CellSubPositions.get_sub_positions(start_cell)
    mc._parent.global_position = CellUtil.cell_to_world(start_cell) + positions[0]
    var target := CellUtil.cell_to_world(Vector2i(58, 50))
    mc.move_to(target)

    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()

    (
        TestHelper
        . assert_eq(
            mc._waypoints.size(),
            2,
            "clear path collapses to a single straight start→destination segment",
        )
    )


func test_blocked_path_keeps_intermediate_waypoints():
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var blocker := Node3D.new()
    blocker.name = "BlockerVehicle"
    blocker.global_position = CellUtil.cell_to_world(Vector2i(54, 50))
    blocker.add_to_group("entities")
    var bstats := StatsComponent.new()
    bstats.name = "StatsComponent"
    bstats.entity_type = EntityData.EntityType.VEHICLE
    bstats.player_id = 1
    blocker.add_child(bstats)
    var bmc := MovementController.new()
    bmc.name = "MovementController"
    blocker.add_child(bmc)
    bmc._parent = blocker
    root.add_child(blocker)
    SpatialHash.instance.rebuild()

    var pair: Array = _make_mc()
    var mc: MovementController = pair[1]
    var start_cell := Vector2i(50, 50)
    var positions: Array[Vector3] = CellSubPositions.get_sub_positions(start_cell)
    mc._parent.global_position = CellUtil.cell_to_world(start_cell) + positions[0]
    var target := CellUtil.cell_to_world(Vector2i(58, 50))
    mc.move_to(target)

    var cr := CellReservation.instance
    if cr:
        cr.clear()
    root.remove_child(blocker)
    blocker.free()
    SpatialHash.instance.rebuild()
    _reset_terrain()
    pair[0].queue_free()

    (
        TestHelper
        . assert_true(
            mc._waypoints.size() > 2,
            "blocked path keeps intermediate waypoints to route around the obstacle",
        )
    )
    var passes_through := false
    for i in range(1, mc._waypoints.size()):
        if CellUtil.world_to_cell(mc._waypoints[i]) == Vector2i(54, 50):
            passes_through = true
    TestHelper.assert_true(not passes_through, "path avoids the blocked cell")


func test_blocked_path_intermediates_use_consistent_lane_offset():
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var blocker := Node3D.new()
    blocker.name = "BlockerVehicle"
    blocker.global_position = CellUtil.cell_to_world(Vector2i(54, 50))
    blocker.add_to_group("entities")
    var bstats := StatsComponent.new()
    bstats.name = "StatsComponent"
    bstats.entity_type = EntityData.EntityType.VEHICLE
    bstats.player_id = 1
    blocker.add_child(bstats)
    var bmc := MovementController.new()
    bmc.name = "MovementController"
    blocker.add_child(bmc)
    bmc._parent = blocker
    root.add_child(blocker)
    SpatialHash.instance.rebuild()

    var pair: Array = _make_mc()
    var mc: MovementController = pair[1]
    var start_cell := Vector2i(50, 50)
    var positions: Array[Vector3] = CellSubPositions.get_sub_positions(start_cell)
    mc._parent.global_position = CellUtil.cell_to_world(start_cell) + positions[0]
    var target := CellUtil.cell_to_world(Vector2i(58, 50))
    mc.move_to(target)

    var expected_lane: Vector3 = (
        mc.get_sub_slot_position()
        - CellUtil.cell_to_world(CellUtil.world_to_cell(mc.get_sub_slot_position()))
    )
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    root.remove_child(blocker)
    blocker.free()
    SpatialHash.instance.rebuild()
    _reset_terrain()

    var lane_consistent := true
    var stays_in_cell := true
    var bad_wp := Vector3.ZERO
    for i in range(1, mc._waypoints.size() - 1):
        var wp_cell := CellUtil.world_to_cell(mc._waypoints[i])
        var center := CellUtil.cell_to_world(wp_cell)
        if mc._waypoints[i].distance_to(center + expected_lane) > 0.01:
            lane_consistent = false
            bad_wp = mc._waypoints[i]
        if mc._waypoints[i].distance_to(center) > 1.0:
            stays_in_cell = false
    pair[0].queue_free()
    TestHelper.assert_true(
        lane_consistent,
        "blocked-path intermediate waypoints share the same lane offset (got %s)" % bad_wp
    )
    TestHelper.assert_true(stays_in_cell, "lane-offset waypoints stay inside their own cells")


func test_destination_sub_slot_still_applied():
    _reset_terrain()
    var pair: Array = _make_mc()
    var mc: MovementController = pair[1]
    var start_cell := Vector2i(50, 50)
    var positions: Array[Vector3] = CellSubPositions.get_sub_positions(start_cell)
    mc._parent.global_position = CellUtil.cell_to_world(start_cell) + positions[0]
    var target := CellUtil.cell_to_world(Vector2i(58, 50))
    mc.move_to(target)

    var dest: Vector3 = mc._waypoints[mc._waypoints.size() - 1]
    var sub_pos: Vector3 = mc.get_sub_slot_position()
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    _reset_terrain()
    pair[0].queue_free()

    TestHelper.assert_true(
        dest.distance_to(sub_pos) < 0.05, "destination waypoint still lands on the booked sub-slot"
    )


func test_idle_unit_does_not_rewrite_y_on_same_cell():
    _reset_terrain()
    var pair: Array = _make_mc()
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    var root: Node = Engine.get_main_loop().root
    root.add_child(entity)
    entity.global_position = CellUtil.cell_to_world(Vector2i(50, 50))
    mc._state = MovementController.State.IDLE
    mc._idle_snapped = false
    mc._physics_process(0.016)
    var snapped_y: float = entity.global_position.y
    entity.global_position.y = snapped_y + 5.0
    mc._physics_process(0.016)
    var unchanged: bool = is_equal_approx(entity.global_position.y, snapped_y + 5.0)
    var cell: Vector2i = CellUtil.world_to_cell(entity.global_position)
    entity.global_position = CellUtil.cell_to_world(cell + Vector2i(4, 0))
    mc._idle_snapped = true
    mc._idle_snap_cell = cell
    mc._physics_process(0.016)
    var re_snapped: bool = not is_equal_approx(entity.global_position.y, snapped_y + 5.0)
    root.remove_child(entity)
    entity.free()
    TestHelper.assert_true(unchanged, "idle unit on the same cell does not rewrite y every tick")
    TestHelper.assert_true(re_snapped, "idle unit re-snaps after moving to a new cell")


func test_open_terrain_move_uses_greedy_without_find_path():
    _reset_terrain()
    var pair: Array = _make_mc()
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    var root: Node = Engine.get_main_loop().root
    root.add_child(entity)
    entity.global_position = CellUtil.cell_to_world(Vector2i(50, 50))
    var before: int = Pathfinder.find_path_call_count
    var target := CellUtil.cell_to_world(Vector2i(60, 50))
    mc.move_to(target)
    var calls: int = Pathfinder.find_path_call_count - before
    var reached := mc._waypoints.size() > 1
    root.remove_child(entity)
    entity.free()
    TestHelper.assert_eq(calls, 0, "open-terrain move completes via greedy descent, no find_path")
    TestHelper.assert_true(reached, "greedy move still produces a waypoint path to the target")


func test_concave_pocket_falls_back_to_find_path():
    _reset_terrain()
    var pair: Array = _make_mc()
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    var root: Node = Engine.get_main_loop().root
    root.add_child(entity)
    # Start inside a U-shaped pocket open to the south; the exit is blocked
    # north/east/west, so greedy stalls and the A* fallback must escape.
    var start_cell := Vector2i(50, 50)
    entity.global_position = CellUtil.cell_to_world(start_cell)
    var wall_offsets := [
        Vector2i(0, -1),
        Vector2i(1, -1),
        Vector2i(-1, -1),
        Vector2i(1, 0),
        Vector2i(-1, 0),
    ]
    for offset in wall_offsets:
        SpatialHash.instance._blocked_cells[CellUtil.cell_key(start_cell + offset)] = true
    var target := CellUtil.cell_to_world(Vector2i(52, 53))
    mc.move_to(target)
    var reached: bool = mc._waypoints.size() > 1
    for offset in wall_offsets:
        SpatialHash.instance._blocked_cells.erase(CellUtil.cell_key(start_cell + offset))
    root.remove_child(entity)
    entity.free()
    TestHelper.assert_true(
        reached, "unit trapped in a concave pocket still gets an escape path via find_path fallback"
    )


func test_flyer_greedy_crosses_height_steps():
    _reset_terrain()
    var pair: Array = _make_mc()
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    var root: Node = Engine.get_main_loop().root
    root.add_child(entity)
    var loco := Locomotor.new()
    loco.terrain_speeds = {"clear": 1.0}
    loco.is_fly = true
    mc._locomotor_data = loco
    entity.global_position = CellUtil.cell_to_world(Vector2i(50, 50))
    # Raise a 3-level wall between start and target; a flyer ignores height.
    for z in range(51, 56):
        _ts.set_vertex(51, z, 3)
        _ts.set_vertex(52, z, 3)
    var before: int = Pathfinder.find_path_call_count
    var target := CellUtil.cell_to_world(Vector2i(50, 56))
    mc.move_to(target)
    var calls: int = Pathfinder.find_path_call_count - before
    var reached := mc._waypoints.size() > 1
    root.remove_child(entity)
    entity.free()
    TestHelper.assert_eq(calls, 0, "flyer greedy crosses height steps without find_path")
    TestHelper.assert_true(reached, "flyer move reaches the far side of the wall")
