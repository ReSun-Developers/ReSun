extends Node

# MovementController terrain speed factor, hover float, hybrids, and slope probe

var _ts: Node = null
var _sh: Node = null


func _reset_terrain() -> void:
    if _ts:
        _ts.init_grid(50, 50)
        _ts.clear()


func _wheel() -> Locomotor:
    var wheel := Locomotor.new()
    wheel.terrain_speeds = {"clear": 1.0, "rough": 0.5, "road": 1.25}
    return wheel


func _subterranean() -> Locomotor:
    var sub := Locomotor.new()
    sub.terrain_speeds = {"clear": 1.0}
    sub.is_subterranean = true
    sub.subterranean_dig_distance = 0.0
    return sub


func _track() -> Locomotor:
    var track := Locomotor.new()
    track.id = "Track"
    track.uphill_factor = 0.5
    track.downhill_factor = 1.1
    return track


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
    return [entity, mc]


func test_terrain_speed_factor():
    if _ts == null:
        TestHelper.fail("TerrainSystem not injected")
        return
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    mc._locomotor_data = _wheel()
    _ts.set_land_type(Vector2i(50, 50), "rough")
    var factor: float = mc._terrain_speed_factor()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_true(is_equal_approx(factor, 0.5), "wheel on rough -> 0.5 speed")


func test_amphibious_water_factor():
    if _ts == null:
        TestHelper.fail("TerrainSystem not injected")
        return
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    var amphibious := Locomotor.new()
    amphibious.terrain_speeds = {"clear": 1.0, "water": 0.6}
    mc._locomotor_data = amphibious
    _ts.set_land_type(Vector2i(50, 50), "water")
    var factor: float = mc._terrain_speed_factor()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_true(is_equal_approx(factor, 0.6), "amphibious on water -> 0.6 speed")


func test_resource_cell_slows_movement():
    if _ts == null:
        TestHelper.fail("TerrainSystem not injected")
        return
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    var wheel := Locomotor.new()
    wheel.terrain_speeds = {"clear": 1.0, "resource": 0.5}
    mc._locomotor_data = wheel
    var cell := CellUtil.world_to_cell(Vector3.ZERO, _ts.grid_cells)
    SpatialHash.instance.register_resource_cell(cell)
    var factor: float = mc._terrain_speed_factor()
    SpatialHash.instance.unregister_resource_cell(cell)
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_true(is_equal_approx(factor, 0.5), "wheel on resource cell -> 0.5 speed")


func test_hover_floats_above_terrain():
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    root.add_child(entity)
    entity.global_position = Vector3.ZERO
    mc._is_hover = true
    mc._hover_height = 2.0
    mc._snap_to_terrain()
    var y: float = entity.global_position.y
    root.remove_child(entity)
    entity.free()
    TestHelper.assert_true(y > 1.5, "hover unit floats ~2 units above terrain")


func test_ground_unit_snaps_to_terrain():
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    root.add_child(entity)
    entity.global_position = Vector3(0.0, 5.0, 0.0)
    mc._snap_to_terrain()
    var y: float = entity.global_position.y
    root.remove_child(entity)
    entity.free()
    TestHelper.assert_true(y < 0.5, "ground unit snaps down to terrain")


func test_subterranean_distant_digs():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    var sub := _subterranean()
    sub.subterranean_dig_distance = 1.0
    mc._locomotor_data = sub
    mc._is_subterranean = true
    var target := CellUtil.cell_to_world(Vector2i(54, 50))
    mc.move_to(target)
    var hybrid: bool = mc._hybrid_active
    var waypoints: int = mc._waypoints.size()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(hybrid, true, "distant target triggers digging")
    TestHelper.assert_eq(waypoints, 2, "dig is a single straight segment")


func test_subterranean_nearby_stays_surface():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    mc._locomotor_data = _subterranean()
    mc._is_subterranean = true
    var target := CellUtil.cell_to_world(Vector2i(52, 50))
    mc.move_to(target)
    var hybrid: bool = mc._hybrid_active
    var waypoints: int = mc._waypoints.size()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(hybrid, false, "nearby reachable target stays on surface")
    TestHelper.assert_true(waypoints > 2, "surface path has intermediate waypoints")


func test_hybrid_reset_on_arrival():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    mc._hybrid_active = true
    mc._waypoints = [Vector3.ZERO, Vector3(0.0005, 0.0, 0.0)]
    mc._spline_t = 1.0
    mc._handle_moving_movement(0.016)
    var hybrid: bool = mc._hybrid_active
    var idle: bool = mc.get_state() == MovementController.State.IDLE
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_eq(hybrid, false, "arrival resets hybrid flag")
    TestHelper.assert_true(idle, "arrival reaches IDLE")


