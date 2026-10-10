extends Node

# GuardComponent Mode A stand-and-shoot (#261): weapon-range acquisition,
# hold-ground fire, idle/power/move gates, throttle.

var _sh: Node = null
var _pm: Node = null
var _ef: Node = null
var _ts: Node = null

const RANGE_CELLS: float = 5.0
const RANGE_WORLD: float = RANGE_CELLS * CellUtil.CELL_SIZE

## Vision fixture: GuardComponent only acquires what the scanning house can see
## (#446), so placed entities must sit in cells their house has explored. Cells
## are unexplored by default in these suites. Reset afterwards so later suites
## do not inherit explored state from this one.
const VISION_PLAYERS: Array[int] = [0, 1, 2, 3]
const VISION_RADIUS: int = 6


func _make_weapon(range_cells: float = RANGE_CELLS) -> WeaponData:
    var w := WeaponData.new()
    w.id = "GUARD_TEST_WEAPON"
    w.damage = 10
    w.attack_range = range_cells
    w.rate_of_fire = 1.0
    w.warhead = "SA"
    return w


var _saved_teams: Dictionary = {}


func _set_teams(a: int, b: int) -> void:
    if _pm == null:
        return
    for id in [a, b]:
        if not _saved_teams.has(id):
            _saved_teams[id] = _pm.get_player_data(id).team_id
    _pm.get_player_data(a).team_id = a
    _pm.get_player_data(b).team_id = b


func _restore_teams() -> void:
    if _pm == null:
        return
    for id in _saved_teams:
        _pm.get_player_data(id).team_id = _saved_teams[id]
    _saved_teams.clear()


func _make_unit(
    player_id: int, with_guard: bool = true, with_mc: bool = false, with_power: bool = false
) -> Node3D:
    var entity := Node3D.new()
    entity.name = "GuardUnit"
    var combat := CombatComponent.new()
    combat.name = "CombatComponent"
    combat.weapons = [_make_weapon()]
    combat._init_cooldowns()
    entity.add_child(combat)
    if with_guard:
        var guard := GuardComponent.new()
        guard.name = "GuardComponent"
        entity.add_child(guard)
    if with_mc:
        var mc := MovementController.new()
        mc.name = "MovementController"
        entity.add_child(mc)
        mc._parent = entity
    if with_power:
        var power := PowerComponent.new()
        power.name = "PowerComponent"
        entity.add_child(power)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    stats.sight = 20
    entity.add_child(stats)
    return entity


func _make_enemy(player_id: int, with_health: bool = true) -> Node3D:
    var entity := Node3D.new()
    entity.name = "Enemy"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    entity.add_child(stats)
    if with_health:
        var health := HealthComponent.new()
        health.name = "HealthComponent"
        health.max_health = 100
        health.current_health = 100
        entity.add_child(health)
    return entity


func _place(root: Node, entity: Node3D, pos: Vector3) -> void:
    root.add_child(entity)
    entity.global_position = pos
    entity.add_to_group("entities")
    var cell := CellUtil.world_to_cell(pos)
    for pid in VISION_PLAYERS:
        ShroudSystem.explore_area(pid, cell, VISION_RADIUS)


func _reset_vision() -> void:
    for pid in VISION_PLAYERS:
        ShroudSystem.cover_shroud(pid)


func _rebuild() -> void:
    if _sh:
        _sh.rebuild()


func _tick_guard(entity: Node3D, times: int = 1, delta: float = 0.05) -> void:
    var guard := entity.get_node("GuardComponent") as GuardComponent
    guard._resolved = false
    guard._scan_timer = 0.0
    for i in times:
        guard._physics_process(delta)


func _cleanup(entities: Array) -> void:
    for e in entities:
        if is_instance_valid(e):
            if e.is_inside_tree():
                e.get_parent().remove_child(e)
            e.free()
    if _sh:
        _sh.rebuild()
    _restore_teams()
    _reset_vision()


