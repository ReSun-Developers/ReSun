extends Node

# Projectile flight integration tests — synchronous, no awaited frames. The
# runner calls test methods directly, so physics behavior is driven by calling
# _physics_process(delta) manually on the projectile and nodes live under the
# real tree root (reached via Engine.get_main_loop()).

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/components/Projectile.tscn")
const HITBOX_SCENE: PackedScene = preload("res://scenes/components/HitboxComponent.tscn")

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
    inv.is_invisible = true
    rules.projectiles["Invisible"] = inv
    factory.set_global_rules(rules)


func _restore_rules() -> void:
    if _real_rules:
        _factory().set_global_rules(_real_rules)
        _real_rules = null


func _make_weapon(
    damage: int = 20, range_cells: float = 5.0, projectile_id: String = ""
) -> WeaponData:
    var w := WeaponData.new()
    w.id = "TEST_W"
    w.damage = damage
    w.attack_range = range_cells
    w.rate_of_fire = 6000.0
    w.warhead = "SA"
    w.projectile = projectile_id
    return w


func _make_data() -> ProjectileData:
    var d := ProjectileData.new()
    d.id = "FlightData"
    d.targets_ground = true
    return d


func _make_entity(player_id: int, armor: String = "none", pos: Vector3 = Vector3.ZERO) -> Node3D:
    var entity := Node3D.new()
    entity.name = "Entity_P%d" % player_id
    # Position BEFORE add_child: collision objects register with the physics
    # server at add-time transform, and without a processed physics frame a
    # later move never reaches the server.
    entity.position = pos
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
    var hitbox := HITBOX_SCENE.instantiate() as HitboxComponent
    hitbox.name = "HitboxComponent"
    hitbox.health_component = health
    hitbox.collision_layer = HitboxComponent.LAYER_HITBOX_GROUND
    hitbox.size = Vector3(2, 2, 2)
    entity.add_child(hitbox)
    _tree().root.add_child(entity)
    return entity


func _make_shooter() -> Node3D:
    var entity := _make_entity(0)
    var combat := CombatComponent.new()
    combat.name = "CombatComponent"
    entity.add_child(combat)
    return entity


## A multi-cell building target: centre-anchored 2x2 hitbox (matching
## EntityFactory's default, since no content sets hitbox_size) plus a
## FoundationComponent, so range/engagement geometry takes the building path.
func _make_building(player_id: int, foundation: Vector2i, pos: Vector3) -> Node3D:
    var entity := Node3D.new()
    entity.name = "Building_P%d" % player_id
    entity.position = pos
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    stats.entity_type = EntityData.EntityType.BUILDING
    entity.add_child(stats)
    var health := HealthComponent.new()
    health.name = "HealthComponent"
    health.max_health = 100
    health.current_health = 100
    entity.add_child(health)
    var hitbox := HITBOX_SCENE.instantiate() as HitboxComponent
    hitbox.name = "HitboxComponent"
    hitbox.health_component = health
    hitbox.collision_layer = HitboxComponent.LAYER_HITBOX_BUILDING
    hitbox.size = Vector3(2, 2, 2)
    entity.add_child(hitbox)
    var fc := FoundationComponent.new()
    fc.name = "FoundationComponent"
    fc.foundation = foundation
    entity.add_child(fc)
    _tree().root.add_child(entity)
    return entity


func _spawn_visible(
    shooter: Node3D, target: Node3D, pos: Vector3, heading: Vector3, speed: float
) -> ProjectileController:
    var data := _make_data()
    var weapon := _make_weapon()
    weapon.speed = speed
    var p := PROJECTILE_SCENE.instantiate() as ProjectileController
    p.setup(data, weapon, shooter, target)
    _tree().root.add_child(p)
    p.global_position = pos
    p._heading = heading.normalized()
    return p


func _tick(p: ProjectileController, times: int = 1) -> void:
    for i in times:
        if not is_instance_valid(p) or p._detonated or p.is_queued_for_deletion():
            return
        p._physics_process(1.0 / 60.0)


func _free_projectiles() -> void:
    for child in _tree().root.get_children():
        if child is ProjectileController:
            child.free()


func _cleanup(nodes: Array) -> void:
    for n in nodes:
        if is_instance_valid(n):
            n.free()


# --- Dispatch branch ---


