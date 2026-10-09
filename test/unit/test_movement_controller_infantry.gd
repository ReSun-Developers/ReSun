extends Node

# MovementController tests — crush mechanics, cursor resolution, and order generation

var _ts: Node = null


func test_crush_kills_enemy():
    var sh := SpatialHash.instance
    if sh == null:
        TestHelper.fail("SpatialHash not available")
        return
    sh._grid.clear()
    var cell := Vector2i(5, 5)
    var key: int = CellUtil.cell_key(cell)
    var enemy := Node3D.new()
    var enemy_stats := StatsComponent.new()
    enemy_stats.entity_type = EntityData.EntityType.INFANTRY
    enemy_stats.player_id = 1
    enemy_stats.crushable = true
    enemy_stats.current_health = 100
    enemy.add_child(enemy_stats)
    add_child(enemy)
    var entry := {
        "node": enemy,
        "mc": null,
        "entity_type": EntityData.EntityType.INFANTRY,
        "player_id": 1,
    }
    sh._grid[key] = [entry]
    # get_crushable_enemies returns the enemy for a crusher on player 0
    var enemies: Array = sh.get_crushable_enemies_on_cell(cell, 0)
    sh._grid.erase(key)
    (
        TestHelper
        . assert_true(
            enemies.size() == 1 and enemies[0] == enemy,
            (
                "crusher identifies enemy infantry for crush: expected 1 enemy, got %d"
                % enemies.size()
            ),
        )
    )
    remove_child(enemy)
    enemy.free()


func test_crush_does_not_kill_friendly():
    var sh := SpatialHash.instance
    if sh == null:
        TestHelper.fail("SpatialHash not available")
        return
    sh._grid.clear()
    var cell := Vector2i(5, 5)
    var key: int = CellUtil.cell_key(cell)
    var friendly := Node3D.new()
    var friendly_stats := StatsComponent.new()
    friendly_stats.entity_type = EntityData.EntityType.INFANTRY
    friendly_stats.player_id = 0
    friendly_stats.crushable = true
    friendly.add_child(friendly_stats)
    var entry := {
        "node": friendly,
        "mc": null,
        "entity_type": EntityData.EntityType.INFANTRY,
        "player_id": 0,
    }
    sh._grid[key] = [entry]
    var enemies: Array = sh.get_crushable_enemies_on_cell(cell, 0)
    sh._grid.erase(key)
    (
        TestHelper
        . assert_true(
            enemies.is_empty(),
            (
                "crusher does not identify friendly infantry as crushable: "
                + "friendly infantry returned as crushable enemy"
            ),
        )
    )
    friendly.free()


func test_crush_does_not_affect_non_crushable():
    var sh := SpatialHash.instance
    if sh == null:
        TestHelper.fail("SpatialHash not available")
        return
    sh._grid.clear()
    var cell := Vector2i(5, 5)
    var key: int = CellUtil.cell_key(cell)
    var enemy := Node3D.new()
    var enemy_stats := StatsComponent.new()
    enemy_stats.entity_type = EntityData.EntityType.INFANTRY
    enemy_stats.player_id = 1
    enemy_stats.crushable = false
    enemy.add_child(enemy_stats)
    var entry := {
        "node": enemy,
        "mc": null,
        "entity_type": EntityData.EntityType.INFANTRY,
        "player_id": 1,
    }
    sh._grid[key] = [entry]
    var enemies: Array = sh.get_crushable_enemies_on_cell(cell, 0)
    sh._grid.erase(key)
    (
        TestHelper
        . assert_true(
            enemies.is_empty(),
            (
                "crush does not affect non-crushable infantry: "
                + "non-crushable infantry returned as crushable enemy"
            ),
        )
    )
    enemy.free()


# --- order-cursor tests (derived from get_order_for_target) ---


