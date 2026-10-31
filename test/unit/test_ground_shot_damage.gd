extends Node

# Cell damage resolution for force-fire: with no entity target a shot lands on
# the impact cell's occupant (allies included, shooter exempt), and cell
# overlays — bridge, ice, tiberium — take damage only under their warhead flag.
# Covers the combat-firing "Cell occupant damage" and "Cell overlay damage"
# requirements and the bridges / ice-drowning warhead-damage requirements.

const SHOOTER_CELL := Vector2i(50, 50)
const DAMAGE := 10

# `_sh` / `_ts` / `_ef` are injected by the runner (SpatialHashSingleton,
# TerrainSystem, EntityFactory); test objects are never added to the tree, so
# absolute-path lookups and _ready() do not run here.
var _ts: Node = null
var _sh: Node = null
var _ef: Node = null
var _real_rules: GlobalRules = null
var _placed: Array[Node3D] = []


func _inject_rules() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    var factory := _ef
    _real_rules = factory.get_global_rules()
    var rules := GlobalRules.new()
    rules.min_damage = 1
    rules.max_damage = 10000
    for aid in ["none", "wood", "light", "heavy", "concrete"]:
        var at := ArmorType.new()
        at.id = aid
        rules.armor_types[aid] = at
    var plain := WarheadData.new()
    plain.id = "PLAIN"
    plain.armor_damage_multipliers = {
        "none": 1.0, "wood": 1.0, "light": 1.0, "heavy": 1.0, "concrete": 1.0
    }
    rules.warheads["PLAIN"] = plain
    var wall := WarheadData.new()
    wall.id = "WALL"
    wall.can_damage_walls = true
    wall.armor_damage_multipliers = {
        "none": 1.0, "wood": 1.0, "light": 1.0, "heavy": 1.0, "concrete": 1.0
    }
    rules.warheads["WALL"] = wall
    var tib := WarheadData.new()
    tib.id = "TIB"
    tib.can_damage_tiberium = true
    tib.armor_damage_multipliers = {
        "none": 1.0, "wood": 1.0, "light": 1.0, "heavy": 1.0, "concrete": 1.0
    }
    rules.warheads["TIB"] = tib
    factory.set_global_rules(rules)


func _restore_rules() -> void:
    if _ef and _real_rules:
        _ef.set_global_rules(_real_rules)
        _real_rules = null


func _make_weapon(warhead: String) -> WeaponData:
    var w := WeaponData.new()
    w.id = "GROUND_TEST"
    w.damage = DAMAGE
    w.attack_range = 5.0
    w.rate_of_fire = 1.0
    w.warhead = warhead
    return w


func _make_shooter() -> Node3D:
    var entity := Node3D.new()
    entity.name = "Shooter"
    var combat := CombatComponent.new()
    combat.name = "CombatComponent"
    entity.add_child(combat)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = 0
    entity.add_child(stats)
    entity.add_to_group("entities")
    _track(entity)
    return entity


## Combat-capable entity with health at `pos`. `health` of 0 omits the
## HealthComponent entirely (an entity the shot can hit but not damage).
func _make_entity(player_id: int, pos: Vector3, health: int = 100) -> Node3D:
    var entity := Node3D.new()
    entity.name = "Occupant"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    stats.entity_type = EntityData.EntityType.VEHICLE
    entity.add_child(stats)
    if health > 0:
        var hc := HealthComponent.new()
        hc.name = "HealthComponent"
        hc.max_health = health
        hc.current_health = health
        entity.add_child(hc)
    entity.add_to_group("entities")
    _place(entity, pos)
    return entity


func _place(entity: Node3D, pos: Vector3) -> void:
    _track(entity)
    if not entity.is_inside_tree():
        Engine.get_main_loop().root.add_child(entity)
    entity.global_position = pos


func _track(entity: Node3D) -> void:
    if entity not in _placed:
        _placed.append(entity)


func _rebuild() -> void:
    if _sh:
        _sh.rebuild()


func _cleanup() -> void:
    _rebuild()
    for entity in _placed:
        if is_instance_valid(entity):
            if entity.is_inside_tree():
                entity.get_parent().remove_child(entity)
            entity.free()
    _placed.clear()


func _health_of(entity: Node3D) -> int:
    var hc := entity.get_node_or_null("HealthComponent") as HealthComponent
    return hc.current_health if hc else -1


func _fx() -> Node:
    return Engine.get_main_loop().root.get_node_or_null("FxSystem")


