extends Node

# SelectionManager tests — selection state management
# Note: selected_entities is Array[SelectComponent], so we can't mock with Node

const SELECT_COMPONENT_SCENE: PackedScene = preload("res://scenes/components/SelectComponent.tscn")
const MOUSE_HANDLER_SCENE: PackedScene = preload("res://scenes/hud/MouseHandler.tscn")

const BOUNDS_GRID := Vector2i(50, 50)
const BOUNDS_IN_CELL := Vector2i(40, 40)

var _sm: Node = null
var _ts: Node = null
var _ss: Node = null
var _pm: Node = null

var _emit_count := 0
var _last_selection_arg: Array[SelectComponent] = []

var _bounds_saved_insets := Vector4i(0, 0, 0, 0)
var _bounds_saved_grid_cells := Vector2i(64, 64)
var _bounds_saved_fog := Vector2i(0, 0)


func _on_selection_changed_counter(selected: Array[SelectComponent]) -> void:
    _emit_count += 1
    _last_selection_arg = selected


func test_deselect_all_clears():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var count: int = _sm.selected_entities.size()
    TestHelper.assert_true(count == 0, "deselect_all clears selection: expected 0, got %d" % count)


func test_external_set_is_selected_reconciles_same_frame():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var entity := Node3D.new()
    entity.add_to_group("selectable")
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    select_comp.name = "SelectComponent"
    entity.add_child(select_comp)
    _sm.add_child(entity)

    _sm._synchronize_visual_selection()

    select_comp.set_is_selected(true)
    (
        TestHelper
        . assert_true(
            _sm.selected_entities.size() == 1 and _sm.selected_entities[0] == select_comp,
            (
                "external set_is_selected(true) reconciles same frame: "
                + "expected component in selection after external select"
            ),
        )
    )
    select_comp.set_is_selected(false)
    (
        TestHelper
        . assert_true(
            not _sm.selected_entities.has(select_comp),
            (
                "external set_is_selected(false) reconciles same frame: "
                + "expected component removed after external deselect"
            ),
        )
    )

    _sm.deselect_all()
    entity.free()


func test_throttled_sync_not_every_frame():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    _sm._selection_sync_counter = 0
    var entity := Node3D.new()
    entity.add_to_group("selectable")
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    select_comp.name = "SelectComponent"
    select_comp.set_is_selected(true)
    entity.add_child(select_comp)
    _sm.add_child(entity)

    for i in 5:
        _sm._process(0.016)
    (
        TestHelper
        . assert_true(
            _sm.selected_entities.is_empty(),
            "throttled sync skips frames: not reconciled before 6th frame",
        )
    )

    _sm._process(0.016)
    (
        TestHelper
        . assert_true(
            _sm.selected_entities.size() == 1,
            (
                "throttled sync runs on 6th frame: expected reconciliation, got %d"
                % _sm.selected_entities.size()
            ),
        )
    )

    _sm.deselect_all()
    entity.free()


func test_select_entity_ignores_null():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    _sm.select_entity(null)
    var count: int = _sm.selected_entities.size()
    TestHelper.assert_true(
        count == 0, "select_entity ignores null: expected 0 after null, got %d" % count
    )


func test_synchronize_visual_selection_adds_missing_component():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var entity := Node3D.new()
    entity.add_to_group("selectable")
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    select_comp.name = "SelectComponent"
    select_comp.set_is_selected(true)
    entity.add_child(select_comp)
    _sm.add_child(entity)

    _sm._synchronize_visual_selection()

    (
        TestHelper
        . assert_true(
            _sm.selected_entities.size() == 1 and _sm.selected_entities[0] == select_comp,
            (
                "visual selection is synchronized into SelectionManager: "
                + "visual selection should be synchronized into SelectionManager"
            ),
        )
    )

    _sm.deselect_all()
    entity.free()


func test_deselect_all_clears_unmanaged_visual_selection():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var entity := Node3D.new()
    entity.add_to_group("selectable")
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    select_comp.name = "SelectComponent"
    select_comp.set_is_selected(true)
    entity.add_child(select_comp)
    _sm.add_child(entity)

    _sm.deselect_all()

    (
        TestHelper
        . assert_true(
            not select_comp.is_selected,
            (
                "deselect_all clears unmanaged visual selection: "
                + "deselect_all should clear unmanaged visual selection"
            ),
        )
    )

    entity.free()


func test_add_entity_allows_enemy_player():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var pm := get_node_or_null("/root/PlayerManager")
    var local_pid: int = pm.get_local_player_id() if pm else 0
    var entity := Node3D.new()
    entity.name = "EnemyEntity"
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity.add_child(select_comp)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = local_pid + 1
    entity.add_child(stats)
    _sm.add_child(entity)

    _sm.add_entity(select_comp)

    (
        TestHelper
        . assert_true(
            _sm.selected_entities.size() == 1,
            (
                "add_entity allows enemy player entity for viewing: "
                + "add_entity should allow enemy entity (selectable for viewing)"
            ),
        )
    )
    _sm.deselect_all()
    entity.free()


