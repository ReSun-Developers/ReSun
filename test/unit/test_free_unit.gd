extends Node

# FreeUnitComponent adjacent free-cell search — routes through the shared build
# intent plus the reservation fact (no direct SpatialHash._reserved read).

const ORIGIN: Vector2i = Vector2i(55, 55)


func _setup() -> void:
    var sh := SpatialHash.instance
    sh._building_cells.clear()
    sh._bib_cells.clear()
    sh._resource_cells.clear()
    sh.clear_reservations()
    sh.rebuild()
    TerrainSystem.init_grid(64, 64)
    TerrainSystem.clear()
    TerrainSystem.set_cell_type(ORIGIN, "clear")


func _find() -> Vector2i:
    var comp := FreeUnitComponent.new()
    var found: Vector2i = comp._find_adjacent_free_cell(ORIGIN, Vector2i(1, 1))
    comp.free()
    return found


func test_free_cell_found_when_clear():
    _setup()
    var found := _find()
    TestHelper.assert_true(
        TerrainSystem.get_cell_type(ORIGIN) == "clear", "fixture: origin seeded clear"
    )
    TestHelper.assert_true(found == ORIGIN, "clear origin returned as the free cell")


func test_edge_origin_never_returns_out_of_bounds():
    _setup()
    var edge := Vector2i(63, 63)
    SpatialHash.instance.register_building_cells([edge])
    var comp := FreeUnitComponent.new()
    var found: Vector2i = comp._find_adjacent_free_cell(edge, Vector2i(1, 1))
    comp.free()
    SpatialHash.instance.unregister_building_cells([edge])
    (
        TestHelper
        . assert_true(
            SpatialHash.instance.is_cell_free_for_build(found),
            "edge-origin search returns an in-bounds buildable cell",
        )
    )


func test_skips_bib_cell():
    _setup()
    SpatialHash.instance.register_bib_cells([ORIGIN])
    var found := _find()
    SpatialHash.instance.unregister_bib_cells([ORIGIN])
    TestHelper.assert_true(found != ORIGIN, "free-unit search skips a bib cell")
    TestHelper.assert_true(
        SpatialHash.instance.is_cell_free_for_build(found), "found cell is buildable"
    )


func test_skips_resource_cell():
    _setup()
    SpatialHash.instance.register_resource_cell(ORIGIN)
    var found := _find()
    SpatialHash.instance.unregister_resource_cell(ORIGIN)
    TestHelper.assert_true(found != ORIGIN, "free-unit search skips a resource cell")


func test_skips_reserved_cell():
    _setup()
    SpatialHash.instance.force_reserve(ORIGIN)
    var found := _find()
    SpatialHash.instance.clear_reservations()
    TestHelper.assert_true(found != ORIGIN, "free-unit search skips a reserved cell")
