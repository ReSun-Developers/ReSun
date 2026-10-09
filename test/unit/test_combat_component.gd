extends Node

# CombatComponent tests — cursor resolution and order generation for targets

var _sm: Node = null
var _pm: Node = null
var _ts: Node = null


func _make_weapon(damage: int = 10, range_cells: float = 5.0, warhead: String = "SA") -> WeaponData:
    var w := WeaponData.new()
    w.id = "TEST_WEAPON"
    w.damage = damage
    w.attack_range = range_cells
    w.rate_of_fire = 1.0
    w.warhead = warhead
    return w


func _make_combat_entity(has_weapon: bool = true, player_id: int = -1) -> Node3D:
    var entity := Node3D.new()
    entity.name = "CombatEntity"
    var combat := CombatComponent.new()
    combat.name = "CombatComponent"
    entity.add_child(combat)
    if has_weapon:
        combat.weapons = [_make_weapon()]
        combat._init_cooldowns()
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


func _make_target_of_type(player_id: int, entity_type: int) -> Node3D:
    var entity := _make_target(player_id)
    var stats := entity.get_node("StatsComponent") as StatsComponent
    stats.entity_type = entity_type
    return entity


# --- order-cursor tests (derived from get_order_for_target) ---


func test_cursor_null_target_returns_default():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var cursor := TestHelper.order_cursor(cc, null)
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "null target -> DEFAULT")
    entity.free()


func test_cursor_empty_weapons_returns_default():
    var entity := _make_combat_entity(false, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target(1)
    var cursor := TestHelper.order_cursor(cc, target)
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "no weapons -> DEFAULT")
    entity.free()
    target.free()


func test_cursor_enemy_returns_attack():
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target(local_id + 1)
    var cursor := TestHelper.order_cursor(cc, target)
    TestHelper.assert_eq(cursor, CursorState.Type.ATTACK, "enemy -> ATTACK")
    entity.free()
    target.free()


func test_cursor_friendly_returns_default():
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target(local_id)
    var cursor := TestHelper.order_cursor(cc, target)
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "friendly -> DEFAULT")
    entity.free()
    target.free()


func test_cursor_neutral_target_returns_default():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target(-1)
    var cursor := TestHelper.order_cursor(cc, target)
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "neutral (player_id=-1) -> DEFAULT")
    entity.free()
    target.free()


func test_cursor_target_without_stats_returns_default():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := Node3D.new()
    target.name = "NoStatsTarget"
    var cursor := TestHelper.order_cursor(cc, target)
    TestHelper.assert_eq(
        cursor, CursorState.Type.DEFAULT, "target without StatsComponent -> DEFAULT"
    )
    entity.free()
    target.free()


# --- get_order_for_target tests ---


func test_order_null_target_returns_null():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var order := cc.get_order_for_target(null, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order == null, "null target -> null order")
    entity.free()