func test_factory_attaches_guard_when_armed():
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    var data := EntityData.new()
    data.id = "guard_factory_armed"
    data.strength = 100
    data.owner = ["GDI"]
    data.weapons = [_make_weapon()]
    _ef._entity_cache[data.id] = data
    var entity: Node = _ef.create_entity(data.id)
    TestHelper.assert_true(entity != null, "armed entity created")
    if entity:
        TestHelper.assert_true(
            entity.get_node_or_null("CombatComponent") != null, "armed entity has CombatComponent"
        )
        TestHelper.assert_true(
            entity.get_node_or_null("GuardComponent") != null, "armed entity has GuardComponent"
        )
        entity.free()
    _ef._entity_cache.erase(data.id)


func test_factory_skips_guard_when_unarmed():
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    var data := EntityData.new()
    data.id = "guard_factory_unarmed"
    data.strength = 100
    data.owner = ["GDI"]
    _ef._entity_cache[data.id] = data
    var entity: Node = _ef.create_entity(data.id)
    TestHelper.assert_true(entity != null, "unarmed entity created")
    if entity:
        TestHelper.assert_true(
            entity.get_node_or_null("CombatComponent") == null,
            "unarmed entity has no CombatComponent"
        )
        TestHelper.assert_true(
            entity.get_node_or_null("GuardComponent") == null,
            "unarmed entity has no GuardComponent"
        )
        entity.free()
    _ef._entity_cache.erase(data.id)


func test_idle_guard_acquires_enemy_in_weapon_range():
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    var enemy := _make_enemy(1)
    _place(root, unit, Vector3(0, 0, 0))
    _place(root, enemy, Vector3(RANGE_WORLD - 1.0, 0, 0))
    _rebuild()
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_eq(combat.get_target(), enemy, "acquires enemy inside weapon range")
    TestHelper.assert_true(combat._hold_ground, "acquisition uses hold_ground")
    _cleanup([unit, enemy])


func test_enemy_beyond_weapon_range_not_acquired():
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    var enemy := _make_enemy(1)
    _place(root, unit, Vector3(0, 0, 0))
    # Beyond weapon range (sight is 20 on unit) — Mode A must ignore.
    _place(root, enemy, Vector3(RANGE_WORLD + 6.0, 0, 0))
    _rebuild()
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_true(combat.get_target() == null, "no acquire beyond weapon range")
    _cleanup([unit, enemy])


func test_friendly_and_neutral_ignored():
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    if not _saved_teams.has(2):
        _saved_teams[2] = _pm.get_player_data(2).team_id
    _pm.get_player_data(2).team_id = 0
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    var friendly := _make_enemy(2)
    var neutral := _make_enemy(-1)
    _place(root, unit, Vector3(0, 0, 0))
    _place(root, friendly, Vector3(4, 0, 0))
    _place(root, neutral, Vector3(6, 0, 0))
    _rebuild()
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_true(combat.get_target() == null, "friendly/neutral not acquired")
    _cleanup([unit, friendly, neutral])


func test_nearest_of_multiple_enemies():
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    var near := _make_enemy(1)
    var far := _make_enemy(1)
    _place(root, unit, Vector3(0, 0, 0))
    _place(root, near, Vector3(4, 0, 0))
    _place(root, far, Vector3(8, 0, 0))
    _rebuild()
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_eq(combat.get_target(), near, "nearest enemy selected")
    _cleanup([unit, near, far])


func test_hold_ground_clears_without_chase_when_target_leaves_range():
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    if _ts:
        _ts.init_grid(32, 32)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0, true, true)
    var enemy := _make_enemy(1)
    _place(root, unit, Vector3(0, 0, 0))
    _place(root, enemy, Vector3(RANGE_WORLD - 1.0, 0, 0))
    _rebuild()
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_eq(combat.get_target(), enemy, "acquired before range break")
    var mc := unit.get_node("MovementController") as MovementController
    var chase_moves := [0]
    mc.movement_started.connect(func(): chase_moves[0] += 1)
    var start_pos := unit.global_position
    # Target leaves weapon range; guard engagement must clear, not chase.
    enemy.global_position = Vector3(RANGE_WORLD + 20.0, 0, 0)
    _rebuild()
    for i in 5:
        combat._physics_process(0.05)
    TestHelper.assert_true(combat.get_target() == null, "hold-ground clears out-of-range target")
    TestHelper.assert_eq(chase_moves[0], 0, "hold-ground issues no movement_started (no chase)")
    TestHelper.assert_eq(unit.global_position, start_pos, "unit did not move (no chase)")
    TestHelper.assert_true(not mc.is_moving(), "MC stays idle after hold-ground clear")
    _cleanup([unit, enemy])