func test_add_entity_allows_local_player():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var pm := get_node_or_null("/root/PlayerManager")
    var local_pid: int = pm.get_local_player_id() if pm else 0
    var entity := Node3D.new()
    entity.name = "FriendlyEntity"
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity.add_child(select_comp)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = local_pid
    entity.add_child(stats)
    _sm.add_child(entity)

    _sm.add_entity(select_comp)

    (
        TestHelper
        . assert_true(
            _sm.selected_entities.size() == 1,
            "add_entity allows local player entity: add_entity should allow local player entity",
        )
    )
    _sm.deselect_all()
    entity.free()


func test_add_entity_allows_unset_player_id():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var entity := Node3D.new()
    entity.name = "UnsetEntity"
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity.add_child(select_comp)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = -1
    entity.add_child(stats)
    _sm.add_child(entity)

    _sm.add_entity(select_comp)

    (
        TestHelper
        . assert_true(
            _sm.selected_entities.size() == 1,
            "add_entity allows unset player_id (-1): add_entity should allow unset player_id (-1)",
        )
    )
    _sm.deselect_all()
    entity.free()


func test_add_entity_allows_no_stats_component():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var entity := Node3D.new()
    entity.name = "NoStatsEntity"
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity.add_child(select_comp)
    _sm.add_child(entity)

    _sm.add_entity(select_comp)

    (
        TestHelper
        . assert_true(
            _sm.selected_entities.size() == 1,
            (
                "add_entity allows entity without StatsComponent: "
                + "add_entity should allow entity without StatsComponent"
            ),
        )
    )
    _sm.deselect_all()
    entity.free()


func test_is_local_entity_filters_enemy():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_pid: int = pm.get_local_player_id() if pm else 0
    var entity := Node3D.new()
    entity.name = "EnemyEntity"
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity.add_child(select_comp)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = local_pid + 1
    entity.add_child(stats)
    _sm.add_child(entity)

    (
        TestHelper
        . assert_true(
            not _sm._is_local_entity(select_comp),
            (
                "_is_local_entity returns false for enemy: "
                + "_is_local_entity should return false for enemy"
            ),
        )
    )
    entity.free()


func test_is_local_entity_allows_local():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_pid: int = pm.get_local_player_id() if pm else 0
    var entity := Node3D.new()
    entity.name = "FriendlyEntity"
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity.add_child(select_comp)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = local_pid
    entity.add_child(stats)
    _sm.add_child(entity)

    (
        TestHelper
        . assert_true(
            _sm._is_local_entity(select_comp),
            (
                "_is_local_entity returns true for local player: "
                + "_is_local_entity should return true for local player"
            ),
        )
    )
    entity.free()


func test_find_sharer_cell_empty():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    # Ensure 50×50 grid so world→cell conversion is deterministic
    if _ts:
        _ts.init_grid(50, 50)
    CellReservation.instance.clear()
    var target := Vector2i(10, 10)
    # Centered: cell (10,10) on 50×50 → world (-79, 0, -79)
    var result: Vector2i = _sm._find_sharer_cell(Vector3(-79, 0, -79))
    TestHelper.assert_true(
        result == target,
        "_find_sharer_cell returns target when empty: expected %s, got %s" % [target, result]
    )


func test_find_sharer_cell_at_capacity():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    # Ensure 50×50 grid so world→cell conversion is deterministic
    if _ts:
        _ts.init_grid(50, 50)
    CellReservation.instance.clear()
    # In-visible cell on 50×50 (orders only target inside the visible diamond);
    # a full cell here must spiral to an in-area neighbor, not an off-map cell.
    var target := Vector2i(30, 30)
    var claimers: Array[Node3D] = []
    for i in CellSubPositions.get_slot_count():
        var claimer := Node3D.new()
        add_child(claimer)
        claimers.append(claimer)
        CellReservation.instance.reserve_sub_slot(target, claimer)
    # Centered coords: cell (30,30) on 50×50 grid → world (-39, 0, -39)
    var result: Vector2i = _sm._find_sharer_cell(Vector3(-39, 0, -39))
    for claimer in claimers:
        claimer.queue_free()
    CellReservation.instance.clear()
    (
        TestHelper
        . assert_true(
            result != target,
            (
                "_find_sharer_cell spirals when target is full: "
                + "should have spiraled away from full cell"
            ),
        )
    )


