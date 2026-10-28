extends Node

# Per-unit movement speed — `EntityData.speed` (TS leptons/frame) wired to
# `MovementController.move_speed` through the GlobalRules conversion. Expected
# values are derived from TS lepton geometry, not copied from the helper body.

const LOGIC_FPS := 30.0
const CELL_SIZE := 2.0
const LEPTONS_PER_CELL := 256.0
const TS_SPEED_FACTOR := 2.56
const DELTA := 0.0167
const TICKS := 200

var _ts: Node = null
var _ef: Node = null


func _reset_terrain() -> void:
    var cr := CellReservation.instance
    if cr:
        cr.clear()
    if _ts:
        _ts.init_grid(50, 50)
        _ts.clear()


## Independent expectation: `2.56 * Speed` leptons/frame, 256 leptons per cell,
## `logic_fps` frames per second, `CELL_SIZE` world units per cell.
func _expected_units_per_second(speed: float) -> float:
    return speed * TS_SPEED_FACTOR * LOGIC_FPS * CELL_SIZE / LEPTONS_PER_CELL


func _make_rules() -> GlobalRules:
    var rules := GlobalRules.new()
    rules.logic_fps = LOGIC_FPS
    var hover := Locomotor.new()
    hover.id = "Hover"
    hover.terrain_speeds = {"clear": 1.0}
    rules.locomotors["Hover"] = hover
    for aid in ["none", "wood", "light", "heavy", "concrete"]:
        var armor := ArmorType.new()
        armor.id = aid
        rules.armor_types[aid] = armor
    var warhead := WarheadData.new()
    warhead.id = "TESTWH"
    warhead.armor_damage_multipliers = {
        "none": 1.0, "wood": 1.0, "light": 1.0, "heavy": 1.0, "concrete": 1.0
    }
    rules.warheads["TESTWH"] = warhead
    return rules


func _install_rules() -> GlobalRules:
    var rules := _make_rules()
    if _ef:
        _ef.set_global_rules(rules)
    return rules


func _restore_rules(previous: GlobalRules) -> void:
    if _ef:
        _ef.set_global_rules(previous)


func _make_mover(speed: float, cell: Vector2i) -> Array:
    var data := EntityData.new()
    data.id = "TEST_MOVER"
    data.entity_type = EntityData.EntityType.VEHICLE
    data.speed = speed
    data.locomotor = "Hover"
    data.rotation_speed = 180.0
    var entity := Node3D.new()
    # Start on a cell centre so the path to the target is collinear — a corner
    # start makes the spline diagonal and the position lerp lags the step.
    entity.position = CellUtil.cell_to_world(cell)
    var stats := StatsComponent.new()
    stats.entity_type = EntityData.EntityType.VEHICLE
    stats.player_id = 0
    stats.weight = 3.0
    entity.add_child(stats)
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    mc.configure(data)
    Engine.get_main_loop().root.add_child(entity)
    # configure() ran before the tree; _ready() applied the converted speed.
    # _resolve_locomotor() overwrites the instant-turn flag, so set it after.
    mc._instant_turn = true
    mc._speed_jitter = 1.0
    return [entity, mc]


func _cleanup(pair: Array) -> void:
    var entity: Node = pair[0]
    var root: Node = entity.get_parent()
    if root:
        root.remove_child(entity)
    entity.free()


func _travel(mc: MovementController) -> float:
    mc.move_to(mc._parent.global_position + Vector3(30.0, 0.0, 0.0))
    var start: Vector3 = mc._parent.global_position
    for _i in TICKS:
        if mc.get_state() == MovementController.State.IDLE:
            break
        mc._handle_moving_movement(DELTA)
    return mc._parent.global_position.distance_to(start)


# --- Conversion helper -------------------------------------------------------


func test_conversion_at_30_hz() -> void:
    var rules := GlobalRules.new()
    rules.logic_fps = 30.0
    (
        TestHelper
        . assert_true(
            is_equal_approx(rules.speed_to_units_per_second(5.0), 3.0),
            "Speed 5 at 30 Hz -> 3.0 u/s (got %f)" % rules.speed_to_units_per_second(5.0),
        )
    )


func test_conversion_scales_with_logic_rate() -> void:
    var rules := GlobalRules.new()
    rules.logic_fps = 15.0
    (
        TestHelper
        . assert_true(
            is_equal_approx(rules.speed_to_units_per_second(5.0), 1.5),
            "Speed 5 at 15 Hz -> 1.5 u/s (got %f)" % rules.speed_to_units_per_second(5.0),
        )
    )


