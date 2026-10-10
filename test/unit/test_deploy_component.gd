extends Node

# DeployComponent tests — component configuration, snapshot, and deploy/undeploy logic

const DEPLOY_COMPONENT_SCRIPT: GDScript = preload("res://scripts/components/DeployComponent.gd")

var _sm: Node = null
var _bm: Node = null
var _pm: Node = null


func test_deploy_component_defaults():
    var entity := Node3D.new()
    var component := Node.new()
    component.name = "DeployComponent"
    component.set_script(DEPLOY_COMPONENT_SCRIPT)
    entity.add_child(component)

    var deploy := component as DeployComponent
    (
        TestHelper
        . assert_true(
            deploy.deploys_into == "" and deploy.undeploys_into == "",
            "DeployComponent defaults are empty strings: DeployComponent defaults should be empty",
        )
    )

    entity.free()


func test_deploy_component_configure():
    var data := EntityData.new()
    data.id = "TEST_MCV"
    data.entity_type = EntityData.EntityType.VEHICLE
    data.strength = 1000
    data.owner = PackedStringArray(["GDI"])
    data.deploys_into = "GDI_CONSTRUCTION_YARD"

    var entity := Node3D.new()
    var component := Node.new()
    component.name = "DeployComponent"
    component.set_script(DEPLOY_COMPONENT_SCRIPT)
    entity.add_child(component)

    var deploy := component as DeployComponent
    deploy.configure(data)

    (
        TestHelper
        . assert_true(
            deploy.deploys_into == "GDI_CONSTRUCTION_YARD",
            (
                "DeployComponent.configure sets deploys_into: Expected deploys_into="
                + "'GDI_CONSTRUCTION_YARD', "
                + "got '%s'" % deploy.deploys_into
            ),
        )
    )

    entity.free()


func test_can_deploy():
    var entity := Node3D.new()
    var component := Node.new()
    component.name = "DeployComponent"
    component.set_script(DEPLOY_COMPONENT_SCRIPT)
    entity.add_child(component)

    var deploy := component as DeployComponent
    deploy.deploys_into = "GDI_CONSTRUCTION_YARD"

    (
        TestHelper
        . assert_true(
            deploy.can_deploy() and not deploy.can_undeploy(),
            (
                "can_deploy() returns true when deploys_into set: can_deploy() should be true, "
                + "can_undeploy() false"
            ),
        )
    )

    entity.free()


func test_can_undeploy():
    var entity := Node3D.new()
    var component := Node.new()
    component.name = "DeployComponent"
    component.set_script(DEPLOY_COMPONENT_SCRIPT)
    entity.add_child(component)

    var deploy := component as DeployComponent
    deploy.undeploys_into = "GDI_MCV"

    (
        TestHelper
        . assert_true(
            deploy.can_undeploy() and not deploy.can_deploy(),
            (
                "can_undeploy() returns true when undeploys_into set: "
                + "can_undeploy() should be true, can_deploy() false"
            ),
        )
    )

    entity.free()


func test_deselect_entity_clears_both_selected_and_hovering():
    var entity := Node3D.new()
    var select_component := SelectComponent.new()
    select_component.name = "SelectComponent"
    select_component.set_is_selected(true)
    select_component.set_is_hovering(true)
    entity.add_child(select_component)
    var deploy := DeployComponent.new()

    deploy._deselect_entity(entity)

    (
        TestHelper
        . assert_true(
            not select_component.is_selected and not select_component.is_hovering,
            (
                "deselect_entity clears both is_selected and is_hovering: "
                + "deselect_entity should clear both flags"
            ),
        )
    )

    entity.free()


func test_deselect_entity_noops_without_select_component():
    var entity := Node3D.new()
    var deploy := DeployComponent.new()

    deploy._deselect_entity(entity)

    TestHelper.assert_true(true, "deselect_entity does not crash without SelectComponent")

    entity.free()


# --- Snapshot tests ---


func test_snapshot_captures_health_ratio():
    var entity := Node3D.new()
    var health := HealthComponent.new()
    health.name = "HealthComponent"
    health.max_health = 1000
    health.current_health = 500
    entity.add_child(health)
    var deploy := DeployComponent.new()

    var snap := deploy._snapshot_entity(entity)

    (
        TestHelper
        . assert_true(
            abs(snap["health_ratio"] - 0.5) < 0.001,
            (
                "snapshot captures health_ratio = 0.5: Expected health_ratio 0.5, got %s"
                % snap["health_ratio"]
            ),
        )
    )

    entity.free()