## Review P1-3: at level > 0 the infantry stand-off spiral must only land on a
## live deck. With the deck destination occupied and a deck authored only on the
## target, every deckless neighbor is skipped, so both `_find_sharer_cell` and
## `_fallback_target` stay on a real deck surface instead of claiming empty air.
func test_level_one_sharer_cell_requires_deck():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var sh := SpatialHash.instance
    if sh == null:
        TestHelper.fail("SpatialHash not available")
        return
    if _ts:
        _ts.init_grid(50, 50)
    CellReservation.instance.clear()
    sh.clear_reservations()
    var target := Vector2i(30, 30)
    var deck_key := CellUtil.cell_level_key(target, 1)
    var had_deck: bool = sh._bridge_cells.has(deck_key)
    sh._bridge_cells[deck_key] = {
        "surface_height": 4.0,
        "is_end": false,
        "piece_id": "sharer_deck",
        "level": 1,
    }
    # Occupy the deck destination so the spiral must move away from it.
    TestHelper.assert_true(sh.reserve_cell(target, 1), "fixture: deck destination reserved")

    var sharer_cell: Vector2i = _sm._find_sharer_cell(CellUtil.cell_to_world(target), 1)
    var sharer_on_deck: bool = sh.has_bridge_on_cell(sharer_cell, 1)
    var fallback: Vector3 = _sm._fallback_target(CellUtil.cell_to_world(target), 1)
    var fallback_on_deck: bool = sh.has_bridge_on_cell(CellUtil.world_to_cell(fallback), 1)

    sh.clear_reservations()
    if not had_deck:
        sh._bridge_cells.erase(deck_key)
    CellReservation.instance.clear()

    (
        TestHelper
        . assert_true(
            sharer_on_deck,
            "level-1 sharer cell sits on a live deck: got %s (deckless)" % sharer_cell,
        )
    )
    (
        TestHelper
        . assert_true(
            fallback_on_deck,
            (
                "level-1 fallback target sits on a live deck: got %s"
                % CellUtil.world_to_cell(fallback)
            ),
        )
    )


func test_deselect_all_emits_selection_changed_once():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var entities: Array[Node3D] = []
    for i in 5:
        var entity := Node3D.new()
        entity.name = "EmitCounter%d" % i
        entity.add_to_group("selectable")
        var sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
        sc.name = "SelectComponent"
        entity.add_child(sc)
        _sm.add_child(entity)
        entities.append(entity)
        _sm.add_entity(sc)
    _emit_count = 0
    _last_selection_arg = []
    _sm.selection_changed.connect(_on_selection_changed_counter)
    _sm.deselect_all()
    _sm.selection_changed.disconnect(_on_selection_changed_counter)
    for e in entities:
        _sm.remove_child(e)
        e.free()
    TestHelper.assert_eq(_emit_count, 1, "deselect_all emits selection_changed exactly once")
    TestHelper.assert_true(
        _last_selection_arg.is_empty(), "the single emit carries an empty selection"
    )
    TestHelper.assert_true(
        _sm.selected_entities.is_empty(), "selected_entities is empty after deselect_all"
    )


func test_non_infantry_sharer_uses_cell_distribution():
    if _sm == null or _ts == null:
        TestHelper.fail("SelectionManager/TerrainSystem not injected")
        return
    var rules := GlobalRules.get_current()
    var saved_shroud: bool = rules.shroud_enabled
    var saved_fog: bool = rules.fog_of_war
    rules.shroud_enabled = false
    rules.fog_of_war = false
    _ts.init_grid(50, 50)
    _sm.deselect_all()
    CellReservation.instance.clear()
    var entity := Node3D.new()
    entity.name = "VehicleSharer"
    var stats := StatsComponent.new()
    stats.player_id = -1
    stats.entity_type = EntityData.EntityType.VEHICLE
    entity.add_child(stats)
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    mc._shares_cell = true
    _sm.add_child(entity)
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    select_comp.name = "SelectComponent"
    entity.add_child(select_comp)
    _sm.select_entity(select_comp)
    _sm.request_move(Vector3(-79, 0, -79))
    var routed: bool = _sm._pending_moves.size() == 1
    _sm.deselect_all()
    CellReservation.instance.clear()
    entity.queue_free()
    rules.shroud_enabled = saved_shroud
    rules.fog_of_war = saved_fog
    (
        TestHelper
        . assert_true(
            routed,
            (
                (
                    "non-infantry sharer routed via cell distribution: "
                    + "expected 1 pending sharer move, got %d"
                )
                % _sm._pending_moves.size()
            ),
        )
    )


# ========================================
# Implode destination overlap guards (#mixed-selection)
# ========================================


func test_find_sharer_cell_avoids_reserved_vehicle_destination():
    if _sm == null or _ts == null:
        TestHelper.fail("SelectionManager/TerrainSystem not injected")
        return
    _ts.init_grid(50, 50)
    CellReservation.instance.clear()
    SpatialHash.instance.clear_reservations()
    # Cell (30,30) sits inside the runner's order area (same anchor as the
    # capacity test); reserve it the way a vehicle destination (or a
    # selection's force-reserved own cell) would be.
    var target := Vector2i(30, 30)
    SpatialHash.instance._reserved[CellUtil.cell_key(target)] = true
    var result: Vector2i = _sm._find_sharer_cell(CellUtil.cell_to_world(target))
    SpatialHash.instance.clear_reservations()
    (
        TestHelper
        . assert_true(
            result != target,
            (
                "sharer cell avoids vehicle-reserved destination: got %s, expected a spiral cell"
                % result
            ),
        )
    )