func _shooter_at(cell: Vector2i) -> Array:
    var shooter := _make_shooter()
    _place(shooter, CellUtil.cell_to_world(cell))
    return [shooter, shooter.get_node("CombatComponent") as CombatComponent]


# ========================================
# Occupant pass
# ========================================


func test_ground_shot_damages_enemy_in_cell():
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var setup := _shooter_at(SHOOTER_CELL)
    var cc: CombatComponent = setup[1]
    var enemy := _make_entity(1, CellUtil.cell_to_world(SHOOTER_CELL) + Vector3(0.4, 0, 0.4))
    _rebuild()
    var impact := CellUtil.cell_to_world(SHOOTER_CELL)
    cc.set_ground_target(impact)
    cc._fire_weapon(_make_weapon("PLAIN"), null)
    var got := _health_of(enemy)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(got, 100 - DAMAGE, "enemy standing in the cell takes the hit")


func test_ground_shot_damages_ally_in_cell():
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var setup := _shooter_at(SHOOTER_CELL)
    var cc: CombatComponent = setup[1]
    var ally := _make_entity(0, CellUtil.cell_to_world(SHOOTER_CELL) + Vector3(0.4, 0, 0.4))
    _rebuild()
    cc.set_ground_target(CellUtil.cell_to_world(SHOOTER_CELL))
    cc._fire_weapon(_make_weapon("PLAIN"), null)
    var got := _health_of(ally)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(got, 100 - DAMAGE, "allies take their share of the damage too")


func test_ground_shot_exempts_shooter():
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var setup := _shooter_at(SHOOTER_CELL)
    var cc: CombatComponent = setup[1]
    var shooter: Node3D = setup[0]
    var hc := HealthComponent.new()
    hc.name = "HealthComponent"
    hc.max_health = 100
    hc.current_health = 100
    shooter.add_child(hc)
    _rebuild()
    cc.set_ground_target(CellUtil.cell_to_world(SHOOTER_CELL))
    cc._fire_weapon(_make_weapon("PLAIN"), null)
    var got := _health_of(shooter)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(got, 100, "the object credited with the shot is exempt")


func test_ground_shot_empty_cell_applies_no_damage():
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var setup := _shooter_at(SHOOTER_CELL)
    var cc: CombatComponent = setup[1]
    _rebuild()
    var victim := _make_entity(1, CellUtil.cell_to_world(SHOOTER_CELL + Vector2i(6, 0)))
    _rebuild()
    cc.set_ground_target(CellUtil.cell_to_world(SHOOTER_CELL))
    cc._fire_weapon(_make_weapon("PLAIN"), null)
    var got := _health_of(victim)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(got, 100, "nothing stands in the cell, so nothing is damaged")


func test_entity_target_without_health_does_not_substitute_occupant():
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var setup := _shooter_at(SHOOTER_CELL)
    var cc: CombatComponent = setup[1]
    var target := _make_entity(1, CellUtil.cell_to_world(SHOOTER_CELL) + Vector3(0.4, 0, 0.4), 0)
    var bystander := _make_entity(1, CellUtil.cell_to_world(SHOOTER_CELL) + Vector3(-0.4, 0, -0.4))
    _rebuild()
    cc.set_target(target)
    cc._fire_weapon(_make_weapon("PLAIN"), target)
    var got := _health_of(bystander)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(
        got, 100, "an entity-targeted shot skips damage instead of hitting the cell's occupant"
    )


# ========================================
# Overlay pass — bridges
# ========================================


func _make_bridge(kind: int, is_end: bool, pos: Vector3) -> Node3D:
    var root := Node3D.new()
    root.name = "BridgeSpan"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = -1
    stats.entity_type = EntityData.EntityType.OVERLAY
    root.add_child(stats)
    var hc := HealthComponent.new()
    hc.name = "HealthComponent"
    hc.max_health = 100
    hc.current_health = 100
    root.add_child(hc)
    var bridge := BridgeComponent.new()
    bridge.name = "BridgeComponent"
    root.add_child(bridge)
    _place(root, pos)
    var data := EntityData.new()
    data.bridge_kind = kind
    data.bridge_end = is_end
    data.bridge_level = 0
    bridge.configure(data)
    return root


