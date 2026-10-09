extends Node

# TransportComponent passenger tests — boarding, unloading, interrupts, death
# eject, and seat pips. Requirements: openspec/changes/add-transport-passengers
# (load is stationary-only and never queues; unload ejects one per interval).
# Entities go under the scene tree root (runner never parents test instances).

const SELECT_SCENE: PackedScene = preload("res://scenes/components/SelectComponent.tscn")
const TEST_CELL := Vector2i(20, 20)

var _sm: Node = null
var _ts: Node = null
var _sh: Node = null


func _tree_root() -> Node:
    return Engine.get_main_loop().root


func _ensure_grid() -> void:
    if _ts:
        _ts.init_grid(64, 64)


func _make_transport_entity(capacity: int = 4, with_health: bool = false) -> Node3D:
    var entity := Node3D.new()
    entity.name = "APC"
    entity.position = CellUtil.cell_to_world(TEST_CELL)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = 0
    entity.add_child(stats)
    if with_health:
        var health := HealthComponent.new()
        health.name = "HealthComponent"
        entity.add_child(health)
    var transport := TransportComponent.new()
    transport.name = "TransportComponent"
    transport.passengers = capacity
    entity.add_child(transport)
    _tree_root().add_child(entity)
    return entity


func _make_infantry(id: String, pip: Color = Color.WHITE, with_select: bool = true) -> Node3D:
    var infantry := Node3D.new()
    infantry.name = id
    infantry.position = CellUtil.cell_to_world(TEST_CELL + Vector2i(1, 0))
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = 0
    infantry.add_child(stats)
    if with_select:
        var sc := SELECT_SCENE.instantiate() as SelectComponent
        sc.name = "SelectComponent"
        infantry.add_child(sc)
    var pcomp := PassengerComponent.new()
    pcomp.name = "PassengerComponent"
    pcomp.pip_color = pip
    infantry.add_child(pcomp)
    _tree_root().add_child(infantry)
    infantry.add_to_group("entities")
    return infantry


func _make_mc(entity: Node3D, state: int = MovementController.State.IDLE) -> MovementController:
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    mc._state = state
    return mc


## Mark the entity as the only selected unit — the precondition for a
## mouse-click unload (mixed selections must not unload via click).
func _select_sole(entity: Node3D) -> void:
    var sc := SELECT_SCENE.instantiate() as SelectComponent
    sc.name = "SelectComponent"
    entity.add_child(sc)
    sc.is_selected = true
    _sm.selected_entities.clear()
    _sm.selected_entities.append(sc)


# --- Boarding ---


func test_board_detaches_passenger_node():
    var apc := _make_transport_entity(4)
    var trooper := _make_infantry("Trooper")
    var t := apc.get_node("TransportComponent") as TransportComponent
    var tree := trooper.get_tree() as SceneTree
    TestHelper.assert_true(t.board(trooper), "board succeeds with free seat")
    TestHelper.assert_true(
        not trooper.is_inside_tree(), "boarded passenger is detached from the tree"
    )
    (
        TestHelper
        . assert_true(
            not tree.get_nodes_in_group("entities").has(trooper),
            "boarded passenger invisible to entities group scans",
        )
    )
    (
        TestHelper
        . assert_true(
            t.passenger_nodes.size() == 1 and t.passenger_nodes[0] == trooper,
            "node held by transport",
        )
    )
    TestHelper.assert_eq(t.current_passengers, 1, "seat count incremented")
    apc.queue_free()


func test_board_captures_pip_colors():
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var red := _make_infantry("Red", Color.RED)
    var blue := _make_infantry("Blue", Color.BLUE)
    TestHelper.assert_true(t.board(red), "red boards")
    TestHelper.assert_true(t.board(blue), "blue boards")
    TestHelper.assert_eq(t.passenger_colors, [Color.RED, Color.BLUE] as Array[Color])
    apc.queue_free()


func test_board_rejects_when_full():
    var apc := _make_transport_entity(1)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var a := _make_infantry("A")
    var b := _make_infantry("B")
    TestHelper.assert_true(t.board(a), "first board succeeds")
    TestHelper.assert_true(not t.board(b), "second board rejected at capacity")
    TestHelper.assert_true(b.is_inside_tree(), "rejected infantry stays on the field")
    apc.queue_free()