func test_vehicle_destination_avoids_infantry_claims():
    if _sm == null or _ts == null:
        TestHelper.fail("SelectionManager/TerrainSystem not injected")
        return
    var rules := GlobalRules.get_current()
    var saved_shroud: bool = rules.shroud_enabled
    var saved_fog: bool = rules.fog_of_war
    rules.shroud_enabled = false
    rules.fog_of_war = false
    _ts.init_grid(50, 50)
    _sm.deselect_all()
    CellReservation.instance.clear()
    SpatialHash.instance.clear_reservations()
    # Infantry sub-slot claim in flight on the target cell: a vehicle in
    # implode mode must not reserve that cell as its parking spot.
    var claimed_cell := Vector2i(30, 30)
    var claimer := Node3D.new()
    add_child(claimer)
    CellReservation.instance.reserve_sub_slot(claimed_cell, claimer)
    var entity := Node3D.new()
    entity.name = "ImplodeVehicle"
    var stats := StatsComponent.new()
    stats.player_id = -1
    stats.entity_type = EntityData.EntityType.VEHICLE
    entity.add_child(stats)
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    _sm.add_child(entity)
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    select_comp.name = "SelectComponent"
    entity.add_child(select_comp)
    _sm.select_entity(select_comp)
    _sm.request_move(CellUtil.cell_to_world(Vector2i(30, 30)), true)
    var routed: bool = _sm._pending_moves.size() == 1
    var landed := (
        CellUtil.world_to_cell(_sm._pending_moves[0][1] as Vector3) if routed else claimed_cell
    )
    _sm.deselect_all()
    CellReservation.instance.clear()
    SpatialHash.instance.clear_reservations()
    entity.queue_free()
    claimer.queue_free()
    rules.shroud_enabled = saved_shroud
    rules.fog_of_war = saved_fog
    TestHelper.assert_true(routed, "vehicle got exactly one pending move")
    (
        TestHelper
        . assert_true(
            landed != claimed_cell,
            "vehicle destination avoids claimed infantry cell: got %s" % landed,
        )
    )


func test_implode_mixed_selection_destinations_do_not_overlap():
    if _sm == null or _ts == null:
        TestHelper.fail("SelectionManager/TerrainSystem not injected")
        return
    var rules := GlobalRules.get_current()
    var saved_shroud: bool = rules.shroud_enabled
    var saved_fog: bool = rules.fog_of_war
    rules.shroud_enabled = false
    rules.fog_of_war = false
    _ts.init_grid(50, 50)
    _sm.deselect_all()
    CellReservation.instance.clear()
    SpatialHash.instance.clear_reservations()
    var vehicles: Array[Node3D] = []
    var infantry: Array[Node3D] = []
    for i in 2:
        var vehicle := Node3D.new()
        vehicle.name = "ImplodeV%d" % i
        var vstats := StatsComponent.new()
        vstats.player_id = -1
        vstats.entity_type = EntityData.EntityType.VEHICLE
        vehicle.add_child(vstats)
        var vmc := MovementController.new()
        vehicle.add_child(vmc)
        _sm.add_child(vehicle)
        var vsc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
        vehicle.add_child(vsc)
        _sm.select_entity(vsc, true)
        vehicles.append(vehicle)
    for i in 3:
        var unit := Node3D.new()
        unit.name = "ImplodeI%d" % i
        var istats := StatsComponent.new()
        istats.player_id = -1
        istats.entity_type = EntityData.EntityType.INFANTRY
        unit.add_child(istats)
        var imc := MovementController.new()
        unit.add_child(imc)
        imc._shares_cell = true
        _sm.add_child(unit)
        var isc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
        unit.add_child(isc)
        _sm.select_entity(isc, true)
        infantry.append(unit)
    _sm.request_move(CellUtil.cell_to_world(Vector2i(30, 30)), true)
    var vehicle_cells: Array[Vector2i] = []
    var infantry_cells: Array[Vector2i] = []
    for entry in _sm._pending_moves:
        var sc := entry[0] as SelectComponent
        var cell := CellUtil.world_to_cell(entry[1] as Vector3)
        if (sc.get_parent() as Node3D) in vehicles:
            vehicle_cells.append(cell)
        else:
            infantry_cells.append(cell)
    _sm.deselect_all()
    CellReservation.instance.clear()
    SpatialHash.instance.clear_reservations()
    for v in vehicles:
        v.queue_free()
    for u in infantry:
        u.queue_free()
    rules.shroud_enabled = saved_shroud
    rules.fog_of_war = saved_fog
    (
        TestHelper
        . assert_true(
            vehicle_cells.size() == 2,
            "both vehicles routed: got %d of %s" % [vehicle_cells.size(), vehicle_cells],
        )
    )
    (
        TestHelper
        . assert_true(
            infantry_cells.size() == 3,
            "all infantry routed: got %d of %s" % [infantry_cells.size(), infantry_cells],
        )
    )
    (
        TestHelper
        . assert_true(
            vehicle_cells[0] != vehicle_cells[1],
            "vehicles do not share a destination cell: %s" % [vehicle_cells],
        )
    )
    for vcell in vehicle_cells:
        (
            TestHelper
            . assert_true(
                not infantry_cells.has(vcell),
                (
                    "no infantry shares a vehicle destination: vehicles=%s infantry=%s"
                    % [vehicle_cells, infantry_cells]
                ),
            )
        )


# ========================================
# Visible-bounds selection gate (#318)
# ========================================


