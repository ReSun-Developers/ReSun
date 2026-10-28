extends Node

const MovementFactory := preload("res://test/movement_test_factory.gd")

# Sub-slot placement regressions: both production placement paths must land the entity on the
# booked sub-slot world position, not on the cell centre.

const CELL: Vector2i = Vector2i(20, 20)

var _spawned: Array[Node3D] = []


func _teardown() -> void:
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    for e in _spawned:
        if is_instance_valid(e):
            if e.get_parent() != null:
                e.get_parent().remove_child(e)
            e.free()
    _spawned.clear()
    var sh := SpatialHash.instance
    if sh:
        sh._grid.clear()
        sh._blocked_cells.clear()
        sh._shared_cell_counts.clear()
        sh.clear_reservations()
        sh.rebuild()
    TerrainSystem.init_grid(64, 64)
    TerrainSystem.clear()


func _setup() -> void:
    _teardown()
    TerrainSystem.init_grid(64, 64)
    for dx in range(-3, 4):
        for dz in range(-3, 4):
            TerrainSystem.set_cell_type(CELL + Vector2i(dx, dz), "clear")


func _root() -> Node3D:
    var root := Node3D.new()
    root.name = "PlacementRoot"
    (Engine.get_main_loop() as SceneTree).root.add_child(root)
    _spawned.append(root)
    return root


func test_entity_placer_lands_on_booked_sub_slot():
    _setup()
    var data := EntityFactory.get_entity_data("GDI_LIGHT_INFANTRY")
    if data == null:
        TestHelper.fail("GDI_LIGHT_INFANTRY fixture missing")
        _teardown()
        return
    var parent := _root()
    var cell_center := CellUtil.cell_to_world(CELL)
    var entity := EntityPlacer.place_entity(data, cell_center, 0, parent)
    TestHelper.assert_true(entity != null, "EntityPlacer spawned the infantry")
    if entity == null:
        _teardown()
        return
    var mc := entity.get_node_or_null("MovementController") as MovementController
    TestHelper.assert_true(mc != null, "spawned infantry has a MovementController")
    if mc == null:
        _teardown()
        return
    var booked: bool = mc.has_sub_slot()
    var expected := mc.get_sub_slot_position()
    var cell := CellUtil.world_to_cell(entity.global_position)
    var slot := mc._assigned_slot
    var slot_position := CellSubPositions.get_sub_position(cell, slot, -1, mc.get_surface_level())
    TestHelper.assert_true(booked, "EntityPlacer booked a sub-slot")
    (
        TestHelper
        . assert_true(
            entity.global_position.is_equal_approx(slot_position),
            "EntityPlacer placed the entity on the booked sub-slot",
        )
    )
    (
        TestHelper
        . assert_true(
            entity.global_position.is_equal_approx(expected),
            "EntityPlacer used the controller's booked position",
        )
    )
    (
        TestHelper
        . assert_true(
            not entity.global_position.is_equal_approx(cell_center),
            "EntityPlacer did not leave the entity at the cell centre",
        )
    )
    _teardown()


func test_place_at_sub_slot_fails_when_cell_is_full():
    _setup()
    var mc := MovementFactory.make_movement_controller(Locomotor.new())
    var cr := CellReservation.instance
    var fillers: Array[Node3D] = []
    for i in CellSubPositions.get_slot_count():
        var filler := Node3D.new()
        fillers.append(filler)
        cr.reserve_sub_slot(CELL, filler)
    var parent := mc.get_parent() as Node3D
    var before := parent.position
    var booked := mc.place_at_sub_slot(CELL)
    TestHelper.assert_eq(booked, false, "place_at_sub_slot refuses a full cell")
    TestHelper.assert_true(
        parent.position.is_equal_approx(before), "a refused placement does not move the parent"
    )
    for filler in fillers:
        filler.free()
    _teardown()


func test_transport_readd_lands_on_booked_sub_slot():
    _setup()
    var root := _root()
    var transport := Node3D.new()
    transport.name = "Transport"
    transport.position = CellUtil.cell_to_world(CELL)
    var t := TransportComponent.new()
    t.name = "TransportComponent"
    transport.add_child(t)
    root.add_child(transport)
    var passenger := Node3D.new()
    passenger.name = "Passenger"
    var mc := MovementController.new()
    mc.name = "MovementController"
    passenger.add_child(mc)
    var loco := Locomotor.new()
    loco.shares_cell = true
    mc.apply_locomotor(loco)
    t._readd_passenger_at_free_cell(passenger)
    var booked: bool = mc.has_sub_slot()
    var expected := mc.get_sub_slot_position()
    var cell := CellUtil.world_to_cell(passenger.global_position)
    var slot := mc._assigned_slot
    var slot_position := CellSubPositions.get_sub_position(cell, slot, -1, mc.get_surface_level())
    TestHelper.assert_true(booked, "transport re-add booked a sub-slot")
    (
        TestHelper
        . assert_true(
            passenger.global_position.is_equal_approx(slot_position),
            "transport re-add placed the passenger on the booked sub-slot",
        )
    )
    (
        TestHelper
        . assert_true(
            passenger.global_position.is_equal_approx(expected),
            "transport re-add used the controller's booked position",
        )
    )
    (
        TestHelper
        . assert_true(
            not passenger.global_position.is_equal_approx(CellUtil.cell_to_world(cell)),
            "transport re-add did not leave the passenger at the cell centre",
        )
    )
    _teardown()