func test_board_rejects_moving_transport():
    var apc := _make_transport_entity(4)
    _make_mc(apc, MovementController.State.MOVING)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var trooper := _make_infantry("Trooper")
    TestHelper.assert_true(not t.can_accept_passenger(), "moving transport accepts no passenger")
    TestHelper.assert_true(not t.board(trooper), "board rejected while moving")
    apc.queue_free()


func test_board_deselects_selected_passenger():
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var trooper := _make_infantry("Trooper")
    var sc := trooper.get_node("SelectComponent") as SelectComponent
    sc.is_selected = true
    _sm.selected_entities.append(sc)
    t.board(trooper)
    TestHelper.assert_true(
        _sm.selected_entities.is_empty(), "selection manager dropped boarded passenger"
    )
    TestHelper.assert_true(not sc.is_selected, "boarded passenger is deselected")
    apc.queue_free()


func test_board_rejects_invalid_passenger():
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    TestHelper.assert_true(not t.board(null), "null passenger rejected")
    apc.queue_free()


# --- Unload pacing and gating ---


func test_unload_ejects_one_per_interval():
    _ensure_grid()
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var a := _make_infantry("A")
    var b := _make_infantry("B")
    var c := _make_infantry("C")
    t.board(a)
    t.board(b)
    t.board(c)
    t.execute_unload()
    # First passenger ejects immediately, then one per unload_interval (0.25s).
    TestHelper.assert_eq(t.current_passengers, 2, "first eject is immediate")
    t._physics_process(0.1)
    t._physics_process(0.1)
    TestHelper.assert_eq(t.current_passengers, 2, "no eject below interval")
    t._physics_process(0.05)
    TestHelper.assert_eq(t.current_passengers, 1, "second eject at 0.25s")
    t._physics_process(0.25)
    TestHelper.assert_eq(t.current_passengers, 0, "third eject at 0.5s")
    TestHelper.assert_true(not t._unloading, "unload completes when empty")
    TestHelper.assert_true(a.is_inside_tree(), "ejected passenger re-enters tree")
    apc.queue_free()


func test_unload_blocked_when_empty():
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    TestHelper.assert_true(not t.can_unload(), "empty transport cannot unload")
    t.execute_unload()
    TestHelper.assert_true(not t._unloading, "execute_unload no-ops when empty")
    apc.queue_free()


func test_unload_cancels_on_move():
    var apc := _make_transport_entity(4)
    var mc := _make_mc(apc)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var trooper := _make_infantry("Trooper")
    TestHelper.assert_true(t.board(trooper), "board succeeds while stationary")
    t.execute_unload()
    TestHelper.assert_eq(t.current_passengers, 0, "first eject is immediate")
    t.board(trooper)
    mc._state = MovementController.State.MOVING
    t._unloading = true
    t._physics_process(1.0)
    TestHelper.assert_true(not t._unloading, "unload cancels when transport moves")
    TestHelper.assert_eq(t.current_passengers, 1, "passenger stays aboard on cancel")
    apc.queue_free()


func test_unload_cancels_on_stop():
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var trooper := _make_infantry("Trooper")
    t.board(trooper)
    t.execute_unload()
    t.cancel_unload()
    t._physics_process(1.0)
    TestHelper.assert_eq(t.current_passengers, 0, "first eject already happened before cancel")
    apc.queue_free()


func test_unload_blocked_on_water():
    _ensure_grid()
    _ts.set_land_type(TEST_CELL, "water")
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var trooper := _make_infantry("Trooper")
    t.board(trooper)
    TestHelper.assert_true(not t.can_unload(), "transport on water cannot unload")
    t.execute_unload()
    TestHelper.assert_eq(t.current_passengers, 1, "no eject on water")
    _ts.set_land_type(TEST_CELL, "clear")
    apc.queue_free()


func test_unload_after_water_clears():
    _ensure_grid()
    _ts.set_land_type(TEST_CELL, "water")
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var trooper := _make_infantry("Trooper")
    t.board(trooper)
    _ts.set_land_type(TEST_CELL, "clear")
    TestHelper.assert_true(t.can_unload(), "unload allowed once back on land")
    apc.queue_free()