func test_conversion_zero_speed() -> void:
    var rules := GlobalRules.new()
    (
        TestHelper
        . assert_true(
            is_equal_approx(rules.speed_to_units_per_second(0.0), 0.0),
            "Speed 0 -> 0 u/s",
        )
    )


# --- Per-unit wiring ---------------------------------------------------------


func test_per_unit_speed_traverses_at_different_rates() -> void:
    _reset_terrain()
    var previous: GlobalRules = _ef.get_global_rules()
    _install_rules()
    var slow_pair := _make_mover(6.0, Vector2i(50, 50))
    var fast_pair := _make_mover(10.0, Vector2i(55, 55))
    var slow_mc: MovementController = slow_pair[1]
    var fast_mc: MovementController = fast_pair[1]
    var slow_dist := _travel(slow_mc)
    var fast_dist := _travel(fast_mc)
    var slow_rate := slow_dist / (TICKS * DELTA)
    var fast_rate := fast_dist / (TICKS * DELTA)
    _cleanup(slow_pair)
    _cleanup(fast_pair)
    _restore_rules(previous)
    _reset_terrain()
    var expected_slow := _expected_units_per_second(6.0)
    var expected_fast := _expected_units_per_second(10.0)
    (
        TestHelper
        . assert_true(
            absf(slow_rate - expected_slow) < 0.05,
            "speed 6 moves at %f u/s (expected %f)" % [slow_rate, expected_slow],
        )
    )
    (
        TestHelper
        . assert_true(
            absf(fast_rate - expected_fast) < 0.05,
            "speed 10 moves at %f u/s (expected %f)" % [fast_rate, expected_fast],
        )
    )
    (
        TestHelper
        . assert_true(
            absf(fast_rate / slow_rate - 10.0 / 6.0) < 0.05,
            "same path at ratio 10:6 (got %f)" % (fast_rate / slow_rate),
        )
    )


## Control: before the fix both units shared the flat move_speed 8.0. Force both
## controllers to flat 8.0 and run the same travel the regression test runs, so
## the measured rate ratio is 1.0 — proving the 10:6 assertion would fail.
func test_flat_speed_cannot_produce_the_ratio() -> void:
    _reset_terrain()
    var previous: GlobalRules = _ef.get_global_rules()
    _install_rules()
    var slow_pair := _make_mover(6.0, Vector2i(50, 50))
    var fast_pair := _make_mover(10.0, Vector2i(55, 55))
    var slow_mc: MovementController = slow_pair[1]
    var fast_mc: MovementController = fast_pair[1]
    slow_mc.move_speed = 8.0
    fast_mc.move_speed = 8.0
    var slow_rate := _travel(slow_mc) / (TICKS * DELTA)
    var fast_rate := _travel(fast_mc) / (TICKS * DELTA)
    _cleanup(slow_pair)
    _cleanup(fast_pair)
    _restore_rules(previous)
    _reset_terrain()
    TestHelper.assert_true(
        absf(slow_rate - 8.0) < 0.05, "flat control moves at 8.0 u/s (got %f)" % slow_rate
    )
    (
        TestHelper
        . assert_true(
            absf(fast_rate / slow_rate - 1.0) < 0.01,
            (
                "flat 8.0 yields a 1.0 rate ratio, failing the 10:6 assertion (got %f)"
                % (fast_rate / slow_rate)
            ),
        )
    )


func test_bare_controller_keeps_export_default() -> void:
    _reset_terrain()
    var entity := Node3D.new()
    var mc := MovementController.new()
    entity.add_child(mc)
    Engine.get_main_loop().root.add_child(entity)
    mc._instant_turn = true
    mc._speed_jitter = 1.0
    mc._waypoints = [Vector3.ZERO, Vector3(10.0, 0.0, 0.0)]
    mc._bake_spline()
    mc._state = MovementController.State.MOVING
    var start: Vector3 = entity.global_position
    mc._handle_moving_movement(DELTA)
    var moved: float = entity.global_position.distance_to(start)
    var speed := mc.move_speed
    entity.get_parent().remove_child(entity)
    entity.free()
    TestHelper.assert_eq(speed, 8.0, "unconfigured controller keeps export default 8.0")
    TestHelper.assert_true(moved > 0.0, "unconfigured controller still moves on its default")