func test_player_default_set_target_still_chases_out_of_range():
    # Regression: hold_ground default false keeps existing chase behavior.
    if _ts:
        _ts.init_grid(32, 32)
    var unit := _make_unit(0, false, true)
    var enemy := _make_enemy(1)
    var root: Node = Engine.get_main_loop().root
    _place(root, unit, Vector3(0, 0, 0))
    _place(root, enemy, Vector3(RANGE_WORLD + 10.0, 0, 0))
    var combat := unit.get_node("CombatComponent") as CombatComponent
    var mc := unit.get_node("MovementController") as MovementController
    var chase_moves := [0]
    mc.movement_started.connect(func(): chase_moves[0] += 1)
    combat.set_target(enemy)
    TestHelper.assert_true(combat._target == enemy, "player set_target stores target")
    TestHelper.assert_true(not combat._hold_ground, "default hold_ground is false")
    TestHelper.assert_eq(chase_moves[0], 1, "default set_target issues one chase move")
    combat._physics_process(0.05)
    TestHelper.assert_true(
        combat.get_target() == enemy, "player-ordered out-of-range target retained for chase"
    )
    _cleanup([unit, enemy])


func test_gates_skip_scan():
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root

    # Active combat target suppresses re-scan.
    var unit_a := _make_unit(0, true, false, false)
    var enemy_a := _make_enemy(1)
    _place(root, unit_a, Vector3(0, 0, 0))
    _place(root, enemy_a, Vector3(4, 0, 0))
    _rebuild()
    var combat_a := unit_a.get_node("CombatComponent") as CombatComponent
    combat_a.set_target(enemy_a)
    var guard_a := unit_a.get_node("GuardComponent") as GuardComponent
    guard_a._resolved = false
    guard_a._scan_timer = 0.0
    var scans_before := guard_a.scan_count
    guard_a._physics_process(0.05)
    TestHelper.assert_eq(guard_a.scan_count, scans_before, "no scan while combat target active")

    # MC moving suppresses acquisition.
    var unit_b := _make_unit(0, true, true, false)
    var enemy_b := _make_enemy(1)
    _place(root, unit_b, Vector3(50, 0, 0))
    _place(root, enemy_b, Vector3(54, 0, 0))
    _rebuild()
    var mc_b := unit_b.get_node("MovementController") as MovementController
    mc_b._state = MovementController.State.MOVING
    var guard_b := unit_b.get_node("GuardComponent") as GuardComponent
    guard_b._resolved = false
    guard_b._scan_timer = 0.0
    var scans_b := guard_b.scan_count
    guard_b._physics_process(0.05)
    TestHelper.assert_eq(guard_b.scan_count, scans_b, "no scan while MC is_moving")
    var combat_b := unit_b.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_true(combat_b.get_target() == null, "no acquire during player move")

    # Power offline suppresses acquisition.
    var unit_c := _make_unit(0, true, false, true)
    var enemy_c := _make_enemy(1)
    _place(root, unit_c, Vector3(100, 0, 0))
    _place(root, enemy_c, Vector3(104, 0, 0))
    _rebuild()
    var power_c := unit_c.get_node("PowerComponent") as PowerComponent
    power_c.is_online = false
    var guard_c := unit_c.get_node("GuardComponent") as GuardComponent
    guard_c._resolved = false
    guard_c._scan_timer = 0.0
    var scans_c := guard_c.scan_count
    guard_c._physics_process(0.05)
    TestHelper.assert_eq(guard_c.scan_count, scans_c, "no scan while power offline")
    var combat_c := unit_c.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_true(combat_c.get_target() == null, "no acquire while power offline")

    _cleanup([unit_a, enemy_a, unit_b, enemy_b, unit_c, enemy_c])