# --- Death eject ---


func test_death_ejects_all_passengers():
    var apc := _make_transport_entity(4, true)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var health := apc.get_node("HealthComponent") as HealthComponent
    var a := _make_infantry("A")
    var b := _make_infantry("B")
    t.board(a)
    t.board(b)
    health.health_zero.emit()
    TestHelper.assert_eq(t.current_passengers, 0, "no passengers held after death")
    TestHelper.assert_true(a.is_inside_tree(), "passenger A ejected on death")
    TestHelper.assert_true(b.is_inside_tree(), "passenger B ejected on death")
    apc.queue_free()


func test_exit_tree_releases_held_passengers():
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var trooper := _make_infantry("Trooper")
    t.board(trooper)
    _tree_root().remove_child(apc)
    # Tree is mid-teardown during _exit_tree, so the backstop drops its
    # references synchronously and re-adds the passenger one frame later.
    TestHelper.assert_true(
        t.passenger_nodes.is_empty(), "transport drops held passengers on exit tree"
    )
    TestHelper.assert_true(
        is_instance_valid(trooper), "held passenger is kept alive for deferred re-add"
    )
    apc.queue_free()


# --- Hover-self DEPLOY cursor and order ---


func test_hover_self_returns_deploy_when_unloadable():
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var trooper := _make_infantry("Trooper")
    t.board(trooper)
    _select_sole(apc)
    (
        TestHelper
        . assert_eq(
            TestHelper.order_cursor(t, apc),
            CursorState.Type.DEPLOY,
            "hover-self on loaded stationary transport -> DEPLOY",
        )
    )
    _sm.selected_entities.clear()
    apc.queue_free()


func test_hover_self_default_when_empty():
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    (
        TestHelper
        . assert_eq(
            TestHelper.order_cursor(t, apc),
            CursorState.Type.DEFAULT,
            "hover-self on empty transport -> DEFAULT",
        )
    )
    apc.queue_free()


func test_hover_self_default_when_moving():
    var apc := _make_transport_entity(4)
    _make_mc(apc, MovementController.State.MOVING)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var trooper := _make_infantry("Trooper")
    t.board(trooper)
    (
        TestHelper
        . assert_eq(
            TestHelper.order_cursor(t, apc),
            CursorState.Type.DEFAULT,
            "hover-self on moving transport -> DEFAULT",
        )
    )
    apc.queue_free()


func test_hover_other_target_returns_default():
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var trooper := _make_infantry("Trooper")
    t.board(trooper)
    var other := Node3D.new()
    (
        TestHelper
        . assert_eq(
            TestHelper.order_cursor(t, other),
            CursorState.Type.DEFAULT,
            "hovering another unit -> DEFAULT",
        )
    )
    other.queue_free()
    apc.queue_free()


func test_self_order_returns_deploy_priority_15():
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var trooper := _make_infantry("Trooper")
    t.board(trooper)
    _select_sole(apc)
    var order := t.get_order_for_target(apc, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order != null, "unload order exists on hover-self")
    TestHelper.assert_eq(order.cursor, CursorState.Type.DEPLOY, "order cursor -> DEPLOY")
    TestHelper.assert_eq(order.priority, 15, "unload order priority -> 15")
    _sm.selected_entities.clear()
    apc.queue_free()


func test_unload_order_blocked_with_mixed_selection():
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var trooper := _make_infantry("Trooper")
    t.board(trooper)
    _select_sole(apc)
    # A second selected unit means the click must not unload — mixed
    # selections resolve to load (ENTER) or converge instead.
    var other := _make_infantry("Other")
    _sm.selected_entities.append(other.get_node("SelectComponent") as SelectComponent)
    (
        TestHelper
        . assert_eq(
            TestHelper.order_cursor(t, apc),
            CursorState.Type.DEFAULT,
            "mixed selection cursor -> DEFAULT",
        )
    )
    (
        TestHelper
        . assert_true(
            t.get_order_for_target(apc, Vector2i.ZERO, Vector3.ZERO, {}) == null,
            "mixed selection -> no unload order",
        )
    )
    _sm.selected_entities.clear()
    apc.queue_free()
    trooper.queue_free()
    other.queue_free()


