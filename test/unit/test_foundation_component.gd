extends Node

# FoundationComponent tests — canonical footprint queries

var _test_passed := 0
var _test_failed := 0


func _ok(cond: bool, name: String) -> void:
    # Report through TestHelper so the runner actually counts these assertions;
    # the local counters/prints are only for readable per-test output.
    TestHelper.assert_true(cond, name)
    if cond:
        _test_passed += 1
        print("    PASS: " + name)
    else:
        _test_failed += 1
        print("    FAIL: " + name)


func _setup_clear(origin: Vector2i, size: Vector2i) -> void:
    TerrainSystem.init_grid(64, 64)
    for dx in size.x:
        for dz in size.y:
            TerrainSystem.set_cell_type(origin + Vector2i(dx, dz), "clear")


func test_occupied_cells_excludes_bib():
    var fc := FoundationComponent.new()
    fc.foundation = Vector2i(2, 2)
    fc.bib_cells = [Vector2i(0, 1)]
    var origin := Vector2i(3, 3)
    var occ := fc.get_occupied_cells(origin)
    fc.free()
    _ok(occ.size() == 3 and not occ.has(Vector2i(3, 4)), "get_occupied_cells excludes bib cell")


func test_occupied_cells_equals_foundation_without_bib():
    var fc := FoundationComponent.new()
    fc.foundation = Vector2i(2, 2)
    var occ := fc.get_occupied_cells(Vector2i(0, 0))
    var found := fc.get_foundation_cells(Vector2i(0, 0))
    fc.free()
    _ok(occ.size() == 4 and found.size() == 4, "occupied == foundation when no bib")


func test_is_cell_buildable_free_clear():
    SpatialHash.instance._building_cells.clear()
    SpatialHash.instance._blocked_cells.clear()
    _setup_clear(Vector2i(5, 5), Vector2i(1, 1))
    _ok(
        TerrainSystem.get_cell_type(Vector2i(5, 5)) == "clear",
        "fixture seeded a clear cell at (5,5)"
    )
    _ok(
        FoundationComponent.is_cell_buildable(Vector2i(5, 5)),
        "is_cell_buildable true on free clear"
    )


func test_is_cell_buildable_building_cell():
    SpatialHash.instance._building_cells.clear()
    _setup_clear(Vector2i(5, 5), Vector2i(1, 1))
    SpatialHash.instance.register_building_cells([Vector2i(5, 5)])
    var result := FoundationComponent.is_cell_buildable(Vector2i(5, 5))
    SpatialHash.instance._building_cells.clear()
    _ok(not result, "is_cell_buildable false on building cell")


func test_is_buildable_true_on_flat_free():
    SpatialHash.instance._building_cells.clear()
    SpatialHash.instance._blocked_cells.clear()
    _setup_clear(Vector2i(10, 10), Vector2i(2, 2))
    var fc := FoundationComponent.new()
    fc.foundation = Vector2i(2, 2)
    var result := fc.is_buildable(Vector2i(10, 10))
    fc.free()
    _ok(result, "is_buildable true on flat free footprint")


func test_is_buildable_false_when_occupied():
    SpatialHash.instance._building_cells.clear()
    _setup_clear(Vector2i(10, 10), Vector2i(2, 2))
    SpatialHash.instance.register_building_cells([Vector2i(11, 11)])
    var fc := FoundationComponent.new()
    fc.foundation = Vector2i(2, 2)
    var result := fc.is_buildable(Vector2i(10, 10))
    SpatialHash.instance._building_cells.clear()
    fc.free()
    _ok(not result, "is_buildable false when a footprint cell is occupied")


func test_is_buildable_false_on_steep_height():
    SpatialHash.instance._building_cells.clear()
    SpatialHash.instance._blocked_cells.clear()
    _setup_clear(Vector2i(20, 20), Vector2i(2, 2))
    # Raise a corner vertex of the (20,20) cell so the footprint's height delta
    # exceeds HEIGHT_STEP. Vertices span the cell, so cell (20,20) is raised.
    TerrainSystem.set_vertex(20, 20, 3)
    var fc := FoundationComponent.new()
    fc.foundation = Vector2i(2, 2)
    var result := fc.is_buildable(Vector2i(20, 20))
    TerrainSystem.init_grid(64, 64)
    fc.free()
    _ok(not result, "is_buildable false when height delta too steep")


# --- nearest_world_point: axis-aligned footprint rectangle, per-axis clamp ---
# Expected points are derived from the rectangle geometry, not the production
# formula: footprint half-extents are foundation * CELL_SIZE / 2 world units.


func _make_foundation(foundation: Vector2i, at: Vector3) -> FoundationComponent:
    var entity := Node3D.new()
    var fc := FoundationComponent.new()
    fc.foundation = foundation
    entity.add_child(fc)
    # global_position only resolves inside the tree.
    Engine.get_main_loop().root.add_child(entity)
    entity.global_position = at
    return fc


func _drop(fc: FoundationComponent) -> void:
    var entity := fc.get_parent()
    Engine.get_main_loop().root.remove_child(entity)
    entity.free()


func _near(a: Vector3, b: Vector3) -> bool:
    return absf(a.x - b.x) < 0.001 and absf(a.y - b.y) < 0.001 and absf(a.z - b.z) < 0.001


func test_nearest_world_point_outside_face():
    # 4x4 at origin -> rect x,z in [-4,4]. Attacker 10 east, 2 north of center.
    var fc := _make_foundation(Vector2i(4, 4), Vector3.ZERO)
    var got: Vector3 = fc.nearest_world_point(Vector3(10.0, 0.0, 2.0))
    TestHelper.assert_true(
        _near(got, Vector3(4.0, 0.0, 2.0)),
        "nearest point clamps x to the near face, keeps lateral z (got %s)" % got
    )
    _drop(fc)


func test_nearest_world_point_outside_corner():
    # Diagonally beyond the +x/+z corner -> the corner itself.
    var fc := _make_foundation(Vector2i(4, 4), Vector3.ZERO)
    var got: Vector3 = fc.nearest_world_point(Vector3(10.0, 0.0, 10.0))
    TestHelper.assert_true(
        _near(got, Vector3(4.0, 0.0, 4.0)), "nearest point clamps to the corner (got %s)" % got
    )
    _drop(fc)


func test_nearest_world_point_inside_returns_self():
    var fc := _make_foundation(Vector2i(4, 4), Vector3.ZERO)
    var inside := Vector3(1.0, 0.0, -2.0)
    var got: Vector3 = fc.nearest_world_point(inside)
    TestHelper.assert_true(
        _near(got, inside), "point inside the footprint is unchanged (got %s)" % got
    )
    _drop(fc)


func test_nearest_world_point_single_cell():
    # 1x1 at origin -> rect x,z in [-1,1].
    var fc := _make_foundation(Vector2i(1, 1), Vector3.ZERO)
    var got: Vector3 = fc.nearest_world_point(Vector3(5.0, 0.0, 0.0))
    TestHelper.assert_true(
        _near(got, Vector3(1.0, 0.0, 0.0)), "1x1 footprint clamps to the near edge (got %s)" % got
    )
    _drop(fc)


func test_nearest_world_point_uses_entity_y():
    var fc := _make_foundation(Vector2i(2, 2), Vector3(3.0, 7.0, -3.0))
    var got: Vector3 = fc.nearest_world_point(Vector3(50.0, 0.0, -3.0))
    TestHelper.assert_true(
        is_equal_approx(got.y, 7.0), "returned point takes Y from the entity (got %s)" % got
    )
    _drop(fc)
