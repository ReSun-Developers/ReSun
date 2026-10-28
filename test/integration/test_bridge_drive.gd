extends Node

# Bridge drive integration — the SHIPPED high-bridge geometry driven with the
# default four-step deck rise (no `bridge_rise` override) and a real bridge-end
# TerrainObject (cliff + 3-cell road cut at grade 4) stamped at the span end.
#
# A high bridge is built on one authored flat span grade: each deck cell's
# walkable height is its lowest terrain corner plus the authored rise, so a deck
# cell abutting the stamped end does not inherit the end cliff's raised corners.
# With that flat base the road cut (grade 4) and every deck cell (grade 0 + the
# four-step rise) resolve to the same height, so the deck is internally level and
# Wheel traffic crosses the span end to end. The companion test removes the deck
# overlays and proves the same ordered crossing no longer routes across them.

const WHEEL_LOCOMOTOR_PATH: String = "res://games/ts/locomotors/Wheel.tres"
## Real generated end caps: `_s` at the north shore (cut row local z=1, bridge
## continues south) and `_n` at the south shore (cut row local z=0, bridge
## continues north). Each cuts a 3-lane road row across x=26..28 and carries a
## grade-4 rock bank at x=25/29; the bridge thus runs north-south on the middle
## lane x=27.
const NEAR_END_ID: String = "cliff_bridge_end_n"
const FAR_END_ID: String = "cliff_bridge_end_s"
const NEAR_ORIGIN: Vector2i = Vector2i(29, 27)
const FAR_ORIGIN: Vector2i = Vector2i(29, 20)
## Middle-lane deck cells the produced path must cross (the sides are water).
const DECK_CELLS: Array[Vector2i] = [
    Vector2i(31, 22), Vector2i(31, 23), Vector2i(31, 24), Vector2i(31, 25), Vector2i(31, 26)
]
## Full water corridor under the three lanes, so no land detour exists.
const WATER_CELLS: Array[Vector2i] = [
    Vector2i(30, 22),
    Vector2i(31, 22),
    Vector2i(32, 22),
    Vector2i(30, 23),
    Vector2i(31, 23),
    Vector2i(32, 23),
    Vector2i(30, 24),
    Vector2i(31, 24),
    Vector2i(32, 24),
    Vector2i(30, 25),
    Vector2i(31, 25),
    Vector2i(32, 25),
    Vector2i(30, 26),
    Vector2i(31, 26),
    Vector2i(32, 26),
]
const START_CELL: Vector2i = Vector2i(31, 21)
const FAR_CELL: Vector2i = Vector2i(31, 27)
const BASE_GRADE: int = 0
## Authored bridge-end road-cut grade (four height steps) per the high-bridge
## spec; the flat deck span grade must match it for entry.
const DECK_GRADE: int = 4
const DRIVE_DT: float = 1.0 / 60.0
const MAX_DRIVE_FRAMES: int = 1800

var _ts: Node = null
var _sh: Node = null
var _ef: Node = null
var _bridges: Array[Node3D] = []


## Flattens a vertex rectangle to `grade` (raw steps), matching the direct
## `_vertex_grid` edit + snapshot invalidation the other bridge fixtures use.
func _flatten_rect(min_v: Vector2i, max_v: Vector2i, grade: int) -> void:
    for vx in range(min_v.x, max_v.x + 1):
        for vz in range(min_v.y, max_v.y + 1):
            _ts._set_vertex_no_cascade(vx, vz, grade)
    _ts.invalidate_height_snapshot()


## Authors a flat grade-`BASE_GRADE` strip, paints the water corridor, stamps the
## north (`_s`) and south (`_n`) end tiles, and places the shipped high-bridge
## deck over the middle water lane.
func _setup() -> void:
    _ts.init_grid(50, 50)
    _ts.clear()
    _flatten_rect(Vector2i(27, 19), Vector2i(35, 29), BASE_GRADE)
    for cell in WATER_CELLS:
        _ts.set_land_type(cell, "water")
    TestHelper.assert_true(
        _ts.stamp_terrain_object_by_id(NEAR_END_ID, NEAR_ORIGIN), "near end tile stamps"
    )
    TestHelper.assert_true(
        _ts.stamp_terrain_object_by_id(FAR_END_ID, FAR_ORIGIN), "far end tile stamps"
    )
    _spawn_bridges()
    _sh.rebuild()


func _spawn_bridges() -> void:
    var root: Node = Engine.get_main_loop().root
    for cell in DECK_CELLS:
        var bridge: Node3D = _ef.create_entity("BRIDGE_HIGH")
        if bridge == null:
            continue
        root.add_child(bridge)
        bridge.global_position = CellUtil.cell_to_world(cell)
        _bridges.append(bridge)


func _remove_bridges() -> void:
    var root: Node = Engine.get_main_loop().root
    for bridge in _bridges:
        if is_instance_valid(bridge):
            root.remove_child(bridge)
            bridge.free()
    _bridges.clear()
    _sh.rebuild()


func _make_vehicle() -> Array:
    var root: Node = Engine.get_main_loop().root
    var entity := Node3D.new()
    entity.name = "BridgeDriveVehicle"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.entity_type = EntityData.EntityType.VEHICLE
    stats.player_id = 0
    stats.weight = 3.0
    entity.add_child(stats)
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    mc._parent = entity
    root.add_child(entity)
    return [entity, mc]