func test_unload_order_blocked_when_transport_not_selected():
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var trooper := _make_infantry("Trooper")
    t.board(trooper)
    # Something else is selected; the APC is not part of the selection.
    _select_sole(trooper)
    (
        TestHelper
        . assert_true(
            t.get_order_for_target(apc, Vector2i.ZERO, Vector3.ZERO, {}) == null,
            "unselected transport -> no unload order",
        )
    )
    _sm.selected_entities.clear()
    apc.queue_free()
    trooper.queue_free()


func test_self_order_null_when_not_unloadable():
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    (
        TestHelper
        . assert_true(
            t.get_order_for_target(apc, Vector2i.ZERO, Vector3.ZERO, {}) == null,
            "no unload order when empty",
        )
    )
    apc.queue_free()


# --- PassengerComponent (infantry side) ---


func test_passenger_configure_captures_pip_color():
    var pcomp := PassengerComponent.new()
    var data := EntityData.new()
    data.pip_color = Color.ORANGE
    pcomp.configure(data)
    TestHelper.assert_eq(pcomp.pip_color, Color.ORANGE, "configure captures pip_color")


func test_passenger_cursor_enter_for_transport():
    var apc := _make_transport_entity(4)
    var trooper := _make_infantry("Trooper")
    var pcomp := trooper.get_node("PassengerComponent") as PassengerComponent
    (
        TestHelper
        . assert_eq(
            TestHelper.order_cursor(pcomp, apc),
            CursorState.Type.ENTER,
            "friendly stationary transport with seats -> ENTER",
        )
    )
    apc.queue_free()


func test_passenger_cursor_gates():
    var apc_full := _make_transport_entity(1)
    var filler := _make_infantry("Filler")
    var t_full := apc_full.get_node("TransportComponent") as TransportComponent
    TestHelper.assert_true(t_full.board(filler), "filler boards to fill transport")
    var apc_moving := _make_transport_entity(4)
    _make_mc(apc_moving, MovementController.State.MOVING)
    var enemy := _make_infantry("Enemy")
    enemy.remove_from_group("entities")
    enemy.add_to_group("enemy")
    var trooper := _make_infantry("Trooper")
    var pcomp := trooper.get_node("PassengerComponent") as PassengerComponent
    (
        TestHelper
        . assert_eq(
            TestHelper.order_cursor(pcomp, apc_full),
            CursorState.Type.DEFAULT,
            "full transport -> DEFAULT",
        )
    )
    (
        TestHelper
        . assert_eq(
            TestHelper.order_cursor(pcomp, apc_moving),
            CursorState.Type.DEFAULT,
            "moving transport -> DEFAULT",
        )
    )
    (
        TestHelper
        . assert_eq(
            TestHelper.order_cursor(pcomp, enemy),
            CursorState.Type.DEFAULT,
            "enemy entity -> DEFAULT",
        )
    )
    (
        TestHelper
        . assert_eq(
            TestHelper.order_cursor(pcomp, trooper),
            CursorState.Type.DEFAULT,
            "self target -> DEFAULT",
        )
    )
    (
        TestHelper
        . assert_eq(
            TestHelper.order_cursor(pcomp, null),
            CursorState.Type.DEFAULT,
            "null target -> DEFAULT",
        )
    )
    apc_full.queue_free()
    apc_moving.queue_free()
    enemy.queue_free()
    trooper.queue_free()


func test_passenger_order_returns_enter_priority_10():
    var apc := _make_transport_entity(4)
    var trooper := _make_infantry("Trooper")
    var pcomp := trooper.get_node("PassengerComponent") as PassengerComponent
    var order := pcomp.get_order_for_target(apc, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order != null, "board order exists")
    TestHelper.assert_eq(order.cursor, CursorState.Type.ENTER, "order cursor -> ENTER")
    TestHelper.assert_eq(order.priority, 10, "board order priority -> 10")
    var queued := pcomp.get_order_for_target(
        apc, Vector2i.ZERO, Vector3.ZERO, {OrderResult.MOD_QUEUED: true}
    )
    TestHelper.assert_true(queued.queued, "queued modifier propagates")
    apc.queue_free()
    trooper.queue_free()