func _bounds_setup() -> void:
    if _ts:
        _ts.init_grid(BOUNDS_GRID.x, BOUNDS_GRID.y)
    _bounds_saved_insets = Vector4i(
        BoundsSystem.left_inset,
        BoundsSystem.right_inset,
        BoundsSystem.top_inset,
        BoundsSystem.bottom_inset,
    )
    _bounds_saved_grid_cells = BoundsSystem.grid_cells
    var rules := GlobalRules.get_current()
    _bounds_saved_fog = Vector2i(
        1 if rules and rules.fog_of_war else 0, 1 if rules and rules.shroud_enabled else 0
    )
    BoundsSystem.grid_cells = BOUNDS_GRID
    BoundsSystem.left_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.x
    BoundsSystem.right_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.y
    BoundsSystem.top_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.z
    BoundsSystem.bottom_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.w
    if _pm:
        _pm._players.clear()
        _pm._local_player_id = 0
        _pm._init_defaults()
    if rules:
        rules.fog_of_war = false
        rules.shroud_enabled = false


func _bounds_teardown() -> void:
    BoundsSystem.left_inset = _bounds_saved_insets.x
    BoundsSystem.right_inset = _bounds_saved_insets.y
    BoundsSystem.top_inset = _bounds_saved_insets.z
    BoundsSystem.bottom_inset = _bounds_saved_insets.w
    BoundsSystem.grid_cells = _bounds_saved_grid_cells
    var rules := GlobalRules.get_current()
    if rules:
        rules.fog_of_war = _bounds_saved_fog.x == 1
        rules.shroud_enabled = _bounds_saved_fog.y == 1


func _make_bounds_entity(cell: Vector2i) -> Node3D:
    var entity := Node3D.new()
    entity.name = "BoundsEntity"
    var sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    sc.name = "SelectComponent"
    entity.add_child(sc)
    _sm.add_child(entity)
    entity.global_position = CellUtil.cell_to_world(cell)
    return entity


func _select_comp_of(entity: Node3D) -> SelectComponent:
    return entity.get_node("SelectComponent") as SelectComponent


## A play-boundary pair: [outside_cell, inside_cell] are orthogonal neighbors,
## so both project close together and one drag rect can span both. Scans every
## out-of-play cell — cells near the diamond tips have no in-play neighbor.
func _play_boundary_pair() -> Array[Vector2i]:
    var extent: Vector2i = CellUtil.get_diamond_extent(BOUNDS_GRID)
    for x in extent.x:
        for z in extent.y:
            var cell := Vector2i(x, z)
            if BoundsSystem.is_in_map_bounds(cell) and not BoundsSystem.is_in_play_area(cell):
                for n in [
                    cell + Vector2i(-1, 0),
                    cell + Vector2i(1, 0),
                    cell + Vector2i(0, -1),
                    cell + Vector2i(0, 1),
                ]:
                    if BoundsSystem.is_in_play_area(n):
                        return [cell, n]
    return [Vector2i(-1, -1), Vector2i(-1, -1)]


func test_click_select_rejects_entity_outside_visible_bounds():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _bounds_setup()
    var out_cell: Vector2i = _play_boundary_pair()[0]
    var setup_ok: bool = (
        BoundsSystem.is_in_map_bounds(out_cell) and not BoundsSystem.is_in_play_area(out_cell)
    )
    var entity := _make_bounds_entity(out_cell)
    var sc := _select_comp_of(entity)
    _sm.deselect_all()
    _sm.select_entity(sc)
    var rejected: bool = not _sm.is_entity_selected(sc) and _sm.selected_entities.is_empty()
    _sm.deselect_all()
    entity.free()
    _bounds_teardown()
    TestHelper.assert_true(
        setup_ok, "fixture: scanned cell is inside map bounds but outside the play area"
    )
    TestHelper.assert_true(rejected, "click-select rejects entity outside the visible play diamond")


func test_click_select_allows_entity_inside_visible_bounds():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _bounds_setup()
    var setup_ok: bool = BoundsSystem.is_in_play_area(BOUNDS_IN_CELL)
    var entity := _make_bounds_entity(BOUNDS_IN_CELL)
    var sc := _select_comp_of(entity)
    _sm.deselect_all()
    _sm.select_entity(sc)
    var selected: bool = _sm.is_entity_selected(sc) and _sm.selected_entities.size() == 1
    _sm.deselect_all()
    entity.free()
    _bounds_teardown()
    TestHelper.assert_true(setup_ok, "fixture: center cell is inside the play area")
    TestHelper.assert_true(selected, "click-select allows entity inside visible bounds")