func test_low_bridge_damaged_only_by_wall_warhead():
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var pos := CellUtil.cell_to_world(SHOOTER_CELL)
    var low := _make_bridge(EntityData.BridgeKind.LOW, false, pos)
    var setup := _shooter_at(SHOOTER_CELL + Vector2i(4, 0))
    var cc: CombatComponent = setup[1]
    _rebuild()
    cc.set_ground_target(pos)
    cc._fire_weapon(_make_weapon("PLAIN"), null)
    var after_plain := _health_of(low)
    cc.set_ground_target(pos)
    cc._fire_weapon(_make_weapon("WALL"), null)
    var after_wall := _health_of(low)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(after_plain, 100, "warhead without can_damage_walls leaves the span alone")
    TestHelper.assert_eq(after_wall, 100 - DAMAGE, "can_damage_walls damages a LOW normal span")


func test_high_bridge_and_end_piece_are_immune():
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var pos := CellUtil.cell_to_world(SHOOTER_CELL)
    var high := _make_bridge(EntityData.BridgeKind.HIGH, false, pos + Vector3(0.0, 0.0, 2.0))
    var end_piece := _make_bridge(EntityData.BridgeKind.LOW, true, pos + Vector3(2.0, 0.0, 0.0))
    var setup := _shooter_at(SHOOTER_CELL + Vector2i(4, 0))
    var cc: CombatComponent = setup[1]
    _rebuild()
    cc.set_ground_target(pos)
    cc._fire_weapon(_make_weapon("WALL"), null)
    cc.set_ground_target(pos + Vector3(0.0, 0.0, 2.0))
    cc._fire_weapon(_make_weapon("WALL"), null)
    var high_health := _health_of(high)
    var end_health := _health_of(end_piece)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(high_health, 100, "a high-bridge cell takes no damage from any warhead")
    TestHelper.assert_eq(end_health, 100, "an end piece takes no damage from any warhead")


# ========================================
# Overlay pass — ice and tiberium
# ========================================


func _make_ice(pos: Vector3, feature_on: bool) -> Node3D:
    var root := Node3D.new()
    root.name = "IceSheet"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = -1
    stats.entity_type = EntityData.EntityType.TERRAIN
    root.add_child(stats)
    var hc := HealthComponent.new()
    hc.name = "HealthComponent"
    hc.max_health = 50
    hc.current_health = 50
    root.add_child(hc)
    # EntityFactory only attaches IceComponent when the game declares
    # `breakable_ice`, so its presence IS the feature gate.
    if feature_on:
        var ice := IceComponent.new()
        ice.name = "IceComponent"
        root.add_child(ice)
        root.add_to_group("ice")
    _place(root, pos)
    return root


func test_ice_damaged_only_with_wall_warhead_and_feature():
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var pos := CellUtil.cell_to_world(SHOOTER_CELL)
    var intact := _make_ice(pos, true)
    var setup := _shooter_at(SHOOTER_CELL + Vector2i(4, 0))
    var cc: CombatComponent = setup[1]
    _rebuild()
    cc.set_ground_target(pos)
    cc._fire_weapon(_make_weapon("PLAIN"), null)
    var after_plain := _health_of(intact)
    cc.set_ground_target(pos)
    cc._fire_weapon(_make_weapon("WALL"), null)
    var after_wall := _health_of(intact)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(after_plain, 50, "warhead without can_damage_walls leaves ice alone")
    TestHelper.assert_eq(after_wall, 50 - DAMAGE, "wall warhead damages ice (feature on)")


func test_ice_untouched_when_feature_is_off():
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var pos := CellUtil.cell_to_world(SHOOTER_CELL)
    var cold := _make_ice(pos, false)
    var setup := _shooter_at(SHOOTER_CELL + Vector2i(4, 0))
    var cc: CombatComponent = setup[1]
    _rebuild()
    cc.set_ground_target(pos)
    cc._fire_weapon(_make_weapon("WALL"), null)
    var got := _health_of(cold)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(got, 50, "without breakable_ice the sheet takes no warhead damage")


func _make_tiberium(pos: Vector3) -> Node3D:
    var root := Node3D.new()
    root.name = "Tiberium"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = -1
    stats.entity_type = EntityData.EntityType.OVERLAY
    root.add_child(stats)
    var hc := HealthComponent.new()
    hc.name = "HealthComponent"
    hc.max_health = 300
    hc.current_health = 300
    root.add_child(hc)
    var resource := ResourceComponent.new()
    resource.name = "ResourceComponent"
    root.add_child(resource)
    var data := EntityData.new()
    data.resource_category = "tiberium"
    resource.configure(data)
    _place(root, pos)
    return root


