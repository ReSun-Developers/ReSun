extends Node

# WeaponDetonation module tests — the impact interface is the test surface, so
# these call detonate() directly with stub entities and the real SpatialHash /
# GlobalRules instances. No physics ticks or shape casts.
#
# Covers: instant-fire vs projectile-arrival parity, typed effective damage,
# armor math/clamps, ground occupant resolution, structure footprint vs
# non-structure point impact, snap radius, overlay pass, and one impact report
# per detonation.

const CELL := Vector2i(50, 50)
const DAMAGE := 100

var _sh: Node = null
var _ef: Node = null
var _real_rules: GlobalRules = null
var _placed: Array[Node3D] = []


func _tree() -> SceneTree:
    return Engine.get_main_loop() as SceneTree


func _fx() -> Node:
    return _tree().root.get_node_or_null("FxSystem")


func _inject_rules() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    _real_rules = _ef.get_global_rules()
    var rules := GlobalRules.new()
    rules.min_damage = 1
    rules.max_damage = 1000
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
    var sa := WarheadData.new()
    sa.id = "SA"
    sa.armor_damage_multipliers = {
        "none": 1.0, "wood": 1.0, "light": 1.0, "heavy": 0.25, "concrete": 0.0
    }
    rules.warheads["SA"] = sa
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
    _ef.set_global_rules(rules)


func _restore_rules() -> void:
    if _ef and _real_rules:
        _ef.set_global_rules(_real_rules)
        _real_rules = null


func _make_weapon(warhead: String, damage: int = DAMAGE) -> WeaponData:
    var weapon := WeaponData.new()
    weapon.id = "DETONATION_TEST"
    weapon.damage = damage
    weapon.attack_range = 5.0
    weapon.rate_of_fire = 1.0
    weapon.warhead = warhead
    return weapon


func _make_entity(
    player_id: int,
    pos: Vector3,
    health: int = 100,
    armor: String = "none",
    etype: int = EntityData.EntityType.VEHICLE
) -> Node3D:
    var entity := Node3D.new()
    entity.name = "Entity_P%d" % player_id
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = player_id
    stats.armor = armor
    stats.entity_type = etype
    entity.add_child(stats)
    var hc := HealthComponent.new()
    hc.name = "HealthComponent"
    hc.max_health = health
    hc.current_health = health
    entity.add_child(hc)
    entity.add_to_group("entities")
    _place(entity, pos)
    return entity


func _make_building(player_id: int, foundation: Vector2i, pos: Vector3) -> Node3D:
    var building := _make_entity(player_id, pos, 200, "none", EntityData.EntityType.BUILDING)
    var fc := FoundationComponent.new()
    fc.name = "FoundationComponent"
    fc.foundation = foundation
    building.add_child(fc)
    var data := EntityData.new()
    data.entity_type = EntityData.EntityType.BUILDING
    data.foundation = foundation
    fc.configure(data)
    return building


func _make_bridge(pos: Vector3) -> Node3D:
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
    data.bridge_kind = EntityData.BridgeKind.LOW
    data.bridge_end = false
    data.bridge_level = 0
    bridge.configure(data)
    return root


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


func _place(entity: Node3D, pos: Vector3) -> void:
    if entity not in _placed:
        _placed.append(entity)
    if not entity.is_inside_tree():
        _tree().root.add_child(entity)
    entity.global_position = pos


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


func _count_reports() -> Array:
    var reports: Array = []
    var fx := _fx()
    if fx == null:
        return reports
    var on_report := func(dtype: String, position: Vector3) -> void:
        reports.append({"type": dtype, "position": position})
    fx.impact_played.connect(on_report)
    return [reports, on_report]


func _stop_reports(on_report: Callable) -> void:
    var fx := _fx()
    if fx and fx.impact_played.is_connected(on_report):
        fx.impact_played.disconnect(on_report)


