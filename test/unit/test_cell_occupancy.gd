extends Node

# Cell occupancy composite query tests — SpatialHash.get_cell_occupancy and the
# build / unit-exit / resource intent projections. Seeding uses public registrars
# and real spawned entities + rebuild; teardown unregisters and frees so nothing
# leaks between suites (the runner shares one process).

var _spawned: Array[Node3D] = []
var _registered_building: Array[Vector2i] = []
var _registered_bib: Array[Vector2i] = []
var _registered_resource: Array[Vector2i] = []

const CELL: Vector2i = Vector2i(30, 30)


func _teardown() -> void:
    var sh := SpatialHash.instance
    for e in _spawned:
        if is_instance_valid(e):
            if e.get_parent() != null:
                e.get_parent().remove_child(e)
            e.free()
    _spawned.clear()
    if sh:
        if not _registered_building.is_empty():
            sh.unregister_building_cells(_registered_building)
        if not _registered_bib.is_empty():
            sh.unregister_bib_cells(_registered_bib)
        for c in _registered_resource:
            sh.unregister_resource_cell(c)
        sh.clear_reservations()
        sh.rebuild()
    _registered_building.clear()
    _registered_bib.clear()
    _registered_resource.clear()
    TerrainSystem.init_grid(64, 64)
    TerrainSystem.clear()


func _setup() -> void:
    _teardown()
    TerrainSystem.init_grid(64, 64)
    TerrainSystem.set_cell_type(CELL, "clear")


func _make_unit(shares: bool, state: int) -> Node3D:
    var entity := Node3D.new()
    entity.name = "Occupant"
    entity.global_position = CellUtil.cell_to_world(CELL)
    entity.add_to_group("entities")
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.entity_type = EntityData.EntityType.INFANTRY
    stats.player_id = 0
    entity.add_child(stats)
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    mc._shares_cell = shares
    mc._state = state
    SpatialHash.instance.add_child(entity)
    _spawned.append(entity)
    return entity


func test_empty_clear_cell_is_free():
    _setup()
    var sh := SpatialHash.instance
    (
        TestHelper
        . assert_true(
            TerrainSystem.get_cell_type(CELL) == "clear",
            "empty clear fixture: seeded type not observed",
        )
    )
    var occ := sh.get_cell_occupancy(CELL)
    TestHelper.assert_true(occ.terrain_buildable, "empty clear cell: terrain_buildable")
    (
        TestHelper
        . assert_true(
            not occ.building and not occ.bib and not occ.resource,
            "empty clear cell: no permanent occupancy",
        )
    )
    (
        TestHelper
        . assert_true(
            occ.units.is_empty() and not occ.blocked and not occ.moving and occ.shared_count == 0,
            "empty clear cell: no momentary occupancy",
        )
    )
    TestHelper.assert_true(sh.is_cell_free_for_build(CELL), "empty clear cell: build free")
    TestHelper.assert_true(sh.is_cell_free_for_unit_exit(CELL), "empty clear cell: exit free")
    TestHelper.assert_true(sh.is_cell_free_for_resource(CELL), "empty clear cell: resource free")
    _teardown()


func test_permanent_facts():
    _setup()
    var sh := SpatialHash.instance
    var b := Vector2i(31, 30)
    sh.register_building_cells([b])
    _registered_building.append(b)
    var bib := Vector2i(32, 30)
    sh.register_bib_cells([bib])
    _registered_bib.append(bib)
    var res := Vector2i(33, 30)
    sh.register_resource_cell(res)
    _registered_resource.append(res)
    TestHelper.assert_true(sh.get_cell_occupancy(b).building, "building fact set")
    TestHelper.assert_true(sh.get_cell_occupancy(bib).bib, "bib fact set")
    TestHelper.assert_true(sh.get_cell_occupancy(res).resource, "resource fact set")
    TestHelper.assert_true(sh.get_cell_occupancy(b).units.is_empty(), "building not in units")
    TestHelper.assert_true(not sh.is_cell_free_for_build(b), "build refused on building cell")
    TestHelper.assert_true(not sh.is_cell_free_for_build(res), "build refused on resource cell")
    TestHelper.assert_true(not sh.is_cell_free_for_unit_exit(b), "exit refused on building cell")
    TestHelper.assert_true(sh.is_cell_free_for_unit_exit(res), "exit allowed on resource cell")
    TestHelper.assert_true(not sh.is_cell_free_for_resource(b), "resource refused on building cell")
    TestHelper.assert_true(not sh.is_cell_free_for_resource(bib), "resource refused on bib cell")
    _teardown()


func test_terrain_gate_and_bounds():
    _setup()
    var sh := SpatialHash.instance
    var slope := Vector2i(34, 30)
    TerrainSystem.set_cell_type(slope, "slope")
    TestHelper.assert_true(
        TerrainSystem.get_cell_type(slope) == "slope", "slope fixture: seeded type not observed"
    )
    TestHelper.assert_true(not sh.is_cell_free_for_build(slope), "build refused on slope")
    TestHelper.assert_true(not sh.is_cell_free_for_resource(slope), "resource refused on slope")
    # Slopes are walkable: the exit test is a movement test, not buildability.
    TestHelper.assert_true(
        sh.is_cell_free_for_unit_exit(slope), "exit allows walkable slope terrain"
    )
    var oob := Vector2i(999, 999)
    TestHelper.assert_true(not sh.is_cell_free_for_build(oob), "build refused out of bounds")
    TestHelper.assert_true(not sh.is_cell_free_for_resource(oob), "resource refused out of bounds")
    _teardown()