func test_arrival_detach_skips_post_emit_tail():
    # Boarding detaches the passenger inside the arrived handler, mid-callback.
    # The cell-tracking tail after the emit must not read the detached parent.
    var sh := SpatialHash.instance
    if sh == null:
        TestHelper.fail("SpatialHash not available")
        return
    sh._blocked_cells.clear()
    var root := Engine.get_main_loop().root as Node
    var walker := Node3D.new()
    walker.name = "Walker"
    root.add_child(walker)
    var mc := MovementController.new()
    walker.add_child(mc)
    var cell := Vector2i(47, 47)
    var target := CellUtil.cell_to_world(cell)
    walker.global_position = target
    mc._waypoints = PackedVector3Array([target])
    mc._state = MovementController.State.MOVING
    mc._last_position = walker.global_position
    var detached := [false]
    mc.arrived.connect(
        func(_p: Vector3) -> void:
            root.remove_child(walker)
            detached[0] = true
    )
    mc._physics_process(0.016)
    TestHelper.assert_true(detached[0], "arrival subscriber detached the mover")
    TestHelper.assert_true(not walker.is_inside_tree(), "walker left the tree mid-callback")
    TestHelper.assert_true(mc._state == MovementController.State.IDLE, "arrival completed")
    TestHelper.assert_eq(
        mc._last_position, target, "tail skipped: last position keeps the arrival value"
    )
    walker.free()


# --- Scatter gate tests ---


func test_scatter_skipped_with_free_neighbor():
    # A free adjacent cell means the mover can sidestep itself — neighbors
    # must not be shoved (this is what relocated idle vehicles before).
    var sh := SpatialHash.instance
    if sh == null:
        TestHelper.fail("SpatialHash not available")
        return
    sh._grid.clear()
    sh._blocked_cells.clear()
    MovementController._scattered_this_frame.clear()
    var root := Engine.get_main_loop().root as Node
    var cell := Vector2i(48, 48)
    var mover := Node3D.new()
    mover.name = "Mover"
    root.add_child(mover)
    mover.global_position = CellUtil.cell_to_world(cell)
    var mc := MovementController.new()
    mover.add_child(mc)
    # One blocker to the east; every other neighbor free.
    var blocker := Node3D.new()
    blocker.name = "Blocker"
    root.add_child(blocker)
    blocker.global_position = CellUtil.cell_to_world(cell + Vector2i(1, 0))
    var blocker_mc := MovementController.new()
    blocker.add_child(blocker_mc)
    var key: int = CellUtil.cell_key(cell + Vector2i(1, 0))
    sh._grid[key] = [{"node": blocker, "mc": blocker_mc}]
    sh._blocked_cells[key] = true
    mc._scatter_blockers()
    TestHelper.assert_true(
        blocker_mc._waypoints.is_empty(), "single neighbor blocked: blocker not scattered"
    )
    TestHelper.assert_true(blocker_mc._state == MovementController.State.IDLE, "blocker stays idle")
    sh._grid.erase(key)
    sh._blocked_cells.erase(key)
    mover.free()
    blocker.free()


func test_scatter_fires_when_fully_boxed_in():
    # All 8 adjacent cells blocked: the mover truly cannot move — blockers
    # get scattered to make room.
    var sh := SpatialHash.instance
    if sh == null:
        TestHelper.fail("SpatialHash not available")
        return
    sh._grid.clear()
    sh._blocked_cells.clear()
    MovementController._scattered_this_frame.clear()
    var root := Engine.get_main_loop().root as Node
    var cell := Vector2i(50, 50)
    var mover := Node3D.new()
    mover.name = "Mover"
    root.add_child(mover)
    mover.global_position = CellUtil.cell_to_world(cell)
    var mc := MovementController.new()
    mover.add_child(mc)
    var blocker := Node3D.new()
    blocker.name = "Blocker"
    root.add_child(blocker)
    blocker.global_position = CellUtil.cell_to_world(cell + Vector2i(1, 0))
    var blocker_mc := MovementController.new()
    blocker.add_child(blocker_mc)
    for dx in range(-1, 2):
        for dz in range(-1, 2):
            if dx == 0 and dz == 0:
                continue
            var ncell := cell + Vector2i(dx, dz)
            var nkey: int = CellUtil.cell_key(ncell)
            sh._blocked_cells[nkey] = true
            if ncell == cell + Vector2i(1, 0):
                sh._grid[nkey] = [{"node": blocker, "mc": blocker_mc}]
    mc._scatter_blockers()
    TestHelper.assert_true(
        blocker_mc._waypoints.size() > 0, "fully boxed in: blocker gets scattered"
    )
    TestHelper.assert_true(
        blocker_mc._state != MovementController.State.IDLE, "blocker moves off the ring"
    )
    sh._grid.clear()
    sh._blocked_cells.clear()
    mover.free()
    blocker.free()


