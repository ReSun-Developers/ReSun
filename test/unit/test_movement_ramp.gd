# test_movement_ramp.gd - Ramp behavior tests

extends Node

var _ts: Node = null


func _reset_terrain() -> void:
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    if _ts:
        _ts.init_grid(50, 50)
        _ts.clear()


func _make_mc(entity_type: int) -> Array:
    var entity := Node3D.new()
    var stats := StatsComponent.new()
    stats.entity_type = entity_type
    stats.player_id = 0
    stats.weight = 3.0
    entity.add_child(stats)
    var mc := MovementController.new()
    entity.add_child(mc)
    mc._parent = entity
    mc._instant_turn = true
    Engine.get_main_loop().root.add_child(entity)
    return [entity, mc]


func _cleanup(pair: Array) -> void:
    var entity: Node = pair[0]
    var root: Node = entity.get_parent()
    if root:
        root.remove_child(entity)
    entity.free()


func _make_locomotor(accelerate: bool, decelerate: bool) -> Locomotor:
    var lm := Locomotor.new()
    lm.id = "TestWheel"
    lm.terrain_speeds = {"clear": 1.0}
    lm.accelerate = accelerate
    lm.decelerate = decelerate
    return lm


## Test: Accelerate ramp-up
## WHEN locomotor with accelerate=true starts from standstill
## THEN per-frame displacement rises toward full speed


func test_accelerate_ramp_up() -> void:
    _reset_terrain()
    var pair := _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    mc._locomotor_data = _make_locomotor(true, false)

    mc.move_to(Vector3(20.0, 0.0, 0.0))
    mc._state = MovementController.State.MOVING

    for i in range(20):
        mc._handle_moving_movement(0.0167)

    TestHelper.assert_true(mc._ramp_speed > 0.0, "Ramp speed should be positive after 20 frames")
    TestHelper.assert_true(
        mc._ramp_speed <= mc.move_speed, "Ramp speed should not exceed move_speed"
    )
    _cleanup(pair)


## Test: Decelerate ramp-down
## WHEN locomotor with decelerate=true approaches final waypoint
## THEN per-frame displacement falls toward crawl speed while still moving


func test_decelerate_ramp_down() -> void:
    _reset_terrain()
    var pair := _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    mc._locomotor_data = _make_locomotor(true, true)

    mc.move_to(Vector3(20.0, 0.0, 0.0))
    mc._state = MovementController.State.MOVING

    for i in range(30):
        mc._handle_moving_movement(0.0167)

    var mid_speed: float = mc._ramp_speed
    TestHelper.assert_true(mid_speed > mc.move_speed * 0.5, "Should reach cruise by halfway")

    # Tick until arrival (capped), tracking the last speed seen while still MOVING.
    # The braking envelope must engage BEFORE arrival — if we only checked after
    # arrival, the IDLE reset would make the assert pass vacuously.
    var last_moving_speed: float = mid_speed
    for i in range(400):
        mc._handle_moving_movement(0.0167)
        if mc.get_state() != MovementController.State.MOVING:
            break
        last_moving_speed = mc._ramp_speed

    TestHelper.assert_true(
        mc.get_state() != MovementController.State.MOVING,
        "Unit should arrive within the tick budget"
    )
    TestHelper.assert_true(
        last_moving_speed < mid_speed, "Speed should drop on final approach while still moving"
    )
    _cleanup(pair)


## Test: No-regression default-off
## WHEN both flags are false
## THEN per-frame displacement is identical to constant-speed behavior


func test_default_off_no_regression() -> void:
    _reset_terrain()
    var pair := _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    mc._locomotor_data = _make_locomotor(false, false)

    mc.move_to(Vector3(10.0, 0.0, 0.0))
    mc._state = MovementController.State.MOVING

    for i in range(60):
        mc._handle_moving_movement(0.0167)

    var expected_dist: float = mc.move_speed * 1.0
    var actual_dist: float = mc._parent.global_position.distance_to(mc._waypoints[0])
    TestHelper.assert_true(
        absf(actual_dist - expected_dist) < 0.5,
        (
            "Default-off should match constant speed (expected %f, got %f)"
            % [expected_dist, actual_dist]
        )
    )
    _cleanup(pair)


## Test: Short-move no overshoot
## WHEN 1-2 cell order with both flags
## THEN lands exactly on sub-slot with no overshoot


func test_short_move_no_overshoot() -> void:
    _reset_terrain()
    var pair := _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    mc._locomotor_data = _make_locomotor(true, true)

    mc.move_to(Vector3(2.0, 0.0, 0.0))
    mc._state = MovementController.State.MOVING

    for i in range(120):
        if mc.get_state() != MovementController.State.MOVING:
            break
        mc._handle_moving_movement(0.0167)

    var dist_to_final: float = mc._parent.global_position.distance_to(
        mc._waypoints[mc._waypoints.size() - 1]
    )
    TestHelper.assert_true(
        dist_to_final < 0.002, "Should arrive within tolerance (got %f)" % dist_to_final
    )
    _cleanup(pair)