func test_snapshot_defaults_health_to_one_when_no_component():
    var entity := Node3D.new()
    var deploy := DeployComponent.new()

    var snap := deploy._snapshot_entity(entity)

    (
        TestHelper
        . assert_true(
            abs(snap["health_ratio"] - 1.0) < 0.001,
            (
                "snapshot defaults health_ratio to 1.0 without HealthComponent: "
                + "Expected default health_ratio 1.0, got %s" % snap["health_ratio"]
            ),
        )
    )

    entity.free()


func test_snapshot_captures_player_id():
    var entity := Node3D.new()
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = 3
    entity.add_child(stats)
    var deploy := DeployComponent.new()

    var snap := deploy._snapshot_entity(entity)

    (
        TestHelper
        . assert_true(
            snap["player_id"] == 3,
            "snapshot captures player_id = 3: Expected player_id 3, got %s" % snap["player_id"],
        )
    )

    entity.free()


func test_snapshot_captures_selection():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return

    _sm.deselect_all()
    var entity := Node3D.new()
    var select_component := SelectComponent.new()
    select_component.name = "SelectComponent"
    entity.add_child(select_component)
    var deploy := DeployComponent.new()
    _sm.add_child(entity)

    _sm.add_entity(select_component)
    var snap := deploy._snapshot_entity(entity)

    (
        TestHelper
        . assert_true(
            snap["was_selected"] == true,
            (
                "snapshot captures was_selected = true: Expected was_selected true, got %s"
                % snap["was_selected"]
            ),
        )
    )

    _sm.deselect_all()
    entity.free()


# --- Apply snapshot tests ---


func test_apply_snapshot_sets_health():
    var target := Node3D.new()
    var health := HealthComponent.new()
    health.name = "HealthComponent"
    health.max_health = 1000
    health.current_health = 1000
    target.add_child(health)
    var deploy := DeployComponent.new()

    var snap := {"health_ratio": 0.5, "was_selected": false, "player_id": 1}
    deploy._apply_snapshot(target, snap)

    TestHelper.assert_true(
        health.current_health == 500,
        (
            (
                "apply_snapshot sets health to 500 (50%% of 1000): "
                + "Expected current_health 500, got %d"
            )
            % health.current_health
        )
    )

    target.free()


func test_apply_snapshot_sets_player_id():
    var target := Node3D.new()
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = -1
    target.add_child(stats)
    var deploy := DeployComponent.new()

    var snap := {"health_ratio": 1.0, "was_selected": false, "player_id": 2}
    deploy._apply_snapshot(target, snap)

    (
        TestHelper
        . assert_true(
            stats.player_id == 2,
            "apply_snapshot sets player_id = 2: Expected player_id 2, got %d" % stats.player_id,
        )
    )

    target.free()


func test_apply_snapshot_restores_selection():
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return

    _sm.deselect_all()
    var target := Node3D.new()
    var select_component := SelectComponent.new()
    select_component.name = "SelectComponent"
    target.add_child(select_component)
    var deploy := DeployComponent.new()
    _sm.add_child(target)

    var snap := {"health_ratio": 1.0, "was_selected": true, "player_id": 1}
    deploy._apply_snapshot(target, snap)

    (
        TestHelper
        . assert_true(
            _sm.selected_entities.has(select_component) and select_component.is_selected,
            (
                "apply_snapshot restores selection on target: "
                + "apply_snapshot should add target SelectComponent to SelectionManager"
            ),
        )
    )

    _sm.deselect_all()
    target.free()


func test_apply_snapshot_respects_transfer_health_ratio_flag():
    var target := Node3D.new()
    var health := HealthComponent.new()
    health.name = "HealthComponent"
    health.max_health = 1000
    health.current_health = 1000
    target.add_child(health)
    var deploy := DeployComponent.new()
    deploy.transfer_health_ratio = false

    var snap := {"health_ratio": 0.25, "was_selected": false, "player_id": 1}
    deploy._apply_snapshot(target, snap)

    (
        TestHelper
        . assert_true(
            health.current_health == 1000,
            (
                "apply_snapshot skips health when transfer_health_ratio is false: "
                + "health should remain 1000, got %d" % health.current_health
            ),
        )
    )

    target.free()


# --- Pending move target tests ---