func test_box_select_skips_entity_outside_visible_bounds():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _bounds_setup()
    var pair := _play_boundary_pair()
    var out_cell: Vector2i = pair[0]
    var in_cell: Vector2i = pair[1]
    var setup_ok: bool = (
        not BoundsSystem.is_in_play_area(out_cell) and BoundsSystem.is_in_play_area(in_cell)
    )
    var in_entity := _make_bounds_entity(in_cell)
    var out_entity := _make_bounds_entity(out_cell)
    in_entity.add_to_group("drag_selectable")
    out_entity.add_to_group("drag_selectable")

    # Top-down orthographic camera rig; the drag rect covers BOTH projections so
    # geometry alone cannot exclude the out-of-bounds entity — only the gate can.
    var pivot := CameraController.new()
    pivot.name = "CameraPivot"
    var cam := Camera3D.new()
    cam.name = "Camera3D"
    cam.projection = Camera3D.PROJECTION_ORTHOGONAL
    cam.size = 120.0
    pivot.add_child(cam)
    _sm.add_child(pivot)
    cam.look_at_from_position(Vector3(0, 80, 0), Vector3.ZERO, Vector3(0, 0, -1))

    var mh := MOUSE_HANDLER_SCENE.instantiate() as MouseHandler
    _sm.add_child(mh)
    mh.camera_controller = pivot

    var p_in := cam.unproject_position(in_entity.global_position)
    var p_out := cam.unproject_position(out_entity.global_position)
    var lo := Vector2(minf(p_in.x, p_out.x), minf(p_in.y, p_out.y))
    var hi := Vector2(maxf(p_in.x, p_out.x), maxf(p_in.y, p_out.y))
    var rect := Rect2(lo - Vector2(2.0, 2.0), hi - lo + Vector2(4.0, 4.0))
    var rig_ok: bool = rect.has_point(p_in) and rect.has_point(p_out) and p_in != p_out

    _sm.deselect_all()
    mh._select_entities_2d_projected(rect)
    var in_selected: bool = _sm.is_entity_selected(_select_comp_of(in_entity))
    var out_selected: bool = _sm.is_entity_selected(_select_comp_of(out_entity))
    _sm.deselect_all()
    mh.free()
    pivot.free()
    out_entity.free()
    in_entity.free()
    _bounds_teardown()
    TestHelper.assert_true(setup_ok, "fixture: pair straddles the play-area boundary")
    TestHelper.assert_true(rig_ok, "fixture: drag rect covers both entity projections")
    TestHelper.assert_true(in_selected, "box-select keeps entity inside visible bounds")
    TestHelper.assert_true(not out_selected, "box-select filters entity outside visible bounds")


func test_add_entity_allows_entity_outside_visible_bounds():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _bounds_setup()
    var out_cell: Vector2i = _play_boundary_pair()[0]
    var entity := _make_bounds_entity(out_cell)
    var sc := _select_comp_of(entity)
    _sm.deselect_all()
    _sm.add_entity(sc)
    var added: bool = _sm.is_entity_selected(sc) and _sm.selected_entities.size() == 1
    _sm.deselect_all()
    entity.free()
    _bounds_teardown()
    TestHelper.assert_true(added, "programmatic add_entity is not gated by visible bounds")


func test_shroud_gate_still_blocks_inside_visible_bounds():
    if _sm == null or _ss == null:
        TestHelper.fail("SelectionManager/ShroudSystem not injected")
        return
    _bounds_setup()
    var rules := GlobalRules.get_current()
    rules.shroud_enabled = true
    rules.fog_of_war = false
    var entity := _make_bounds_entity(BOUNDS_IN_CELL)
    var sc := _select_comp_of(entity)
    _sm.deselect_all()
    _sm.select_entity(sc)
    var blocked: bool = not _sm.is_entity_selected(sc)
    _ss.explore_area(0, BOUNDS_IN_CELL, 1)
    _sm.select_entity(sc)
    var allowed_after_reveal: bool = _sm.is_entity_selected(sc)
    _sm.deselect_all()
    entity.free()
    _bounds_teardown()
    TestHelper.assert_true(
        blocked, "fog/shroud gate still blocks unrevealed entity inside visible bounds"
    )
    TestHelper.assert_true(allowed_after_reveal, "revealed in-bounds entity becomes selectable")


# ========================================
# Ownership exclusivity (#166) — no mixed own+enemy selection
# ========================================


func _make_owner_entity(player_id: int) -> Node3D:
    var entity := Node3D.new()
    entity.name = "OwnerEntity%d" % player_id
    var sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    sc.name = "SelectComponent"
    entity.add_child(sc)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    entity.add_child(stats)
    _sm.add_child(entity)
    entity.global_position = CellUtil.cell_to_world(BOUNDS_IN_CELL)
    return entity


func test_shift_click_enemy_clears_local_selection():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _bounds_setup()
    var pm := get_node_or_null("/root/PlayerManager")
    var local_pid: int = pm.get_local_player_id() if pm else 0
    var local := _make_owner_entity(local_pid)
    var enemy := _make_owner_entity(local_pid + 1)
    var local_sc := _select_comp_of(local)
    var enemy_sc := _select_comp_of(enemy)

    _sm.deselect_all()
    _sm.select_entity(local_sc)
    var local_first: bool = _sm.is_entity_selected(local_sc)
    _sm.select_entity(enemy_sc, true)
    var enemy_only: bool = _sm.selected_entities.size() == 1 and _sm.is_entity_selected(enemy_sc)
    var local_cleared: bool = not _sm.is_entity_selected(local_sc)

    _sm.deselect_all()
    local.free()
    enemy.free()
    _bounds_teardown()
    TestHelper.assert_true(local_first, "fixture: local unit selected first")
    TestHelper.assert_true(local_cleared, "shift-click enemy clears the local selection")
    TestHelper.assert_true(enemy_only, "enemy becomes the sole selection (no mix)")