func test_tiberium_damaged_only_under_its_warhead_flag():
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var pos := CellUtil.cell_to_world(SHOOTER_CELL)
    var crystal := _make_tiberium(pos)
    var setup := _shooter_at(SHOOTER_CELL + Vector2i(4, 0))
    var cc: CombatComponent = setup[1]
    _rebuild()
    if _sh:
        _sh.register_resource_cell(SHOOTER_CELL)
    cc.set_ground_target(pos)
    cc._fire_weapon(_make_weapon("PLAIN"), null)
    var after_plain := _health_of(crystal)
    cc.set_ground_target(pos)
    cc._fire_weapon(_make_weapon("TIB"), null)
    var after_tib := _health_of(crystal)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(after_plain, 300, "warhead without can_damage_tiberium is a no-op")
    TestHelper.assert_eq(after_tib, 300 - DAMAGE, "can_damage_tiberium damages the crystal")


func test_ground_blast_resolves_one_cell_for_both_passes():
    # One blast, one point: a ground shot with no victim resolves the occupant
    # and the overlays at the ordered position, so a projectile that overshoots
    # by a frame cannot damage an entity in one cell and a bridge in the next.
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var ordered := CellUtil.cell_to_world(SHOOTER_CELL)
    var overshoot := CellUtil.cell_to_world(SHOOTER_CELL + Vector2i(0, 3))
    var shooter := _make_shooter()
    _place(shooter, CellUtil.cell_to_world(SHOOTER_CELL + Vector2i(4, 0)))
    var occupant := _make_entity(1, ordered + Vector3(0.3, 0.0, 0.3))
    var bridge := _make_bridge(EntityData.BridgeKind.LOW, false, ordered)
    _rebuild()
    var data := ProjectileData.new()
    data.targets_ground = true
    var projectile := CombatComponent.PROJECTILE_SCENE.instantiate() as ProjectileController
    _track(projectile)
    projectile.setup(data, _make_weapon("WALL"), shooter, null, ordered)
    Engine.get_main_loop().root.add_child(projectile)
    projectile.global_position = overshoot
    projectile._detonate_on(null)
    var occupant_health := _health_of(occupant)
    var bridge_health := _health_of(bridge)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(occupant_health, 100 - DAMAGE, "occupant resolved at the ordered cell")
    TestHelper.assert_eq(bridge_health, 100 - DAMAGE, "overlay resolved at the ordered cell too")


func test_mixed_entity_and_overlay_hit_plays_one_impact_report():
    # One ground detonation can damage an entity occupant and a cell overlay.
    # The overlay must not fire a second per-victim impact report at the same
    # point (two FX/sounds for one blast).
    if not _sh or not _ef:
        TestHelper.fail("SpatialHash/EntityFactory not injected")
        return
    _inject_rules()
    var pos := CellUtil.cell_to_world(SHOOTER_CELL)
    var occupant := _make_entity(1, pos + Vector3(0.3, 0.0, 0.3))
    var bridge := _make_bridge(EntityData.BridgeKind.LOW, false, pos)
    var setup := _shooter_at(SHOOTER_CELL + Vector2i(4, 0))
    var cc: CombatComponent = setup[1]
    _rebuild()
    var reports: Array[String] = []
    var on_report := func(dtype: String, _p: Vector3) -> void: reports.append(dtype)
    _fx().impact_played.connect(on_report)
    cc.set_ground_target(pos)
    cc._fire_weapon(_make_weapon("WALL"), null)
    _fx().impact_played.disconnect(on_report)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(reports.size(), 1, "one detonation plays one impact report")


func test_incapable_warhead_scans_no_overlays():
    # A warhead that cannot damage walls/ice or tiberium must resolve no
    # overlays, so the shot pays no registry scan.
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var pos := CellUtil.cell_to_world(SHOOTER_CELL)
    _make_bridge(EntityData.BridgeKind.LOW, false, pos)
    _make_tiberium(pos)
    _rebuild()
    _sh.register_resource_cell(SHOOTER_CELL)
    var rules: GlobalRules = _ef.get_global_rules()
    var plain: WarheadData = rules.get_warhead("PLAIN")
    var wall: WarheadData = rules.get_warhead("WALL")
    var none: Array = _sh.find_cell_overlays(SHOOTER_CELL, plain)
    var some: Array = _sh.find_cell_overlays(SHOOTER_CELL, wall)
    _cleanup()
    _restore_rules()
    TestHelper.assert_true(none.is_empty(), "warhead that can damage nothing skips every overlay")
    TestHelper.assert_eq(some.size(), 1, "wall warhead still finds the LOW bridge span")