func test_build_refuses_any_unit():
    _setup()
    var sh := SpatialHash.instance
    _make_unit(false, MovementController.State.IDLE)
    sh.rebuild()
    var occ := sh.get_cell_occupancy(CELL)
    TestHelper.assert_true(occ.units.size() == 1, "idle non-sharer appears in units")
    TestHelper.assert_true(occ.blocked and not occ.moving, "idle non-sharer is blocked, not moving")
    TestHelper.assert_true(
        not sh.is_cell_free_for_build(CELL), "build refused with idle non-sharer"
    )
    _teardown()


func test_exit_allows_idle_sharer_below_capacity():
    _setup()
    var sh := SpatialHash.instance
    _make_unit(true, MovementController.State.IDLE)
    sh.rebuild()
    var occ := sh.get_cell_occupancy(CELL)
    (
        TestHelper
        . assert_true(
            occ.shared_count >= 1 and not occ.blocked and not occ.moving,
            "idle sharer counted, not blocked or moving",
        )
    )
    (
        TestHelper
        . assert_true(
            sh.is_cell_free_for_unit_exit(CELL),
            "exit allows an idle sharer below capacity (non-vacuous shared-exit case)",
        )
    )
    TestHelper.assert_true(not sh.is_cell_free_for_build(CELL), "build still refuses idle sharer")
    _teardown()


func test_exit_refuses_at_capacity():
    _setup()
    var sh := SpatialHash.instance
    var cap: int = CellSubPositions.get_slot_count()
    for i in cap:
        _make_unit(true, MovementController.State.IDLE)
    sh.rebuild()
    var occ := sh.get_cell_occupancy(CELL)
    TestHelper.assert_true(occ.shared_count == cap, "capacity sharers counted")
    TestHelper.assert_true(not sh.is_cell_free_for_unit_exit(CELL), "exit refused at capacity")
    _teardown()


func test_exit_refuses_moving_unit():
    _setup()
    var sh := SpatialHash.instance
    _make_unit(false, MovementController.State.MOVING)
    sh.rebuild()
    var occ := sh.get_cell_occupancy(CELL)
    TestHelper.assert_true(occ.moving, "moving unit flagged")
    TestHelper.assert_true(not sh.is_cell_free_for_unit_exit(CELL), "exit refused with moving unit")
    _teardown()


func test_exit_refuses_idle_non_sharer():
    _setup()
    var sh := SpatialHash.instance
    _make_unit(false, MovementController.State.IDLE)
    sh.rebuild()
    TestHelper.assert_true(
        not sh.is_cell_free_for_unit_exit(CELL), "exit refused with an idle non-sharer"
    )
    _teardown()


func test_level_scoping():
    _setup()
    var sh := SpatialHash.instance
    var e := _make_unit(false, MovementController.State.IDLE)
    var mc := e.get_node("MovementController") as MovementController
    mc._surface_level = 1
    sh.rebuild()
    var l0 := sh.get_cell_occupancy(CELL, 0)
    var l1 := sh.get_cell_occupancy(CELL, 1)
    TestHelper.assert_true(l0.units.is_empty(), "level 0 is empty for a level-1 occupant")
    TestHelper.assert_true(l1.units.size() == 1, "level 1 sees the deck occupant")
    (
        TestHelper
        . assert_true(
            not l1.building and not l1.terrain_buildable,
            "permanent facts are not reported above ground level",
        )
    )
    _teardown()


func test_resource_ignores_units():
    _setup()
    var sh := SpatialHash.instance
    _make_unit(false, MovementController.State.IDLE)
    sh.rebuild()
    TestHelper.assert_true(sh.is_cell_free_for_resource(CELL), "resource intent ignores units")
    _teardown()


func test_exclusion_allows_own_cell_but_not_others():
    _setup()
    var sh := SpatialHash.instance
    var a := _make_unit(false, MovementController.State.IDLE)
    sh.rebuild()
    TestHelper.assert_true(not sh.is_cell_free_for_build(CELL), "occupied before exclusion")
    TestHelper.assert_true(sh.is_cell_free_for_build(CELL, 0, a), "own cell free when excluded")
    _make_unit(false, MovementController.State.IDLE)
    sh.rebuild()
    TestHelper.assert_true(not sh.is_cell_free_for_build(CELL, 0, a), "second unit not excluded")
    _teardown()


func test_reserved_fact_survives_exclusion():
    _setup()
    var sh := SpatialHash.instance
    sh.force_reserve(CELL)
    var dummy := Node3D.new()
    var occ := sh.get_cell_occupancy(CELL, 0, dummy)
    TestHelper.assert_true(occ.reserved, "reservation fact set and survives exclusion")
    dummy.free()
    _teardown()