func test_undeploy_stores_pending_move_target():
    var entity := Node3D.new()
    var deploy := DeployComponent.new()
    deploy.undeploys_into = "GDI_MCV"
    entity.add_child(deploy)

    var target := Vector3(10.0, 0.0, 5.0)
    deploy.execute_undeploy(entity, target)

    (
        TestHelper
        . assert_true(
            deploy._has_pending_move and deploy._pending_move_target == target,
            (
                "execute_undeploy stores pending move target: "
                + "_has_pending_move should be true, _pending_move_target should match"
            ),
        )
    )

    deploy._state = DeployComponent.DeployState.IDLE
    entity.free()


func test_undeploy_no_pending_move_when_no_target():
    var entity := Node3D.new()
    var deploy := DeployComponent.new()
    deploy.undeploys_into = "GDI_MCV"
    entity.add_child(deploy)

    deploy.execute_undeploy(entity)

    (
        TestHelper
        . assert_true(
            not deploy._has_pending_move,
            (
                "execute_undeploy without target does not set pending move: "
                + "_has_pending_move should be false when no target given"
            ),
        )
    )

    deploy._state = DeployComponent.DeployState.IDLE
    entity.free()


# --- get_order_for_target tests ---


func test_order_self_with_can_deploy():
    var entity := Node3D.new()
    var deploy := DeployComponent.new()
    deploy.name = "DeployComponent"
    deploy.deploys_into = "GDI_CONSTRUCTION_YARD"
    entity.add_child(deploy)
    var order := deploy.get_order_for_target(entity, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order != null, "click self with can_deploy -> order not null")
    TestHelper.assert_eq(order.cursor, CursorState.Type.DEPLOY, "cursor -> DEPLOY")
    TestHelper.assert_eq(order.priority, 15, "priority -> 15")
    TestHelper.assert_true(order.execute.is_valid(), "has valid execute callable")
    entity.free()


func test_order_other_entity_returns_null():
    var entity := Node3D.new()
    var deploy := DeployComponent.new()
    deploy.name = "DeployComponent"
    deploy.deploys_into = "GDI_CONSTRUCTION_YARD"
    entity.add_child(deploy)
    var other := Node3D.new()
    other.name = "Other"
    var order := deploy.get_order_for_target(other, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order == null, "click other entity -> null")
    entity.free()
    other.free()


func test_order_no_target_can_undeploy():
    var entity := Node3D.new()
    var deploy := DeployComponent.new()
    deploy.name = "DeployComponent"
    deploy.undeploys_into = "GDI_MCV"
    entity.add_child(deploy)
    var order := deploy.get_order_for_target(null, Vector2i.ZERO, Vector3(5.0, 0.0, 10.0), {})
    TestHelper.assert_true(order != null, "no target + can_undeploy -> order not null")
    TestHelper.assert_eq(order.cursor, CursorState.Type.MOVE, "cursor -> MOVE")
    TestHelper.assert_eq(order.priority, 5, "priority -> 5")
    entity.free()


func test_order_no_target_cannot_undeploy():
    var entity := Node3D.new()
    var deploy := DeployComponent.new()
    deploy.name = "DeployComponent"
    entity.add_child(deploy)
    var order := deploy.get_order_for_target(null, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order == null, "no target + cannot undeploy -> null")
    entity.free()


func test_order_self_cannot_deploy():
    var entity := Node3D.new()
    var deploy := DeployComponent.new()
    deploy.name = "DeployComponent"
    entity.add_child(deploy)
    var order := deploy.get_order_for_target(entity, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order == null, "click self + cannot deploy -> null")
    entity.free()


func test_order_queued_modifier():
    var entity := Node3D.new()
    var deploy := DeployComponent.new()
    deploy.name = "DeployComponent"
    deploy.deploys_into = "GDI_CONSTRUCTION_YARD"
    entity.add_child(deploy)
    var modifiers := {OrderResult.MOD_QUEUED: true}
    var order := deploy.get_order_for_target(entity, Vector2i.ZERO, Vector3.ZERO, modifiers)
    TestHelper.assert_true(order != null, "queued modifier -> order not null")
    TestHelper.assert_true(order.queued, "queued modifier -> order.queued = true")
    entity.free()


