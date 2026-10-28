extends Node

# Stacked-deck integration: real TerrainSystem surfaces + SpatialHash bridge
# registry + Pathfinder/ MovementController drive. Two deck levels are authored
# over one corridor; a ground vehicle drives under them on level 0 while a
# second vehicle drives across on level 1, both in the same frame loop. A level-2
# deck stacked above must be traversable by pathing without disturbing either.
#
# Fixtures are real in-map cells flattened to ground grade; deck heights are
# authored so the ground cannot climb (grade gate), keeping each vehicle on its
# own surface observably.

const WHEEL_LOCOMOTOR_PATH: String = "res://games/ts/locomotors/Wheel.tres"
const MAP: Vector2i = Vector2i(50, 50)
const START_CELL: Vector2i = Vector2i(25, 25)
const MID_CELL: Vector2i = Vector2i(26, 25)
const FAR_CELL: Vector2i = Vector2i(27, 25)
const LEVEL1_HEIGHT: float = 4.0
const LEVEL2_HEIGHT: float = 8.0
const DRIVE_DT: float = 1.0 / 60.0
const MAX_DRIVE_FRAMES: int = 1800


class StubBridge:
    extends Node3D
    var data: Dictionary = {}

    func get_bridge_cell_data() -> Dictionary:
        return data


var _ts: Node = null
var _sh: Node = null
var _root: Node = null
var _bridges: Array[Node3D] = []
var _vehicles: Array[Node3D] = []


func _flatten(cell: Vector2i, height: int) -> void:
    for vx in [cell.x, cell.x + 1]:
        for vz in [cell.y, cell.y + 1]:
            _ts._vertex_grid[vx][vz] = height
    _ts.invalidate_height_snapshot()


func _register_deck(cell: Vector2i, level: int, surface_height: float) -> void:
    var bridge := StubBridge.new()
    bridge.data = {
        "surface_height": surface_height,
        "is_end": false,
        "piece_id": "stack_%d" % level,
        "level": level,
    }
    bridge.add_to_group("bridge")
    _root.add_child(bridge)
    bridge.global_position = CellUtil.cell_to_world(cell)
    _bridges.append(bridge)


func _make_vehicle(name: String) -> Array:
    var entity := Node3D.new()
    entity.name = name
    entity.add_to_group("entities")
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.entity_type = EntityData.EntityType.VEHICLE
    stats.player_id = 0
    entity.add_child(stats)
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    mc._parent = entity
    mc._locomotor_data = load(WHEEL_LOCOMOTOR_PATH) as Locomotor
    _root.add_child(entity)
    _vehicles.append(entity)
    return [entity, mc]