func test_reacquire_after_clear():
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    var first := _make_enemy(1)
    var second := _make_enemy(1)
    _place(root, unit, Vector3(0, 0, 0))
    _place(root, first, Vector3(4, 0, 0))
    _place(root, second, Vector3(6, 0, 0))
    _rebuild()
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_eq(combat.get_target(), first, "first target acquired")
    combat.clear_target()
    # first still alive in range — re-acquire
    _tick_guard(unit)
    TestHelper.assert_true(
        combat.get_target() != null, "re-acquires after clear while enemy remains"
    )
    combat.clear_target()
    # remove all enemies from range
    first.global_position = Vector3(500, 0, 500)
    second.global_position = Vector3(500, 0, 502)
    _rebuild()
    _tick_guard(unit)
    TestHelper.assert_true(combat.get_target() == null, "stays idle when no enemy in range")
    _cleanup([unit, first, second])


func test_throttle_limits_scans_per_interval():
    if _sh == null:
        TestHelper.fail("SpatialHash not injected")
        return
    var unit := _make_unit(0)
    var root: Node = Engine.get_main_loop().root
    _place(root, unit, Vector3(0, 0, 0))
    _rebuild()
    var guard := unit.get_node("GuardComponent") as GuardComponent
    guard._resolved = false
    guard._scan_timer = 0.0
    var before := guard.scan_count
    # Several physics ticks well under SCAN_INTERVAL (0.3).
    for i in 10:
        guard._physics_process(0.01)
    TestHelper.assert_eq(guard.scan_count, before + 1, "at most one scan per throttle interval")
    _cleanup([unit])


func test_diagonal_corner_cell_in_range_acquired():
    # Cell-index circle of radius 5 skips offset (4,4) (32 > 25) even when
    # world distance is within weapon range — square hood must still find it.
    if _sh == null or _pm == null or _ts == null:
        TestHelper.fail("SpatialHash/PlayerManager/TerrainSystem not injected")
        return
    _set_teams(0, 1)
    _ts.init_grid(32, 32)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    var enemy := _make_enemy(1)
    var unit_cell := Vector2i(10, 10)
    var enemy_cell := unit_cell + Vector2i(4, 4)
    var u_center := CellUtil.cell_to_world(unit_cell)
    var e_center := CellUtil.cell_to_world(enemy_cell)
    # Pull each toward the shared corner so world dist < range while cell
    # offsets stay (4,4).
    _place(root, unit, u_center + Vector3(0.9, 0, 0.9))
    _place(root, enemy, e_center + Vector3(-0.9, 0, -0.9))
    _rebuild()
    var dx := enemy.global_position.x - unit.global_position.x
    var dz := enemy.global_position.z - unit.global_position.z
    var dist := Vector2(dx, dz).length()
    TestHelper.assert_true(dist <= RANGE_WORLD, "fixture distance is within weapon range")
    var u_cell := CellUtil.world_to_cell(unit.global_position)
    var e_cell := CellUtil.world_to_cell(enemy.global_position)
    var offset := e_cell - u_cell
    TestHelper.assert_eq(offset, Vector2i(4, 4), "fixture sits at cell offset (4,4)")
    TestHelper.assert_true(
        offset.x * offset.x + offset.y * offset.y > 25,
        "fixture would be skipped by a cell-index circle of radius 5"
    )
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_eq(combat.get_target(), enemy, "diagonal in-range enemy acquired")
    _cleanup([unit, enemy])


func test_candidate_without_health_not_acquired():
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    var enemy := _make_enemy(1, false)
    _place(root, unit, Vector3(0, 0, 0))
    _place(root, enemy, Vector3(4, 0, 0))
    _rebuild()
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_true(
        combat.get_target() == null, "hostile without HealthComponent is not acquired"
    )
    _cleanup([unit, enemy])


func test_preview_meta_disables_guard_scan():
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    unit.set_meta("detached", true)
    var enemy := _make_enemy(1)
    _place(root, unit, Vector3(0, 0, 0))
    _place(root, enemy, Vector3(4, 0, 0))
    _rebuild()
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_true(combat.get_target() == null, "detached entity does not scan or acquire")
    _cleanup([unit, enemy])