func test_order_cursor_ground_move_valid():
    var mc := MovementController.new()
    mc.name = "MovementController"
    var entity := Node3D.new()
    entity.add_child(mc)

    var cursor := TestHelper.order_cursor(mc, null)
    TestHelper.assert_eq(cursor, CursorState.Type.MOVE, "ground target -> MOVE")

    entity.queue_free()


func test_order_cursor_entity_default_without_force_move():
    var mc := MovementController.new()
    mc.name = "MovementController"
    var entity := Node3D.new()
    entity.add_child(mc)

    var target := Node3D.new()
    target.name = "SomeTarget"
    var cursor := TestHelper.order_cursor(mc, target)
    TestHelper.assert_eq(
        cursor, CursorState.Type.DEFAULT, "entity target without force-move -> DEFAULT"
    )

    entity.queue_free()
    target.queue_free()


func test_order_cursor_entity_move_with_force_move():
    var mc := MovementController.new()
    mc.name = "MovementController"
    var entity := Node3D.new()
    entity.add_child(mc)

    var target := Node3D.new()
    target.name = "SomeTarget"
    var order := mc.get_order_for_target(
        target, Vector2i.ZERO, Vector3.ZERO, {OrderResult.MOD_FORCE_MOVE: true}
    )
    TestHelper.assert_true(order != null, "force-move over entity -> order not null")
    TestHelper.assert_eq(order.cursor, CursorState.Type.MOVE, "force-move over entity -> MOVE")

    entity.queue_free()
    target.queue_free()


# --- get_order_for_target tests ---


func test_order_no_target_returns_move_order():
    var mc := MovementController.new()
    mc.name = "MovementController"
    var entity := Node3D.new()
    entity.add_child(mc)

    var target_pos := Vector3(10.0, 0.0, 20.0)
    var order := mc.get_order_for_target(null, Vector2i.ZERO, target_pos, {})

    TestHelper.assert_true(order != null, "no target -> order not null")
    TestHelper.assert_eq(order.cursor, CursorState.Type.MOVE, "cursor -> MOVE")
    TestHelper.assert_eq(order.priority, 5, "priority -> 5")
    TestHelper.assert_eq(order.target_pos, target_pos, "stores target_pos")

    entity.queue_free()


func test_order_with_target_returns_null():
    var mc := MovementController.new()
    mc.name = "MovementController"
    var entity := Node3D.new()
    entity.add_child(mc)

    var target := Node3D.new()
    target.name = "SomeTarget"
    var order := mc.get_order_for_target(target, Vector2i.ZERO, Vector3.ZERO, {})

    TestHelper.assert_true(order == null, "click target -> null (not a move order)")

    entity.queue_free()
    target.queue_free()


func test_order_queued_modifier():
    var mc := MovementController.new()
    mc.name = "MovementController"
    var entity := Node3D.new()
    entity.add_child(mc)

    var modifiers := {OrderResult.MOD_QUEUED: true}
    var order := mc.get_order_for_target(null, Vector2i.ZERO, Vector3.ZERO, modifiers)

    TestHelper.assert_true(order != null, "queued modifier -> order not null")
    TestHelper.assert_true(order.queued, "queued modifier -> order.queued = true")

    entity.queue_free()