func test_ground_projectile_fizzles_at_max_range():
    # A ground shot has no live target to invalidate it, so it must respect max
    # range on its own; otherwise a non-converging shot orbits forever.
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var shooter := _make_shooter()
    _place(shooter, CellUtil.cell_to_world(SHOOTER_CELL + Vector2i(4, 0)))
    _rebuild()
    var data := ProjectileData.new()
    data.targets_ground = true
    var weapon := _make_weapon("PLAIN")
    weapon.attack_range = 1.0
    var projectile := CombatComponent.PROJECTILE_SCENE.instantiate() as ProjectileController
    _track(projectile)
    projectile.setup(data, weapon, shooter, null, Vector3.ZERO)
    Engine.get_main_loop().root.add_child(projectile)
    projectile.global_position = Vector3(1000.0, 0.0, 0.0)
    projectile._heading = Vector3.LEFT
    projectile._armed = true
    projectile._traveled = 10.0
    projectile._physics_process(0.016)
    var freed := projectile.is_queued_for_deletion()
    _cleanup()
    _restore_rules()
    TestHelper.assert_true(freed, "a ground shot past max range is consumed")


func test_building_edge_cell_resolves_its_occupant():
    # A building is indexed in the grid only at its centre cell, so force-firing
    # an edge cell of a large structure used to find no occupant at all.
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var centre := CellUtil.cell_to_world(SHOOTER_CELL)
    var edge := CellUtil.cell_to_world(SHOOTER_CELL + Vector2i(1, 0))
    var building := Node3D.new()
    building.name = "LargeBuilding"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = 1
    stats.entity_type = EntityData.EntityType.BUILDING
    building.add_child(stats)
    var hc := HealthComponent.new()
    hc.name = "HealthComponent"
    hc.max_health = 200
    hc.current_health = 200
    building.add_child(hc)
    var foundation := FoundationComponent.new()
    foundation.name = "FoundationComponent"
    foundation.foundation = Vector2i(3, 3)
    building.add_child(foundation)
    var data := EntityData.new()
    data.entity_type = EntityData.EntityType.BUILDING
    data.foundation = Vector2i(3, 3)
    foundation.configure(data)
    building.position = centre
    building.add_to_group("entities")
    _track(building)
    Engine.get_main_loop().root.add_child(building)
    var shooter := _make_shooter()
    _place(shooter, CellUtil.cell_to_world(SHOOTER_CELL + Vector2i(4, 0)))
    _rebuild()
    var cc := shooter.get_node("CombatComponent") as CombatComponent
    cc.set_ground_target(edge)
    cc._fire_weapon(_make_weapon("PLAIN"), null)
    var got := _health_of(building)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(got, 200 - DAMAGE, "edge cell of a building resolves its occupant")


# ========================================
# Impact point (cell centre / nearest footprint point)
# ========================================


func test_ground_impact_stays_on_cell_centre_with_occupant():
    # Force-fire snaps to the cell centre; an occupant takes the hit but does
    # not drag the impact point onto itself.
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var setup := _shooter_at(SHOOTER_CELL)
    var cc: CombatComponent = setup[1]
    var centre := CellUtil.cell_to_world(SHOOTER_CELL)
    var enemy := _make_entity(1, centre + Vector3(0.6, 0.0, 0.0))
    _rebuild()
    cc.set_ground_target(centre + Vector3(0.6, 0.0, 0.0))
    cc._fire_weapon(_make_weapon("PLAIN"), null)
    var hc := enemy.get_node("HealthComponent") as HealthComponent
    var impact: Vector3 = hc.last_impact_pos
    var got := _health_of(enemy)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(got, 100 - DAMAGE, "occupant still takes the ground shot")
    (
        TestHelper
        . assert_eq(
            Vector2(impact.x, impact.z),
            Vector2(centre.x, centre.z),
            "impact stays on the cell centre, not the occupant",
        )
    )