## Cell -> surface level for every deck cell the produced path crosses. Empty when
## the route avoids the deck cells entirely.
func _path_deck_levels(mc: MovementController) -> Dictionary:
    var levels: Dictionary = {}
    for i in mc._waypoints.size():
        var cell := CellUtil.world_to_cell(mc._waypoints[i])
        if DECK_CELLS.has(cell):
            levels[cell] = mc._waypoint_levels[i] if i < mc._waypoint_levels.size() else -1
    return levels


func _teardown(pair: Array) -> void:
    var root: Node = Engine.get_main_loop().root
    if pair.size() == 2:
        var vehicle: Node = pair[0] as Node
        if is_instance_valid(vehicle):
            root.remove_child(vehicle)
            vehicle.free()
    _remove_bridges()
    if CellReservation.instance:
        CellReservation.instance.clear()
    if _ts != null:
        _ts.init_grid(50, 50)
        _ts.clear()


## The shipped high bridge, driven end to end with the default four-step rise.
func test_shipped_high_bridge_drive_crosses_the_span() -> void:
    if _ts == null or _sh == null or _ef == null:
        TestHelper.fail("autoloads not injected")
        return
    _setup()
    var wheel := load(WHEEL_LOCOMOTOR_PATH) as Locomotor
    TestHelper.assert_true(wheel != null, "Wheel locomotor loads")

    # Geometry: the near road cut and every deck cell resolve to the same flat
    # grade, so the deck is enterable and internally level.
    var deck_height: float = float(DECK_GRADE) * _ts.HEIGHT_STEP
    (
        TestHelper
        . assert_true(
            is_equal_approx(_ts.get_cell_min_height(START_CELL), deck_height),
            "the near road cut sits at the deck grade",
        )
    )
    for cell in DECK_CELLS:
        (
            TestHelper
            . assert_true(
                is_equal_approx(_ts.get_cell_surface_height(cell, 1), deck_height),
                "deck cell %s sits at the flat span grade" % cell,
            )
        )

    var pair := _make_vehicle()
    var vehicle: Node3D = pair[0] as Node3D
    var mc: MovementController = pair[1] as MovementController
    mc._locomotor_data = wheel
    vehicle.global_position = CellUtil.cell_to_world(START_CELL)
    vehicle.global_position.y = deck_height
    mc.move_to(CellUtil.cell_to_world(FAR_CELL))

    # The produced path crosses every deck cell on the level-1 surface.
    var crossed: Dictionary = _path_deck_levels(mc)
    for cell in DECK_CELLS:
        TestHelper.assert_true(crossed.has(cell), "the path crosses deck cell %s" % cell)
        if crossed.has(cell):
            TestHelper.assert_eq(int(crossed[cell]), 1, "deck cell %s is crossed at level 1" % cell)

    # Drive the real physics tick: the unit follows each deck cell's surface Y and
    # arrives on the far road cut within the frame budget.
    var deck_y: Dictionary = {}
    var frames := 0
    while frames < MAX_DRIVE_FRAMES and mc.get_state() != MovementController.State.IDLE:
        mc._physics_process(DRIVE_DT)
        frames += 1
        var cell := CellUtil.world_to_cell(vehicle.global_position)
        if DECK_CELLS.has(cell):
            deck_y[cell] = vehicle.global_position.y
    TestHelper.assert_true(
        frames < MAX_DRIVE_FRAMES, "the vehicle finished within the frame budget"
    )
    TestHelper.assert_eq(mc.get_state(), MovementController.State.IDLE, "the vehicle ends idle")
    TestHelper.assert_eq(
        CellUtil.world_to_cell(vehicle.global_position), FAR_CELL, "the vehicle ends on FAR_CELL"
    )
    for cell in DECK_CELLS:
        TestHelper.assert_true(deck_y.has(cell), "the vehicle drove across deck cell %s" % cell)
        if deck_y.has(cell):
            var expected: float = _ts.get_cell_surface_height(cell, 1)
            (
                TestHelper
                . assert_true(
                    absf(float(deck_y[cell]) - expected) < 0.05,
                    (
                        "driven Y on deck cell %s follows the deck surface (got %.4f, want %.4f)"
                        % [cell, float(deck_y[cell]), expected]
                    ),
                )
            )
    _teardown(pair)


## Non-vacuity control: with the deck overlays removed the same ordered crossing
## must not use the deck cells (they are water at ground level); restoring the
## decks puts the crossing back on the route.
func test_shipped_high_bridge_crossing_needs_the_decks() -> void:
    if _ts == null or _sh == null or _ef == null:
        TestHelper.fail("autoloads not injected")
        return
    _setup()
    _remove_bridges()
    TestHelper.assert_true(
        not _sh.has_bridge_on_cell(DECK_CELLS[1], 1), "control: no deck registered after removal"
    )
    var wheel := load(WHEEL_LOCOMOTOR_PATH) as Locomotor
    var pair := _make_vehicle()
    var vehicle: Node3D = pair[0] as Node3D
    var mc: MovementController = pair[1] as MovementController
    mc._locomotor_data = wheel
    vehicle.global_position = CellUtil.cell_to_world(START_CELL)
    vehicle.global_position.y = float(DECK_GRADE) * _ts.HEIGHT_STEP
    mc.move_to(CellUtil.cell_to_world(FAR_CELL))
    TestHelper.assert_eq(
        _path_deck_levels(mc).size(), 0, "without decks the route uses no deck cell"
    )

    # Restore the decks: the same order now routes across them, proving the
    # control had a reachable crossing to lose.
    _spawn_bridges()
    _sh.rebuild()
    mc.move_to(CellUtil.cell_to_world(FAR_CELL))
    TestHelper.assert_true(
        _path_deck_levels(mc).size() > 0, "restored decks put the crossing back on the route"
    )
    _teardown(pair)