func _assert_vector_eq(got: Vector3, expected: Vector3, message: String) -> void:
    (
        TestHelper
        . assert_true(
            (
                is_equal_approx(got.x, expected.x)
                and is_equal_approx(got.y, expected.y)
                and is_equal_approx(got.z, expected.z)
            ),
            message,
        )
    )


# ========================================
# Parity and typed damage
# ========================================


func test_hitscan_and_projectile_inputs_yield_same_damage():
    _inject_rules()
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL))
    var hitscan_victim := _make_entity(
        1, CellUtil.cell_to_world(CELL + Vector2i(1, 0)), 100, "heavy"
    )
    var projectile_victim := _make_entity(
        1, CellUtil.cell_to_world(CELL + Vector2i(0, 1)), 100, "heavy"
    )
    var weapon := _make_weapon("SA", 100)
    var hitscan := WeaponDetonation.detonate(weapon, shooter, weapon.damage, hitscan_victim)
    var projectile := WeaponDetonation.detonate(
        weapon,
        shooter,
        weapon.damage,
        projectile_victim,
        Vector3.INF,
        projectile_victim.global_position
    )
    var hitscan_health := _health_of(hitscan_victim)
    var projectile_health := _health_of(projectile_victim)
    var hitscan_pos := hitscan.position
    var projectile_pos := projectile.position
    var hitscan_victim_pos := hitscan_victim.global_position
    var projectile_victim_pos := projectile_victim.global_position
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(hitscan_health, 75, "instant fire: SA vs heavy = 0.25x")
    TestHelper.assert_eq(projectile_health, 75, "projectile arrival: same damage")
    TestHelper.assert_eq(
        hitscan.damage, projectile.damage, "both paths report the same applied damage"
    )
    TestHelper.assert_eq(hitscan_health, projectile_health, "parity regression: both paths agree")
    _assert_vector_eq(hitscan_pos, hitscan_victim_pos, "instant fire impact is the victim centre")
    _assert_vector_eq(
        projectile_pos, projectile_victim_pos, "projectile impact snaps to the victim centre"
    )


func test_effective_damage_replaces_weapon_base():
    _inject_rules()
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL))
    var victim := _make_entity(1, CellUtil.cell_to_world(CELL + Vector2i(1, 0)), 500)
    var weapon := _make_weapon("PLAIN", 100)
    var impact := WeaponDetonation.detonate(weapon, shooter, 200, victim)
    var got := _health_of(victim)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(got, 300, "typed effective damage (200) is used, not weapon.damage (100)")
    TestHelper.assert_eq(impact.damage, 200, "result reports the typed effective damage")


func test_armor_zero_multiplier_is_a_noop():
    _inject_rules()
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL))
    var victim := _make_entity(1, CellUtil.cell_to_world(CELL + Vector2i(1, 0)), 100, "concrete")
    var impact := WeaponDetonation.detonate(_make_weapon("SA", 100), shooter, 100, victim)
    var got := _health_of(victim)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(got, 100, "SA vs concrete = 0.0x: no damage")
    TestHelper.assert_eq(impact.damage, 0, "result reports zero applied damage")


func test_damage_clamps_to_rules_bounds():
    _inject_rules()
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL))
    var high := _make_entity(1, CellUtil.cell_to_world(CELL + Vector2i(1, 0)), 5000)
    var low := _make_entity(1, CellUtil.cell_to_world(CELL + Vector2i(0, 1)), 100, "heavy")
    var high_impact := WeaponDetonation.detonate(_make_weapon("PLAIN", 5000), shooter, 5000, high)
    var low_impact := WeaponDetonation.detonate(_make_weapon("SA", 1), shooter, 1, low)
    var high_health := _health_of(high)
    var low_health := _health_of(low)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(high_impact.damage, 1000, "damage capped at max_damage")
    TestHelper.assert_eq(high_health, 4000, "victim loses the capped amount")
    TestHelper.assert_eq(low_impact.damage, 1, "damage floored at min_damage")
    TestHelper.assert_eq(low_health, 99, "victim loses the floored amount")