func test_slope_probe_uphill():
    if _ts == null:
        TestHelper.fail("TerrainSystem not injected")
        return
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    mc._locomotor_data = _track()
    for v in [Vector2i(51, 50), Vector2i(52, 50), Vector2i(51, 51), Vector2i(52, 51)]:
        _ts._vertex_grid[v.x][v.y] = 3
    mc._waypoints = [Vector3.ZERO, CellUtil.cell_to_world(Vector2i(51, 50))]
    mc._spline_t = 0.0
    var coeff: float = mc._slope_coefficient()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_true(is_equal_approx(coeff, 0.5), "tracked uphill -> 0.5")


func test_slope_probe_downhill():
    if _ts == null:
        TestHelper.fail("TerrainSystem not injected")
        return
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    mc._locomotor_data = _track()
    for v in [Vector2i(50, 50), Vector2i(50, 51)]:
        _ts._vertex_grid[v.x][v.y] = 3
    mc._waypoints = [Vector3.ZERO, CellUtil.cell_to_world(Vector2i(51, 50))]
    mc._spline_t = 0.0
    var coeff: float = mc._slope_coefficient()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_true(is_equal_approx(coeff, 1.1), "tracked downhill -> 1.1")


func test_slope_probe_flat():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    mc._locomotor_data = _track()
    mc._waypoints = [Vector3.ZERO, CellUtil.cell_to_world(Vector2i(51, 50))]
    mc._spline_t = 0.0
    var coeff: float = mc._slope_coefficient()
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_true(is_equal_approx(coeff, 1.0), "flat segment -> no coefficient")


func test_frame_height_memo_matches_direct_read_on_slope():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    # Two unit positions in the same cell on a sloped cell: the memo caches the
    # per-cell corners and bilinear-interpolates at the exact position, so it
    # must be bit-identical to a direct smooth read (no bucket quantization).
    var pos_a := Vector3(0.2, 0.0, 0.2)
    var pos_b := Vector3(0.7, 0.0, 0.6)
    _ts._vertex_grid[50][50] = 3
    _ts._vertex_grid[51][50] = 0
    _ts._vertex_grid[50][51] = 0
    _ts._vertex_grid[51][51] = 3
    _ts.invalidate_height_snapshot()
    var direct_a: float = _ts.get_height_at_world_smooth(pos_a)
    _ts.invalidate_height_snapshot()
    var memo_b: float = mc._memoized_smooth_height(pos_b)
    _ts.invalidate_height_snapshot()
    var direct_b: float = _ts.get_height_at_world_smooth(pos_b)
    _reset_terrain()
    pair[0].queue_free()
    (
        TestHelper
        . assert_eq(
            memo_b,
            direct_b,
            (
                "memo matches the exact smooth read at the position on a slope "
                + "(memo %s vs direct %s)" % [memo_b, direct_b]
            ),
        )
    )
    (
        TestHelper
        . assert_true(
            absf(direct_a - direct_b) > 0.0,
            "slope cell gives distinct heights per position (test is meaningful)",
        )
    )


func test_frame_height_memo_caches_per_cell():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    _ts._vertex_grid[50][50] = 3
    _ts._vertex_grid[51][50] = 0
    _ts._vertex_grid[50][51] = 0
    _ts._vertex_grid[51][51] = 3
    _ts._vertex_grid[60][60] = 2
    _ts._vertex_grid[61][60] = 1
    _ts._vertex_grid[60][61] = 1
    _ts._vertex_grid[61][61] = 2
    _ts.invalidate_height_snapshot()
    var h_a: float = mc._memoized_smooth_height(Vector3(0.2, 0.0, 0.2))
    var h_b: float = mc._memoized_smooth_height(Vector3(0.7, 0.0, 0.6))
    var cache_size: int = mc._frame_heights.size()
    var h_c: float = mc._memoized_smooth_height(Vector3(20.2, 0.0, 20.2))
    var cache_size_grown: int = mc._frame_heights.size()
    var direct_c: float = _ts.get_height_at_world_smooth(Vector3(20.2, 0.0, 20.2))
    _reset_terrain()
    pair[0].queue_free()
    # Same cell, distinct positions: distinct exact heights (no bucket flattening).
    TestHelper.assert_true(
        absf(h_a - h_b) > 0.0, "distinct positions in the same sloped cell get distinct heights"
    )
    # One corner fetch per cell: two reads in the same cell stay a single entry,
    # a read in another cell grows the cache by one.
    TestHelper.assert_eq(cache_size, 1, "two reads in the same cell share one cached corner array")
    TestHelper.assert_eq(
        cache_size_grown, cache_size + 1, "a read in a new cell adds one corner array"
    )
    (
        TestHelper
        . assert_eq(
            h_c,
            direct_c,
            "cached cell read matches the exact smooth height at that position",
        )
    )