func test_order_empty_weapons_returns_null():
    var entity := _make_combat_entity(false, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target(1)
    var order := cc.get_order_for_target(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order == null, "no weapons -> null order")
    entity.free()
    target.free()


func test_order_enemy_returns_attack_order():
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target(local_id + 1)
    var order := cc.get_order_for_target(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order != null, "enemy -> order not null")
    TestHelper.assert_eq(order.cursor, CursorState.Type.ATTACK, "enemy order cursor -> ATTACK")
    TestHelper.assert_eq(order.priority, 30, "enemy order priority -> 30")
    TestHelper.assert_true(order.execute.is_valid(), "enemy order has valid execute callable")
    entity.free()
    target.free()


func test_order_friendly_returns_null():
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target(local_id)
    var order := cc.get_order_for_target(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order == null, "friendly -> null order")
    entity.free()
    target.free()


func test_order_neutral_returns_null():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target(-1)
    var order := cc.get_order_for_target(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order == null, "neutral -> null order")
    entity.free()
    target.free()


func test_order_force_attack_modifier_allows_friendly():
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target(local_id)
    var modifiers := {OrderResult.MOD_FORCE_ATTACK: true}
    var order := cc.get_order_for_target(target, Vector2i.ZERO, Vector3.ZERO, modifiers)
    TestHelper.assert_true(order != null, "force_attack on friendly -> order not null")
    TestHelper.assert_eq(order.cursor, CursorState.Type.ATTACK, "force_attack cursor -> ATTACK")
    entity.free()
    target.free()


func test_order_queued_modifier_sets_queued_flag():
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target(local_id + 1)
    var modifiers := {OrderResult.MOD_QUEUED: true}
    var order := cc.get_order_for_target(target, Vector2i.ZERO, Vector3.ZERO, modifiers)
    TestHelper.assert_true(order != null, "queued modifier -> order not null")
    TestHelper.assert_true(order.queued, "queued modifier -> order.queued = true")
    entity.free()
    target.free()


func test_order_no_queued_modifier_sets_queued_false():
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target(local_id + 1)
    var order := cc.get_order_for_target(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order != null, "no queued modifier -> order not null")
    TestHelper.assert_true(not order.queued, "no queued modifier -> order.queued = false")
    entity.free()
    target.free()


func test_order_target_without_stats_returns_null():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := Node3D.new()
    target.name = "NoStatsTarget"
    var order := cc.get_order_for_target(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order == null, "target without StatsComponent -> null order")
    entity.free()
    target.free()


func test_order_stores_target_reference():
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target(local_id + 1)
    var order := cc.get_order_for_target(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(order.target, target, "order stores target reference")
    entity.free()
    target.free()


func test_order_stores_target_pos():
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target(local_id + 1)
    var pos := Vector3(10.0, 0.0, 20.0)
    var order := cc.get_order_for_target(target, Vector2i.ZERO, pos, {})
    TestHelper.assert_eq(order.target_pos, pos, "order stores target_pos")
    entity.free()
    target.free()


# --- configure tests ---


func test_configure_sets_weapons():
    var entity := _make_combat_entity(false, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var data := EntityData.new()
    data.id = "TEST"
    data.weapons = [_make_weapon(20, 3.0)]
    cc.configure(data)
    TestHelper.assert_eq(cc.weapons.size(), 1, "configure sets weapons array")
    TestHelper.assert_eq(cc.weapons[0].damage, 20, "configure copies weapon data")
    entity.free()


func test_get_current_weapon_with_weapons():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var weapon := cc.get_current_weapon()
    TestHelper.assert_true(weapon != null, "get_current_weapon returns weapon when weapons exist")
    TestHelper.assert_eq(weapon.id, "TEST_WEAPON", "get_current_weapon returns correct weapon")
    entity.free()


func test_get_current_weapon_empty_weapons():
    var entity := _make_combat_entity(false, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var weapon := cc.get_current_weapon()
    TestHelper.assert_true(weapon == null, "get_current_weapon returns null when no weapons")
    entity.free()


func test_validate_no_weapons():
    var entity := _make_combat_entity(false, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var data := EntityData.new()
    data.id = "TEST_EMPTY"
    var errors := cc.validate(data)
    TestHelper.assert_true(errors.size() > 0, "validate reports error for no weapons")
    entity.free()


# --- Firing logic tests ---


func _make_target_with_health(
    player_id: int = 1, health: int = 100, armor: String = "none"
) -> Node3D:
    var entity := Node3D.new()
    entity.name = "TargetEntity"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    stats.armor = armor
    entity.add_child(stats)
    var hc := HealthComponent.new()
    hc.name = "HealthComponent"
    hc.max_health = health
    hc.current_health = health
    entity.add_child(hc)
    return entity


func test_set_target_stores_reference():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(1)
    cc.set_target(target)
    TestHelper.assert_eq(cc._target, target, "set_target stores reference")
    TestHelper.assert_true(cc._attack_active, "set_target sets _attack_active")
    entity.free()
    target.free()


func test_clear_target_clears_reference():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(1)
    cc.set_target(target)
    cc.clear_target()
    TestHelper.assert_eq(cc._target, null, "clear_target nulls reference")
    TestHelper.assert_eq(cc._attack_active, false, "clear_target clears _attack_active")
    entity.free()
    target.free()


func test_cooldown_blocks_fire():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(1, 100)
    cc.set_target(target)
    cc._channels[0].cooldown = 5.0
    var old_health: int = target.get_node("HealthComponent").current_health
    cc._physics_process(0.1)
    var new_health: int = target.get_node("HealthComponent").current_health
    TestHelper.assert_eq(new_health, old_health, "cooldown blocks fire — health unchanged")
    entity.free()
    target.free()


func test_cooldown_uses_rof_frames_at_ts_logic_rate():
    # TS ROF= is a rearm delay in engine frames at 30 fps logic:
    # seconds_between_shots = ROF / 30. ROF=30 → 1.0 s, not 60/30 = 2.0 s.
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var weapon := _make_weapon()
    weapon.rate_of_fire = 30.0
    cc.weapons = [weapon]
    cc._init_cooldowns()
    var target := _make_target_with_health(1, 100)
    cc.set_target(target)
    cc._fire_channel(cc._channels[0])
    TestHelper.assert_eq(
        cc._channels[0].cooldown, 1.0, "ROF=30 frames rearm delay → 1.0 s cooldown"
    )
    entity.free()
    target.free()


func test_fire_deals_damage_in_range():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(1, 100)
    var weapon := cc.get_current_weapon()
    cc._fire_weapon(weapon, target)
    var health: int = target.get_node("HealthComponent").current_health
    TestHelper.assert_eq(health, 100 - weapon.damage, "fire deals weapon.damage")
    entity.free()
    target.free()


func test_target_invalidated_no_crash():
    var entity := _make_combat_entity(true, 0)
    add_child(entity)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(1)
    add_child(target)
    cc.set_target(target)
    remove_child(target)
    target.free()
    cc._physics_process(0.1)
    cc._physics_process(0.1)
    TestHelper.assert_eq(cc._target, null, "invalid target cleared")
    # A freed reference already compares equal to null, so the assertion above
    # passes even when the engagement was never torn down. _attack_active is
    # what distinguishes "cleared" from "still firing at a stale point".
    TestHelper.assert_true(not cc._attack_active, "stale entity engagement is torn down")
    remove_child(entity)
    entity.free()


func test_target_death_clears_target():
    var entity := _make_combat_entity(true, 0)
    add_child(entity)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(1, 10)
    add_child(target)
    target.global_position = Vector3(0, 0, 0)
    entity.global_position = Vector3(0, 0, 0)
    cc.set_target(target)
    var weapon := cc.get_current_weapon()
    target.get_node("HealthComponent").take_damage(weapon.damage)
    TestHelper.assert_eq(cc._target, null, "dead target cleared via health_zero signal")
    remove_child(entity)
    remove_child(target)
    entity.free()
    target.free()


func test_weapon_fired_signal_emits():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(1, 100)
    var result := [false, null]
    cc.weapon_fired.connect(
        func(w: WeaponData, _t: Node3D):
            result[0] = true
            result[1] = w
    )
    var weapon := cc.get_current_weapon()
    cc._fire_weapon(weapon, target)
    TestHelper.assert_true(result[0], "weapon_fired signal emitted")
    TestHelper.assert_eq(result[1], weapon, "signal passes weapon data")
    entity.free()
    target.free()


# --- Powered-down structures do not fire ---


func _make_powered_combat_entity(powered: bool) -> Node3D:
    var entity := _make_combat_entity(true, 0)
    var pc := PowerComponent.new()
    pc.name = "PowerComponent"
    pc.power = -100
    pc.powered = powered
    entity.add_child(pc)
    return entity


func test_offline_structure_holds_fire_and_retains_target():
    var entity := _make_powered_combat_entity(true)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var pc := entity.get_node("PowerComponent") as PowerComponent
    var target := _make_target_with_health(0, 100)
    var fired := [false]
    cc.weapon_fired.connect(func(_w: WeaponData, _t: Node3D) -> void: fired[0] = true)
    cc.set_target(target)
    pc.set_online(false)
    cc._physics_process(0.016)
    TestHelper.assert_true(not fired[0], "offline structure fires nothing")
    TestHelper.assert_true(cc._target == target, "target retained while offline")
    pc.set_online(true)
    cc._physics_process(0.016)
    TestHelper.assert_true(fired[0], "restored structure resumes engagement")
    entity.free()
    target.free()


func test_online_powered_entity_fires_normally():
    var entity := _make_powered_combat_entity(true)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(0, 100)
    var fired := [false]
    cc.weapon_fired.connect(func(_w: WeaponData, _t: Node3D) -> void: fired[0] = true)
    cc.set_target(target)
    cc._physics_process(0.016)
    TestHelper.assert_true(fired[0], "online powered entity fires as before")
    entity.free()
    target.free()


func test_entity_without_power_component_unaffected():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(0, 100)
    var fired := [false]
    cc.weapon_fired.connect(func(_w: WeaponData, _t: Node3D) -> void: fired[0] = true)
    cc.set_target(target)
    cc._physics_process(0.016)
    TestHelper.assert_true(fired[0], "no PowerComponent -> firing unchanged")
    entity.free()
    target.free()


# --- Armor resolution (warhead vs armor) tests ---

var _real_rules: GlobalRules = null


func _inject_test_rules() -> void:
    var rules := GlobalRules.new()
    rules.min_damage = 1
    rules.max_damage = 1000
    for aid in ["none", "wood", "light", "heavy", "concrete"]:
        var at := ArmorType.new()
        at.id = aid
        rules.armor_types[aid] = at
    var sa := WarheadData.new()
    sa.id = "SA"
    sa.armor_damage_multipliers = {
        "none": 1.0, "wood": 0.6, "light": 0.4, "heavy": 0.25, "concrete": 0.1
    }
    rules.warheads["SA"] = sa
    var ap := WarheadData.new()
    ap.id = "AP"
    ap.armor_damage_multipliers = {
        "none": 0.25, "wood": 0.65, "light": 0.75, "heavy": 1.0, "concrete": 0.6
    }
    rules.warheads["AP"] = ap
    var mechanical := WarheadData.new()
    mechanical.id = "Mechanical"
    mechanical.armor_damage_multipliers = {
        "none": 0.0, "wood": 1.0, "light": 1.0, "heavy": 1.0, "concrete": 1.0
    }
    rules.warheads["Mechanical"] = mechanical
    var fire := WarheadData.new()
    fire.id = "Fire"
    fire.armor_damage_multipliers = {
        "none": 6.0, "wood": 1.48, "light": 0.59, "heavy": 0.06, "concrete": 0.02
    }
    rules.warheads["Fire"] = fire
    var main_loop := Engine.get_main_loop()
    var ef: Node = main_loop.root.get_node_or_null("EntityFactory") if main_loop else null
    if ef and ef.has_method("set_global_rules"):
        _real_rules = ef.get_global_rules()
        ef.set_global_rules(rules)


func _restore_rules() -> void:
    var main_loop := Engine.get_main_loop()
    var ef: Node = main_loop.root.get_node_or_null("EntityFactory") if main_loop else null
    if ef and ef.has_method("set_global_rules"):
        ef.set_global_rules(_real_rules)


func test_armor_sa_vs_heavy():
    _inject_test_rules()
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    cc.weapons = [_make_weapon(100, 5.0, "SA")]
    cc._init_cooldowns()
    var target := _make_target_with_health(1, 1000, "heavy")
    var weapon := cc.get_current_weapon()
    cc._fire_weapon(weapon, target)
    var health: int = target.get_node("HealthComponent").current_health
    TestHelper.assert_eq(health, 1000 - 25, "SA vs heavy (0.25) deals 25 damage")
    entity.free()
    target.free()
    _restore_rules()


func test_armor_ap_vs_heavy_full():
    _inject_test_rules()
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    cc.weapons = [_make_weapon(100, 5.0, "AP")]
    cc._init_cooldowns()
    var target := _make_target_with_health(1, 1000, "heavy")
    var weapon := cc.get_current_weapon()
    cc._fire_weapon(weapon, target)
    var health: int = target.get_node("HealthComponent").current_health
    TestHelper.assert_eq(health, 1000 - 100, "AP vs heavy (1.0) deals full damage")
    entity.free()
    target.free()
    _restore_rules()


func test_armor_sa_vs_concrete_min_floor():
    _inject_test_rules()
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    cc.weapons = [_make_weapon(5, 5.0, "SA")]
    cc._init_cooldowns()
    var target := _make_target_with_health(1, 1000, "concrete")
    var weapon := cc.get_current_weapon()
    cc._fire_weapon(weapon, target)
    var health: int = target.get_node("HealthComponent").current_health
    TestHelper.assert_eq(health, 1000 - 1, "SA vs concrete (0.1*5=0.5) floors to min_damage 1")
    entity.free()
    target.free()
    _restore_rules()


func test_armor_zero_damage_pairing():
    _inject_test_rules()
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    cc.weapons = [_make_weapon(100, 5.0, "Mechanical")]
    cc._init_cooldowns()
    var target := _make_target_with_health(1, 1000, "none")
    var weapon := cc.get_current_weapon()
    cc._fire_weapon(weapon, target)
    var health: int = target.get_node("HealthComponent").current_health
    TestHelper.assert_eq(health, 1000 - 0, "Mechanical vs none (0.0) deals 0 damage")
    entity.free()
    target.free()
    _restore_rules()


func test_armor_unknown_warhead_full():
    _inject_test_rules()
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    cc.weapons = [_make_weapon(50, 5.0, "UnknownWH")]
    cc._init_cooldowns()
    var target := _make_target_with_health(1, 1000, "heavy")
    var weapon := cc.get_current_weapon()
    cc._fire_weapon(weapon, target)
    var health: int = target.get_node("HealthComponent").current_health
    TestHelper.assert_eq(health, 1000 - 50, "unknown warhead deals full damage")
    entity.free()
    target.free()
    _restore_rules()


func test_armor_unknown_target_armor_full():
    _inject_test_rules()
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    cc.weapons = [_make_weapon(50, 5.0, "SA")]
    cc._init_cooldowns()
    var target := _make_target_with_health(1, 1000, "flak")
    var weapon := cc.get_current_weapon()
    cc._fire_weapon(weapon, target)
    var health: int = target.get_node("HealthComponent").current_health
    TestHelper.assert_eq(health, 1000 - 50, "unknown armor deals full damage")
    entity.free()
    target.free()
    _restore_rules()


func test_armor_fire_overkill_caps_at_max():
    _inject_test_rules()
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    cc.weapons = [_make_weapon(500, 5.0, "Fire")]
    cc._init_cooldowns()
    var target := _make_target_with_health(1, 100000, "none")
    var weapon := cc.get_current_weapon()
    cc._fire_weapon(weapon, target)
    var health: int = target.get_node("HealthComponent").current_health
    TestHelper.assert_eq(
        health, 100000 - 1000, "Fire vs none (6.0*500=3000) caps to max_damage 1000"
    )
    entity.free()
    target.free()
    _restore_rules()


# --- OrderResolver integration: selected units + enemy click ---


func test_order_resolver_returns_attack_for_enemy_with_selection():
    var pm := get_node_or_null("/root/PlayerManager")
    var local_id: int = pm.get_local_player_id() if pm else 0
    var entity := _make_combat_entity(true, local_id)
    add_child(entity)
    var select_comp := SelectComponent.new()
    select_comp.name = "SelectComponent"
    entity.add_child(select_comp)
    var sm := get_node_or_null("/root/SelectionManager")
    if sm:
        sm.add_entity(select_comp)
    var target := _make_target(local_id + 1)
    add_child(target)
    var results := OrderResolver.resolve_all(
        [select_comp], target, Vector2i.ZERO, target.global_position, {}
    )
    TestHelper.assert_true(results.size() > 0, "enemy target returns order")
    var best: OrderResult = results[0]
    TestHelper.assert_eq(best.cursor, CursorState.Type.ATTACK, "cursor -> ATTACK")
    TestHelper.assert_true(best.execute.is_valid(), "execute callable valid")
    if sm:
        sm.deselect_all()
    remove_child(entity)
    remove_child(target)
    entity.free()
    target.free()


# --- Player move cancels attack ---


func test_player_move_clears_attack_target():
    if _ts == null:
        TestHelper.fail("TerrainSystem not injected")
        return
    _ts.init_grid(32, 32)
    if SpatialHash.instance:
        SpatialHash.instance._grid.clear()
    var entity := _make_combat_entity(true, 0)
    add_child(entity)
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    mc._parent = entity
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(1, 100)
    add_child(target)
    entity.global_position = Vector3(1, 0, 1)
    cc.set_target(target)
    TestHelper.assert_eq(cc._target, target, "target set before move")
    TestHelper.assert_true(cc._attack_active, "attack active before move")
    mc.set_target_position(Vector3(5, 0, 5))
    TestHelper.assert_eq(cc._target, null, "target cleared after player move")
    TestHelper.assert_eq(cc._attack_active, false, "attack inactive after player move")
    _ts.clear()
    remove_child(entity)
    remove_child(target)
    entity.free()
    target.free()


func test_combat_move_preserves_attack_target():
    if _ts == null:
        TestHelper.fail("TerrainSystem not injected")
        return
    _ts.init_grid(32, 32)
    if SpatialHash.instance:
        SpatialHash.instance._grid.clear()
    var entity := _make_combat_entity(true, 0)
    add_child(entity)
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    mc._parent = entity
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(1, 100)
    add_child(target)
    entity.global_position = Vector3(1, 0, 1)
    cc.set_target(target)
    cc._combat_move = true
    mc.set_target_position(Vector3(5, 0, 5))
    TestHelper.assert_eq(cc._target, target, "target preserved after combat move")
    TestHelper.assert_true(cc._attack_active, "attack active after combat move")
    _ts.clear()
    remove_child(entity)
    remove_child(target)
    entity.free()
    target.free()


func _make_moving_ground_attacker(waypoint_dir: Vector3 = Vector3(1, 0, 0)) -> Array:
    # A ground unit mid-move on a per-cell player-move path (21 cells), in the
    # scene tree so global positions resolve. Returns [entity, mc, cc].
    if _ts == null:
        TestHelper.fail("TerrainSystem not injected")
        return []
    _ts.init_grid(32, 32)
    if SpatialHash.instance:
        SpatialHash.instance._grid.clear()
    var root: Node = Engine.get_main_loop().root
    var entity := _make_combat_entity(true, 0)
    root.add_child(entity)
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    mc._parent = entity
    entity.global_position = Vector3(0, 0, 0)
    mc._state = MovementController.State.MOVING
    var waypoints := PackedVector3Array()
    for i in range(0, 21):
        waypoints.append(Vector3(i * 2.0, 0, 0) * waypoint_dir)
    mc._waypoints = waypoints
    var cc := entity.get_node("CombatComponent") as CombatComponent
    return [entity, mc, cc]


func test_ground_attack_in_range_stops_and_fires():
    # A ground unit mid-move must abandon the old destination on an in-range
    # attack, stop the move (settling within a cell), and fire (#195).
    var setup: Array = _make_moving_ground_attacker()
    if setup.is_empty():
        return
    var entity: Node3D = setup[0]
    var mc: MovementController = setup[1]
    var cc: CombatComponent = setup[2]
    var root: Node = Engine.get_main_loop().root
    var target := _make_target_with_health(1, 100)
    root.add_child(target)
    target.global_position = Vector3(3.0, 0.0, 0.0)
    var old_dest: Vector3 = mc.get_target_position()
    cc.set_target(target)
    var collapsed_dest: Vector3 = mc.get_target_position()
    var abandoned: bool = collapsed_dest.distance_to(old_dest) > 5.0
    # Let the stop-glide leg finish (the facing gate holds fire while it is
    # live), then process combat ticks.
    for i in 100:
        if not mc.is_moving():
            break
        mc._physics_process(0.016)
    cc._physics_process(0.1)
    cc._physics_process(0.1)
    var health: int = target.get_node("HealthComponent").current_health
    var fired: bool = health < 100
    var still_attacking: bool = cc._target == target
    root.remove_child(entity)
    root.remove_child(target)
    entity.free()
    target.free()
    TestHelper.assert_true(abandoned, "in-range attack abandons old move destination")
    TestHelper.assert_true(fired, "in-range attack fires after stopping")
    TestHelper.assert_true(still_attacking, "attack target preserved after stopping")


func test_moving_attacker_holds_fire_until_facing():
    # In-range attack mid-move must not fire while the stop-glide leg drives
    # the body; the first shot waits until the leg ends and the hull slews
    # onto the target (rotate-to-face-first).
    var setup: Array = _make_moving_ground_attacker()
    if setup.is_empty():
        return
    var entity: Node3D = setup[0]
    var mc: MovementController = setup[1]
    var cc: CombatComponent = setup[2]
    var root: Node = Engine.get_main_loop().root
    var target := _make_target_with_health(1, 100)
    root.add_child(target)
    target.global_position = Vector3(5.0, 0.0, -5.0)
    cc.set_target(target)
    # Glide leg live: target ~7.07 away (in range, past the deadzone), body
    # along +X while the target sits off-axis -> every tick must hold fire.
    var fired_while_moving := false
    for i in 10:
        cc._physics_process(0.1)
        if target.get_node("HealthComponent").current_health < 100:
            fired_while_moving = true
    TestHelper.assert_true(not fired_while_moving, "no shot fires while the stop-glide leg is live")
    # End the leg, then the hull slews onto the target before the first shot.
    for i in 100:
        if not mc.is_moving():
            break
        mc._physics_process(0.016)
    TestHelper.assert_true(not mc.is_moving(), "stop-glide leg ended")
    var fired := false
    for i in 20:
        cc._physics_process(0.1)
        if target.get_node("HealthComponent").current_health < 100:
            fired = true
            break
    var still_attacking: bool = cc._target == target
    TestHelper.assert_true(fired, "first shot fires only after the hull faces the target")
    TestHelper.assert_true(still_attacking, "attack target preserved through stop-and-face")
    root.remove_child(entity)
    root.remove_child(target)
    entity.free()
    target.free()


func test_ground_attack_out_of_range_supersedes_move():
    # A ground unit mid-move heading elsewhere (along Z) must drop that
    # destination on an out-of-range attack and immediately head along a fresh
    # approach path into range (#256).
    var setup: Array = _make_moving_ground_attacker(Vector3(0, 0, 1))
    if setup.is_empty():
        return
    var entity: Node3D = setup[0]
    var mc: MovementController = setup[1]
    var cc: CombatComponent = setup[2]
    var root: Node = Engine.get_main_loop().root
    var target := _make_target_with_health(1, 100)
    root.add_child(target)
    target.global_position = Vector3(40.0, 0.0, 0.0)
    var old_dest: Vector3 = mc.get_target_position()
    cc.set_target(target)
    var new_dest: Vector3 = mc.get_target_position()
    var weapon := cc.get_current_weapon()
    var range_world := weapon.attack_range * CellUtil.CELL_SIZE
    var in_range_of_target: bool = (
        Vector2(new_dest.x - 40.0, new_dest.z).length() <= range_world + 0.5
    )
    var abandoned: bool = new_dest.distance_to(old_dest) > 5.0
    var target_preserved: bool = cc._target == target
    root.remove_child(entity)
    root.remove_child(target)
    entity.free()
    target.free()
    TestHelper.assert_true(abandoned, "out-of-range attack abandons old move destination")
    TestHelper.assert_true(
        in_range_of_target, "new destination is an approach point within weapon range"
    )
    TestHelper.assert_true(target_preserved, "attack target preserved after superseding move")


func test_range_ignores_vertical_separation():
    var root: Node = Engine.get_main_loop().root
    var entity := _make_combat_entity(true, 0)
    root.add_child(entity)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(1, 100)
    root.add_child(target)
    entity.global_position = Vector3(0, 0, 0)
    target.global_position = Vector3(4.0, 50.0, 0.0)
    cc.set_target(target)
    var old_health: int = target.get_node("HealthComponent").current_health
    cc._physics_process(0.1)
    var new_health: int = target.get_node("HealthComponent").current_health
    TestHelper.assert_true(
        new_health < old_health, "vertical separation does not block firing when XZ in range"
    )
    root.remove_child(entity)
    root.remove_child(target)
    entity.free()
    target.free()


func test_range_horizontal_distance_used():
    var root: Node = Engine.get_main_loop().root
    var entity := _make_combat_entity(true, 0)
    root.add_child(entity)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(1, 100)
    root.add_child(target)
    entity.global_position = Vector3(0, 0, 0)
    var weapon := cc.get_current_weapon()
    var range_world := weapon.attack_range * CellUtil.CELL_SIZE
    target.global_position = Vector3(range_world + 1.0, 0.0, 0.0)
    cc.set_target(target)
    cc._physics_process(0.1)
    var health_out: int = target.get_node("HealthComponent").current_health
    target.get_node("HealthComponent").current_health = 100
    target.global_position = Vector3(range_world - 1.0, 0.0, 0.0)
    cc.set_target(target)
    cc._physics_process(0.1)
    var health_in: int = target.get_node("HealthComponent").current_health
    TestHelper.assert_eq(health_out, 100, "out of XZ range does not fire")
    TestHelper.assert_true(health_in < 100, "within XZ range fires")
    root.remove_child(entity)
    root.remove_child(target)
    entity.free()
    target.free()


## A building target with a FoundationComponent (footprint != 1x1) and health.
func _make_building_target(foundation: Vector2i, pos: Vector3) -> Node3D:
    var entity := Node3D.new()
    entity.name = "BuildingTarget"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = 1
    stats.entity_type = EntityData.EntityType.BUILDING
    entity.add_child(stats)
    var hc := HealthComponent.new()
    hc.name = "HealthComponent"
    hc.max_health = 100
    hc.current_health = 100
    entity.add_child(hc)
    var fc := FoundationComponent.new()
    fc.name = "FoundationComponent"
    fc.foundation = foundation
    entity.add_child(fc)
    # local position == global once parented to the identity-transform root.
    entity.position = pos
    return entity


func test_building_attacks_measure_nearest_foundation_point():
    # Regression: a 4x4 building at origin has half-extent 4, so its near edge is
    # 4 world units closer than its center. An attacker 12 from the center is out
    # of the 10-unit weapon range of the center but 8 from the near edge, so it
    # must fire. Center-only measurement (pre-fix) does not fire.
    if _ts == null:
        TestHelper.fail("TerrainSystem not injected")
        return
    _ts.init_grid(32, 32)
    if SpatialHash.instance:
        SpatialHash.instance._grid.clear()
        SpatialHash.instance._building_cells.clear()
    var root: Node = Engine.get_main_loop().root
    var entity := _make_combat_entity(true, 0)
    root.add_child(entity)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var building := _make_building_target(Vector2i(4, 4), Vector3.ZERO)
    root.add_child(building)
    var weapon := cc.get_current_weapon()
    var range_world := weapon.attack_range * CellUtil.CELL_SIZE
    var center_dist := 12.0
    var nearest_dist := center_dist - 4.0
    TestHelper.assert_true(center_dist > range_world, "fixture: footprint center is out of range")
    TestHelper.assert_true(
        nearest_dist <= range_world, "fixture: nearest foundation edge is in range"
    )
    entity.global_position = Vector3(-center_dist, 0.0, 0.0)
    cc.set_target(building)
    cc._physics_process(0.1)
    cc._physics_process(0.1)
    var health: int = building.get_node("HealthComponent").current_health
    root.remove_child(entity)
    root.remove_child(building)
    entity.free()
    building.free()
    TestHelper.assert_true(
        health < 100, "building is engaged when its nearest footprint edge is in range"
    )


func test_building_attack_stops_at_nearest_edge_range():
    # The chase stop must sit `range` from the nearest footprint point, not the
    # footprint centre: a 4x4 building at origin, attacker 20 west, range 10 ->
    # stop near x = -4 - 10 = -14, well short of the centre-based -10.
    var setup: Array = _make_chase_attacker()
    if setup.is_empty():
        return
    var entity: Node3D = setup[0]
    var mc: MovementController = setup[1]
    var cc: CombatComponent = setup[2]
    var root: Node = Engine.get_main_loop().root
    var building := _make_building_target(Vector2i(4, 4), Vector3.ZERO)
    root.add_child(building)
    entity.global_position = Vector3(-20.0, 0.0, 0.0)
    var range_world: float = cc.get_current_weapon().attack_range * CellUtil.CELL_SIZE
    cc.set_target(building)
    var dest: Vector3 = mc.get_target_position()
    var nearest := Vector3(-4.0, 0.0, 0.0)
    var dist_to_nearest := Vector2(dest.x - nearest.x, dest.z - nearest.z).length()
    var dist_to_center := Vector2(dest.x, dest.z).length()
    root.remove_child(entity)
    root.remove_child(building)
    entity.free()
    building.free()
    TestHelper.assert_true(
        dist_to_nearest <= range_world + 0.5,
        "stop lands within weapon range of the nearest footprint edge (got %s)" % dest
    )
    TestHelper.assert_true(
        dist_to_center > range_world + 1.0,
        "stop is short of the center-based point, not closed to the centre (got %s)" % dest
    )


func test_building_facing_targets_nearest_footprint_corner():
    # Diagonal approach: the effective target point is the footprint corner, not
    # the centre. 4x4 at origin, attacker at (-20,0,-20) -> nearest (-4,0,-4).
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var building := _make_building_target(Vector2i(4, 4), Vector3.ZERO)
    var root: Node = Engine.get_main_loop().root
    root.add_child(entity)
    root.add_child(building)
    entity.global_position = Vector3(-20.0, 0.0, -20.0)
    cc.set_target(building)
    var pos: Vector3 = cc._effective_target_pos()
    # A point target (unit) still resolves to its own origin.
    var unit_target := _make_target_with_health(1, 100)
    root.add_child(unit_target)
    unit_target.position = Vector3(7.0, 0.0, 7.0)
    cc.set_target(unit_target)
    var unit_pos: Vector3 = cc._effective_target_pos()
    root.remove_child(entity)
    root.remove_child(building)
    root.remove_child(unit_target)
    entity.free()
    building.free()
    unit_target.free()
    TestHelper.assert_true(
        pos.distance_to(Vector3(-4.0, 0.0, -4.0)) < 0.001,
        "building facing point is the nearest footprint corner (got %s)" % pos
    )
    TestHelper.assert_true(
        unit_pos.distance_to(Vector3(7.0, 0.0, 7.0)) < 0.001,
        "unit facing point is the entity origin (got %s)" % unit_pos
    )


func test_multi_cell_non_structure_measures_to_origin():
    # Classifier parity with GuardComponent: a multi-cell entity that is not a
    # structure keeps point semantics, even though it carries a
    # FoundationComponent (EntityFactory attaches one for any foundation != 1x1).
    var root: Node = Engine.get_main_loop().root
    var entity := _make_combat_entity(true, 0)
    root.add_child(entity)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(1, 100)
    var stats := target.get_node("StatsComponent") as StatsComponent
    stats.entity_type = EntityData.EntityType.VEHICLE
    var fc := FoundationComponent.new()
    fc.name = "FoundationComponent"
    fc.foundation = Vector2i(4, 4)
    target.add_child(fc)
    root.add_child(target)
    entity.global_position = Vector3(-20.0, 0.0, 0.0)
    target.position = Vector3(7.0, 0.0, 7.0)
    cc.set_target(target)
    var pos: Vector3 = cc._effective_target_pos()
    root.remove_child(entity)
    root.remove_child(target)
    entity.free()
    target.free()
    TestHelper.assert_true(
        pos.distance_to(Vector3(7.0, 0.0, 7.0)) < 0.001,
        "multi-cell non-structure measures to its origin, not the footprint (got %s)" % pos
    )


# --- Follow-attack blocker routing (#277) ---


func _make_chase_attacker() -> Array:
    # A ground attacker with a MovementController, in the tree so global
    # positions resolve. Returns [entity, mc, cc].
    if _ts == null:
        TestHelper.fail("TerrainSystem not injected")
        return []
    _ts.init_grid(32, 32)
    if SpatialHash.instance:
        SpatialHash.instance._grid.clear()
        SpatialHash.instance._building_cells.clear()
    var root: Node = Engine.get_main_loop().root
    var entity := _make_combat_entity(true, 0)
    root.add_child(entity)
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    mc._parent = entity
    entity.global_position = Vector3(0, 0, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    return [entity, mc, cc]


func _chase_move_count(mc: MovementController) -> Array:
    # Signal counter for movement_started on this controller.
    var counter := [0]
    mc.movement_started.connect(func(): counter[0] += 1)
    return counter


func _path_crosses_cell(waypoints: PackedVector3Array, cell: Vector2i) -> bool:
    for i in range(1, waypoints.size()):
        if CellUtil.world_to_cell(waypoints[i]) == cell:
            return true
    return false


func test_chase_replans_around_building():
    # Regression (#277): a target moving behind a building must trigger an
    # obstacle-aware re-plan whose path never enters the building footprint.
    var setup: Array = _make_chase_attacker()
    if setup.is_empty():
        return
    var entity: Node3D = setup[0]
    var mc: MovementController = setup[1]
    var cc: CombatComponent = setup[2]
    var root: Node = Engine.get_main_loop().root
    var target := _make_target_with_health(1, 100)
    root.add_child(target)
    target.global_position = Vector3(30.0, 0.0, 0.0)
    var building_cell := CellUtil.world_to_cell(Vector3(10.0, 0.0, 0.0))
    SpatialHash.instance.register_building_cells([building_cell])
    var count := _chase_move_count(mc)
    cc.set_target(target)
    var first_path_clear: bool = not _path_crosses_cell(mc._waypoints, building_cell)
    var replans_after_order: int = count[0]
    cc._last_chase_replan_time = 0.0
    target.global_position = Vector3(30.0, 0.0, 4.0)
    cc._physics_process(0.1)
    var replanned: bool = count[0] > replans_after_order
    var second_path_clear: bool = not _path_crosses_cell(mc._waypoints, building_cell)
    var target_preserved: bool = cc._target == target
    SpatialHash.instance.unregister_building_cells([building_cell])
    root.remove_child(entity)
    root.remove_child(target)
    entity.free()
    target.free()
    TestHelper.assert_true(first_path_clear, "initial chase path routes around the building cell")
    TestHelper.assert_true(replanned, "chase re-plans when the target crosses a cell boundary")
    TestHelper.assert_true(second_path_clear, "re-planned path avoids the building cell")
    TestHelper.assert_true(target_preserved, "attack target preserved across re-plan")


func test_chase_stationary_target_no_replans():
    # A target that never changes cell must produce exactly one chase move.
    var setup: Array = _make_chase_attacker()
    if setup.is_empty():
        return
    var entity: Node3D = setup[0]
    var mc: MovementController = setup[1]
    var cc: CombatComponent = setup[2]
    var root: Node = Engine.get_main_loop().root
    var target := _make_target_with_health(1, 100)
    root.add_child(target)
    target.global_position = Vector3(30.0, 0.0, 0.0)
    var count := _chase_move_count(mc)
    cc.set_target(target)
    var initial_dest: Vector3 = mc.get_target_position()
    var after_order: int = count[0]
    for i in 5:
        cc._physics_process(0.1)
    var dest_unchanged: bool = mc.get_target_position().is_equal_approx(initial_dest)
    var no_replans: bool = count[0] == after_order
    var target_kept: bool = cc._target == target
    root.remove_child(entity)
    root.remove_child(target)
    entity.free()
    target.free()
    TestHelper.assert_eq(after_order, 1, "set_target issues exactly one chase move")
    TestHelper.assert_true(no_replans, "stationary target triggers no re-plans")
    TestHelper.assert_true(dest_unchanged, "chase destination unchanged for stationary target")
    TestHelper.assert_true(target_kept, "attack target preserved")


func test_chase_replan_throttle():
    # Boundary: a cell-crossing target re-plans at most once per throttle
    # interval; the same stale leg re-plans once the interval elapses.
    var setup: Array = _make_chase_attacker()
    if setup.is_empty():
        return
    var entity: Node3D = setup[0]
    var mc: MovementController = setup[1]
    var cc: CombatComponent = setup[2]
    var root: Node = Engine.get_main_loop().root
    var target := _make_target_with_health(1, 100)
    root.add_child(target)
    target.global_position = Vector3(30.0, 0.0, 0.0)
    var count := _chase_move_count(mc)
    cc.set_target(target)
    var first_dest: Vector3 = mc.get_target_position()
    cc._last_chase_replan_time = cc._now()
    target.global_position = Vector3(30.0, 0.0, 4.0)
    cc._physics_process(0.1)
    var throttled: bool = count[0] == 1
    var dest_held: bool = mc.get_target_position().is_equal_approx(first_dest)
    cc._last_chase_replan_time = 0.0
    cc._physics_process(0.1)
    var replanned: bool = count[0] == 2
    var dest_updated: bool = not mc.get_target_position().is_equal_approx(first_dest)
    root.remove_child(entity)
    root.remove_child(target)
    entity.free()
    target.free()
    TestHelper.assert_true(throttled, "re-plan suppressed within the throttle interval")
    TestHelper.assert_true(dest_held, "destination held while throttled")
    TestHelper.assert_true(replanned, "stale leg re-plans once the throttle elapses")
    TestHelper.assert_true(dest_updated, "destination updated after re-plan")


func test_chase_stop_position_clamped_off_building():
    # Destination invariant: a range-circle stop landing on a building cell is
    # relocated to a passable cell before the move is issued, and the relocated
    # stop stays within weapon range so the attacker fires on arrival.
    var setup: Array = _make_chase_attacker()
    if setup.is_empty():
        return
    var entity: Node3D = setup[0]
    var mc: MovementController = setup[1]
    var cc: CombatComponent = setup[2]
    var root: Node = Engine.get_main_loop().root
    var target := _make_target_with_health(1, 100)
    root.add_child(target)
    target.global_position = Vector3(20.0, 0.0, 0.0)
    var building_cell := CellUtil.world_to_cell(Vector3(10.0, 0.0, 0.0))
    SpatialHash.instance.register_building_cells([building_cell])
    cc.set_target(target)
    var dest_pos: Vector3 = mc.get_target_position()
    var dest_cell := CellUtil.world_to_cell(dest_pos)
    var blocked: bool = SpatialHash.instance.get_blocked_cells().has(CellUtil.cell_key(dest_cell))
    var weapon := cc.get_current_weapon()
    var range_world := weapon.attack_range * CellUtil.CELL_SIZE
    var in_range: bool = (
        (
            Vector2(dest_pos.x - target.global_position.x, dest_pos.z - target.global_position.z)
            . length()
        )
        <= range_world + 0.01
    )
    SpatialHash.instance.unregister_building_cells([building_cell])
    root.remove_child(entity)
    root.remove_child(target)
    entity.free()
    target.free()
    (
        TestHelper
        . assert_true(
            dest_cell != building_cell and not blocked,
            (
                "chase stop position relocated off a building cell (dest_cell=%s, building=%s)"
                % [dest_cell, building_cell]
            ),
        )
    )
    TestHelper.assert_true(in_range, "relocated chase stop stays within weapon range")


func test_chase_replans_out_of_wait_state():
    # A WAIT-state attacker with an out-of-range target must leave WAIT and
    # issue a new approach move instead of freezing.
    var setup: Array = _make_chase_attacker()
    if setup.is_empty():
        return
    var entity: Node3D = setup[0]
    var mc: MovementController = setup[1]
    var cc: CombatComponent = setup[2]
    var root: Node = Engine.get_main_loop().root
    var target := _make_target_with_health(1, 100)
    root.add_child(target)
    target.global_position = Vector3(30.0, 0.0, 0.0)
    cc.set_target(target)
    mc._state = MovementController.State.WAIT
    cc._physics_process(0.1)
    var left_wait: bool = mc._state != MovementController.State.WAIT
    var target_kept: bool = cc._target == target
    root.remove_child(entity)
    root.remove_child(target)
    entity.free()
    target.free()
    TestHelper.assert_true(left_wait, "WAIT attacker re-plans when target out of range")
    TestHelper.assert_true(target_kept, "attack target preserved after WAIT re-plan")


func test_chase_in_range_wait_fires_without_replan():
    # An in-range WAIT attacker fires normally and must NOT re-plan.
    var setup: Array = _make_chase_attacker()
    if setup.is_empty():
        return
    var entity: Node3D = setup[0]
    var mc: MovementController = setup[1]
    var cc: CombatComponent = setup[2]
    var root: Node = Engine.get_main_loop().root
    var target := _make_target_with_health(1, 100)
    root.add_child(target)
    target.global_position = Vector3(3.0, 0.0, 0.0)
    cc.set_target(target)
    mc._state = MovementController.State.WAIT
    # The first ticks slew the body onto the target; the shot follows once
    # aligned, without any re-plan.
    var fired := false
    for i in 20:
        cc._physics_process(0.1)
        if target.get_node("HealthComponent").current_health < 100:
            fired = true
            break
    var stayed_wait: bool = mc._state == MovementController.State.WAIT
    root.remove_child(entity)
    root.remove_child(target)
    entity.free()
    target.free()
    TestHelper.assert_true(fired, "in-range WAIT attacker fires")
    TestHelper.assert_true(stayed_wait, "in-range WAIT attacker does not re-plan")


func test_chase_pathfinding_failure_backoff():
    # A failed chase path must gate re-plans behind a backoff (no per-tick A*
    # storm) while still allowing fire-in-place for an in-range target.
    var setup: Array = _make_chase_attacker()
    if setup.is_empty():
        return
    var entity: Node3D = setup[0]
    var mc: MovementController = setup[1]
    var cc: CombatComponent = setup[2]
    var root: Node = Engine.get_main_loop().root
    var target := _make_target_with_health(1, 100)
    root.add_child(target)
    target.global_position = Vector3(30.0, 0.0, 0.0)
    var count := _chase_move_count(mc)
    cc.set_target(target)
    cc._on_pathfinding_failed()
    var find_calls: int = Pathfinder.find_path_call_count
    var dest_before: Vector3 = mc.get_target_position()
    target.global_position = Vector3(30.0, 0.0, 4.0)
    for i in 3:
        cc._physics_process(0.1)
    var no_replan: bool = count[0] == 1
    var dest_held: bool = mc.get_target_position().is_equal_approx(dest_before)
    var no_a_star: bool = Pathfinder.find_path_call_count == find_calls
    target.get_node("HealthComponent").current_health = 100
    target.global_position = Vector3(3.0, 0.0, 0.0)
    # The failed chase never re-targets, so the leg ends; the idle attacker
    # must slew onto the target before firing during the backoff.
    mc._state = MovementController.State.IDLE
    var fired_backoff := false
    for i in 20:
        cc._physics_process(0.1)
        if target.get_node("HealthComponent").current_health < 100:
            fired_backoff = true
            break
    root.remove_child(entity)
    root.remove_child(target)
    entity.free()
    target.free()
    TestHelper.assert_true(no_replan, "no re-plan during pathfinding-failure backoff")
    TestHelper.assert_true(dest_held, "destination held during backoff")
    TestHelper.assert_true(no_a_star, "no A* retried per tick during backoff")
    TestHelper.assert_true(fired_backoff, "in-range target still fired during backoff")


func test_chase_replan_keeps_target_then_player_move_clears():
    # Re-plans must preserve the attack target; a player move order must clear it.
    var setup: Array = _make_chase_attacker()
    if setup.is_empty():
        return
    var entity: Node3D = setup[0]
    var mc: MovementController = setup[1]
    var cc: CombatComponent = setup[2]
    var root: Node = Engine.get_main_loop().root
    var target := _make_target_with_health(1, 100)
    root.add_child(target)
    target.global_position = Vector3(30.0, 0.0, 0.0)
    cc.set_target(target)
    cc._last_chase_replan_time = 0.0
    target.global_position = Vector3(30.0, 0.0, 4.0)
    cc._physics_process(0.1)
    var kept_after_replan: bool = cc._target == target
    mc.set_target_position(Vector3(5, 0, 5))
    var cleared_after_player_move: bool = cc._target == null
    root.remove_child(entity)
    root.remove_child(target)
    entity.free()
    target.free()
    TestHelper.assert_true(kept_after_replan, "attack target kept across chase re-plan")
    TestHelper.assert_true(cleared_after_player_move, "player move order clears the attack target")


# --- Combat facing (units-face-attack-target) ---


func _make_facing_attacker(rotation_deg: float, instant: bool) -> Array:
    # Stationary ground attacker with a MovementController whose _rotation_target
    # is a plain child pivot (avoids TerrainSystem normal reads in _apply_facing).
    # Returns [entity, mc, cc, pivot].
    var entity := _make_combat_entity(true, 0)
    var root: Node = Engine.get_main_loop().root
    root.add_child(entity)
    entity.global_position = Vector3(0, 0, 0)
    var mc := MovementController.new()
    mc.name = "MovementController"
    mc.rotation_speed = rotation_deg
    entity.add_child(mc)
    mc._parent = entity
    var pivot := Node3D.new()
    pivot.name = "FacingPivot"
    entity.add_child(pivot)
    mc._rotation_target = pivot
    mc._stand_upright = true
    mc._instant_turn = instant
    mc._rotation_yaw = 0.0
    var cc := entity.get_node("CombatComponent") as CombatComponent
    return [entity, mc, cc, pivot]


func _yaw_of(pivot: Node3D) -> float:
    return pivot.global_transform.basis.z.signed_angle_to(Vector3(0, 0, 1), Vector3.UP)


func test_configure_adopts_rotation_speed():
    var mc := MovementController.new()
    var data := EntityData.new()
    data.rotation_speed = 90.0
    mc.configure(data)
    TestHelper.assert_eq(mc.rotation_speed, 90.0, "configure adopts data.rotation_speed")
    mc.free()
    data.free()


func test_proportional_slew_same_arc():
    # Two units slewing the same 90-degree arc at 90 vs 180 deg/s: the first
    # takes twice as many fixed-delta steps to align (independent of impl).
    var results := []
    for rate in [90.0, 180.0]:
        var setup: Array = _make_facing_attacker(rate, false)
        var mc: MovementController = setup[1]
        var target_pos := Vector3(10.0, 0.0, 0.0)
        var steps := 0
        var aligned := false
        while not aligned and steps < 100:
            aligned = mc.face_toward(target_pos, 0.1)
            steps += 1
        results.append(steps)
        (setup[0] as Node3D).get_parent().remove_child(setup[0])
        (setup[0] as Node3D).free()
    TestHelper.assert_true(results[0] > 0, "slow unit needs steps to align")
    TestHelper.assert_true(results[1] > 0, "fast unit needs steps to align")
    TestHelper.assert_eq(results[0], results[1] * 2, "half rate takes twice the steps")


func test_face_toward_instant_turn_snaps():
    var setup: Array = _make_facing_attacker(180.0, true)
    var mc: MovementController = setup[1]
    var pivot: Node3D = setup[3]
    var aligned: bool = mc.face_toward(Vector3(10.0, 0.0, 0.0), 0.016)
    var yaw := _yaw_of(pivot)
    TestHelper.assert_true(aligned, "instant-turn returns aligned same call")
    TestHelper.assert_true(absf(yaw - PI / 2.0) < 0.01, "infantry snaps to target")
    (setup[0] as Node3D).get_parent().remove_child(setup[0])
    (setup[0] as Node3D).free()


func test_face_toward_slew_no_signals():
    var setup: Array = _make_facing_attacker(180.0, false)
    var mc: MovementController = setup[1]
    var fired := [false]
    mc.movement_started.connect(func(): fired[0] = true)
    var aligned: bool = mc.face_toward(Vector3(10.0, 0.0, 0.0), 0.25)
    var waypoints_empty: bool = mc._waypoints.is_empty()
    TestHelper.assert_true(not aligned, "90-degree slew not aligned after 45-degree step")
    TestHelper.assert_true(not fired[0], "face_toward emits no movement_started")
    TestHelper.assert_true(waypoints_empty, "face_toward touches no waypoints")
    (setup[0] as Node3D).get_parent().remove_child(setup[0])
    (setup[0] as Node3D).free()


func _make_moved_vehicle() -> Array:
    # Vehicle that just drove a curved MOVING leg: body faces +X while the yaw
    # mirror still holds the leg-start heading (0) — the stale-mirror state a
    # curved move used to leave behind. One tick travels +X from origin.
    var setup: Array = _make_facing_attacker(180.0, false)
    var entity: Node3D = setup[0]
    var mc: MovementController = setup[1]
    mc._apply_facing(Vector3(1, 0, 0))
    mc._rotation_yaw = 0.0
    mc._state = MovementController.State.MOVING
    mc._waypoints = PackedVector3Array(
        [entity.global_position, entity.global_position + Vector3(10, 0, 0)]
    )
    mc._bake_spline()
    mc._spline_t = 0.0
    mc._handle_moving_movement(0.016)
    return setup


func test_moving_tick_syncs_rotation_yaw_with_body():
    var setup: Array = _make_moved_vehicle()
    var mc: MovementController = setup[1]
    var pivot: Node3D = setup[3]
    # Travelling +X maps to the face_toward yaw convention atan2(-1, 0) = -PI/2.
    TestHelper.assert_true(
        absf(mc._rotation_yaw + PI / 2.0) < 0.02,
        "MOVING tick syncs _rotation_yaw to travel heading: got %f" % mc._rotation_yaw
    )
    TestHelper.assert_true(
        absf(mc._rotation_yaw + _yaw_of(pivot)) < 0.02,
        "yaw mirror matches actual body heading after a MOVING tick"
    )
    (setup[0] as Node3D).get_parent().remove_child(setup[0])
    (setup[0] as Node3D).free()


func test_attack_facing_after_move_slews_from_true_heading():
    # Reported glitch: vehicle moving, attack issued with the target already in
    # range, and the post-stop facing call snapped the body because face_toward
    # trusted the stale yaw mirror. The body must slew from its true heading.
    var setup: Array = _make_moved_vehicle()
    var entity: Node3D = setup[0]
    var mc: MovementController = setup[1]
    var pivot: Node3D = setup[3]
    var yaw_before: float = _yaw_of(pivot)
    var step: float = deg_to_rad(mc.rotation_speed) * 0.016
    mc.face_toward(entity.global_position + Vector3(0, 0, -10), 0.016)
    var moved := absf(angle_difference(yaw_before, _yaw_of(pivot)))
    TestHelper.assert_true(
        moved <= step + 0.02,
        "first attack-facing tick slews from true heading, no snap: moved %f" % moved
    )
    var steps := 1
    while absf(angle_difference(_yaw_of(pivot), 0.0)) > deg_to_rad(5.0) and steps < 100:
        mc.face_toward(entity.global_position + Vector3(0, 0, -10), 0.016)
        steps += 1
    TestHelper.assert_true(steps < 100, "body actually reaches the attack heading")
    (entity as Node3D).get_parent().remove_child(entity)
    (entity as Node3D).free()


func test_stationary_vehicle_holds_fire_then_fires_aligned():
    var setup: Array = _make_facing_attacker(180.0, false)
    var entity: Node3D = setup[0]
    var pivot: Node3D = setup[3]
    var cc: CombatComponent = setup[2]
    var target := _make_target_with_health(1, 1000)
    Engine.get_main_loop().root.add_child(target)
    target.global_position = Vector3(6.0, 0.0, 0.0)
    var fired := [false]
    cc.weapon_fired.connect(func(_w: WeaponData, _t: Node3D): fired[0] = true)
    cc.set_target(target)
    cc._physics_process(0.25)
    var held: bool = not fired[0]
    var ticks := 0
    while not fired[0] and ticks < 20:
        cc._physics_process(0.25)
        ticks += 1
    var yaw := _yaw_of(pivot)
    Engine.get_main_loop().root.remove_child(target)
    entity.get_parent().remove_child(entity)
    target.free()
    entity.free()
    TestHelper.assert_true(held, "out-of-arc vehicle holds fire first tick")
    TestHelper.assert_true(fired[0], "vehicle fires once aligned")
    TestHelper.assert_true(
        absf(absf(yaw) - PI / 2.0) < deg_to_rad(6.0), "yaw within tolerance at fire time"
    )


func test_stationary_infantry_snaps_and_fires_same_tick():
    var setup: Array = _make_facing_attacker(180.0, true)
    var entity: Node3D = setup[0]
    var cc: CombatComponent = setup[2]
    var target := _make_target_with_health(1, 1000)
    Engine.get_main_loop().root.add_child(target)
    target.global_position = Vector3(0, 0, -6.0)
    var fired := [false]
    cc.weapon_fired.connect(func(_w: WeaponData, _t: Node3D): fired[0] = true)
    cc.set_target(target)
    cc._physics_process(0.016)
    Engine.get_main_loop().root.remove_child(target)
    entity.get_parent().remove_child(entity)
    target.free()
    entity.free()
    TestHelper.assert_true(fired[0], "infantry snaps and fires same tick")


func test_building_fires_without_mc():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target_with_health(1, 1000)
    target.global_position = Vector3(0, 0, -6.0)
    var fired := [false]
    cc.weapon_fired.connect(func(_w: WeaponData, _t: Node3D): fired[0] = true)
    cc.set_target(target)
    cc._physics_process(0.016)
    TestHelper.assert_true(fired[0], "building without MC fires with no facing gate")
    TestHelper.assert_true(entity.rotation.y == 0.0, "building does not rotate")
    entity.free()
    target.free()


func test_close_range_fires_without_turning():
    var setup: Array = _make_facing_attacker(1.0, false)
    var entity: Node3D = setup[0]
    var pivot: Node3D = setup[3]
    var cc: CombatComponent = setup[2]
    var target := _make_target_with_health(1, 1000)
    Engine.get_main_loop().root.add_child(target)
    target.global_position = Vector3(1.0, 5.0, 0.0)
    var fired := [false]
    cc.weapon_fired.connect(func(_w: WeaponData, _t: Node3D): fired[0] = true)
    cc.set_target(target)
    cc._physics_process(0.016)
    var yaw := _yaw_of(pivot)
    Engine.get_main_loop().root.remove_child(target)
    entity.get_parent().remove_child(entity)
    target.free()
    entity.free()
    TestHelper.assert_true(fired[0], "close target fires despite yaw (deadzone)")
    TestHelper.assert_true(absf(yaw) < 0.01, "body did not turn for deadzone shot")
    TestHelper.assert_true(true, "vertical separation ignored for yaw")


# --- ground engagement (force-fire) ---


func _add_to_tree(entity: Node3D, pos: Vector3) -> void:
    Engine.get_main_loop().root.add_child(entity)
    entity.global_position = pos


func _remove_from_tree(entity: Node3D) -> void:
    if entity.is_inside_tree():
        entity.get_parent().remove_child(entity)
    entity.free()


func test_order_force_attack_ground_returns_attack():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var pos := Vector3(8.0, 0.0, 4.0)
    var order := cc.get_order_for_target(
        null, Vector2i.ZERO, pos, {OrderResult.MOD_FORCE_ATTACK: true}
    )
    TestHelper.assert_true(order != null, "force-fire on ground -> order not null")
    TestHelper.assert_eq(order.cursor, CursorState.Type.ATTACK, "ground cursor -> ATTACK")
    TestHelper.assert_eq(order.priority, 30, "ground force-fire priority -> 30")
    TestHelper.assert_true(order.target == null, "ground force-fire holds no entity target")
    TestHelper.assert_eq(order.target_pos, pos, "ground force-fire carries the ordered position")
    order.execute.call()
    TestHelper.assert_true(cc.is_engaged(), "executing the order engages")
    TestHelper.assert_true(cc.get_target() == null, "ground engagement holds no entity target")
    var expected_center := CellUtil.cell_to_world(CellUtil.world_to_cell(pos))
    (
        TestHelper
        . assert_eq(
            cc._target_pos,
            Vector3(expected_center.x, pos.y, expected_center.z),
            "engagement snaps the ordered position to the cell centre",
        )
    )
    cc.clear_target()
    entity.free()


func test_order_force_attack_ground_unarmed_returns_null():
    var entity := _make_combat_entity(false, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var order := cc.get_order_for_target(
        null, Vector2i.ZERO, Vector3.ZERO, {OrderResult.MOD_FORCE_ATTACK: true}
    )
    TestHelper.assert_true(order == null, "unarmed entity never force-fires")
    entity.free()


func test_order_force_attack_neutral_returns_attack():
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    var target := _make_target(-1)
    var order := cc.get_order_for_target(
        target, Vector2i.ZERO, Vector3.ZERO, {OrderResult.MOD_FORCE_ATTACK: true}
    )
    TestHelper.assert_true(order != null, "force-fire on neutral -> order not null")
    TestHelper.assert_eq(order.cursor, CursorState.Type.ATTACK, "neutral cursor -> ATTACK")
    entity.free()
    target.free()


func test_ground_engagement_fires_in_range():
    _inject_test_rules()
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    _add_to_tree(entity, Vector3.ZERO)
    var fired := [0]
    cc.weapon_fired.connect(func(_w: WeaponData, _t: Node3D) -> void: fired[0] += 1)
    cc.set_ground_target(Vector3(4.0, 0.0, 0.0))
    cc._physics_process(0.016)
    var health_missing := cc.get_target() == null
    TestHelper.assert_eq(fired[0], 1, "ground engagement fires in range")
    TestHelper.assert_true(health_missing, "no entity target while firing at ground")
    _remove_from_tree(entity)
    _restore_rules()


func test_ground_engagement_repeats_across_cooldowns():
    _inject_test_rules()
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    _add_to_tree(entity, Vector3.ZERO)
    var fired := [0]
    cc.weapon_fired.connect(func(_w: WeaponData, _t: Node3D) -> void: fired[0] += 1)
    cc.set_ground_target(Vector3(4.0, 0.0, 0.0))
    for i in 4:
        cc._physics_process(0.05)
    TestHelper.assert_true(fired[0] >= 2, "repeats on each elapsed cooldown without re-issue")
    TestHelper.assert_true(cc.is_engaged(), "still engaged after repeated fire")
    _remove_from_tree(entity)
    _restore_rules()


func test_ground_engagement_survives_many_ticks():
    _inject_test_rules()
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    _add_to_tree(entity, Vector3.ZERO)
    cc.set_ground_target(Vector3(4.0, 0.0, 0.0))
    for i in 120:
        cc._physics_process(0.016)
    TestHelper.assert_true(cc.is_engaged(), "ground engagement never self-terminates")
    TestHelper.assert_true(cc.get_target() == null, "still no entity target")
    _remove_from_tree(entity)
    _restore_rules()


func test_ground_engagement_approaches_when_out_of_range():
    _inject_test_rules()
    var setup: Array = _make_moving_ground_attacker()
    if setup.is_empty():
        _restore_rules()
        return
    var entity: Node3D = setup[0]
    var cc: CombatComponent = setup[2]
    cc.set_ground_target(Vector3(40.0, 0.0, 0.0))
    # _combat_move is consumed by the movement_started signal the approach move
    # itself emits, so assert on the chase anchor it writes alongside it.
    var chased := cc._chase_leg_enemy_cell == CellUtil.world_to_cell(Vector3(40.0, 0.0, 0.0))
    TestHelper.assert_true(cc.is_engaged(), "engaged while out of range")
    TestHelper.assert_true(chased, "an approach move was issued for the ground point")
    _remove_from_tree(entity)
    _restore_rules()


func test_player_move_clears_ground_engagement():
    if _ts == null:
        TestHelper.fail("TerrainSystem not injected")
        return
    _ts.init_grid(32, 32)
    var entity := _make_combat_entity(true, 0)
    add_child(entity)
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    mc._parent = entity
    var cc := entity.get_node("CombatComponent") as CombatComponent
    entity.global_position = Vector3(1, 0, 1)
    cc.set_ground_target(Vector3(9, 0, 9))
    TestHelper.assert_true(cc.is_engaged(), "ground engagement active before the move")
    mc.set_target_position(Vector3(5, 0, 5))
    TestHelper.assert_true(not cc.is_engaged(), "player move clears the ground engagement")
    _ts.clear()
    remove_child(entity)
    entity.free()


func test_entity_to_ground_transition_detaches_health_signal():
    # Regression: set_ground_target() nulls _target, so _connect_health_signal()
    # used to bail before disconnecting the previous entity — its death then
    # called clear_target() and cancelled the player's ground engagement.
    _inject_test_rules()
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    _add_to_tree(entity, Vector3.ZERO)
    var old_target := _make_target_with_health(1, 100)
    _add_to_tree(old_target, Vector3(4.0, 0.0, 0.0))
    cc.set_target(old_target)
    cc.set_ground_target(Vector3(8.0, 0.0, 0.0))
    var hc := old_target.get_node("HealthComponent") as HealthComponent
    var still_connected: bool = hc.health_zero.is_connected(cc._on_target_health_zero)
    hc.health_zero.emit()
    var survived: bool = cc.is_engaged() and cc.get_target() == null
    _remove_from_tree(old_target)
    _remove_from_tree(entity)
    _restore_rules()
    TestHelper.assert_true(not still_connected, "old target's health_zero is detached")
    TestHelper.assert_true(survived, "ground engagement survives the old target dying")


func test_set_target_null_is_rejected():
    # A null entity would engage at whatever position the previous target left
    # behind, so the entry point refuses it (push_error + return).
    var entity := _make_combat_entity(true, 0)
    var cc := entity.get_node("CombatComponent") as CombatComponent
    cc.set_ground_target(Vector3(6.0, 0.0, 2.0))
    var pos_before: Vector3 = cc._target_pos
    cc.set_target(null)
    var unchanged: bool = cc._target_pos == pos_before and cc.is_engaged()
    cc.clear_target()
    entity.free()
    TestHelper.assert_true(unchanged, "set_target(null) is rejected and leaves state untouched")