# ========================================
# Victim and impact-point resolution
# ========================================


func test_ground_shot_resolves_occupant_at_ordered_point():
    _inject_rules()
    var ordered := CellUtil.cell_to_world(CELL)
    var shooter := _make_entity(0, ordered)
    var victim := _make_entity(1, ordered + Vector3(0.4, 0.0, 0.4))
    _rebuild()
    var impact := WeaponDetonation.detonate(_make_weapon("PLAIN", 10), shooter, 10, null, ordered)
    var victim_health := _health_of(victim)
    var shooter_health := _health_of(shooter)
    var victim_is_resolved := impact.victim == victim
    var impact_pos := impact.position
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(victim_health, 90, "the cell occupant takes the hit")
    TestHelper.assert_eq(shooter_health, 100, "the shooter is exempt")
    TestHelper.assert_true(victim_is_resolved, "result names the resolved occupant")
    _assert_vector_eq(impact_pos, ordered, "impact stays on the ordered point, not the occupant")


func test_structure_impact_reads_on_nearest_footprint_point():
    _inject_rules()
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL + Vector2i(6, 0)))
    var building := _make_building(1, Vector2i(3, 3), CellUtil.cell_to_world(CELL))
    var foundation := building.get_node("FoundationComponent") as FoundationComponent
    _rebuild()
    var expected := foundation.nearest_world_point(shooter.global_position)
    var impact := WeaponDetonation.detonate(_make_weapon("PLAIN", 10), shooter, 10, building)
    var got := impact.position
    var health := _health_of(building)
    _cleanup()
    _restore_rules()
    _assert_vector_eq(got, expected, "building impact sits on the nearest footprint point")
    TestHelper.assert_eq(health, 190, "the building still takes the damage")


func test_multi_cell_non_structure_reads_on_its_centre():
    _inject_rules()
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL + Vector2i(6, 0)))
    var unit := _make_entity(1, CellUtil.cell_to_world(CELL), 200)
    var fc := FoundationComponent.new()
    fc.name = "FoundationComponent"
    fc.foundation = Vector2i(3, 3)
    unit.add_child(fc)
    var data := EntityData.new()
    data.foundation = Vector2i(3, 3)
    fc.configure(data)
    _rebuild()
    var expected := unit.global_position
    var impact := WeaponDetonation.detonate(_make_weapon("PLAIN", 10), shooter, 10, unit)
    var got := impact.position
    _cleanup()
    _restore_rules()
    _assert_vector_eq(got, expected, "a multi-cell non-structure stays a point target")


func test_close_arrival_snaps_and_distant_arrival_is_kept():
    _inject_rules()
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL))
    var close_victim := _make_entity(1, CellUtil.cell_to_world(CELL + Vector2i(2, 0)), 100)
    var far_victim := _make_entity(1, CellUtil.cell_to_world(CELL + Vector2i(0, 2)), 100)
    var close_impact := WeaponDetonation.detonate(
        _make_weapon("PLAIN", 10),
        shooter,
        10,
        close_victim,
        Vector3.INF,
        close_victim.global_position + Vector3(1.5, 0.0, 0.0)
    )
    var far_arrival := far_victim.global_position + Vector3(5.0, 0.0, 0.0)
    var far_impact := WeaponDetonation.detonate(
        _make_weapon("PLAIN", 10), shooter, 10, far_victim, Vector3.INF, far_arrival
    )
    var close_pos := close_impact.position
    var far_pos := far_impact.position
    var close_expected := close_victim.global_position
    _cleanup()
    _restore_rules()
    _assert_vector_eq(close_pos, close_expected, "close arrival snaps to the victim")
    _assert_vector_eq(far_pos, far_arrival, "distant arrival is kept as-is")