func test_arrival_boards_adjacent_transport():
    var apc := _make_transport_entity(4)
    var trooper := _make_infantry("Trooper")
    var mc := _make_mc(trooper)
    var pcomp := trooper.get_node("PassengerComponent") as PassengerComponent
    # Far enough that _approach must walk (registers pending + exact target)...
    trooper.position = CellUtil.cell_to_world(TEST_CELL + Vector2i(3, 0))
    pcomp._approach(apc)
    TestHelper.assert_true(pcomp._pending_transport == apc, "approach registers pending transport")
    TestHelper.assert_eq(mc.get_target_position(), apc.global_position, "targets the APC cell")
    # ...then arrival adjacent to the APC boards it.
    trooper.position = CellUtil.cell_to_world(TEST_CELL + Vector2i(1, 0))
    pcomp._on_arrived(trooper.global_position)
    var t := apc.get_node("TransportComponent") as TransportComponent
    TestHelper.assert_eq(t.current_passengers, 1, "arrival boards adjacent stationary transport")
    TestHelper.assert_true(pcomp._pending_transport == null, "pending cleared after attempt")
    apc.queue_free()
    trooper.queue_free()


func test_arrival_skips_when_far():
    var apc := _make_transport_entity(4)
    apc.position = CellUtil.cell_to_world(TEST_CELL + Vector2i(10, 0))
    var trooper := _make_infantry("Trooper")
    var pcomp := trooper.get_node("PassengerComponent") as PassengerComponent
    pcomp._pending_transport = apc
    pcomp._on_arrived(trooper.global_position)
    var t := apc.get_node("TransportComponent") as TransportComponent
    TestHelper.assert_eq(t.current_passengers, 0, "distant transport is not boarded")
    apc.queue_free()


func test_arrival_skips_when_transport_gone():
    var apc := _make_transport_entity(4)
    var trooper := _make_infantry("Trooper")
    var pcomp := trooper.get_node("PassengerComponent") as PassengerComponent
    pcomp._pending_transport = apc
    _tree_root().remove_child(apc)
    apc.queue_free()
    pcomp._on_arrived(trooper.global_position)
    TestHelper.assert_true(pcomp._pending_transport == null, "pending cleared for dead transport")


func test_arrival_skips_when_transport_moving():
    var apc := _make_transport_entity(4)
    _make_mc(apc, MovementController.State.MOVING)
    var trooper := _make_infantry("Trooper")
    var pcomp := trooper.get_node("PassengerComponent") as PassengerComponent
    pcomp._pending_transport = apc
    pcomp._on_arrived(trooper.global_position)
    var t := apc.get_node("TransportComponent") as TransportComponent
    TestHelper.assert_eq(t.current_passengers, 0, "moving transport is not boarded")
    apc.queue_free()


func test_detached_passenger_state_preserved():
    var apc := _make_transport_entity(4)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var trooper := _make_infantry("Trooper")
    var stats := trooper.get_node("StatsComponent") as StatsComponent
    stats.player_id = 77
    TestHelper.assert_true(t.board(trooper), "trooper boards")
    t.eject_all()
    var after := (trooper.get_node("StatsComponent") as StatsComponent).player_id
    TestHelper.assert_eq(after, 77, "passenger state survives the ride")
    TestHelper.assert_true(trooper.is_inside_tree(), "ejected passenger is back on the field")
    apc.queue_free()


# --- Exact-target boarding approach ---