func test_baked_spline_matches_spline_util():
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    var waypoints := PackedVector3Array(
        [
            Vector3(0, 0, 0),
            Vector3(4, 0, 2),
            Vector3(8, 0, 5),
            Vector3(12, 0, 3),
        ]
    )
    mc._waypoints = waypoints
    mc._bake_spline()
    for t: float in [0.0, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0]:
        var baked_pos: Vector3 = mc._get_spline_pos(t)
        var direct_pos: Vector3 = SplineUtil.evaluate(waypoints, t)
        TestHelper.assert_eq(
            baked_pos, direct_pos, "baked position matches SplineUtil at t=%s" % [t]
        )
        var baked_tangent: Vector3 = mc._get_spline_tangent(t)
        var direct_tangent: Vector3 = SplineUtil.tangent(waypoints, t)
        TestHelper.assert_eq(
            baked_tangent, direct_tangent, "baked tangent matches SplineUtil at t=%s" % [t]
        )
    var seg_len_0: float = mc._segment_length(0)
    TestHelper.assert_eq(
        seg_len_0, waypoints[0].distance_to(waypoints[1]), "baked seg length matches"
    )
    _reset_terrain()
    pair[0].queue_free()


func test_memoized_height_follows_bridge_deck():
    if _ts == null or _sh == null:
        TestHelper.fail("autoloads not injected")
        return
    _reset_terrain()
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var mc: MovementController = pair[1]
    var cell := Vector2i(50, 50)
    var deck: float = 4.0 * _ts.HEIGHT_STEP
    _sh._bridge_cells[CellUtil.cell_level_key(cell, 1)] = {
        "surface_height": deck,
        "is_end": false,
        "piece_id": "piece_test",
        "level": 1,
    }
    # Ground level ignores the deck above; deck level samples it.
    mc._surface_level = 0
    var ground_y: float = mc._memoized_smooth_height(CellUtil.cell_to_world(cell))
    mc._surface_level = 1
    var deck_y: float = mc._memoized_smooth_height(CellUtil.cell_to_world(cell))
    _sh._bridge_cells.erase(CellUtil.cell_level_key(cell, 1))
    _reset_terrain()
    pair[0].queue_free()
    TestHelper.assert_true(
        is_equal_approx(ground_y, 0.0), "(_surface_level 0 ignores the deck, got %s)" % ground_y
    )
    TestHelper.assert_true(
        is_equal_approx(deck_y, deck), "(_surface_level 1 follows the deck, got %s)" % deck_y
    )


func test_mover_y_on_deck_and_under_deck():
    if _ts == null or _sh == null:
        TestHelper.fail("autoloads not injected")
        return
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var cell := Vector2i(50, 50)
    _ts._vertex_grid[50][50] = 1
    _ts._vertex_grid[51][50] = 1
    _ts._vertex_grid[50][51] = 1
    _ts._vertex_grid[51][51] = 1
    _ts.invalidate_height_snapshot()
    var ground_height: float = 1.0 * _ts.HEIGHT_STEP
    var deck: float = ground_height + 4.0 * _ts.HEIGHT_STEP
    _sh._bridge_cells[CellUtil.cell_level_key(cell, 1)] = {
        "surface_height": deck,
        "is_end": false,
        "piece_id": "piece_test",
        "level": 1,
    }
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    root.add_child(entity)
    entity.global_position = CellUtil.cell_to_world(cell)
    # Ground mover under the deck snaps to the ground surface.
    mc._surface_level = 0
    for _i in 5:
        mc._snap_to_terrain()
    var under_y: float = entity.global_position.y
    # Deck mover snaps to the deck surface.
    mc._surface_level = 1
    for _i in 5:
        mc._snap_to_terrain()
    var on_y: float = entity.global_position.y
    _sh._bridge_cells.erase(CellUtil.cell_level_key(cell, 1))
    root.remove_child(entity)
    entity.free()
    _reset_terrain()
    TestHelper.assert_true(
        is_equal_approx(under_y, ground_height), "under-deck mover Y is the ground surface"
    )
    TestHelper.assert_true(is_equal_approx(on_y, deck), "on-deck mover Y is the deck surface")


