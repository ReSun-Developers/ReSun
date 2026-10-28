extends Node

# FX trigger integration tests — CombatComponent plays the weapon muzzle effect,
# and WeaponDetonation plays the warhead impact effect through FxSystem, for both
# the hitscan and projectile damage paths. Synchronous: no awaited frames.

var _ef: Node = null
var _rules: GlobalRules = null
var _real_rules: GlobalRules = null

const MUZZLE_ORIGIN := Vector3(3, 2, 1)


func _tree() -> SceneTree:
    return Engine.get_main_loop() as SceneTree


func _fx() -> Node:
    return _tree().root.get_node_or_null("FxSystem")


func _inject_rules(impact_fx: FxData = null) -> void:
    _real_rules = _ef.get_global_rules() as GlobalRules
    _rules = GlobalRules.new()
    _rules.shroud_enabled = false
    _rules.fog_of_war = false
    _rules.min_damage = 1
    _rules.max_damage = 1000
    _rules.default_projectile_speed = 12.0
    var sa := WarheadData.new()
    sa.id = "SA"
    sa.armor_damage_multipliers = {"none": 1.0}
    sa.impact_fx = impact_fx
    _rules.warheads["SA"] = sa
    var invisible := ProjectileData.new()
    invisible.id = "Invisible"
    invisible.is_invisible = true
    _rules.projectiles["Invisible"] = invisible
    _ef.set_global_rules(_rules)


func _restore_rules() -> void:
    if _real_rules != null:
        _ef.set_global_rules(_real_rules)
    _real_rules = null
    _rules = null


func _reset_fx() -> void:
    var fx := _fx()
    if fx == null:
        return
    for entry in fx._active:
        var node: Node3D = entry["node"]
        if is_instance_valid(node):
            node.free()
    fx._active.clear()


func _last_fx_node() -> Node3D:
    var fx := _fx()
    if fx == null or fx._active.is_empty():
        return null
    return fx._active[-1]["node"] as Node3D


func _sprite_fx(id: String) -> FxData:
    var fx := FxData.new()
    fx.id = id
    fx.kind = FxData.Kind.SPRITE
    var sheet := SpriteFrames.new()
    if not sheet.has_animation("default"):
        sheet.add_animation("default")
    sheet.set_animation_speed("default", 1.0)
    sheet.add_frame("default", PlaceholderTexture2D.new(), 0.2)
    fx.sprite_frames = sheet
    fx.duration = 0.2
    return fx


func _make_entity(player_id: int, pos: Vector3 = Vector3.ZERO) -> Node3D:
    var entity := Node3D.new()
    entity.name = "Entity_P%d" % player_id
    entity.position = pos
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    stats.armor = "none"
    entity.add_child(stats)
    var health := HealthComponent.new()
    health.name = "HealthComponent"
    health.max_health = 100
    health.current_health = 100
    entity.add_child(health)
    _tree().root.add_child(entity)
    return entity


func _make_shooter() -> Node3D:
    var entity := _make_entity(0)
    var combat := CombatComponent.new()
    combat.name = "CombatComponent"
    entity.add_child(combat)
    return entity


func _make_weapon(projectile_id: String, muzzle_fx: FxData = null) -> WeaponData:
    var weapon := WeaponData.new()
    weapon.id = "TEST_W"
    weapon.damage = 20
    weapon.attack_range = 5.0
    weapon.rate_of_fire = 6000.0
    weapon.warhead = "SA"
    weapon.projectile = projectile_id
    weapon.fire_offset = Vector3(1, 1, 0)
    weapon.muzzle_fx = muzzle_fx
    return weapon


func _cleanup(nodes: Array) -> void:
    for n in nodes:
        if is_instance_valid(n):
            n.free()


func test_muzzle_fx_body_mounted_at_fire_offset():
    _inject_rules()
    _reset_fx()
    var shooter := _make_shooter()
    var victim := _make_entity(1, Vector3(4, 0, 0))
    var combat := shooter.get_node("CombatComponent") as CombatComponent
    var muzzle := _sprite_fx("Muzzle")
    var weapon := _make_weapon("", muzzle)
    combat._fire_weapon(weapon, victim)
    var node := _last_fx_node()
    TestHelper.assert_true(node != null, "muzzle effect spawned")
    (
        TestHelper
        . assert_true(
            node.global_position.distance_to(shooter.global_transform * weapon.fire_offset) < 0.001,
            "muzzle effect sits at the body muzzle (entity transform * fire_offset)",
        )
    )
    _cleanup([shooter, victim])
    _reset_fx()
    _restore_rules()


func test_muzzle_fx_body_mounted_follows_body_rotation():
    # The fire offset is entity-local: a rotated body must move the muzzle off
    # the world-space axis, not keep it fixed.
    _inject_rules()
    _reset_fx()
    var shooter := _make_shooter()
    shooter.rotation.y = deg_to_rad(90.0)
    var victim := _make_entity(1, Vector3(4, 0, 0))
    var combat := shooter.get_node("CombatComponent") as CombatComponent
    var muzzle := _sprite_fx("MuzzleRotated")
    var weapon := _make_weapon("", muzzle)
    var expected := shooter.global_transform * weapon.fire_offset
    combat._fire_weapon(weapon, victim)
    var node := _last_fx_node()
    TestHelper.assert_true(node != null, "muzzle effect spawned")
    (
        TestHelper
        . assert_true(
            node.global_position.distance_to(expected) < 0.001,
            "muzzle follows the body orientation",
        )
    )
    (
        TestHelper
        . assert_true(
            node.global_position.distance_to(shooter.global_position + weapon.fire_offset) > 0.01,
            "muzzle is not the fixed world-space offset",
        )
    )
    _cleanup([shooter, victim])
    _reset_fx()
    _restore_rules()