func test_map_editor_ancestor_disables_guard_scan():
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root
    var editor := Node3D.new()
    editor.name = "MapEditor"
    editor.set_meta("is_map_editor", true)
    root.add_child(editor)
    var unit := _make_unit(0)
    editor.add_child(unit)
    unit.global_position = Vector3(0, 0, 0)
    unit.add_to_group("entities")
    var enemy := _make_enemy(1)
    _place(root, enemy, Vector3(4, 0, 0))
    _rebuild()
    var guard := unit.get_node("GuardComponent") as GuardComponent
    guard._ready()
    # Gate is set_physics_process(false) — engine will not invoke _physics_process.
    TestHelper.assert_true(
        not guard.is_physics_processing(), "map-editor entity disables Guard physics"
    )
    _cleanup([unit, enemy])
    if is_instance_valid(editor):
        root.remove_child(editor)
        editor.free()


func _make_building_enemy(player_id: int, foundation: Vector2i) -> Node3D:
    var entity := _make_enemy(player_id)
    var stats := entity.get_node("StatsComponent") as StatsComponent
    stats.entity_type = EntityData.EntityType.BUILDING
    var fc := FoundationComponent.new()
    fc.name = "FoundationComponent"
    fc.foundation = foundation
    entity.add_child(fc)
    return entity


func test_guard_acquires_building_by_nearest_footprint_edge():
    # 4x4 building at origin: centre is 12 away (> 10 range), nearest edge 8
    # (<= 10). The guard must acquire it, matching CombatComponent range.
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    var building := _make_building_enemy(1, Vector2i(4, 4))
    _place(root, unit, Vector3(-12, 0, 0))
    _place(root, building, Vector3(0, 0, 0))
    _rebuild()
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_eq(
        combat.get_target(), building, "guard acquires a building whose nearest edge is in range"
    )
    TestHelper.assert_true(combat._hold_ground, "building acquisition uses hold_ground")
    _cleanup([unit, building])


func test_guard_ignores_point_enemy_at_same_center_distance():
    # Same 12-unit centre offset as the building case, but a point target: out of
    # the 10-unit range, so it must stay unacquired. Proves the building case is
    # about the footprint edge, not a wider hood alone.
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    var enemy := _make_enemy(1)
    _place(root, unit, Vector3(-12, 0, 0))
    _place(root, enemy, Vector3(0, 0, 0))
    _rebuild()
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_true(
        combat.get_target() == null, "a point enemy 12 away stays outside the 10-unit range"
    )
    _cleanup([unit, enemy])


func test_guard_acquires_building_corner_diagonal():
    # Diagonal approach: centre 14.14 away (out of 10 range) but the nearest
    # footprint corner 8.49 away (in range). Pins the corner path and the hood
    # margin in the diagonal direction.
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    var building := _make_building_enemy(1, Vector2i(4, 4))
    _place(root, unit, Vector3(-10, 0, -10))
    _place(root, building, Vector3(0, 0, 0))
    _rebuild()
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_eq(
        combat.get_target(), building, "guard acquires a diagonal building by its nearest corner"
    )
    _cleanup([unit, building])


func test_enemy_in_unexplored_cell_not_acquired():
    # Visibility gate (#446): a hostile inside weapon range but in a cell the
    # scanning house has never explored is not a candidate.
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    var enemy := _make_enemy(1)
    _place(root, unit, Vector3(0, 0, 0))
    _place(root, enemy, Vector3(RANGE_WORLD - 1.0, 0, 0))
    _rebuild()
    # Shroud everything for the scanning house, then reveal only its own cell.
    _reset_vision()
    ShroudSystem.explore_area(0, CellUtil.world_to_cell(unit.global_position), 1)
    var enemy_cell := CellUtil.world_to_cell(enemy.global_position)
    TestHelper.assert_true(
        not ShroudSystem.is_explored(0, enemy_cell), "fixture: enemy cell stays unexplored"
    )
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_true(combat.get_target() == null, "shrouded enemy not acquired")
    _cleanup([unit, enemy])