func test_fire_with_resolvable_projectile_spawns_not_direct_damage():
    _inject_test_rules()
    var shooter := _make_shooter()
    var victim := _make_entity(1)
    var combat := shooter.get_node("CombatComponent") as CombatComponent
    combat.weapons = [_make_weapon(20, 5.0, "Invisible")]
    combat._init_cooldowns()
    var fired: Array = []
    combat.weapon_fired.connect(func(w: WeaponData, t: Node3D) -> void: fired.append(w))
    combat._fire_weapon(combat.weapons[0], victim)
    var spawned: Array = []
    for child in _tree().root.get_children():
        if child is ProjectileController:
            spawned.append(child)
    TestHelper.assert_eq(spawned.size(), 1, "resolvable projectile id spawns one projectile")
    (
        TestHelper
        . assert_true(
            (victim.get_node("HealthComponent") as HealthComponent).current_health == 80,
            "damage applied by the projectile pipeline (20), not by CombatComponent directly",
        )
    )
    TestHelper.assert_eq(fired.size(), 1, "weapon_fired emitted on projectile dispatch")
    spawned[0].free()
    _cleanup([shooter, victim])
    _restore_rules()


func test_fire_with_unresolvable_projectile_falls_back_to_hitscan():
    _inject_test_rules()
    var shooter := _make_shooter()
    var victim := _make_entity(1)
    var combat := shooter.get_node("CombatComponent") as CombatComponent
    combat.weapons = [_make_weapon(20, 5.0, "MissingProjectile")]
    combat._init_cooldowns()
    combat._fire_weapon(combat.weapons[0], victim)
    (
        TestHelper
        . assert_eq(
            (victim.get_node("HealthComponent") as HealthComponent).current_health,
            80,
            "unresolvable id falls back to direct hitscan damage",
        )
    )
    var spawned: Array = []
    for child in _tree().root.get_children():
        if child is ProjectileController:
            spawned.append(child)
    TestHelper.assert_eq(spawned.size(), 0, "no projectile spawned on fallback")
    _cleanup([shooter, victim])
    _restore_rules()


# --- Invisible teleport-detonate ---


func test_invisible_projectile_detonates_at_dispatch_with_legacy_parity():
    _inject_test_rules()
    var shooter := _make_shooter()
    var victim := _make_entity(1)
    var victim_legacy := _make_entity(1)
    var combat := shooter.get_node("CombatComponent") as CombatComponent
    combat.weapons = [_make_weapon(20, 5.0, "Invisible")]
    combat._init_cooldowns()
    combat._fire_weapon(combat.weapons[0], victim)
    var legacy_weapon := _make_weapon(20, 5.0, "")
    shooter.get_node("CombatComponent")._apply_hitscan_damage(legacy_weapon, victim_legacy)
    (
        TestHelper
        . assert_eq(
            (victim_legacy.get_node("HealthComponent") as HealthComponent).current_health,
            80,
            "legacy hitscan baseline: 100 - 20",
        )
    )
    (
        TestHelper
        . assert_eq(
            (victim.get_node("HealthComponent") as HealthComponent).current_health,
            80,
            "invisible projectile deals the same damage on the same tick",
        )
    )
    _free_projectiles()
    _cleanup([shooter, victim, victim_legacy])
    _restore_rules()


# --- Visible flight ---


func test_contact_detonation_reduces_victim_health():
    _inject_test_rules()
    var shooter := _make_shooter()
    var victim := _make_entity(1, "none", Vector3(3, 0, 0))
    var p := _spawn_visible(shooter, victim, Vector3.ZERO, Vector3(1, 0, 0), 12.0)
    _tick(p, 20)
    TestHelper.assert_true(p._detonated, "projectile detonated on contact")
    (
        TestHelper
        . assert_true(
            (victim.get_node("HealthComponent") as HealthComponent).current_health < 100,
            "victim health reduced",
        )
    )
    _cleanup([shooter, victim, p])
    _restore_rules()


func test_spawn_heading_initialized_toward_target():
    _inject_test_rules()
    var shooter := _make_shooter()
    var victim := _make_entity(1, "none", Vector3(0, 0, 8))
    var p := PROJECTILE_SCENE.instantiate() as ProjectileController
    p.setup(_make_data(), _make_weapon(), shooter, victim)
    _tree().root.add_child(p)
    var expected := (victim.global_position - shooter.global_position).normalized()
    (
        TestHelper
        . assert_true(
            p._heading.dot(expected) > 0.999,
            "production spawn points the heading at the target, not at FORWARD",
        )
    )
    _cleanup([shooter, victim, p])
    _restore_rules()