func test_order_undeploy_stores_target_pos():
    var entity := Node3D.new()
    var deploy := DeployComponent.new()
    deploy.name = "DeployComponent"
    deploy.undeploys_into = "GDI_MCV"
    entity.add_child(deploy)
    var pos := Vector3(15.0, 0.0, 25.0)
    var order := deploy.get_order_for_target(null, Vector2i.ZERO, pos, {})
    TestHelper.assert_eq(order.target_pos, pos, "order stores target_pos")
    entity.free()


# --- deploy seeks a free cell and centres before rotating (issue #478) ---

const _CY_CELL: String = "GDI_CONSTRUCTION_YARD"


func _make_deploy_entity(root: Node, cell: Vector2i, rotation: float = 90.0) -> Array:
    TerrainSystem.init_grid(50, 50)
    TerrainSystem.clear()
    var entity := Node3D.new()
    root.add_child(entity)
    entity.global_position = CellUtil.cell_to_world(cell) + Vector3(0.6, 0.0, 0.6)
    var stats := StatsComponent.new()
    stats.entity_type = EntityData.EntityType.VEHICLE
    stats.player_id = 0
    stats.weight = 3.0
    entity.add_child(stats)
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    mc._parent = entity
    mc._shares_cell = true
    mc._organic_path = true
    mc._instant_turn = true
    var loco := Locomotor.new()
    loco.terrain_speeds = {"clear": 1.0}
    loco.shares_cell = true
    loco.organic_path = true
    mc._locomotor_data = loco
    var deploy := DeployComponent.new()
    deploy.name = "DeployComponent"
    deploy.deploys_into = _CY_CELL
    deploy.deploy_rotation = rotation
    entity.add_child(deploy)
    return [entity, mc, deploy]


func _foundation_cells(deploy: DeployComponent, cell: Vector2i) -> Array[Vector2i]:
    var data := EntityFactory.get_entity_data(_CY_CELL)
    var origin := deploy._origin_for_cell(cell, data.foundation)
    var cells: Array[Vector2i] = []
    for dx in data.foundation.x:
        for dz in data.foundation.y:
            cells.append(origin + Vector2i(dx, dz))
    return cells


func test_execute_deploy_seeks_current_cell_centre():
    var root: Node = Engine.get_main_loop().root
    var start_cell := Vector2i(30, 30)
    var parts := _make_deploy_entity(root, start_cell)
    var entity: Node3D = parts[0]
    var mc: MovementController = parts[1]
    var deploy: DeployComponent = parts[2]

    var ok := deploy.execute_deploy(entity)

    TestHelper.assert_true(ok, "deploy engages on a clear cell")
    TestHelper.assert_eq(deploy._target_cell, start_cell, "uses the current cell")
    (
        TestHelper
        . assert_eq(
            deploy._state,
            DeployComponent.DeployState.SEEKING_DEPLOY,
            "seeks the centre before rotating",
        )
    )
    # The unit glides to the cell centre through the movement controller, it is
    # not teleported there.
    var centre := CellUtil.cell_to_world(start_cell)
    var target := mc.get_target_position()
    (
        TestHelper
        . assert_true(
            Vector2(target.x - centre.x, target.z - centre.z).length() < 0.01,
            "moves to the cell centre",
        )
    )

    entity.global_position = centre
    deploy._on_arrived(centre)
    (
        TestHelper
        . assert_eq(
            deploy._state,
            DeployComponent.DeployState.ROTATING_DEPLOY,
            "rotates after reaching the centre",
        )
    )

    deploy._state = DeployComponent.DeployState.IDLE
    root.remove_child(entity)
    entity.free()


func test_execute_deploy_follows_path_forward():
    var root: Node = Engine.get_main_loop().root
    var start_cell := Vector2i(30, 30)
    var parts := _make_deploy_entity(root, start_cell)
    var entity: Node3D = parts[0]
    var mc: MovementController = parts[1]
    var deploy: DeployComponent = parts[2]

    # Simulate an in-progress move: the unit is in cell (30,30) with the next
    # waypoint ahead in (31,30) and its final move target far in (35,30).
    mc._waypoints = PackedVector3Array(
        [
            CellUtil.cell_to_world(start_cell),
            CellUtil.cell_to_world(Vector2i(31, 30)),
            CellUtil.cell_to_world(Vector2i(35, 30)),
        ]
    )
    mc._waypoint_levels = PackedInt32Array([0, 0, 0])
    mc._spline_t = 0.0
    mc._state = MovementController.State.MOVING

    var ok := deploy.execute_deploy(entity)

    TestHelper.assert_true(ok, "deploy engages while moving")
    (
        TestHelper
        . assert_eq(
            deploy._target_cell,
            Vector2i(31, 30),
            "deploys at the next cell ahead, not the cell being left",
        )
    )
    TestHelper.assert_true(
        deploy._target_cell != start_cell, "does not reverse to the previous cell"
    )

    deploy._state = DeployComponent.DeployState.IDLE
    root.remove_child(entity)
    entity.free()


