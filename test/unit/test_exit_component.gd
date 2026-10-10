extends Node

# ExitComponent tests — positioning, facing, signal emission, free cell search

var _unit_spawned_received := false
var _spawned_unit: Node3D = null


func _make_exit(
    exit_off: Vector3 = Vector3(0, 0, 2),
    spawn_off: Vector3 = Vector3(0, 0, 0),
    facing: int = 90,
    delay: float = 0.0
) -> ExitComponent:
    var exit := ExitComponent.new()
    exit.name = "ExitComponent"
    exit.exit_offset = exit_off
    exit.spawn_offset = spawn_off
    exit.exit_facing = facing
    exit.exit_delay = delay
    return exit


func _on_unit_spawned(unit: Node3D) -> void:
    _unit_spawned_received = true
    _spawned_unit = unit


# --- Basic tests ---


func test_exit_offset():
    var exit := _make_exit(Vector3(0, 0, 3))
    TestHelper.assert_true(
        exit.exit_offset == Vector3(0, 0, 3), "exit_offset set correctly: exit_offset not set"
    )


func test_spawn_offset():
    var exit := _make_exit(Vector3(0, 0, 2), Vector3(1, 0, 0))
    TestHelper.assert_true(
        exit.spawn_offset == Vector3(1, 0, 0), "spawn_offset set correctly: spawn_offset not set"
    )


func test_exit_facing():
    var exit := _make_exit(Vector3(0, 0, 2), Vector3.ZERO, 180)
    TestHelper.assert_true(
        exit.exit_facing == 180, "exit_facing set correctly: exit_facing not set"
    )


func test_exit_delay():
    var exit := _make_exit(Vector3.ZERO, Vector3.ZERO, 0, 1.5)
    TestHelper.assert_true(exit.exit_delay == 1.5, "exit_delay set correctly: exit_delay not set")


func test_signal_emitted():
    var exit := _make_exit()
    exit.unit_spawned.connect(_on_unit_spawned)

    var unit := Node3D.new()
    unit.name = "TestUnit"
    add_child(unit)

    var building := Node3D.new()
    building.name = "TestBuilding"
    building.global_position = Vector3(0, 0, 0)
    add_child(building)
    building.add_child(exit)

    _unit_spawned_received = false
    _spawned_unit = null

    exit.on_unit_produced(unit)

    (
        TestHelper
        . assert_true(
            _unit_spawned_received and _spawned_unit == unit,
            "unit_spawned signal emitted correctly: unit_spawned signal not emitted",
        )
    )

    building.remove_child(exit)
    remove_child(building)
    remove_child(unit)


func test_configure_from_entity_data():
    var exit := _make_exit()
    var data := EntityData.new()
    data.spawn_offset = Vector3(2, 0, 0)
    data.exit_offset = Vector3(0, 0, 4)
    data.exit_facing = 270
    data.exit_delay = 2.0
    exit.configure(data)
    (
        TestHelper
        . assert_true(
            (
                exit.spawn_offset == Vector3(2, 0, 0)
                and exit.exit_offset == Vector3(0, 0, 4)
                and exit.exit_facing == 270
                and exit.exit_delay == 2.0
            ),
            "configure() copies fields from EntityData: configure() did not copy fields",
        )
    )


# --- Free cell tests ---


func test_is_cell_available_clear():
    _reset_nudge_fixture()
    var exit := _make_exit()
    add_child(exit)
    # An in-bounds clear cell with no occupant should be available. (An
    # out-of-bounds cell is NOT buildable terrain and must be refused.)
    var cell := Vector2i(30, 30)
    TerrainSystem.set_cell_type(cell, "clear")
    (
        TestHelper
        . assert_true(
            TerrainSystem.get_cell_type(cell) == "clear",
            "test_is_cell_available_clear fixture: seeded type not observed",
        )
    )
    (
        TestHelper
        . assert_true(
            exit._is_cell_available(cell),
            (
                "_is_cell_available returns true for clear cell: "
                + "_is_cell_available returned false for clear cell"
            ),
        )
    )
    remove_child(exit)


