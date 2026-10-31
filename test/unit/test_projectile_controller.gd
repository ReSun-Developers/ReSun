extends Node

# ProjectileController unit tests — speed precedence, typed detonation handoff,
# and friendly-fire victim classification. All synchronous: the projectile is
# configured with setup() and detonated via _detonate_on() directly, no physics
# frames required. Nodes live under the real tree root so global transforms
# resolve; each test frees what it creates.

var _real_rules: GlobalRules = null


func _tree() -> SceneTree:
    return Engine.get_main_loop() as SceneTree


func _factory() -> Node:
    return _tree().root.get_node("EntityFactory")


func _inject_test_rules() -> void:
    var factory := _factory()
    _real_rules = factory.get_global_rules()
    var rules := GlobalRules.new()
    rules.min_damage = 1
    rules.max_damage = 1000
    rules.default_projectile_speed = 12.0
    var sa := WarheadData.new()
    sa.id = "SA"
    sa.armor_damage_multipliers = {"none": 1.0, "heavy": 0.25, "concrete": 0.0}
    rules.warheads["SA"] = sa
    var inv := ProjectileData.new()
    inv.id = "Invisible"
    rules.projectiles["Invisible"] = inv
    factory.set_global_rules(rules)


func _restore_rules() -> void:
    if _real_rules:
        _factory().set_global_rules(_real_rules)
        _real_rules = null


func _make_weapon(damage: int = 100) -> WeaponData:
    var w := WeaponData.new()
    w.id = "TEST_W"
    w.damage = damage
    w.attack_range = 5.0
    w.rate_of_fire = 60.0
    w.warhead = "SA"
    return w


func _make_data() -> ProjectileData:
    var d := ProjectileData.new()
    d.id = "TestData"
    d.targets_ground = true
    return d


func _make_entity(player_id: int, armor: String = "none") -> Node3D:
    var entity := Node3D.new()
    entity.name = "Unit%d" % player_id
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    stats.armor = armor
    entity.add_child(stats)
    var health := HealthComponent.new()
    health.name = "HealthComponent"
    health.max_health = 100
    health.current_health = 100
    entity.add_child(health)
    _tree().root.add_child(entity)
    return entity


func _make_projectile(
    data: ProjectileData,
    weapon: WeaponData,
    shooter: Node3D,
    target: Node3D,
    effective_damage: int = -1
) -> ProjectileController:
    var p := ProjectileController.new()
    p.setup(data, weapon, shooter, target, Vector3.INF, effective_damage)
    _tree().root.add_child(p)
    return p


func _teardown(nodes: Array) -> void:
    for n in nodes:
        if is_instance_valid(n):
            n.free()


# --- Speed precedence ---


func test_resolve_speed_override_wins():
    var data := _make_data()
    data.speed_override = 30.0
    var weapon := _make_weapon()
    weapon.speed = 10.0
    var rules := GlobalRules.new()
    rules.default_projectile_speed = 5.0
    (
        TestHelper
        . assert_eq(
            ProjectileController.resolve_speed(data, weapon, rules),
            30.0,
            "speed_override > weapon speed > default",
        )
    )


func test_resolve_speed_weapon_used_when_no_override():
    var data := _make_data()
    var weapon := _make_weapon()
    weapon.speed = 10.0
    var rules := GlobalRules.new()
    rules.default_projectile_speed = 5.0
    (
        TestHelper
        . assert_eq(
            ProjectileController.resolve_speed(data, weapon, rules),
            10.0,
            "weapon speed used when speed_override is 0",
        )
    )


func test_resolve_speed_global_default_last():
    var data := _make_data()
    var weapon := _make_weapon()
    var rules := GlobalRules.new()
    rules.default_projectile_speed = 7.5
    (
        TestHelper
        . assert_eq(
            ProjectileController.resolve_speed(data, weapon, rules),
            7.5,
            "GlobalRules default used when both data and weapon speeds are 0",
        )
    )


func test_resolve_speed_no_rules_zero():
    (
        TestHelper
        . assert_eq(
            ProjectileController.resolve_speed(_make_data(), _make_weapon(), null),
            0.0,
            "no rules and no speeds resolves to 0",
        )
    )


# --- Detonation handoff ---


func test_detonation_damage_reaches_health():
    _inject_test_rules()
    var shooter := _make_entity(0)
    var victim := _make_entity(1, "none")
    var p := _make_projectile(_make_data(), _make_weapon(100), shooter, victim)
    p._detonate_on(victim)
    var health := victim.get_node("HealthComponent") as HealthComponent
    TestHelper.assert_eq(health.current_health, 0, "SA vs none = 1.0x: 100 damage lands")
    _teardown([shooter, victim, p])
    _restore_rules()


func test_effective_damage_is_carried_to_detonation():
    _inject_test_rules()
    var shooter := _make_entity(0)
    var victim := _make_entity(1, "none")
    var health := victim.get_node("HealthComponent") as HealthComponent
    health.max_health = 200
    health.current_health = 200
    var p := _make_projectile(_make_data(), _make_weapon(100), shooter, victim, 125)
    p._detonate_on(victim)
    TestHelper.assert_eq(health.current_health, 75, "typed effective damage 125 is used")
    _teardown([shooter, victim, p])
    _restore_rules()


func test_impacted_signal_emitted_once():
    _inject_test_rules()
    var shooter := _make_entity(0)
    var victim := _make_entity(1, "none")
    var p := _make_projectile(_make_data(), _make_weapon(10), shooter, victim)
    var hits: Array[Vector3] = []
    p.impacted.connect(func(pos: Vector3) -> void: hits.append(pos))
    p._detonate_on(victim)
    p._detonate_on(victim)
    TestHelper.assert_eq(hits.size(), 1, "impacted emitted exactly once despite double call")
    _teardown([shooter, victim, p])
    _restore_rules()


# --- Friendly-fire victim classification ---


func test_shooter_is_invalid_victim():
    var shooter := _make_entity(0)
    var p := _make_projectile(_make_data(), _make_weapon(), shooter, _make_entity(1))
    TestHelper.assert_true(not p._is_valid_victim(shooter), "shooter never a valid victim")
    _teardown([shooter, p])


func test_ally_is_invalid_victim():
    var shooter := _make_entity(0)
    var ally := _make_entity(0)
    var p := _make_projectile(_make_data(), _make_weapon(), shooter, _make_entity(1))
    TestHelper.assert_true(not p._is_valid_victim(ally), "same-team unit never a valid victim")
    _teardown([shooter, ally, p])


func test_enemy_is_valid_victim():
    var shooter := _make_entity(0)
    var enemy := _make_entity(1)
    var p := _make_projectile(_make_data(), _make_weapon(), shooter, enemy)
    TestHelper.assert_true(p._is_valid_victim(enemy), "enemy is a valid victim")
    _teardown([shooter, enemy, p])


func test_neutral_is_valid_victim():
    var shooter := _make_entity(0)
    var neutral := _make_entity(-1)
    var p := _make_projectile(_make_data(), _make_weapon(), shooter, _make_entity(1))
    TestHelper.assert_true(
        p._is_valid_victim(neutral), "neutral (player_id -1) detonates projectile"
    )
    _teardown([shooter, neutral, p])


func test_statless_node_is_valid_victim():
    var shooter := _make_entity(0)
    var bare := Node3D.new()
    var p := _make_projectile(_make_data(), _make_weapon(), shooter, _make_entity(1))
    TestHelper.assert_true(
        p._is_valid_victim(bare), "node without StatsComponent detonates projectile"
    )
    bare.free()
    _teardown([shooter, p])