func test_target_behind_default_heading_still_reaches_target():
    _inject_test_rules()
    var shooter := _make_shooter()
    var victim := _make_entity(1, "none", Vector3(0, 0, 8))
    # Production path, no manual heading. Regression: heading stayed FORWARD
    # (0,0,-1), the distance to the +Z target grew every frame, and the
    # overshoot trigger detonated at the shooter's feet with instant damage.
    var p := PROJECTILE_SCENE.instantiate() as ProjectileController
    p.setup(_make_data(), _make_weapon(), shooter, victim)
    _tree().root.add_child(p)
    var hits: Array[Vector3] = []
    p.impacted.connect(func(pos: Vector3) -> void: hits.append(pos))
    _tick(p, 60)
    TestHelper.assert_true(p._detonated, "projectile reaches the +Z target")
    (
        TestHelper
        . assert_true(
            hits.size() == 1 and hits[0].distance_to(victim.global_position) <= 2.0,
            "detonation lands at the target, not at the shooter",
        )
    )
    (
        TestHelper
        . assert_true(
            (victim.get_node("HealthComponent") as HealthComponent).current_health < 100,
            "victim damaged",
        )
    )
    _cleanup([shooter, victim, p])
    _restore_rules()


func test_fast_projectile_cannot_tunnel_through_thin_hitbox():
    _inject_test_rules()
    var shooter := _make_shooter()
    var victim := _make_entity(1, "none", Vector3(4.1, 0, 0))
    var hitbox := victim.get_node("HitboxComponent") as HitboxComponent
    hitbox.size = Vector3(0.1, 2, 2)
    var p := _spawn_visible(shooter, victim, Vector3.ZERO, Vector3(1, 0, 0), 240.0)
    TestHelper.assert_true(
        240.0 / 60.0 > 2.0, "sanity: projectile moves more than a cell width per frame"
    )
    _tick(p, 5)
    TestHelper.assert_true(p._detonated, "segment cast catches >1 cell/frame motion")
    (
        TestHelper
        . assert_true(
            (victim.get_node("HealthComponent") as HealthComponent).current_health < 100,
            "thin hitbox victim damaged",
        )
    )
    _cleanup([shooter, victim, p])
    _restore_rules()


func test_shooter_immune_at_point_blank():
    _inject_test_rules()
    var shooter := _make_shooter()
    var victim := _make_entity(1, "none", Vector3(4, 0, 0))
    var p := _spawn_visible(shooter, victim, shooter.global_position, Vector3(1, 0, 0), 12.0)
    _tick(p, 1)
    (
        TestHelper
        . assert_eq(
            (shooter.get_node("HealthComponent") as HealthComponent).current_health,
            100,
            "shooter undamaged when projectile spawns inside own hitbox",
        )
    )
    TestHelper.assert_true(not p._detonated, "projectile did not detonate on shooter")
    _cleanup([shooter, victim, p])
    _restore_rules()


func test_ally_passed_through_enemy_hit():
    _inject_test_rules()
    var shooter := _make_shooter()
    var ally := _make_entity(0, "none", Vector3(1, 0, 0))
    var victim := _make_entity(1, "none", Vector3(4, 0, 0))
    var p := _spawn_visible(shooter, victim, Vector3.ZERO, Vector3(1, 0, 0), 12.0)
    _tick(p, 30)
    (
        TestHelper
        . assert_eq(
            (ally.get_node("HealthComponent") as HealthComponent).current_health,
            100,
            "allied hitbox passed through unharmed",
        )
    )
    (
        TestHelper
        . assert_true(
            (victim.get_node("HealthComponent") as HealthComponent).current_health < 100,
            "enemy beyond the ally is hit",
        )
    )
    _cleanup([shooter, ally, victim, p])
    _restore_rules()


func test_unarmed_passes_through_then_overshoot_detonates():
    _inject_test_rules()
    var shooter := _make_shooter()
    var victim := _make_entity(1, "none", Vector3(2, 0, 0))
    var data := _make_data()
    data.arm_delay = 3
    var weapon := _make_weapon()
    weapon.speed = 120.0
    var p := PROJECTILE_SCENE.instantiate() as ProjectileController
    p.setup(data, weapon, shooter, victim)
    _tree().root.add_child(p)
    p.global_position = Vector3.ZERO
    p._heading = Vector3(1, 0, 0)
    _tick(p, 1)
    (
        TestHelper
        . assert_eq(
            (victim.get_node("HealthComponent") as HealthComponent).current_health,
            100,
            "unarmed projectile passes through without detonating",
        )
    )
    _tick(p, 30)
    TestHelper.assert_true(p._detonated, "armed projectile detonates after passing the target")
    (
        TestHelper
        . assert_true(
            (victim.get_node("HealthComponent") as HealthComponent).current_health < 100,
            "overshoot detonation still damages the target",
        )
    )
    _cleanup([shooter, victim, p])
    _restore_rules()