## GAP B: an idle unit placed on a deck at deck height keeps that surface — the
## idle snap resolves the level from the unit's own Y instead of defaulting to 0.
func test_idle_deck_unit_keeps_deck_height():
    if _ts == null or _sh == null:
        TestHelper.fail("autoloads not injected")
        return
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var cell := Vector2i(50, 50)
    _ts._vertex_grid[50][50] = 1
    _ts._vertex_grid[51][50] = 1
    _ts._vertex_grid[50][51] = 1
    _ts._vertex_grid[51][51] = 1
    _ts.invalidate_height_snapshot()
    var ground_height: float = 1.0 * _ts.HEIGHT_STEP
    var deck: float = ground_height + 4.0 * _ts.HEIGHT_STEP
    _sh._bridge_cells[CellUtil.cell_level_key(cell, 1)] = {
        "surface_height": deck,
        "is_end": false,
        "piece_id": "piece_test",
        "level": 1,
    }
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    mc._locomotor_data = _wheel()
    root.add_child(entity)
    entity.global_position = CellUtil.cell_to_world(cell)
    entity.global_position.y = deck
    # Non-vacuity control: with the resolver bypassed (stale level 0) the idle
    # memo samples the ground beneath the deck — the bug this fix removes.
    mc._surface_level = 0
    var without_resolver: float = mc._memoized_smooth_height(entity.global_position)
    (
        TestHelper
        . assert_true(
            is_equal_approx(without_resolver, ground_height),
            "control: stale level 0 samples the ground beneath the deck",
        )
    )
    mc._idle_snapped = false
    mc._physics_process(1.0 / 60.0)
    var resolved_level: int = mc.get_surface_level()
    var stayed_y: float = entity.global_position.y
    _sh._bridge_cells.erase(CellUtil.cell_level_key(cell, 1))
    root.remove_child(entity)
    entity.free()
    _reset_terrain()
    TestHelper.assert_eq(resolved_level, 1, "idle unit on a deck resolves to the deck level")
    (
        TestHelper
        . assert_true(
            is_equal_approx(stayed_y, deck),
            "idle unit on a deck stays at deck height (got %s)" % stayed_y,
        )
    )


## GAP B: an idle unit placed at ground height under a deck resolves to level 0
## and stays on the ground, not snapping up to the deck.
func test_idle_ground_unit_under_deck_stays_on_ground():
    if _ts == null or _sh == null:
        TestHelper.fail("autoloads not injected")
        return
    _reset_terrain()
    var root: Node = Engine.get_main_loop().root
    var cell := Vector2i(50, 50)
    _ts._vertex_grid[50][50] = 1
    _ts._vertex_grid[51][50] = 1
    _ts._vertex_grid[50][51] = 1
    _ts._vertex_grid[51][51] = 1
    _ts.invalidate_height_snapshot()
    var ground_height: float = 1.0 * _ts.HEIGHT_STEP
    var deck: float = ground_height + 4.0 * _ts.HEIGHT_STEP
    _sh._bridge_cells[CellUtil.cell_level_key(cell, 1)] = {
        "surface_height": deck,
        "is_end": false,
        "piece_id": "piece_test",
        "level": 1,
    }
    var pair: Array = _make_mc(EntityData.EntityType.VEHICLE)
    var entity: Node3D = pair[0]
    var mc: MovementController = pair[1]
    mc._locomotor_data = _wheel()
    root.add_child(entity)
    entity.global_position = CellUtil.cell_to_world(cell)
    entity.global_position.y = ground_height
    # Non-vacuity control: a stale level 1 would sample the deck above.
    mc._surface_level = 1
    var without_resolver: float = mc._memoized_smooth_height(entity.global_position)
    (
        TestHelper
        . assert_true(
            is_equal_approx(without_resolver, deck),
            "control: stale level 1 samples the deck above the ground",
        )
    )
    mc._idle_snapped = false
    mc._physics_process(1.0 / 60.0)
    var resolved_level: int = mc.get_surface_level()
    var stayed_y: float = entity.global_position.y
    _sh._bridge_cells.erase(CellUtil.cell_level_key(cell, 1))
    root.remove_child(entity)
    entity.free()
    _reset_terrain()
    TestHelper.assert_eq(resolved_level, 0, "idle unit at ground height resolves to level 0")
    (
        TestHelper
        . assert_true(
            is_equal_approx(stayed_y, ground_height),
            "idle unit under a deck stays at ground height (got %s)" % stayed_y,
        )
    )