func test_approach_targets_apc_cell_exactly():
    _ensure_grid()
    var apc := _make_transport_entity(4)
    var trooper := _make_infantry("Trooper")
    var mc := _make_mc(trooper)
    var apc_cell := CellUtil.world_to_cell(apc.global_position)
    # Mark the APC's cell occupied the way a vehicle would be — a normal move
    # would relocate the destination to a neighboring free cell.
    _sh._grid[CellUtil.cell_key(apc_cell)] = [
        {"node": apc, "mc": MovementController.new()},
    ]
    trooper.position = CellUtil.cell_to_world(apc_cell + Vector2i(3, 0))
    var pcomp := trooper.get_node("PassengerComponent") as PassengerComponent
    pcomp._approach(apc)
    TestHelper.assert_true(pcomp._pending_transport == apc, "approach registers pending transport")
    TestHelper.assert_eq(
        mc.get_target_position(), apc.global_position, "destination stays on the APC's cell"
    )
    TestHelper.assert_true(mc._exact_target, "exact-target mode active")
    _sh._grid.erase(CellUtil.cell_key(apc_cell))
    apc.queue_free()
    trooper.queue_free()


func test_exact_target_arrives_on_occupied_cell():
    _ensure_grid()
    var walker := Node3D.new()
    walker.name = "Walker"
    _tree_root().add_child(walker)
    var mc := _make_mc(walker)
    var cell := Vector2i(30, 30)
    var target := CellUtil.cell_to_world(cell)
    walker.position = target
    _sh._grid[CellUtil.cell_key(cell)] = [
        {"node": Node3D.new(), "mc": MovementController.new()},
    ]
    mc._exact_target = true
    mc._waypoints = PackedVector3Array([target])
    mc._state = MovementController.State.WAIT
    var arrived_count := [0]
    mc.arrived.connect(func(_p: Vector3) -> void: arrived_count[0] += 1)
    mc._physics_process(0.016)
    TestHelper.assert_true(
        mc._state == MovementController.State.IDLE, "settles onto the occupied cell"
    )
    TestHelper.assert_true(arrived_count[0] == 1, "arrived fires for exact-target moves")
    _sh._grid.erase(CellUtil.cell_key(cell))
    walker.queue_free()


func test_normal_move_waits_on_occupied_cell():
    _ensure_grid()
    var walker := Node3D.new()
    walker.name = "Walker"
    _tree_root().add_child(walker)
    var mc := _make_mc(walker)
    var cell := Vector2i(31, 31)
    var target := CellUtil.cell_to_world(cell)
    walker.position = target
    _sh._grid[CellUtil.cell_key(cell)] = [
        {"node": Node3D.new(), "mc": MovementController.new()},
    ]
    mc._waypoints = PackedVector3Array([target])
    mc._state = MovementController.State.WAIT
    var arrived_count := [0]
    mc.arrived.connect(func(_p: Vector3) -> void: arrived_count[0] += 1)
    mc._physics_process(0.016)
    TestHelper.assert_true(
        mc._state == MovementController.State.WAIT, "normal moves wait on occupied cells"
    )
    TestHelper.assert_true(arrived_count[0] == 0, "no arrival while the cell stays occupied")
    _sh._grid.erase(CellUtil.cell_key(cell))
    walker.queue_free()


func test_approach_adjacent_walks_to_center_before_boarding():
    _ensure_grid()
    var apc := _make_transport_entity(4)
    var trooper := _make_infantry("Trooper")
    var mc := _make_mc(trooper)
    var pcomp := trooper.get_node("PassengerComponent") as PassengerComponent
    var t := apc.get_node("TransportComponent") as TransportComponent
    # Adjacent infantry must not vanish instantly: it walks to the APC's
    # center first, and only arrival boards it.
    pcomp._approach(apc)
    TestHelper.assert_eq(t.current_passengers, 0, "adjacent infantry does not board instantly")
    TestHelper.assert_true(pcomp._pending_transport == apc, "approach registers pending transport")
    TestHelper.assert_eq(mc.get_target_position(), apc.global_position, "walks to the APC center")
    TestHelper.assert_true(mc._exact_target, "walk uses exact-target mode")
    pcomp._on_arrived(apc.global_position)
    TestHelper.assert_eq(t.current_passengers, 1, "arrival at the APC center boards")
    apc.queue_free()
    trooper.queue_free()