func test_muzzle_fx_explicit_muzzle_origin():
    # Covers the turret/socket path: CombatComponent calls _fire_weapon with the
    # socket world muzzle transform (origin + basis) as explicit arguments.
    _inject_rules()
    _reset_fx()
    var shooter := _make_shooter()
    var victim := _make_entity(1, Vector3(4, 0, 0))
    var combat := shooter.get_node("CombatComponent") as CombatComponent
    var muzzle := _sprite_fx("MuzzleSocket")
    var weapon := _make_weapon("", muzzle)
    var muzzle_basis := Basis(Vector3.UP, deg_to_rad(90.0))
    combat._fire_weapon(weapon, victim, MUZZLE_ORIGIN, muzzle_basis)
    var node := _last_fx_node()
    TestHelper.assert_true(node != null, "muzzle effect spawned")
    (
        TestHelper
        . assert_true(
            node.global_position.distance_to(MUZZLE_ORIGIN) < 0.001,
            "muzzle effect uses the explicit socket muzzle origin",
        )
    )
    (
        TestHelper
        . assert_true(
            node.global_transform.basis.is_equal_approx(muzzle_basis),
            "muzzle effect keeps the socket basis so directional particles aim along the barrel",
        )
    )
    _cleanup([shooter, victim])
    _reset_fx()
    _restore_rules()


func test_muzzle_fx_null_is_silent():
    _inject_rules()
    _reset_fx()
    var shooter := _make_shooter()
    var victim := _make_entity(1, Vector3(4, 0, 0))
    var combat := shooter.get_node("CombatComponent") as CombatComponent
    combat._fire_weapon(_make_weapon("", null), victim)
    TestHelper.assert_eq(_fx().active_count(), 0, "no effect spawned when muzzle_fx is null")
    _cleanup([shooter, victim])
    _reset_fx()
    _restore_rules()


func test_warhead_impact_fx_on_hitscan_damage():
    var impact := _sprite_fx("HitPuff")
    _inject_rules(impact)
    _reset_fx()
    var shooter := _make_shooter()
    var victim := _make_entity(1, Vector3(4, 0, 0))
    var combat := shooter.get_node("CombatComponent") as CombatComponent
    combat._fire_weapon(_make_weapon("", null), victim)
    var node := _last_fx_node()
    TestHelper.assert_true(node != null, "impact effect spawned on hitscan hit")
    (
        TestHelper
        . assert_true(
            node.global_position.distance_to(victim.global_position) < 0.001,
            "impact effect sits at the victim",
        )
    )
    _cleanup([shooter, victim])
    _reset_fx()
    _restore_rules()


func test_warhead_impact_fx_on_projectile_damage():
    var impact := _sprite_fx("HitPuff")
    _inject_rules(impact)
    _reset_fx()
    var shooter := _make_shooter()
    var victim := _make_entity(1, Vector3(4, 0, 0))
    var combat := shooter.get_node("CombatComponent") as CombatComponent
    # Invisible projectile teleport-detonates at dispatch through the same
    # detonation module as a visible projectile's contact detonation.
    combat._fire_weapon(_make_weapon("Invisible", null), victim)
    var node := _last_fx_node()
    TestHelper.assert_true(node != null, "impact effect spawned on projectile hit")
    (
        TestHelper
        . assert_true(
            node.global_position.distance_to(victim.global_position) < 0.001,
            "impact effect sits at the victim",
        )
    )
    _cleanup([shooter, victim])
    for child in _tree().root.get_children():
        if child is ProjectileController:
            child.free()
    _reset_fx()
    _restore_rules()


func test_warhead_impact_fx_null_is_silent():
    _inject_rules(null)
    _reset_fx()
    var shooter := _make_shooter()
    var victim := _make_entity(1, Vector3(4, 0, 0))
    var combat := shooter.get_node("CombatComponent") as CombatComponent
    combat._fire_weapon(_make_weapon("", null), victim)
    TestHelper.assert_eq(_fx().active_count(), 0, "no effect spawned when impact_fx is null")
    _cleanup([shooter, victim])
    _reset_fx()
    _restore_rules()


func test_warhead_impact_fx_zero_amount_is_silent():
    # A positive hit can round to zero applied damage (veteran armor); it must
    # not play an impact on a hit that dealt nothing.
    _inject_rules(_sprite_fx("HitPuff"))
    _rules.veteran_armor = 1.0
    _reset_fx()
    var shooter := _make_shooter()
    var victim := _make_entity(1, Vector3(4, 0, 0))
    var stats := victim.get_node("StatsComponent") as StatsComponent
    stats.veteran_level = 1
    var reports: Array = []
    var on_report := func(dtype: String, _position: Vector3) -> void: reports.append(dtype)
    _fx().impact_played.connect(on_report)
    var weapon := _make_weapon("", null)
    WeaponDetonation.detonate(weapon, shooter, weapon.damage, victim)
    _fx().impact_played.disconnect(on_report)
    TestHelper.assert_eq(reports.size(), 0, "no impact report on a zero-damage hit")
    TestHelper.assert_eq(_fx().active_count(), 0, "no impact effect on a zero-damage hit")
    _cleanup([shooter, victim])
    _reset_fx()
    _restore_rules()