func test_find_free_near_returns_input_when_available():
    _reset_nudge_fixture()
    var exit := _make_exit()
    add_child(exit)
    var cell := Vector2i(30, 30)
    TerrainSystem.set_cell_type(cell, "clear")
    TestHelper.assert_true(
        TerrainSystem.get_cell_type(cell) == "clear", "fixture: seeded clear type not observed"
    )
    var result: Vector2i = exit._find_free_near(cell)
    (
        TestHelper
        . assert_true(
            result == cell,
            (
                "_find_free_near returns input when cell is available: "
                + "_find_free_near changed an available cell"
            ),
        )
    )
    remove_child(exit)


# --- Nudge ownership (#164) ---
# An exit may only nudge its own/allied idle blockers off the exit cell;
# opponents' units must never be moved by another player's production exit.

const _NUDGE_OWNER_CELL := Vector2i(20, 20)
const _NUDGE_BLOCK_CELL := Vector2i(21, 20)


func _reset_nudge_fixture() -> void:
    var sh := SpatialHash.instance
    if sh:
        sh._grid.clear()
        sh._blocked_cells.clear()
        sh._building_cells.clear()
        sh._shared_cell_counts.clear()
        sh.clear_reservations()
    if CellReservation.instance:
        CellReservation.instance.clear()
    TerrainSystem.init_grid(64, 64)
    TerrainSystem.clear()
    PlayerManager.get_player_data(0).team_id = 1
    PlayerManager.get_player_data(1).team_id = 2


func _make_nudge_building(player: int) -> Node3D:
    var building := Node3D.new()
    building.name = "NudgeBuilding"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player
    building.add_child(stats)
    building.add_child(_make_exit())
    add_child(building)
    building.global_position = CellUtil.cell_to_world(_NUDGE_OWNER_CELL)
    return building


func _make_nudge_blocker(player: int, cell: Vector2i) -> Array:
    var entity := Node3D.new()
    entity.name = "NudgeBlocker"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player
    entity.add_child(stats)
    var mc := MovementController.new()
    entity.add_child(mc)
    mc._parent = entity
    add_child(entity)
    entity.global_position = CellUtil.cell_to_world(cell)
    var key := CellUtil.cell_key(cell)
    SpatialHash.instance._grid[key] = [
        {
            "node": entity,
            "mc": mc,
            "state": MovementController.State.IDLE,
            "shares": false,
            "level": 0,
        }
    ]
    SpatialHash.instance._blocked_cells[key] = true
    return [entity, mc]


func _cleanup_nudge(building: Node3D, blocker: Array) -> void:
    SpatialHash.instance._grid.clear()
    SpatialHash.instance._blocked_cells.clear()
    SpatialHash.instance.clear_reservations()
    remove_child(building)
    building.free()
    remove_child(blocker[0] as Node)
    (blocker[0] as Node).free()


func test_nudge_blocker_moves_own_unit():
    _reset_nudge_fixture()
    var building := _make_nudge_building(0)
    var blocker := _make_nudge_blocker(0, _NUDGE_BLOCK_CELL)
    var mc: MovementController = blocker[1]
    TestHelper.assert_true(not PlayerManager.is_enemy(0, 0), "precondition: self is not an enemy")
    var exit := building.get_node("ExitComponent") as ExitComponent
    exit._nudge_blocker(_NUDGE_BLOCK_CELL)
    var moved: bool = mc._waypoints.size() > 0
    _cleanup_nudge(building, blocker)
    TestHelper.assert_true(moved, "exit nudge still moves a same-player idle blocker")


func test_nudge_blocker_moves_allied_unit():
    _reset_nudge_fixture()
    PlayerManager.get_player_data(1).team_id = 1
    var building := _make_nudge_building(0)
    var blocker := _make_nudge_blocker(1, _NUDGE_BLOCK_CELL)
    var mc: MovementController = blocker[1]
    TestHelper.assert_true(not PlayerManager.is_enemy(0, 1), "precondition: allies are not enemies")
    var exit := building.get_node("ExitComponent") as ExitComponent
    exit._nudge_blocker(_NUDGE_BLOCK_CELL)
    var moved: bool = mc._waypoints.size() > 0
    _cleanup_nudge(building, blocker)
    TestHelper.assert_true(moved, "exit nudge still moves an allied idle blocker")