## Test: Decel-only first move starts at cruise
## WHEN locomotor has decelerate=true, accelerate=false and orders its first move
## THEN ramp starts at full speed (TS semantics: no Accelerate = immediate cruise)


func test_decel_only_first_move_starts_at_cruise() -> void:
    _reset_terrain()
    var pair := _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    mc._locomotor_data = _make_locomotor(false, true)

    mc.move_to(Vector3(20.0, 0.0, 0.0))
    mc._state = MovementController.State.MOVING

    TestHelper.assert_eq(
        mc._ramp_speed, mc.move_speed, "Decel-only fresh order should start at cruise"
    )

    mc._handle_moving_movement(0.0167)

    TestHelper.assert_true(
        mc._ramp_speed > mc.move_speed * 0.9,
        "First tick must not clobber decel-only cruise start (got %f)" % mc._ramp_speed
    )
    _cleanup(pair)


## Test: Final step lands on target, never past it
## WHEN the unit's actual position is within one step of the final waypoint
##      while the spline parameter still has distance remaining
## THEN the step is clamped to the remaining distance — no offshoot-then-snap


func test_final_step_lands_on_target_not_past() -> void:
    _reset_terrain()
    var pair := _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    mc._locomotor_data = _make_locomotor(false, false)
    mc._waypoints = [Vector3.ZERO, Vector3(10.0, 0.0, 0.0)]
    mc._bake_spline()

    var final_pos: Vector3 = mc._waypoints[mc._waypoints.size() - 1]
    mc._parent.global_position = final_pos - Vector3(0.01, 0.0, 0.0)
    mc._last_position = mc._parent.global_position
    # Parameter lags behind the real position (repulsion / lerp lag can do this),
    # so the gate at _spline_t >= end would fire one tick too late.
    mc._spline_t = float(mc._num_segments()) - 0.02
    mc._state = MovementController.State.MOVING

    mc._handle_moving_movement(0.0167)

    var dist_after: float = mc._parent.global_position.distance_to(final_pos)
    TestHelper.assert_true(
        dist_after <= 0.001,
        "Final step must land on the target, not past it (dist %f)" % dist_after
    )

    var arrived_at: Array[Vector3] = []
    mc.arrived.connect(func(p: Vector3) -> void: arrived_at.append(p))
    mc._handle_moving_movement(0.0167)

    TestHelper.assert_true(
        mc.get_state() == MovementController.State.IDLE,
        "Arrival should fire the tick after landing"
    )
    TestHelper.assert_true(
        arrived_at.size() == 1 and arrived_at[0].distance_to(final_pos) < 0.001,
        "arrived should emit once at the final waypoint"
    )
    _cleanup(pair)


## Test: Mid-path movement is unaffected by the final-step clamp
## WHEN the unit is far from the final waypoint
## THEN it moves a full step and keeps moving


func test_midpath_step_not_clamped() -> void:
    _reset_terrain()
    var pair := _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    mc._locomotor_data = _make_locomotor(false, false)
    mc._waypoints = [Vector3.ZERO, Vector3(10.0, 0.0, 0.0)]
    mc._bake_spline()

    var final_pos: Vector3 = mc._waypoints[mc._waypoints.size() - 1]
    mc._parent.global_position = Vector3(5.0, 0.0, 0.0)
    mc._last_position = mc._parent.global_position
    mc._spline_t = 0.5
    mc._state = MovementController.State.MOVING

    mc._handle_moving_movement(0.0167)

    var dist: float = mc._parent.global_position.distance_to(final_pos)
    TestHelper.assert_true(
        dist > 4.8 and dist < 5.0, "Mid-path step should move a full step (dist %f)" % dist
    )
    TestHelper.assert_true(
        mc.get_state() == MovementController.State.MOVING, "Mid-path unit must keep moving"
    )
    _cleanup(pair)


## Test: Carry-forward on internal re-target
## WHEN internal re-target occurs mid-move
## THEN current ramped speed carries forward


func test_ramp_carries_on_retarget() -> void:
    _reset_terrain()
    var pair := _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    mc._locomotor_data = _make_locomotor(true, false)

    mc.move_to(Vector3(20.0, 0.0, 0.0))
    mc._state = MovementController.State.MOVING

    for i in range(10):
        mc._handle_moving_movement(0.0167)

    var ramp_speed_before: float = mc._ramp_speed

    mc._retarget(Vector3(30.0, 0.0, 0.0))

    TestHelper.assert_true(
        abs(mc._ramp_speed - ramp_speed_before) < 0.1,
        "Ramp speed should carry on internal re-target"
    )
    _cleanup(pair)