func test_execute_deploy_seeks_nearest_free_cell_when_blocked():
    var root: Node = Engine.get_main_loop().root
    var start_cell := Vector2i(30, 30)
    var parts := _make_deploy_entity(root, start_cell)
    var entity: Node3D = parts[0]
    var deploy: DeployComponent = parts[2]

    var blocked: Array[Vector2i] = [_foundation_cells(deploy, start_cell)[0]]
    SpatialHash.instance.register_building_cells(blocked)

    var ok := deploy.execute_deploy(entity)

    TestHelper.assert_true(ok, "deploy relocates when the current cell is blocked")
    TestHelper.assert_eq(
        deploy._state, DeployComponent.DeployState.SEEKING_DEPLOY, "seeks a free cell first"
    )
    TestHelper.assert_true(deploy._target_cell != start_cell, "picked a different cell")

    var target_cells := _foundation_cells(deploy, deploy._target_cell)
    for cell in target_cells:
        (
            TestHelper
            . assert_true(
                not SpatialHash.instance.get_building_cells().has(CellUtil.cell_key(cell)),
                "chosen cell's foundation is free",
            )
        )

    SpatialHash.instance.unregister_building_cells(blocked)
    deploy._state = DeployComponent.DeployState.IDLE
    root.remove_child(entity)
    entity.free()


func test_execute_deploy_rotates_on_arrival():
    var root: Node = Engine.get_main_loop().root
    var start_cell := Vector2i(30, 30)
    var parts := _make_deploy_entity(root, start_cell)
    var entity: Node3D = parts[0]
    var deploy: DeployComponent = parts[2]

    var blocked: Array[Vector2i] = [_foundation_cells(deploy, start_cell)[0]]
    SpatialHash.instance.register_building_cells(blocked)
    deploy.execute_deploy(entity)
    TestHelper.assert_eq(deploy._state, DeployComponent.DeployState.SEEKING_DEPLOY, "seek engaged")

    entity.global_position = CellUtil.cell_to_world(deploy._target_cell)
    deploy._on_arrived(entity.global_position)

    (
        TestHelper
        . assert_eq(
            deploy._state,
            DeployComponent.DeployState.ROTATING_DEPLOY,
            "rotates once it stands on the chosen cell",
        )
    )

    SpatialHash.instance.unregister_building_cells(blocked)
    deploy._state = DeployComponent.DeployState.IDLE
    root.remove_child(entity)
    entity.free()


func test_execute_deploy_clears_combat_target():
    TerrainSystem.init_grid(50, 50)
    var root: Node = Engine.get_main_loop().root
    var entity := Node3D.new()
    root.add_child(entity)
    entity.global_position = CellUtil.cell_to_world(Vector2i(30, 30))
    var combat := CombatComponent.new()
    combat.name = "CombatComponent"
    combat._attack_active = true
    entity.add_child(combat)

    var deploy := DeployComponent.new()
    deploy.name = "DeployComponent"
    deploy.deploys_into = _CY_CELL
    deploy.deploy_rotation = 90.0
    entity.add_child(deploy)

    deploy.execute_deploy(entity)

    TestHelper.assert_true(not combat.is_engaged(), "deploy clears an active combat engagement")

    deploy._state = DeployComponent.DeployState.IDLE
    root.remove_child(entity)
    entity.free()