# --- is_moving() tests ---


func test_is_moving_false_when_idle():
    var mc := MovementController.new()
    mc.name = "MovementController"
    var entity := Node3D.new()
    entity.add_child(mc)

    TestHelper.assert_eq(mc.is_moving(), false, "idle state -> is_moving() = false")

    entity.queue_free()


func test_is_moving_true_when_rotating():
    var mc := MovementController.new()
    mc.name = "MovementController"
    var entity := Node3D.new()
    entity.add_child(mc)
    mc._state = MovementController.State.ROTATING

    TestHelper.assert_eq(mc.is_moving(), true, "rotating state -> is_moving() = true")

    entity.queue_free()


func test_is_moving_true_when_moving():
    var mc := MovementController.new()
    mc.name = "MovementController"
    var entity := Node3D.new()
    entity.add_child(mc)
    mc._state = MovementController.State.MOVING

    TestHelper.assert_eq(mc.is_moving(), true, "moving state -> is_moving() = true")

    entity.queue_free()


func test_is_moving_true_when_wait():
    var mc := MovementController.new()
    mc.name = "MovementController"
    var entity := Node3D.new()
    entity.add_child(mc)
    mc._state = MovementController.State.WAIT

    TestHelper.assert_eq(mc.is_moving(), true, "wait state -> is_moving() = true")

    entity.queue_free()


func test_two_units_same_cell_get_distinct_slots():
    var cr := CellReservation.instance
    if cr == null:
        TestHelper.assert_true(false, "CellReservation not available")
        return
    cr.clear()
    var cell := Vector2i(30, 30)
    var entity_a := Node3D.new()
    var mc_a := MovementController.new()
    entity_a.add_child(mc_a)
    mc_a._parent = entity_a
    var entity_b := Node3D.new()
    var mc_b := MovementController.new()
    entity_b.add_child(mc_b)
    mc_b._parent = entity_b
    mc_a._assign_sub_slot_at_cell(cell)
    mc_b._assign_sub_slot_at_cell(cell)
    var distinct: bool = mc_a._assigned_slot != mc_b._assigned_slot
    var both_have: bool = mc_a._has_sub_slot and mc_b._has_sub_slot
    cr.clear()
    entity_a.queue_free()
    entity_b.queue_free()
    TestHelper.assert_true(distinct, "two units same cell get distinct sub-slots")
    TestHelper.assert_true(both_have, "both units hold a sub-slot")


func test_idle_occupant_slot_visible_to_new_arrival():
    var cr := CellReservation.instance
    var sh := SpatialHash.instance
    if cr == null or sh == null:
        TestHelper.assert_true(false, "CellReservation/SpatialHash not available")
        return
    cr.clear()
    sh._grid.clear()
    var cell := Vector2i(30, 30)
    var key := CellUtil.cell_key(cell)
    var idle_root := Node3D.new()
    var idle_mc := MovementController.new()
    idle_root.add_child(idle_mc)
    idle_mc._parent = idle_root
    idle_mc._assigned_slot = 0
    sh._grid[key] = [
        {
            "node": idle_root,
            "mc": idle_mc,
            "entity_type": EntityData.EntityType.INFANTRY,
            "player_id": 0,
        },
    ]
    var entity_b := Node3D.new()
    var mc_b := MovementController.new()
    entity_b.add_child(mc_b)
    mc_b._parent = entity_b
    mc_b._assign_sub_slot_at_cell(cell)
    var slot_b: int = mc_b._assigned_slot
    sh._grid.erase(key)
    cr.clear()
    idle_root.queue_free()
    entity_b.queue_free()
    TestHelper.assert_eq(slot_b, 1, "new arrival avoids idle occupant's slot")