func test_engaged_target_leaving_visibility_is_retained():
    # Acquisition is the only visibility test: once held, the engagement
    # survives the target walking out of sight.
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    var enemy := _make_enemy(1)
    _place(root, unit, Vector3(0, 0, 0))
    _place(root, enemy, Vector3(RANGE_WORLD - 1.0, 0, 0))
    _rebuild()
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    TestHelper.assert_eq(combat.get_target(), enemy, "acquired while visible")
    _reset_vision()
    _tick_guard(unit)
    _tick_guard(unit)
    TestHelper.assert_eq(
        combat.get_target(), enemy, "engagement retained after the target leaves visibility"
    )
    _cleanup([unit, enemy])


func test_computer_owned_guard_uses_own_visibility():
    # The scanning house's own shroud decides, never the local player's: a
    # computer-owned unit must not be blinded by (or benefit from) the human
    # player's fog.
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(1)
    var enemy := _make_enemy(0)
    _place(root, unit, Vector3(0, 0, 0))
    _place(root, enemy, Vector3(RANGE_WORLD - 1.0, 0, 0))
    _rebuild()
    _reset_vision()
    var enemy_cell := CellUtil.world_to_cell(enemy.global_position)
    ShroudSystem.explore_area(0, enemy_cell, VISION_RADIUS)
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    (
        TestHelper
        . assert_true(
            combat.get_target() == null,
            "computer house blind to a cell only the local player has explored",
        )
    )
    ShroudSystem.explore_area(1, enemy_cell, VISION_RADIUS)
    _tick_guard(unit)
    TestHelper.assert_eq(
        combat.get_target(), enemy, "acquired once the scanning house itself sees it"
    )
    _cleanup([unit, enemy])


func test_guard_does_not_steal_ground_engagement():
    # is_engaged() — not a non-null target — is what suppresses the scan, so a
    # force-fire ground engagement (target == null) is not overwritten.
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    var enemy := _make_enemy(1)
    _place(root, unit, Vector3(0, 0, 0))
    _place(root, enemy, Vector3(RANGE_WORLD - 1.0, 0, 0))
    _rebuild()
    var combat := unit.get_node("CombatComponent") as CombatComponent
    combat.set_ground_target(Vector3(40, 0, 0))
    TestHelper.assert_true(combat.is_engaged(), "ground engagement is active")
    TestHelper.assert_true(combat.get_target() == null, "ground engagement holds no entity target")
    _tick_guard(unit)
    TestHelper.assert_true(combat.get_target() == null, "guard did not steal the ground engagement")
    TestHelper.assert_true(combat.is_engaged(), "ground engagement still active after a scan")
    _cleanup([unit, enemy])


func test_guard_visibility_uses_footprint_point():
    # Visibility is judged at the same footprint point the range test uses: a
    # structure whose in-range edge is visible while its centre cell sits in
    # shroud must still be acquired.
    if _sh == null or _pm == null:
        TestHelper.fail("SpatialHash/PlayerManager not injected")
        return
    _set_teams(0, 1)
    var rules := GlobalRules.get_current()
    var saved_shroud: bool = rules.shroud_enabled if rules else false
    if rules:
        rules.shroud_enabled = true
    var root: Node = Engine.get_main_loop().root
    var unit := _make_unit(0)
    var building := _make_building_enemy(1, Vector2i(4, 4))
    _place(root, unit, Vector3(-12, 0, 0))
    _place(root, building, Vector3(0, 0, 0))
    _rebuild()
    _reset_vision()
    var fc := building.get_node("FoundationComponent") as FoundationComponent
    var edge_cell := CellUtil.world_to_cell(fc.nearest_world_point(unit.global_position))
    var centre_cell := CellUtil.world_to_cell(building.global_position)
    ShroudSystem.explore_area(0, edge_cell, 1)
    var centre_dark: bool = not ShroudSystem.is_explored(0, centre_cell)
    _tick_guard(unit)
    var combat := unit.get_node("CombatComponent") as CombatComponent
    var acquired: bool = combat.get_target() == building
    _cleanup([unit, building])
    if rules:
        rules.shroud_enabled = saved_shroud
    TestHelper.assert_true(centre_dark, "fixture: the building centre cell stays unexplored")
    TestHelper.assert_true(acquired, "visible footprint edge acquires a shrouded-centre building")