func test_shift_click_local_clears_enemy_selection():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _bounds_setup()
    var pm := get_node_or_null("/root/PlayerManager")
    var local_pid: int = pm.get_local_player_id() if pm else 0
    var local := _make_owner_entity(local_pid)
    var enemy := _make_owner_entity(local_pid + 1)
    var local_sc := _select_comp_of(local)
    var enemy_sc := _select_comp_of(enemy)

    _sm.deselect_all()
    _sm.select_entity(enemy_sc)
    var enemy_first: bool = _sm.is_entity_selected(enemy_sc)
    _sm.select_entity(local_sc, true)
    var local_only: bool = _sm.selected_entities.size() == 1 and _sm.is_entity_selected(local_sc)
    var enemy_cleared: bool = not _sm.is_entity_selected(enemy_sc)

    _sm.deselect_all()
    local.free()
    enemy.free()
    _bounds_teardown()
    TestHelper.assert_true(enemy_first, "fixture: enemy selected first")
    TestHelper.assert_true(enemy_cleared, "shift-click local unit clears the enemy selection")
    TestHelper.assert_true(local_only, "local unit becomes the sole selection (no mix)")


func test_shift_click_second_enemy_replaces_first():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _bounds_setup()
    var pm := get_node_or_null("/root/PlayerManager")
    var local_pid: int = pm.get_local_player_id() if pm else 0
    var enemy_a := _make_owner_entity(local_pid + 1)
    var enemy_b := _make_owner_entity(local_pid + 2)
    var enemy_a_sc := _select_comp_of(enemy_a)
    var enemy_b_sc := _select_comp_of(enemy_b)

    _sm.deselect_all()
    _sm.select_entity(enemy_a_sc)
    _sm.select_entity(enemy_b_sc, true)
    var b_only: bool = _sm.selected_entities.size() == 1 and _sm.is_entity_selected(enemy_b_sc)
    var a_cleared: bool = not _sm.is_entity_selected(enemy_a_sc)

    _sm.deselect_all()
    enemy_a.free()
    enemy_b.free()
    _bounds_teardown()
    TestHelper.assert_true(a_cleared, "second enemy click clears the first")
    TestHelper.assert_true(b_only, "only the newest enemy stays selected")


func test_shift_click_second_local_still_adds():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _bounds_setup()
    var pm := get_node_or_null("/root/PlayerManager")
    var local_pid: int = pm.get_local_player_id() if pm else 0
    var local_a := _make_owner_entity(local_pid)
    var local_b := _make_owner_entity(local_pid)
    var local_a_sc := _select_comp_of(local_a)
    var local_b_sc := _select_comp_of(local_b)

    _sm.deselect_all()
    _sm.select_entity(local_a_sc)
    _sm.select_entity(local_b_sc, true)
    var both: bool = (
        _sm.selected_entities.size() == 2
        and _sm.is_entity_selected(local_a_sc)
        and _sm.is_entity_selected(local_b_sc)
    )

    _sm.deselect_all()
    local_a.free()
    local_b.free()
    _bounds_teardown()
    TestHelper.assert_true(both, "two local units coexist (shift adds, no clearing)")


func test_plain_click_selects_lone_enemy():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _bounds_setup()
    var pm := get_node_or_null("/root/PlayerManager")
    var local_pid: int = pm.get_local_player_id() if pm else 0
    var enemy := _make_owner_entity(local_pid + 1)
    var enemy_sc := _select_comp_of(enemy)

    _sm.deselect_all()
    _sm.select_entity(enemy_sc)
    var selected: bool = _sm.selected_entities.size() == 1 and _sm.is_entity_selected(enemy_sc)

    _sm.deselect_all()
    enemy.free()
    _bounds_teardown()
    TestHelper.assert_true(selected, "a lone enemy is selectable for viewing")


func test_box_select_while_enemy_selected_clears_enemy():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _bounds_setup()
    var pm := get_node_or_null("/root/PlayerManager")
    var local_pid: int = pm.get_local_player_id() if pm else 0
    var local := _make_owner_entity(local_pid)
    local.add_to_group("drag_selectable")
    var enemy := _make_owner_entity(local_pid + 1)
    var local_sc := _select_comp_of(local)
    var enemy_sc := _select_comp_of(enemy)

    var pivot := CameraController.new()
    pivot.name = "CameraPivot"
    var cam := Camera3D.new()
    cam.name = "Camera3D"
    cam.projection = Camera3D.PROJECTION_ORTHOGONAL
    cam.size = 120.0
    pivot.add_child(cam)
    _sm.add_child(pivot)
    cam.look_at_from_position(Vector3(0, 80, 0), Vector3.ZERO, Vector3(0, 0, -1))

    var mh := MOUSE_HANDLER_SCENE.instantiate() as MouseHandler
    _sm.add_child(mh)
    mh.camera_controller = pivot

    var p := cam.unproject_position(local.global_position)
    var rect := Rect2(p - Vector2(4, 4), Vector2(8, 8))

    _sm.deselect_all()
    _sm.select_entity(enemy_sc)
    mh._select_entities_2d_projected(rect)
    var local_selected: bool = _sm.is_entity_selected(local_sc)
    var enemy_cleared: bool = not _sm.is_entity_selected(enemy_sc)

    _sm.deselect_all()
    mh.free()
    pivot.free()
    local.free()
    enemy.free()
    _bounds_teardown()
    TestHelper.assert_true(local_selected, "box-select selects the local unit")
    TestHelper.assert_true(enemy_cleared, "box-select clears a selected enemy (no mix)")


