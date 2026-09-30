extends Node

# OrderResolver tests — resolve_single and resolve_all order resolution

const SELECT_COMPONENT_SCENE: PackedScene = preload("res://scenes/components/SelectComponent.tscn")

var _sm: Node = null
var _pm: Node = null


func _make_weapon(damage: int = 10, range_cells: float = 5.0) -> WeaponData:
    var w := WeaponData.new()
    w.id = "TEST_WEAPON"
    w.damage = damage
    w.attack_range = range_cells
    w.rate_of_fire = 1.0
    return w


func _make_combat_entity(has_weapon: bool = true, player_id: int = -1) -> Node3D:
    var entity := Node3D.new()
    entity.name = "CombatEntity"
    var combat := CombatComponent.new()
    combat.name = "CombatComponent"
    entity.add_child(combat)
    if has_weapon:
        combat.weapons = [_make_weapon()]
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    entity.add_child(stats)
    return entity


func _make_target(player_id: int) -> Node3D:
    var entity := Node3D.new()
    entity.name = "TargetEntity"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    entity.add_child(stats)
    return entity


func _make_selectable(player_id: int = -1) -> Node3D:
    var entity := Node3D.new()
    entity.name = "SelectableEntity"
    entity.add_to_group("selectable")
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity.add_child(select_comp)
    if player_id >= 0:
        var stats := StatsComponent.new()
        stats.name = "StatsComponent"
        stats.player_id = player_id
        entity.add_child(stats)
    return entity


func _setup_selection(entities: Array[Node3D]) -> void:
    if _sm == null:
        return
    _sm.deselect_all()
    for entity in entities:
        _sm.add_child(entity)
        var sc := entity.get_node_or_null("SelectComponent") as SelectComponent
        if not sc:
            sc = SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
            sc.name = "SelectComponent"
            entity.add_child(sc)
        _sm.add_entity(sc)


func _teardown_selection(entities: Array[Node3D]) -> void:
    if _sm:
        _sm.deselect_all()
    for entity in entities:
        if is_instance_valid(entity):
            entity.free()


# --- resolve_all tests ---


func test_resolve_all_empty_selection():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var target := _make_target(1)
    var results := OrderResolver.resolve_all(
        _sm.selected_entities, target, Vector2i.ZERO, Vector3.ZERO, {}
    )
    TestHelper.assert_eq(results.size(), 0, "empty selection -> no orders")
    target.free()


func test_resolve_all_entity_without_combat():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_selectable(local_id)
    var target := _make_target(local_id + 1)
    _setup_selection([entity])
    var results := OrderResolver.resolve_all(
        _sm.selected_entities, target, Vector2i.ZERO, Vector3.ZERO, {}
    )
    TestHelper.assert_eq(results.size(), 0, "entity without CombatComponent -> no orders")
    _teardown_selection([entity])
    target.free()


func test_resolve_all_combat_entity_vs_enemy():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity.add_child(select_comp)
    var target := _make_target(local_id + 1)
    _setup_selection([entity])
    var results := OrderResolver.resolve_all(
        _sm.selected_entities, target, Vector2i.ZERO, Vector3.ZERO, {}
    )
    TestHelper.assert_eq(results.size(), 1, "combat entity vs enemy -> 1 order")
    TestHelper.assert_eq(results[0].cursor, CursorState.Type.ATTACK, "order cursor -> ATTACK")
    TestHelper.assert_eq(
        results[0].get("voice_event"), VoiceData.EVENT_ATTACK, "attack order -> attack voice event"
    )
    _teardown_selection([entity])
    target.free()


func test_resolve_all_combat_entity_vs_friendly():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity.add_child(select_comp)
    var target := _make_target(local_id)
    _setup_selection([entity])
    var results := OrderResolver.resolve_all(
        _sm.selected_entities, target, Vector2i.ZERO, Vector3.ZERO, {}
    )
    TestHelper.assert_eq(results.size(), 0, "combat entity vs friendly -> no orders")
    _teardown_selection([entity])
    target.free()


func test_resolve_all_multiple_entities_mixed():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var combat_entity := _make_combat_entity(true, local_id)
    var combat_sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    combat_entity.add_child(combat_sc)
    var non_combat_entity := _make_combat_entity(false, local_id)
    var non_combat_sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    non_combat_entity.add_child(non_combat_sc)
    var target := _make_target(local_id + 1)
    _setup_selection([combat_entity, non_combat_entity])
    var results := OrderResolver.resolve_all(
        _sm.selected_entities, target, Vector2i.ZERO, Vector3.ZERO, {}
    )
    TestHelper.assert_eq(results.size(), 1, "mixed selection vs enemy -> 1 order (only combat)")
    _teardown_selection([combat_entity, non_combat_entity])
    target.free()