func test_structure_without_foundation_keeps_arrival_point():
    _inject_rules()
    var ordered := CellUtil.cell_to_world(CELL)
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL + Vector2i(6, 0)))
    var building := _make_entity(1, ordered, 200, "none", EntityData.EntityType.BUILDING)
    var arrival := building.global_position + Vector3(1.0, 0.0, 0.0)
    var impact := WeaponDetonation.detonate(
        _make_weapon("PLAIN", 10), shooter, 10, building, Vector3.INF, arrival
    )
    var got := impact.position
    _cleanup()
    _restore_rules()
    _assert_vector_eq(got, arrival, "a structure without a foundation keeps the arrival point")


# ========================================
# Overlay pass and impact report
# ========================================


func test_overlay_only_hit_plays_one_report():
    _inject_rules()
    var ordered := CellUtil.cell_to_world(CELL)
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL + Vector2i(4, 0)))
    var bridge := _make_bridge(ordered)
    _rebuild()
    var setup := _count_reports()
    var reports: Array = setup[0]
    var on_report: Callable = setup[1]
    var impact := WeaponDetonation.detonate(_make_weapon("WALL", 10), shooter, 10, null, ordered)
    _stop_reports(on_report)
    var health := _health_of(bridge)
    var report_count := reports.size()
    var report_pos: Vector3 = reports[0]["position"] if report_count > 0 else Vector3.INF
    var overlay_hit := impact.overlay_hit
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(health, 90, "the bridge span takes the wall warhead")
    TestHelper.assert_true(overlay_hit, "result marks the overlay hit")
    TestHelper.assert_eq(report_count, 1, "an overlay-only hit plays exactly one report")
    _assert_vector_eq(report_pos, ordered, "the report plays at the impact point")


func test_mixed_entity_and_overlay_hit_plays_one_report():
    _inject_rules()
    var ordered := CellUtil.cell_to_world(CELL)
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL + Vector2i(4, 0)))
    var occupant := _make_entity(1, ordered + Vector3(0.3, 0.0, 0.3))
    var bridge := _make_bridge(ordered)
    _rebuild()
    var setup := _count_reports()
    var reports: Array = setup[0]
    var on_report: Callable = setup[1]
    WeaponDetonation.detonate(_make_weapon("WALL", 10), shooter, 10, null, ordered)
    _stop_reports(on_report)
    var occupant_health := _health_of(occupant)
    var bridge_health := _health_of(bridge)
    var report_count := reports.size()
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(occupant_health, 90, "the occupant takes the hit")
    TestHelper.assert_eq(bridge_health, 90, "the overlay takes the hit")
    TestHelper.assert_eq(report_count, 1, "one detonation plays one report, not one per victim")


func test_overlay_target_is_damaged_once():
    _inject_rules()
    var ordered := CellUtil.cell_to_world(CELL)
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL + Vector2i(4, 0)))
    var crystal := _make_tiberium(ordered)
    _rebuild()
    _sh.register_resource_cell(CELL)
    WeaponDetonation.detonate(_make_weapon("TIB", 10), shooter, 10, crystal)
    var health := _health_of(crystal)
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(health, 290, "an overlay target takes exactly one hit")


func test_empty_ground_shot_still_plays_one_report():
    _inject_rules()
    var ordered := CellUtil.cell_to_world(CELL)
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL + Vector2i(4, 0)))
    _rebuild()
    var setup := _count_reports()
    var reports: Array = setup[0]
    var on_report: Callable = setup[1]
    var impact := WeaponDetonation.detonate(_make_weapon("WALL", 10), shooter, 10, null, ordered)
    _stop_reports(on_report)
    var report_count := reports.size()
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(impact.damage, 0, "nothing takes damage")
    TestHelper.assert_true(not impact.entity_hit and not impact.overlay_hit, "nothing was hit")
    TestHelper.assert_eq(report_count, 1, "an empty ground shot still bangs once")