func test_nudge_blocker_leaves_enemy_unit():
    _reset_nudge_fixture()
    var building := _make_nudge_building(0)
    var blocker := _make_nudge_blocker(1, _NUDGE_BLOCK_CELL)
    var mc: MovementController = blocker[1]
    TestHelper.assert_true(
        PlayerManager.is_enemy(0, 1), "precondition: players 0 and 1 are enemies"
    )
    var exit := building.get_node("ExitComponent") as ExitComponent
    exit._nudge_blocker(_NUDGE_BLOCK_CELL)
    var untouched: bool = mc._state == MovementController.State.IDLE and mc._waypoints.is_empty()
    _cleanup_nudge(building, blocker)
    TestHelper.assert_true(untouched, "exit nudge must not move an enemy blocker")


# --- Shared exit-intent tests ---
# The exit predicate now routes through SpatialHash.is_cell_free_for_unit_exit:
# a moving unit and an idle non-sharer refuse a cell; idle sharers below capacity
# and tiberium cells are accepted; non-buildable terrain is refused.


func _make_exit_occupant(cell: Vector2i, shares: bool, state: int) -> Node3D:
    var entity := Node3D.new()
    entity.name = "ExitOccupant"
    entity.global_position = CellUtil.cell_to_world(cell)
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
    return entity


func test_exit_cell_refuses_moving_unit():
    _reset_nudge_fixture()
    var exit := _make_exit()
    add_child(exit)
    var cell := Vector2i(30, 30)
    var unit := _make_exit_occupant(cell, false, MovementController.State.MOVING)
    SpatialHash.instance.rebuild()
    var refused: bool = not exit._is_cell_available(cell)
    SpatialHash.instance.remove_child(unit)
    unit.free()
    remove_child(exit)
    TestHelper.assert_true(refused, "exit cell refused with a moving unit")


func test_exit_cell_allows_idle_sharer_below_capacity():
    _reset_nudge_fixture()
    var exit := _make_exit()
    add_child(exit)
    var cell := Vector2i(30, 30)
    var unit := _make_exit_occupant(cell, true, MovementController.State.IDLE)
    SpatialHash.instance.rebuild()
    var allowed: bool = exit._is_cell_available(cell)
    SpatialHash.instance.remove_child(unit)
    unit.free()
    remove_child(exit)
    TestHelper.assert_true(allowed, "exit cell allows an idle sharer below capacity")


func test_exit_cell_allows_tiberium():
    _reset_nudge_fixture()
    var exit := _make_exit()
    add_child(exit)
    var cell := Vector2i(30, 30)
    SpatialHash.instance.register_resource_cell(cell)
    var registered: bool = SpatialHash.instance.get_cell_occupancy(cell).resource
    var allowed: bool = exit._is_cell_available(cell)
    SpatialHash.instance.unregister_resource_cell(cell)
    remove_child(exit)
    TestHelper.assert_true(registered, "tiberium fixture: resource fact not observed")
    TestHelper.assert_true(allowed, "exit cell allows a tiberium cell (driveable)")


func test_exit_cell_allows_walkable_slope():
    _reset_nudge_fixture()
    var exit := _make_exit()
    add_child(exit)
    var cell := Vector2i(30, 30)
    TerrainSystem.set_cell_type(cell, "slope")
    var observed: bool = TerrainSystem.get_cell_type(cell) == "slope"
    var allowed: bool = exit._is_cell_available(cell)
    TerrainSystem.set_cell_type(cell, "clear")
    remove_child(exit)
    TestHelper.assert_true(observed, "slope fixture: seeded type not observed")
    TestHelper.assert_true(allowed, "exit cell allows walkable slope terrain")