## Real seam: an entity built through EntityFactory gets the converted speed.
func test_entity_factory_wires_converted_speed() -> void:
    _reset_terrain()
    var entity: Node3D = _ef.create_entity("GDI_TITAN")
    if entity == null:
        TestHelper.fail("EntityFactory could not create GDI_TITAN")
        return
    Engine.get_main_loop().root.add_child(entity)
    var mc := entity.get_node_or_null("MovementController") as MovementController
    var has_mc := mc != null
    var got: float = mc.move_speed if mc else -1.0
    _cleanup_nodes([entity])
    _reset_terrain()
    TestHelper.assert_true(has_mc, "Titan gets a MovementController")
    (
        TestHelper
        . assert_true(
            absf(got - _expected_units_per_second(6.0)) < 0.001,
            (
                "create_entity wires Speed 6 -> %f u/s (got %f)"
                % [_expected_units_per_second(6.0), got]
            ),
        )
    )


## Real seam: speed = 0 attaches no controller (pins the entity-data scenario).
func test_entity_factory_skips_controller_for_immobile() -> void:
    var entity: Node3D = _ef.create_entity("GDI_TITAN", {"speed": 0.0})
    if entity == null:
        TestHelper.fail("EntityFactory could not create GDI_TITAN override")
        return
    Engine.get_main_loop().root.add_child(entity)
    var has_mc := entity.get_node_or_null("MovementController") != null
    _cleanup_nodes([entity])
    TestHelper.assert_true(not has_mc, "speed 0 attaches no MovementController")


# --- Projectile parity -------------------------------------------------------


## The default projectile must outrun the fastest unit, or a pursuing shot can
## never close (Orca Fighter, TS Speed 20).
func test_default_projectile_outruns_fastest_unit() -> void:
    var rules := GlobalRules.new()
    var fastest_world := rules.speed_to_units_per_second(20.0)
    (
        TestHelper
        . assert_true(
            rules.default_projectile_speed > fastest_world,
            (
                "default projectile %f u/s outruns the fastest unit %f u/s"
                % [rules.default_projectile_speed, fastest_world]
            ),
        )
    )


## Behavioral complement: a projectile fired from behind catches a target
## receding at the fastest unit speed.
func test_pursuing_projectile_catches_fastest_unit() -> void:
    _reset_terrain()
    var previous: GlobalRules = _ef.get_global_rules()
    _install_rules()
    var delta := 0.016
    var unit_world := _expected_units_per_second(20.0)
    var target := Node3D.new()
    var tstats := StatsComponent.new()
    tstats.player_id = 1
    tstats.entity_type = EntityData.EntityType.VEHICLE
    tstats.armor = "none"
    target.add_child(tstats)
    var thc := HealthComponent.new()
    thc.max_health = 10000
    thc.current_health = 10000
    target.add_child(thc)
    Engine.get_main_loop().root.add_child(target)
    target.global_position = Vector3.ZERO
    var shooter := Node3D.new()
    var sstats := StatsComponent.new()
    sstats.player_id = 0
    shooter.add_child(sstats)
    Engine.get_main_loop().root.add_child(shooter)
    var weapon := WeaponData.new()
    weapon.id = "PURSUE"
    weapon.damage = 10
    weapon.attack_range = 100.0
    weapon.warhead = "TESTWH"
    var projectile := CombatComponent.PROJECTILE_SCENE.instantiate() as ProjectileController
    projectile.setup(ProjectileData.new(), weapon, shooter, target, Vector3.ZERO)
    Engine.get_main_loop().root.add_child(projectile)
    projectile.global_position = Vector3(-5.0, 0.0, 0.0)
    projectile._heading = Vector3.RIGHT
    projectile._armed = true
    for _i in 200:
        target.global_position += Vector3(unit_world * delta, 0.0, 0.0)
        projectile._physics_process(delta)
        if projectile._detonated or projectile.is_queued_for_deletion():
            break
    var detonated: bool = projectile._detonated
    _cleanup_nodes([target, shooter, projectile])
    _restore_rules(previous)
    _reset_terrain()
    TestHelper.assert_true(detonated, "a pursuing projectile catches an Orca-speed target")


func _cleanup_nodes(nodes: Array) -> void:
    for node in nodes:
        if not is_instance_valid(node):
            continue
        if node.is_inside_tree():
            node.get_parent().remove_child(node)
        if not node.is_queued_for_deletion():
            node.free()