func test_moving_occupant_does_not_block_slot():
    var cr := CellReservation.instance
    var sh := SpatialHash.instance
    if cr == null or sh == null:
        TestHelper.assert_true(false, "CellReservation/SpatialHash not available")
        return
    cr.clear()
    sh._grid.clear()
    var cell := Vector2i(30, 30)
    var key := CellUtil.cell_key(cell)
    var moving_root := Node3D.new()
    var moving_mc := MovementController.new()
    moving_root.add_child(moving_mc)
    moving_mc._parent = moving_root
    moving_mc._assigned_slot = 0
    moving_mc._state = MovementController.State.MOVING
    sh._grid[key] = [
        {
            "node": moving_root,
            "mc": moving_mc,
            "entity_type": EntityData.EntityType.INFANTRY,
            "player_id": 0,
        },
    ]
    var entity_b := Node3D.new()
    var mc_b := MovementController.new()
    entity_b.add_child(mc_b)
    mc_b._parent = entity_b
    mc_b._assign_sub_slot_at_cell(cell)
    var slot_b: int = mc_b._assigned_slot
    sh._grid.erase(key)
    cr.clear()
    moving_root.queue_free()
    entity_b.queue_free()
    TestHelper.assert_eq(slot_b, 0, "moving transit unit does not hold its slot")


func test_finish_stop_releases_sub_slot_claim():
    var cr := CellReservation.instance
    if cr == null:
        TestHelper.assert_true(false, "CellReservation not available")
        return
    cr.clear()
    var cell := Vector2i(30, 30)
    var entity := Node3D.new()
    var mc := MovementController.new()
    entity.add_child(mc)
    mc._parent = entity
    mc._assign_sub_slot_at_cell(cell)
    var before: int = cr.get_claim_count(cell)
    mc._finish_stop()
    var after: int = cr.get_claim_count(cell)
    cr.clear()
    entity.queue_free()
    TestHelper.assert_eq(before, 1, "move start holds a claim")
    TestHelper.assert_eq(after, 0, "finish stop releases the claim")


func test_full_cell_spreads_to_neighbor():
    var cr := CellReservation.instance
    if cr == null:
        TestHelper.assert_true(false, "CellReservation not available")
        return
    cr.clear()
    var target := Vector2i(30, 30)
    var owners: Array[Node3D] = []
    for i in CellSubPositions.get_slot_count():
        var owner := Node3D.new()
        add_child(owner)
        owners.append(owner)
        cr.reserve_sub_slot(target, owner)
    var entity := Node3D.new()
    var mc := MovementController.new()
    entity.add_child(mc)
    mc._parent = entity
    var free_cell := mc._find_nearest_free_sub_slot_cell(target)
    var spread: bool = free_cell != target
    cr.clear()
    for owner in owners:
        owner.queue_free()
    entity.queue_free()
    TestHelper.assert_true(spread, "full cell spreads to a neighbor")


func test_non_infantry_sharer_books_sub_slot():
    var cr := CellReservation.instance
    var sh := SpatialHash.instance
    if cr == null or sh == null or _ts == null:
        TestHelper.fail("CellReservation/SpatialHash/TerrainSystem not available")
        return
    cr.clear()
    _ts.init_grid(50, 50)
    var cell := Vector2i(40, 40)
    var entity := Node3D.new()
    var stats := StatsComponent.new()
    stats.entity_type = EntityData.EntityType.VEHICLE
    entity.add_child(stats)
    var mc := MovementController.new()
    entity.add_child(mc)
    mc._parent = entity
    mc._shares_cell = true
    _ts.add_child(entity)
    mc.set_target_position(CellUtil.cell_to_world(cell))
    var claim: int = cr.get_claim_count(cell)
    cr.clear()
    _ts.remove_child(entity)
    entity.queue_free()
    (
        TestHelper
        . assert_true(
            claim >= 1,
            (
                "non-infantry shares_cell unit books a sub-slot: "
                + "non-infantry shares_cell unit books a sub-slot"
            ),
        )
    )