func test_redirect_move_clears_pending_board():
    _ensure_grid()
    var apc := _make_transport_entity(4)
    var trooper := _make_infantry("Trooper")
    var mc := _make_mc(trooper)
    var pcomp := trooper.get_node("PassengerComponent") as PassengerComponent
    var t := apc.get_node("TransportComponent") as TransportComponent
    pcomp._approach(apc)
    # Player redirects with a plain move order: the pending board must drop,
    # so arriving near the transport later never auto-boards.
    mc.set_target_position(CellUtil.cell_to_world(TEST_CELL + Vector2i(5, 5)))
    pcomp._on_arrived(trooper.global_position)
    TestHelper.assert_eq(t.current_passengers, 0, "redirected infantry does not board")
    TestHelper.assert_true(pcomp._pending_transport == null, "pending cleared on redirect")
    TestHelper.assert_true(
        not mc.arrived.is_connected(pcomp._on_arrived), "arrived disconnected after redirect"
    )
    apc.queue_free()
    trooper.queue_free()


func test_move_after_stop_does_not_board():
    _ensure_grid()
    var apc := _make_transport_entity(4)
    var trooper := _make_infantry("Trooper")
    var mc := _make_mc(trooper)
    var pcomp := trooper.get_node("PassengerComponent") as PassengerComponent
    var t := apc.get_node("TransportComponent") as TransportComponent
    pcomp._approach(apc)
    mc.stop()
    TestHelper.assert_true(pcomp._pending_transport != null, "stop alone keeps the board order")
    # The next player move (stop then redirect) supersedes the stale board.
    mc.set_target_position(CellUtil.cell_to_world(TEST_CELL + Vector2i(6, 6)))
    pcomp._on_arrived(trooper.global_position)
    TestHelper.assert_eq(t.current_passengers, 0, "infantry does not board after redirect")
    TestHelper.assert_true(pcomp._pending_transport == null, "pending cleared on next move")
    apc.queue_free()
    trooper.queue_free()


func test_board_water_parked_apc_stops_at_shore():
    _ensure_grid()
    _ts.set_land_type(TEST_CELL, "water")
    var apc := _make_transport_entity(4)
    var trooper := _make_infantry("Trooper")
    trooper.position = CellUtil.cell_to_world(TEST_CELL + Vector2i(3, 0))
    var mc := _make_mc(trooper)
    # Make the water cell unreachable the way a real infantry locomotor
    # would (water-blocked pathing): the path must end on a shore cell, and
    # the straight final leg must NOT extend onto the water.
    var apc_cell := CellUtil.world_to_cell(apc.global_position)
    _sh._blocked_cells[CellUtil.cell_key(apc_cell)] = true
    var pcomp := trooper.get_node("PassengerComponent") as PassengerComponent
    pcomp._approach(apc)
    var last_cell := CellUtil.world_to_cell(mc.get_target_position())
    (
        TestHelper
        . assert_true(
            _ts.get_land_type(last_cell) != "water",
            "final waypoint stays on land, not the water cell: %s" % last_cell,
        )
    )
    # Arrival at the shore cell (1 cell away) still boards via the range check.
    trooper.position = CellUtil.cell_to_world(TEST_CELL + Vector2i(1, 0))
    pcomp._on_arrived(trooper.global_position)
    var t := apc.get_node("TransportComponent") as TransportComponent
    TestHelper.assert_eq(t.current_passengers, 1, "shore arrival boards the water-parked APC")
    _sh._blocked_cells.erase(CellUtil.cell_key(apc_cell))
    _ts.set_land_type(TEST_CELL, "clear")
    apc.queue_free()
    trooper.queue_free()


func test_board_failure_sidesteps():
    var apc := _make_transport_entity(1)
    var t := apc.get_node("TransportComponent") as TransportComponent
    var filler := _make_infantry("Filler")
    TestHelper.assert_true(t.board(filler), "filler takes the only seat")
    var trooper := _make_infantry("Trooper")
    var mc := _make_mc(trooper)
    var pcomp := trooper.get_node("PassengerComponent") as PassengerComponent
    pcomp._pending_transport = apc
    pcomp._on_arrived(trooper.global_position)
    TestHelper.assert_eq(t.current_passengers, 1, "full transport unchanged")
    TestHelper.assert_true(
        mc._state != MovementController.State.IDLE, "failed board issues a sidestep move"
    )
    TestHelper.assert_true(not mc._exact_target, "sidestep is a normal relocated move")
    apc.queue_free()
    trooper.queue_free()