func test_hotkey_stop_skips_enemy_selection():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _bounds_setup()
    var pm := get_node_or_null("/root/PlayerManager")
    var local_pid: int = pm.get_local_player_id() if pm else 0
    var local := _make_owner_entity(local_pid)
    var enemy := _make_owner_entity(local_pid + 1)
    var local_harvest := HarvestComponent.new()
    local_harvest.name = "HarvestComponent"
    local.add_child(local_harvest)
    var enemy_harvest := HarvestComponent.new()
    enemy_harvest.name = "HarvestComponent"
    enemy.add_child(enemy_harvest)

    var mh := MOUSE_HANDLER_SCENE.instantiate() as MouseHandler
    _sm.add_child(mh)
    mh.selection_manager = _sm

    local_harvest._state = HarvestComponent.State.SEEK_NODE
    enemy_harvest._state = HarvestComponent.State.SEEK_NODE
    _sm.deselect_all()
    _sm.select_entity(_select_comp_of(local))
    mh.apply_selection_hotkey(true)
    var local_stopped: bool = local_harvest._state == HarvestComponent.State.IDLE

    enemy_harvest._state = HarvestComponent.State.SEEK_NODE
    _sm.select_entity(_select_comp_of(enemy))
    mh.apply_selection_hotkey(true)
    var enemy_untouched: bool = enemy_harvest._state == HarvestComponent.State.SEEK_NODE

    _sm.deselect_all()
    mh.free()
    local.free()
    enemy.free()
    _bounds_teardown()
    TestHelper.assert_true(local_stopped, "stop hotkey cancels a local harvester")
    TestHelper.assert_true(
        enemy_untouched, "stop hotkey never commands a selected enemy (issue #166)"
    )


func test_hotkey_stop_clears_engagement():
    # stop-command's "Stop during combat" scenario: Stop reverts an engaged
    # unit to idle (entity target or ground position) while leaving guard free
    # to acquire again. mc.stop() alone never does this — an engaged unit
    # firing at a fixed point is IDLE, so no movement signal fires.
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _bounds_setup()
    var pm := get_node_or_null("/root/PlayerManager")
    var local_pid: int = pm.get_local_player_id() if pm else 0
    var local := _make_owner_entity(local_pid)
    var combat := CombatComponent.new()
    combat.name = "CombatComponent"
    local.add_child(combat)
    var target := _make_owner_entity(local_pid + 1)

    var mh := MOUSE_HANDLER_SCENE.instantiate() as MouseHandler
    _sm.add_child(mh)
    mh.selection_manager = _sm

    _sm.deselect_all()
    _sm.select_entity(_select_comp_of(local))

    combat.set_target(target)
    var engaged_before: bool = combat.is_engaged()
    mh.apply_selection_hotkey(true)
    var entity_cleared: bool = not combat.is_engaged() and combat.get_target() == null

    combat.set_ground_target(local.global_position + Vector3(4.0, 0.0, 0.0))
    var ground_before: bool = combat.is_engaged()
    mh.apply_selection_hotkey(true)
    var ground_cleared: bool = not combat.is_engaged()

    mh.queue_free()
    _sm.remove_child(target)
    target.free()
    _sm.remove_child(local)
    local.free()
    _bounds_teardown()
    TestHelper.assert_true(engaged_before, "unit was engaged before Stop")
    TestHelper.assert_true(entity_cleared, "Stop ends an entity fire mission")
    TestHelper.assert_true(ground_before, "ground engagement active before Stop")
    TestHelper.assert_true(ground_cleared, "Stop ends a ground engagement")


func test_has_rally_receiver_requires_rally_component():
    _bounds_setup()
    var with_rally := _make_bounds_entity(Vector2i(3, 3))
    var rally := RallyPointComponent.new()
    rally.name = "RallyPointComponent"
    with_rally.add_child(rally)
    var without_rally := _make_bounds_entity(Vector2i(4, 3))
    _sm.add_entity(_select_comp_of(without_rally))
    TestHelper.assert_true(not _sm.has_rally_receiver(), "no rally component -> false")
    _sm.deselect_all()
    _sm.add_entity(_select_comp_of(with_rally))
    TestHelper.assert_true(_sm.has_rally_receiver(), "selected rally receiver -> true")
    _sm.deselect_all()
    _sm.remove_child(with_rally)
    with_rally.free()
    _sm.remove_child(without_rally)
    without_rally.free()
    _bounds_teardown()