func test_building_impact_reads_on_nearest_footprint_point():
    # A building's impact effect lands on the nearest footprint point facing the
    # shooter, not its centre.
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var shooter := _make_shooter()
    _place(shooter, CellUtil.cell_to_world(SHOOTER_CELL + Vector2i(6, 0)))
    var cc := shooter.get_node("CombatComponent") as CombatComponent
    var building := Node3D.new()
    building.name = "LargeBuilding"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = 1
    stats.entity_type = EntityData.EntityType.BUILDING
    building.add_child(stats)
    var hc := HealthComponent.new()
    hc.name = "HealthComponent"
    hc.max_health = 200
    hc.current_health = 200
    building.add_child(hc)
    var foundation := FoundationComponent.new()
    foundation.name = "FoundationComponent"
    foundation.foundation = Vector2i(3, 3)
    building.add_child(foundation)
    building.add_to_group("entities")
    _place(building, CellUtil.cell_to_world(SHOOTER_CELL))
    _rebuild()
    cc.set_target(building)
    cc._fire_weapon(_make_weapon("PLAIN"), building)
    var expected := foundation.nearest_world_point(shooter.global_position)
    var got: Vector3 = hc.last_impact_pos
    _cleanup()
    _restore_rules()
    (
        TestHelper
        . assert_true(
            (
                is_equal_approx(got.x, expected.x)
                and is_equal_approx(got.z, expected.z)
                and is_equal_approx(got.y, expected.y)
            ),
            "building impact sits on the nearest footprint point",
        )
    )


func test_projectile_at_tiberium_routes_through_overlay_gate():
    # A tiberium entity carries an interact HitboxComponent with no wired
    # HealthComponent; a projectile used to mark that as an entity hit and
    # swallow the shot (no damage, no impact FX). It must fall through to the
    # warhead-gated overlay pass instead.
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var pos := CellUtil.cell_to_world(SHOOTER_CELL)
    var crystal := _make_tiberium(pos)
    var interact := (
        preload("res://scenes/components/HitboxComponent.tscn").instantiate() as HitboxComponent
    )
    interact.name = "HitboxComponent"
    crystal.add_child(interact)
    var shooter := _make_shooter()
    _place(shooter, CellUtil.cell_to_world(SHOOTER_CELL + Vector2i(4, 0)))
    _rebuild()
    _sh.register_resource_cell(SHOOTER_CELL)
    var data := ProjectileData.new()
    data.id = "TEST"
    var plain := CombatComponent.PROJECTILE_SCENE.instantiate() as ProjectileController
    _track(plain)
    plain.setup(data, _make_weapon("PLAIN"), shooter, crystal)
    Engine.get_main_loop().root.add_child(plain)
    plain.global_position = pos
    plain._detonate_on(crystal)
    var after_plain := _health_of(crystal)
    var tib := CombatComponent.PROJECTILE_SCENE.instantiate() as ProjectileController
    _track(tib)
    tib.setup(data, _make_weapon("TIB"), shooter, crystal)
    Engine.get_main_loop().root.add_child(tib)
    tib.global_position = pos
    tib._detonate_on(crystal)
    var after_tib := _health_of(crystal)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(after_plain, 300, "non-tiberium warhead leaves the crystal alone")
    TestHelper.assert_eq(
        after_tib, 300 - DAMAGE, "tiberium warhead reaches the crystal via the overlay pass"
    )


func test_hitscan_tiberium_target_respects_flag_and_reduces_bales():
    # A tiberium entity targeted directly must obey the same flag gate as the
    # ground shot, and warhead damage must reduce the harvestable amount.
    if not _sh:
        TestHelper.fail("SpatialHash not injected")
        return
    _inject_rules()
    var pos := CellUtil.cell_to_world(SHOOTER_CELL)
    var crystal := _make_tiberium(pos)
    var resource := crystal.get_node("ResourceComponent") as ResourceComponent
    var shooter := _make_shooter()
    _place(shooter, CellUtil.cell_to_world(SHOOTER_CELL + Vector2i(4, 0)))
    _rebuild()
    _sh.register_resource_cell(SHOOTER_CELL)
    var cc := shooter.get_node("CombatComponent") as CombatComponent
    var original_bales := resource.get_amount()
    cc._fire_weapon(_make_weapon("PLAIN"), crystal)
    var health_plain := _health_of(crystal)
    var bales_plain := resource.get_amount()
    cc._fire_weapon(_make_weapon("TIB"), crystal)
    var health_tib := _health_of(crystal)
    var bales_tib := resource.get_amount()
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(health_plain, 300, "flagless warhead cannot hurt the crystal directly")
    TestHelper.assert_eq(bales_plain, original_bales, "no damage means no bale loss")
    TestHelper.assert_eq(health_tib, 300 - DAMAGE, "flagged warhead damages the crystal directly")
    TestHelper.assert_true(bales_tib < original_bales, "damage reduces the tiberium amount")