func test_ground_and_level_one_traffic_share_stacked_corridor() -> void:
    if _ts == null or _sh == null:
        TestHelper.fail("autoloads not injected")
        return
    _root = Engine.get_main_loop().root
    _ts.init_grid(MAP.x, MAP.y)
    _ts.clear()
    for cell: Vector2i in [START_CELL, MID_CELL, FAR_CELL]:
        TestHelper.assert_true(
            CellUtil.is_in_diamond(cell, MAP), "corridor cell %s is inside the map" % cell
        )
        _flatten(cell, 0)
    var level1_y: float = LEVEL1_HEIGHT * _ts.HEIGHT_STEP
    var level2_y: float = LEVEL2_HEIGHT * _ts.HEIGHT_STEP
    for cell: Vector2i in [START_CELL, MID_CELL, FAR_CELL]:
        _register_deck(cell, 1, level1_y)
        _register_deck(cell, 2, level2_y)
    _sh.rebuild()

    # Control: the stacked cell exposes ground plus both decks as separate surfaces.
    TestHelper.assert_eq(
        _ts.get_cell_surface_levels(MID_CELL), [0, 1, 2], "mid cell stacks ground + two decks"
    )
    (
        TestHelper
        . assert_true(
            is_equal_approx(_ts.get_cell_surface_height(MID_CELL, 1), level1_y),
            "level 1 surface is the lower deck",
        )
    )
    (
        TestHelper
        . assert_true(
            is_equal_approx(_ts.get_cell_surface_height(MID_CELL, 2), level2_y),
            "level 2 surface is the upper deck",
        )
    )

    var ground_pair := _make_vehicle("GroundVehicle")
    var ground: Node3D = ground_pair[0] as Node3D
    var ground_mc: MovementController = ground_pair[1] as MovementController
    ground_mc._surface_level = 0
    ground.global_position = CellUtil.cell_to_world(START_CELL)

    var deck_pair := _make_vehicle("DeckVehicle")
    var deck: Node3D = deck_pair[0] as Node3D
    var deck_mc: MovementController = deck_pair[1] as MovementController
    deck_mc._surface_level = 1
    deck.global_position = CellUtil.cell_to_world(START_CELL)
    deck.global_position.y = level1_y

    ground_mc.player_move(CellUtil.cell_to_world(FAR_CELL), null, null, 0)
    deck_mc.player_move(CellUtil.cell_to_world(FAR_CELL), null, null, 1)
    TestHelper.assert_true(
        ground_mc.get_state() != MovementController.State.IDLE, "ground vehicle accepted the order"
    )
    TestHelper.assert_true(
        deck_mc.get_state() != MovementController.State.IDLE, "deck vehicle accepted the order"
    )
    # Control: each route crosses the mid cell; the ground path is at level 0 and
    # the deck path at level 1 (a level-2 crossing is proven by the path query).
    TestHelper.assert_true(
        _path_has_state(ground_mc, MID_CELL, 0), "ground route crosses mid at level 0"
    )
    TestHelper.assert_true(
        _path_has_state(deck_mc, MID_CELL, 1), "deck route crosses mid at level 1"
    )

    var level2_path: Array[Vector3i] = _path_states(
        Pathfinder.find_path_detailed(
            CellUtil.cell_to_world(START_CELL),
            CellUtil.cell_to_world(FAR_CELL),
            {},
            ground_mc._locomotor_data,
            false,
            null,
            _ts,
            2,
            2
        )
    )
    (
        TestHelper
        . assert_true(
            level2_path.has(Vector3i(MID_CELL.x, MID_CELL.y, 2)),
            "level 2 path crosses mid on the upper deck",
        )
    )

    var ground_mid_y := NAN
    var deck_mid_y := NAN
    var frames := 0
    while frames < MAX_DRIVE_FRAMES and not _both_idle(ground_mc, deck_mc):
        if ground_mc.get_state() != MovementController.State.IDLE:
            ground_mc._physics_process(DRIVE_DT)
            if CellUtil.world_to_cell(ground.global_position) == MID_CELL:
                ground_mid_y = ground.global_position.y
        if deck_mc.get_state() != MovementController.State.IDLE:
            deck_mc._physics_process(DRIVE_DT)
            if CellUtil.world_to_cell(deck.global_position) == MID_CELL:
                deck_mid_y = deck.global_position.y
        frames += 1

    TestHelper.assert_true(frames < MAX_DRIVE_FRAMES, "both vehicles finished within the budget")
    TestHelper.assert_eq(
        ground_mc.get_state(), MovementController.State.IDLE, "ground vehicle stopped"
    )
    TestHelper.assert_eq(deck_mc.get_state(), MovementController.State.IDLE, "deck vehicle stopped")
    TestHelper.assert_eq(
        CellUtil.world_to_cell(ground.global_position), FAR_CELL, "ground vehicle reached far shore"
    )
    TestHelper.assert_eq(
        CellUtil.world_to_cell(deck.global_position), FAR_CELL, "deck vehicle reached far shore"
    )
    # The ground vehicle drove on level 0 (a level-1 deck four steps up cannot be
    # entered); the deck vehicle followed the level-1 deck surface.
    (
        TestHelper
        . assert_true(
            not is_nan(ground_mid_y) and absf(ground_mid_y - 0.0) < 0.05,
            "ground vehicle crossed mid at ground Y (got %.4f)" % ground_mid_y,
        )
    )
    (
        TestHelper
        . assert_true(
            not is_nan(deck_mid_y) and absf(deck_mid_y - level1_y) < 0.05,
            "deck vehicle crossed mid at the level-1 deck Y (got %.4f)" % deck_mid_y,
        )
    )

    # Real occupancy registration: the two idle vehicles at the far cell block
    # their own level only.
    _sh.rebuild()
    TestHelper.assert_true(
        _sh.is_cell_blocked(FAR_CELL, 0), "ground occupant blocks the far cell at level 0"
    )
    TestHelper.assert_true(
        _sh.is_cell_blocked(FAR_CELL, 1), "deck occupant blocks the far cell at level 1"
    )
    (
        TestHelper
        . assert_true(
            not _sh.is_cell_blocked(MID_CELL, 0) and not _sh.is_cell_blocked(MID_CELL, 1),
            "mid cell is clear at both levels after both vehicles leave",
        )
    )

    # Level-scoped reservation at the shared mid XZ, in flight: a claim on one
    # level must not block either other level, while the same (cell, level) still
    # refuses a double claim — the "neither blocks the other" contract.
    _sh.clear_reservations()
    TestHelper.assert_true(_sh.reserve_cell(MID_CELL, 1), "deck vehicle reserves mid at level 1")
    (
        TestHelper
        . assert_true(
            not _sh.reserve_cell(MID_CELL, 1),
            "control: the same (cell, level) cannot be reserved twice",
        )
    )
    TestHelper.assert_true(
        _sh.reserve_cell(MID_CELL, 0), "the deck claim leaves the ground beneath free"
    )
    TestHelper.assert_true(
        _sh.reserve_cell(MID_CELL, 2), "the deck claim leaves the upper deck free"
    )
    _sh.clear_reservations()
    _teardown()


func _both_idle(a: MovementController, b: MovementController) -> bool:
    return a._state == MovementController.State.IDLE and b._state == MovementController.State.IDLE


func _path_has_state(mc: MovementController, cell: Vector2i, level: int) -> bool:
    for i in mc._waypoints.size():
        if CellUtil.world_to_cell(mc._waypoints[i]) != cell:
            continue
        var wp_level: int = mc._waypoint_levels[i] if i < mc._waypoint_levels.size() else 0
        if wp_level == level:
            return true
    return false


func _path_states(detailed: Dictionary) -> Array[Vector3i]:
    var states: Array[Vector3i] = []
    var path: PackedVector3Array = detailed["path"]
    var levels: PackedInt32Array = detailed["levels"]
    for i in path.size():
        var cell := CellUtil.world_to_cell(path[i])
        states.append(Vector3i(cell.x, cell.y, levels[i]))
    return states


func _teardown() -> void:
    for vehicle in _vehicles:
        if is_instance_valid(vehicle):
            _root.remove_child(vehicle)
            vehicle.free()
    _vehicles.clear()
    for bridge in _bridges:
        if is_instance_valid(bridge):
            _root.remove_child(bridge)
            bridge.free()
    _bridges.clear()
    if _sh != null:
        _sh.rebuild()
    if CellReservation.instance:
        CellReservation.instance.clear()
    if _ts != null:
        _ts.init_grid(MAP.x, MAP.y)
        _ts.clear()