func test_max_range_fizzle_deals_no_damage():
    _inject_test_rules()
    var shooter := _make_shooter()
    var victim := _make_entity(1, "none", Vector3(50, 0, 0))
    var weapon := _make_weapon(20, 0.5)
    weapon.speed = 12.0
    var p := PROJECTILE_SCENE.instantiate() as ProjectileController
    p.setup(_make_data(), weapon, shooter, victim)
    _tree().root.add_child(p)
    p.global_position = Vector3.ZERO
    p._heading = Vector3(1, 0, 0)
    var hits: Array[Vector3] = []
    p.impacted.connect(func(pos: Vector3) -> void: hits.append(pos))
    _tick(p, 30)
    TestHelper.assert_true(not p._detonated, "max-range projectile fizzles without detonation")
    TestHelper.assert_eq(hits.size(), 0, "fizzle emits no impacted signal")
    (
        TestHelper
        . assert_true(
            (victim.get_node("HealthComponent") as HealthComponent).current_health == 100,
            "distant victim untouched",
        )
    )
    _cleanup([shooter, victim, p])
    _restore_rules()


func test_physical_projectile_damages_large_building_from_edge_range():
    # Regression (#360): the attacker stops at weapon range from the nearest
    # footprint edge, but the projectile flies to the footprint centre. Without
    # extending reach, a physical shot fizzles at weapon range before the wall.
    # 4x4 building at x=16 (near edge 12, centre 16), weapon range 6 cells = 12.
    _inject_test_rules()
    var shooter := _make_shooter()
    var building := _make_building(1, Vector2i(4, 4), Vector3(16, 0, 0))
    var weapon := _make_weapon(20, 6.0)
    weapon.speed = 12.0
    var p := PROJECTILE_SCENE.instantiate() as ProjectileController
    p.setup(_make_data(), weapon, shooter, building)
    _tree().root.add_child(p)
    p.global_position = Vector3.ZERO
    p._heading = Vector3(1, 0, 0)
    _tick(p, 120)
    TestHelper.assert_true(p._detonated, "projectile reaches and detonates on the building")
    (
        TestHelper
        . assert_true(
            (building.get_node("HealthComponent") as HealthComponent).current_health < 100,
            "physical projectile damages a 4x4 building fired from nearest-edge range",
        )
    )
    _cleanup([shooter, building, p])
    _restore_rules()


func test_target_death_continues_to_last_known_position_then_frees():
    _inject_test_rules()
    var shooter := _make_shooter()
    var victim := _make_entity(1, "none", Vector3(2, 0, 0))
    var p := _spawn_visible(shooter, victim, Vector3.ZERO, Vector3(1, 0, 0), 12.0)
    # Mirror the real death flow: the entity leaves the tree, leaving only the
    # projectile's last known position behind.
    victim.free()
    _tick(p, 30)
    TestHelper.assert_true(not p._detonated, "no detonation on dead target")
    (
        TestHelper
        . assert_true(
            p.is_queued_for_deletion(),
            "projectile frees after reaching the last known target position",
        )
    )
    if is_instance_valid(p):
        p.free()
    shooter.free()
    _restore_rules()


## A fired projectile parents under the match World root's Effects container
## (not the current scene), so a match swap releases it.
func test_projectile_parents_to_match_world_root():
    _inject_test_rules()
    var world: Node = World.new()
    world.name = "ProjectileParentTestWorld"
    _tree().root.add_child(world)

    var shooter := _make_shooter()
    var target := _make_entity(1, "none", Vector3(2, 0, 0))
    var combat := shooter.get_node("CombatComponent") as CombatComponent
    combat._spawn_projectile(_make_data(), _make_weapon(), target, Vector3.ZERO)

    var effects: Node = world.get_node_or_null(World.EFFECTS_NAME)
    TestHelper.assert_true(effects != null, "the World has an Effects container")
    (
        TestHelper
        . assert_true(
            effects != null and effects.get_child_count() >= 1,
            "a fired projectile is parented under World/Effects",
        )
    )
    if effects != null and effects.get_child_count() >= 1:
        (
            TestHelper
            . assert_true(
                world.is_ancestor_of(effects.get_child(0)),
                "the projectile is a descendant of the World root",
            )
        )

    world.free()
    shooter.free()
    target.free()
    _restore_rules()