func test_resource_entity_does_not_block_idle_cell():
    var sh := SpatialHash.instance
    if sh == null:
        TestHelper.fail("SpatialHash not available")
        return
    sh._grid.clear()
    var cell := Vector2i(20, 20)
    var key := CellUtil.cell_key(cell)
    var resource_node := Node3D.new()
    resource_node.name = "TibField"
    add_child(resource_node)
    var resource_entry := {
        "node": resource_node,
        "mc": null,
        "entity_type": EntityData.EntityType.TERRAIN,
        "player_id": -1,
    }
    sh._grid[key] = [resource_entry]
    var entity := Node3D.new()
    var mc := MovementController.new()
    entity.add_child(mc)
    mc._parent = entity
    var occupied: bool = mc._is_cell_occupied_by_idle(cell)
    sh._grid.erase(key)
    entity.queue_free()
    resource_node.queue_free()
    TestHelper.assert_eq(
        occupied, false, "resource-only cell is not occupied: expected false, got true"
    )


func test_idle_unit_still_blocks_idle_cell():
    var sh := SpatialHash.instance
    if sh == null:
        TestHelper.fail("SpatialHash not available")
        return
    sh._grid.clear()
    var cell := Vector2i(21, 21)
    var key := CellUtil.cell_key(cell)
    var idle_root := Node3D.new()
    var idle_mc := MovementController.new()
    idle_root.add_child(idle_mc)
    idle_mc._parent = idle_root
    add_child(idle_root)
    var entry := {
        "node": idle_root,
        "mc": idle_mc,
        "entity_type": EntityData.EntityType.INFANTRY,
        "player_id": 0,
    }
    sh._grid[key] = [entry]
    var entity := Node3D.new()
    var mc := MovementController.new()
    entity.add_child(mc)
    mc._parent = entity
    var occupied: bool = mc._is_cell_occupied_by_idle(cell)
    sh._grid.erase(key)
    entity.queue_free()
    idle_root.queue_free()
    TestHelper.assert_eq(occupied, true, "idle unit cell is occupied: expected true, got false")


func test_building_still_blocks_idle_cell():
    var sh := SpatialHash.instance
    if sh == null:
        TestHelper.fail("SpatialHash not available")
        return
    sh._grid.clear()
    var cell := Vector2i(22, 22)
    var key := CellUtil.cell_key(cell)
    sh._building_cells[key] = true
    var entity := Node3D.new()
    var mc := MovementController.new()
    entity.add_child(mc)
    mc._parent = entity
    var occupied: bool = mc._is_cell_occupied_by_idle(cell)
    sh._building_cells.erase(key)
    entity.queue_free()
    TestHelper.assert_eq(occupied, true, "building cell is occupied: expected true, got false")


func test_non_sharing_vehicle_does_not_book():
    var cr := CellReservation.instance
    if cr == null or SpatialHash.instance == null or _ts == null:
        TestHelper.fail("CellReservation/SpatialHash/TerrainSystem not available")
        return
    cr.clear()
    _ts.init_grid(50, 50)
    var cell := Vector2i(45, 45)
    var entity := Node3D.new()
    var mc := MovementController.new()
    entity.add_child(mc)
    mc._parent = entity
    _ts.add_child(entity)
    mc.set_target_position(CellUtil.cell_to_world(cell))
    var claim: int = cr.get_claim_count(cell)
    cr.clear()
    _ts.remove_child(entity)
    entity.queue_free()
    TestHelper.assert_true(
        claim == 0, "non-sharing vehicle books no sub-slot: expected 0 claims, got %d" % claim
    )


# --- scatter/nudge ownership (#164) ---
# Opponents must never move each other's units: a waiting unit's wait scatter
# and cell nudges may only re-target own/allied idle units.