func test_resolved_warhead_without_media_still_reports():
    _inject_rules()
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL))
    var victim := _make_entity(1, CellUtil.cell_to_world(CELL + Vector2i(1, 0)))
    var setup := _count_reports()
    var reports: Array = setup[0]
    var on_report: Callable = setup[1]
    WeaponDetonation.detonate(_make_weapon("WALL", 10), shooter, 10, victim)
    _stop_reports(on_report)
    var report_count := reports.size()
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(
        report_count, 1, "a resolved warhead with no FX/sound still counts as one report"
    )


func test_non_warhead_damage_type_is_silent():
    _inject_rules()
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL))
    var victim := _make_entity(1, CellUtil.cell_to_world(CELL + Vector2i(1, 0)))
    var setup := _count_reports()
    var reports: Array = setup[0]
    var on_report: Callable = setup[1]
    WeaponDetonation.detonate(_make_weapon("NO_SUCH_WARHEAD", 10), shooter, 10, victim)
    _stop_reports(on_report)
    var health := _health_of(victim)
    var report_count := reports.size()
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(health, 90, "unknown warhead still applies full damage")
    TestHelper.assert_eq(report_count, 0, "unknown warhead plays no impact report")


func test_overlay_at_zero_health_plays_no_report():
    _inject_rules()
    var ordered := CellUtil.cell_to_world(CELL)
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL + Vector2i(4, 0)))
    var bridge := _make_bridge(ordered)
    var bridge_health := bridge.get_node("HealthComponent") as HealthComponent
    bridge_health.current_health = 0
    _rebuild()
    var setup := _count_reports()
    var reports: Array = setup[0]
    var on_report: Callable = setup[1]
    WeaponDetonation.detonate(_make_weapon("WALL", 10), shooter, 10, null, ordered)
    _stop_reports(on_report)
    var report_count := reports.size()
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(
        report_count, 0, "a damageable overlay with zero applied damage plays no report"
    )


func test_mixed_zero_entity_overlay_damage_plays_one_report():
    _inject_rules()
    var rules: GlobalRules = _ef.get_global_rules()
    rules.veteran_armor = 1.0
    var ordered := CellUtil.cell_to_world(CELL)
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL + Vector2i(4, 0)))
    var occupant := _make_entity(1, ordered + Vector3(0.3, 0.0, 0.3))
    var stats := occupant.get_node("StatsComponent") as StatsComponent
    stats.veteran_level = 1
    var bridge := _make_bridge(ordered)
    _rebuild()
    var setup := _count_reports()
    var reports: Array = setup[0]
    var on_report: Callable = setup[1]
    WeaponDetonation.detonate(_make_weapon("WALL", 10), shooter, 10, null, ordered)
    _stop_reports(on_report)
    var occupant_health := _health_of(occupant)
    var bridge_health := _health_of(bridge)
    var report_count := reports.size()
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(occupant_health, 100, "the veteran occupant rounds the hit to zero")
    TestHelper.assert_eq(bridge_health, 90, "the overlay still takes damage")
    TestHelper.assert_eq(report_count, 1, "the overlay damage makes the detonation report once")


func test_zero_applied_damage_plays_no_report():
    _inject_rules()
    var rules: GlobalRules = _ef.get_global_rules()
    rules.veteran_armor = 1.0
    var shooter := _make_entity(0, CellUtil.cell_to_world(CELL))
    var victim := _make_entity(1, CellUtil.cell_to_world(CELL + Vector2i(1, 0)))
    var stats := victim.get_node("StatsComponent") as StatsComponent
    stats.veteran_level = 1
    var setup := _count_reports()
    var reports: Array = setup[0]
    var on_report: Callable = setup[1]
    var impact := WeaponDetonation.detonate(_make_weapon("PLAIN", 10), shooter, 10, victim)
    _stop_reports(on_report)
    var health := _health_of(victim)
    var report_count := reports.size()
    _cleanup()
    _restore_rules()
    TestHelper.assert_eq(health, 100, "veteran armor rounds the hit to zero")
    TestHelper.assert_eq(impact.damage, 0, "result reports zero applied damage")
    TestHelper.assert_eq(report_count, 0, "a zero-applied hit plays no impact report")