func test_execute_deploy_blocked_leaves_move_intact():
    TerrainSystem.init_grid(50, 50)
    var root: Node = Engine.get_main_loop().root
    var start_cell := Vector2i(30, 30)
    var parts := _make_deploy_entity(root, start_cell)
    var entity: Node3D = parts[0]
    var mc: MovementController = parts[1]
    var deploy: DeployComponent = parts[2]
    # No relocation: the current foundation is the only candidate.
    deploy.deploy_search_radius_cells = 0
    mc._waypoints = PackedVector3Array([CellUtil.cell_to_world(Vector2i(40, 40))])
    mc._state = MovementController.State.MOVING

    var blocked: Array[Vector2i] = [_foundation_cells(deploy, start_cell)[0]]
    SpatialHash.instance.register_building_cells(blocked)

    var ok := deploy.execute_deploy(entity)

    TestHelper.assert_true(not ok, "deploy fails when no free cell exists")
    TestHelper.assert_eq(
        mc._state, MovementController.State.MOVING, "failed deploy leaves the move intact"
    )
    TestHelper.assert_true(not mc._waypoints.is_empty(), "failed deploy keeps the move path")

    SpatialHash.instance.unregister_building_cells(blocked)
    deploy._state = DeployComponent.DeployState.IDLE
    root.remove_child(entity)
    entity.free()


func test_stop_cancels_deploy_seek():
    var root: Node = Engine.get_main_loop().root
    var start_cell := Vector2i(30, 30)
    var parts := _make_deploy_entity(root, start_cell)
    var entity: Node3D = parts[0]
    var deploy: DeployComponent = parts[2]

    var blocked: Array[Vector2i] = [_foundation_cells(deploy, start_cell)[0]]
    SpatialHash.instance.register_building_cells(blocked)
    deploy.execute_deploy(entity)
    TestHelper.assert_true(deploy.is_transitioning(), "deploy is in flight")

    # Stop command: cancels the seek and releases the unit.
    deploy.cancel_deploy()

    TestHelper.assert_true(not deploy.is_transitioning(), "stop cancels the deploy")
    deploy._on_arrived(entity.global_position)
    TestHelper.assert_eq(
        deploy._state, DeployComponent.DeployState.IDLE, "a cancelled seek does not resume"
    )

    SpatialHash.instance.unregister_building_cells(blocked)
    root.remove_child(entity)
    entity.free()


func test_seek_interrupted_when_movement_stops():
    var root: Node = Engine.get_main_loop().root
    var start_cell := Vector2i(30, 30)
    var parts := _make_deploy_entity(root, start_cell)
    var entity: Node3D = parts[0]
    var mc: MovementController = parts[1]
    var deploy: DeployComponent = parts[2]

    var blocked: Array[Vector2i] = [_foundation_cells(deploy, start_cell)[0]]
    SpatialHash.instance.register_building_cells(blocked)
    deploy.execute_deploy(entity)
    TestHelper.assert_true(deploy.is_transitioning(), "deploy is in flight")

    # A controller stopped without emitting `arrived` must not strand the deploy.
    mc._state = MovementController.State.IDLE
    deploy._process(0.016)

    TestHelper.assert_true(
        not deploy.is_transitioning(), "stalled seek aborts instead of locking the unit"
    )

    SpatialHash.instance.unregister_building_cells(blocked)
    root.remove_child(entity)
    entity.free()


## A cell occupied only by the deploying source is free for deploy (the source is
## excluded); a second unit on the same cell refuses it. Covers the shared
## build-intent exclusion replacing the old _is_only_source_* helpers.
func test_deploy_cell_free_excludes_source():
    var root: Node = Engine.get_main_loop().root
    var cell := Vector2i(30, 30)
    var parts := _make_deploy_entity(root, cell)
    var entity: Node3D = parts[0]
    var deploy: DeployComponent = parts[2]
    entity.add_to_group("entities")
    var src_cell := CellUtil.world_to_cell(entity.global_position)
    SpatialHash.instance.rebuild()

    (
        TestHelper
        . assert_true(
            deploy._is_cell_free_for_deploy(src_cell, entity),
            "deploy cell is free when only the source occupies it",
        )
    )

    var other := Node3D.new()
    other.global_position = CellUtil.cell_to_world(src_cell)
    other.add_to_group("entities")
    var ostats := StatsComponent.new()
    ostats.name = "StatsComponent"
    ostats.entity_type = EntityData.EntityType.VEHICLE
    ostats.player_id = 1
    other.add_child(ostats)
    var omc := MovementController.new()
    omc.name = "MovementController"
    other.add_child(omc)
    SpatialHash.instance.add_child(other)
    SpatialHash.instance.rebuild()

    var refused: bool = not deploy._is_cell_free_for_deploy(src_cell, entity)

    SpatialHash.instance.remove_child(other)
    other.free()
    root.remove_child(entity)
    entity.free()
    SpatialHash.instance.rebuild()

    TestHelper.assert_true(refused, "deploy cell refused when a second unit is present")