const _SCATTER_A_CELL := Vector2i(30, 30)
const _SCATTER_B_CELL := Vector2i(31, 30)


func _reset_scatter_fixture() -> void:
    var sh := SpatialHash.instance
    if sh:
        sh._grid.clear()
        sh._blocked_cells.clear()
        sh._building_cells.clear()
        sh._shared_cell_counts.clear()
        sh.clear_reservations()
    MovementController._scattered_this_frame.clear()
    if CellReservation.instance:
        CellReservation.instance.clear()
    if _ts:
        _ts.init_grid(50, 50)
        _ts.clear()
    PlayerManager.get_player_data(0).team_id = 1
    PlayerManager.get_player_data(1).team_id = 2


func _make_scatter_unit(player: int, cell: Vector2i) -> Array:
    var entity := Node3D.new()
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.entity_type = EntityData.EntityType.INFANTRY
    stats.player_id = player
    entity.add_child(stats)
    var mc := MovementController.new()
    entity.add_child(mc)
    mc._parent = entity
    Engine.get_main_loop().root.add_child(entity)
    entity.global_position = CellUtil.cell_to_world(cell)
    return [entity, mc]


func _register_idle_blocker(entity: Node3D, mc: MovementController, cell: Vector2i) -> void:
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    var key := CellUtil.cell_key(cell)
    SpatialHash.instance._grid[key] = [
        {
            "node": entity,
            "mc": mc,
            "entity_type": stats.entity_type if stats else -1,
            "player_id": stats.player_id if stats else -1,
            "state": mc._state,
            "shares": false,
        },
    ]
    SpatialHash.instance._blocked_cells[key] = true


func _cleanup_scatter_units(pair_a: Array, pair_b: Array) -> void:
    SpatialHash.instance._grid.erase(CellUtil.cell_key(_SCATTER_B_CELL))
    SpatialHash.instance._blocked_cells.clear()
    SpatialHash.instance.clear_reservations()
    var root: Node = Engine.get_main_loop().root
    root.remove_child(pair_a[0] as Node)
    (pair_a[0] as Node).free()
    root.remove_child(pair_b[0] as Node)
    (pair_b[0] as Node).free()
    PlayerManager.get_player_data(0).team_id = 1
    PlayerManager.get_player_data(1).team_id = 2


func _box_in(cell: Vector2i) -> void:
    # `_scatter_blockers` bails unless every neighbor is blocked; the fixture
    # must reproduce that or the wait-scatter branch is never reached.
    for dx in range(-1, 2):
        for dz in range(-1, 2):
            if dx == 0 and dz == 0:
                continue
            SpatialHash.instance._blocked_cells[CellUtil.cell_key(cell + Vector2i(dx, dz))] = true


func _trigger_wait_scatter(mc: MovementController) -> void:
    _box_in(_SCATTER_A_CELL)
    mc._state = MovementController.State.WAIT
    mc._waypoints = PackedVector3Array([CellUtil.cell_to_world(_SCATTER_A_CELL)])
    mc._wait_time = 0.0
    mc._wait_threshold = 10.0
    mc._physics_process(0.3)


func _blocker_retargeted(mc: MovementController) -> bool:
    return mc._waypoints.size() > 1 and mc._state != MovementController.State.IDLE


func test_wait_scatter_moves_own_blocker():
    _reset_scatter_fixture()
    var pair_a := _make_scatter_unit(0, _SCATTER_A_CELL)
    var pair_b := _make_scatter_unit(0, _SCATTER_B_CELL)
    var mc_a: MovementController = pair_a[1]
    var mc_b: MovementController = pair_b[1]
    _register_idle_blocker(pair_b[0], mc_b, _SCATTER_B_CELL)
    TestHelper.assert_true(
        not PlayerManager.is_enemy(0, 0), "precondition: a unit is never its own enemy"
    )
    _trigger_wait_scatter(mc_a)
    var retargeted: bool = _blocker_retargeted(mc_b)
    _cleanup_scatter_units(pair_a, pair_b)
    TestHelper.assert_true(retargeted, "wait scatter still re-targets a same-player idle blocker")