func test_resolve_all_invalid_select_component_skipped():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity.add_child(select_comp)
    _sm.add_child(entity)
    _sm.add_entity(select_comp)
    entity.free()
    var target := _make_target(local_id + 1)
    var results := OrderResolver.resolve_all(
        _sm.selected_entities, target, Vector2i.ZERO, Vector3.ZERO, {}
    )
    TestHelper.assert_eq(results.size(), 0, "invalid select_component -> skipped")
    _sm.deselect_all()
    target.free()


# --- resolve_single tests ---


func test_resolve_single_empty_selection():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    _sm.deselect_all()
    var target := _make_target(1)
    var result := OrderResolver.resolve_single(
        _sm.selected_entities, target, Vector2i.ZERO, Vector3.ZERO, {}
    )
    TestHelper.assert_true(result == null, "empty selection -> null")
    target.free()


func test_resolve_single_combat_vs_enemy():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity.add_child(select_comp)
    var target := _make_target(local_id + 1)
    _setup_selection([entity])
    var result := OrderResolver.resolve_single(
        _sm.selected_entities, target, Vector2i.ZERO, Vector3.ZERO, {}
    )
    TestHelper.assert_true(result != null, "combat vs enemy -> order not null")
    TestHelper.assert_eq(result.cursor, CursorState.Type.ATTACK, "cursor -> ATTACK")
    _teardown_selection([entity])
    target.free()


func test_resolve_single_combat_vs_friendly():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity.add_child(select_comp)
    var target := _make_target(local_id)
    _setup_selection([entity])
    var result := OrderResolver.resolve_single(
        _sm.selected_entities, target, Vector2i.ZERO, Vector3.ZERO, {}
    )
    TestHelper.assert_true(result == null, "combat vs friendly -> null")
    _teardown_selection([entity])
    target.free()


func test_resolve_single_picks_highest_priority():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity1 := _make_combat_entity(true, local_id)
    var sc1 := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity1.add_child(sc1)
    var entity2 := _make_combat_entity(false, local_id)
    var sc2 := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity2.add_child(sc2)
    var target := _make_target(local_id + 1)
    _setup_selection([entity1, entity2])
    var result := OrderResolver.resolve_single(
        _sm.selected_entities, target, Vector2i.ZERO, Vector3.ZERO, {}
    )
    TestHelper.assert_true(result != null, "mixed selection -> order not null")
    TestHelper.assert_eq(result.cursor, CursorState.Type.ATTACK, "best order -> ATTACK from combat")
    _teardown_selection([entity1, entity2])
    target.free()


func test_resolve_single_force_attack_allows_friendly():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    entity.add_child(select_comp)
    var target := _make_target(local_id)
    _setup_selection([entity])
    var modifiers := {OrderResult.MOD_FORCE_ATTACK: true}
    var result := OrderResolver.resolve_single(
        _sm.selected_entities, target, Vector2i.ZERO, Vector3.ZERO, modifiers
    )
    TestHelper.assert_true(result != null, "force_attack vs friendly -> order not null")
    TestHelper.assert_eq(
        result.get("voice_event"), VoiceData.EVENT_ATTACK, "force-fire entity -> attack voice event"
    )
    _teardown_selection([entity])
    target.free()


# --- voice event tests ---


func test_order_result_defaults_to_move_voice_event():
    var order := OrderResult.new(CursorState.Type.MOVE, 5)
    TestHelper.assert_eq(
        order.get("voice_event"), VoiceData.EVENT_MOVE, "default voice event is the move voice"
    )


# --- _is_better tests ---


func test_is_better_higher_priority_wins():
    var high := OrderResult.new(CursorState.Type.ATTACK, 30)
    var low := OrderResult.new(CursorState.Type.MOVE, 5)
    var result := OrderResolver._is_better(high, low)
    TestHelper.assert_true(result, "higher priority is better")


func test_is_better_lower_priority_loses():
    var high := OrderResult.new(CursorState.Type.ATTACK, 30)
    var low := OrderResult.new(CursorState.Type.MOVE, 5)
    var result := OrderResolver._is_better(low, high)
    TestHelper.assert_true(not result, "lower priority is not better")


func test_is_better_equal_priority_not_better():
    var a := OrderResult.new(CursorState.Type.ATTACK, 30)
    var b := OrderResult.new(CursorState.Type.ATTACK, 30)
    var result := OrderResolver._is_better(a, b)
    TestHelper.assert_true(not result, "equal priority is not better")
