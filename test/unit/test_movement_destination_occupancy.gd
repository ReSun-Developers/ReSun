extends Node

# Movement destination occupancy rules. Characterizes the two predicates that used to iterate
# SpatialHash._grid directly, then pins the chosen rules: buildings are ground-only facts and
# grid entries with no MovementController are not mobile occupants.

const CELL: Vector2i = Vector2i(30, 30)

var _spawned: Array[Node3D] = []
var _registered_building: Array[Vector2i] = []


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
        sh._grid.clear()
        sh._blocked_cells.clear()
        sh._shared_cell_counts.clear()
        sh._bridge_cells.clear()
        sh.clear_reservations()
        sh.rebuild()
    _registered_building.clear()
    TerrainSystem.init_grid(64, 64)
    TerrainSystem.clear()


func _setup() -> void:
    _teardown()
    TerrainSystem.init_grid(64, 64)
    TerrainSystem.set_cell_type(CELL, "clear")


func _make_controller(level: int, shares: bool) -> MovementController:
    var root := Node3D.new()
    root.name = "Mover"
    root.position = CellUtil.cell_to_world(CELL)
    var mc := MovementController.new()
    mc.name = "MovementController"
    root.add_child(mc)
    mc._parent = root
    mc._surface_level = level
    var loco := Locomotor.new()
    loco.shares_cell = shares
    mc.apply_locomotor(loco)
    _spawned.append(root)
    return mc


func _register_building(cell: Vector2i) -> void:
    SpatialHash.instance.register_building_cells([cell])
    _registered_building.append(cell)


func _grid_entry(
    root: Node3D, mc: MovementController, level: int, state: int, shares: bool
) -> void:
    SpatialHash.instance._grid[CellUtil.cell_key(CELL)] = [
        {
            "node": root,
            "mc": mc,
            "level": level,
            "state": state,
            "shares": shares,
        }
    ]


func test_building_does_not_block_deck_above_it():
    _setup()
    _register_building(CELL)
    var mc := _make_controller(1, false)
    (
        TestHelper
        . assert_eq(
            mc._is_cell_occupied(CELL),
            false,
            "building below a deck does not make the level-1 destination occupied",
        )
    )
    _teardown()


func test_building_blocks_ground_level():
    _setup()
    _register_building(CELL)
    var mc := _make_controller(0, false)
    TestHelper.assert_eq(mc._is_cell_occupied(CELL), true, "building blocks its ground cell")
    _teardown()


func test_no_mc_entry_does_not_block_destination():
    _setup()
    var overlay := Node3D.new()
    overlay.name = "Overlay"
    _spawned.append(overlay)
    _grid_entry(overlay, null, 0, MovementController.State.IDLE, false)
    var mc := _make_controller(0, false)
    (
        TestHelper
        . assert_eq(
            mc._is_cell_occupied(CELL),
            false,
            "a grid entry with no MovementController does not block a destination",
        )
    )
    _teardown()


func test_moving_non_sharer_blocks_destination():
    _setup()
    var other_root := Node3D.new()
    other_root.name = "Other"
    _spawned.append(other_root)
    var other_mc := MovementController.new()
    other_mc.name = "MovementController"
    other_root.add_child(other_mc)
    other_mc._parent = other_root
    var other_loco := Locomotor.new()
    other_loco.shares_cell = false
    other_mc.apply_locomotor(other_loco)
    _grid_entry(other_root, other_mc, 0, MovementController.State.MOVING, false)
    var mc := _make_controller(0, false)
    TestHelper.assert_eq(
        mc._is_cell_occupied(CELL), true, "a moving non-sharing unit blocks the destination"
    )
    _teardown()


func test_moving_sharer_is_ignored_by_sharing_mover():
    _setup()
    var other_root := Node3D.new()
    other_root.name = "Other"
    _spawned.append(other_root)
    var other_mc := MovementController.new()
    other_mc.name = "MovementController"
    other_root.add_child(other_mc)
    other_mc._parent = other_root
    var other_loco := Locomotor.new()
    other_loco.shares_cell = true
    other_mc.apply_locomotor(other_loco)
    _grid_entry(other_root, other_mc, 0, MovementController.State.MOVING, true)
    var mc := _make_controller(0, true)
    (
        TestHelper
        . assert_eq(
            mc._is_cell_occupied(CELL),
            false,
            "a sharing mover ignores another moving sharer on the destination",
        )
    )
    _teardown()


func test_own_cell_is_excluded():
    _setup()
    var mc := _make_controller(0, false)
    _grid_entry(mc.get_parent(), mc, 0, MovementController.State.IDLE, false)
    TestHelper.assert_eq(
        mc._is_cell_occupied(CELL), false, "the mover's own grid entry is excluded"
    )
    _teardown()


func test_non_sharing_unit_blocks_destination():
    _setup()
    var other_root := Node3D.new()
    other_root.name = "Other"
    _spawned.append(other_root)
    var other_mc := MovementController.new()
    other_mc.name = "MovementController"
    other_root.add_child(other_mc)
    other_mc._parent = other_root
    var other_loco := Locomotor.new()
    other_loco.shares_cell = false
    other_mc.apply_locomotor(other_loco)
    _grid_entry(other_root, other_mc, 0, MovementController.State.IDLE, false)
    var mc := _make_controller(0, false)
    TestHelper.assert_eq(
        mc._is_cell_occupied(CELL), true, "an idle non-sharing unit blocks the destination"
    )
    _teardown()


func test_sharing_mover_ignores_other_sharers():
    _setup()
    var other_root := Node3D.new()
    other_root.name = "Other"
    _spawned.append(other_root)
    var other_mc := MovementController.new()
    other_mc.name = "MovementController"
    other_root.add_child(other_mc)
    other_mc._parent = other_root
    var other_loco := Locomotor.new()
    other_loco.shares_cell = true
    other_mc.apply_locomotor(other_loco)
    _grid_entry(other_root, other_mc, 0, MovementController.State.IDLE, true)
    var mc := _make_controller(0, true)
    (
        TestHelper
        . assert_eq(
            mc._is_cell_occupied(CELL),
            false,
            "a sharing mover ignores another sharing unit on the destination",
        )
    )
    _teardown()


func test_non_sharer_is_blocked_by_sharer():
    _setup()
    var other_root := Node3D.new()
    other_root.name = "Other"
    _spawned.append(other_root)
    var other_mc := MovementController.new()
    other_mc.name = "MovementController"
    other_root.add_child(other_mc)
    other_mc._parent = other_root
    var other_loco := Locomotor.new()
    other_loco.shares_cell = true
    other_mc.apply_locomotor(other_loco)
    _grid_entry(other_root, other_mc, 0, MovementController.State.IDLE, true)
    var mc := _make_controller(0, false)
    TestHelper.assert_eq(
        mc._is_cell_occupied(CELL), true, "a non-sharing mover is blocked by a sharer"
    )
    _teardown()