func test_wait_scatter_moves_allied_blocker():
    _reset_scatter_fixture()
    PlayerManager.get_player_data(1).team_id = 1
    var pair_a := _make_scatter_unit(0, _SCATTER_A_CELL)
    var pair_b := _make_scatter_unit(1, _SCATTER_B_CELL)
    var mc_a: MovementController = pair_a[1]
    var mc_b: MovementController = pair_b[1]
    _register_idle_blocker(pair_b[0], mc_b, _SCATTER_B_CELL)
    TestHelper.assert_true(
        not PlayerManager.is_enemy(0, 1), "precondition: same-team players are allied"
    )
    _trigger_wait_scatter(mc_a)
    var retargeted: bool = _blocker_retargeted(mc_b)
    _cleanup_scatter_units(pair_a, pair_b)
    TestHelper.assert_true(retargeted, "wait scatter still re-targets an allied idle blocker")


func test_wait_scatter_leaves_enemy_blocker_alone():
    _reset_scatter_fixture()
    var pair_a := _make_scatter_unit(0, _SCATTER_A_CELL)
    var pair_b := _make_scatter_unit(1, _SCATTER_B_CELL)
    var mc_a: MovementController = pair_a[1]
    var mc_b: MovementController = pair_b[1]
    _register_idle_blocker(pair_b[0], mc_b, _SCATTER_B_CELL)
    TestHelper.assert_true(
        PlayerManager.is_enemy(0, 1), "precondition: players 0 and 1 start on enemy teams"
    )
    _trigger_wait_scatter(mc_a)
    var untouched: bool = (
        mc_b._state == MovementController.State.IDLE and mc_b._waypoints.is_empty()
    )
    _cleanup_scatter_units(pair_a, pair_b)
    TestHelper.assert_true(untouched, "wait scatter must not issue a move order to an enemy unit")


func test_nudge_moves_own_blocker():
    _reset_scatter_fixture()
    var pair_a := _make_scatter_unit(0, _SCATTER_A_CELL)
    var pair_b := _make_scatter_unit(0, _SCATTER_B_CELL)
    var mc_a: MovementController = pair_a[1]
    var mc_b: MovementController = pair_b[1]
    _register_idle_blocker(pair_b[0], mc_b, _SCATTER_B_CELL)
    var nudged: bool = mc_a.nudge_from_cell(_SCATTER_B_CELL)
    var retargeted: bool = _blocker_retargeted(mc_b)
    _cleanup_scatter_units(pair_a, pair_b)
    TestHelper.assert_true(nudged, "nudge reports success for a same-player idle blocker")
    TestHelper.assert_true(retargeted, "nudge still re-targets a same-player idle blocker")


func test_nudge_leaves_enemy_blocker_alone():
    _reset_scatter_fixture()
    var pair_a := _make_scatter_unit(0, _SCATTER_A_CELL)
    var pair_b := _make_scatter_unit(1, _SCATTER_B_CELL)
    var mc_a: MovementController = pair_a[1]
    var mc_b: MovementController = pair_b[1]
    _register_idle_blocker(pair_b[0], mc_b, _SCATTER_B_CELL)
    TestHelper.assert_true(
        PlayerManager.is_enemy(0, 1), "precondition: players 0 and 1 start on enemy teams"
    )
    var nudged: bool = mc_a.nudge_from_cell(_SCATTER_B_CELL)
    var untouched: bool = (
        mc_b._state == MovementController.State.IDLE and mc_b._waypoints.is_empty()
    )
    _cleanup_scatter_units(pair_a, pair_b)
    TestHelper.assert_true(not nudged, "nudge must not report success on an enemy unit")
    TestHelper.assert_true(untouched, "nudge must not issue a move order to an enemy unit")
