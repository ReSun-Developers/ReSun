extends Node

# MouseHandler hover takeover: moving from a hovered selectable unit onto a
# resource interact hitbox must clear the unit's hover preview immediately.

const SELECT_COMPONENT_SCENE: PackedScene = preload("res://scenes/components/SelectComponent.tscn")
const HITBOX_SCENE: PackedScene = preload("res://scenes/components/HitboxComponent.tscn")

var _sm: Node = null


func _setup_world() -> Dictionary:
    # The suite runs every test in a single synchronous frame, so nodes freed
    # via queue_free() in earlier tests stay in the scene tree and physics space
    # until the suite ends. Their SelectComponent hitboxes (layer 16) shadow this
    # test's hover raycast and resolve to the leftover unit instead of the
    # crystal. Free leftover physics-bearing entities for a clean space.
    var tree := _sm.get_tree()
    for group in ["selectable", "entities", "resources", "ice"]:
        for node in tree.get_nodes_in_group(group):
            if is_instance_valid(node):
                node.free()
    # Fresh hover state — clear_hover_preview() only resets hovered_entity.
    _sm.hovered_node = null
    _sm.hovered_entity = null

    var cc := CameraController.new()
    cc.name = "CameraController"
    var cam := Camera3D.new()
    cam.name = "Camera3D"
    cam.position = Vector3(0, 12, 14)
    cc.add_child(cam)
    _sm.add_child(cc)
    cam.look_at(Vector3.ZERO, Vector3.UP)

    var rules := GlobalRules.get_current()
    var saved_shroud: bool = rules.shroud_enabled
    var saved_fog: bool = rules.fog_of_war
    rules.shroud_enabled = false
    rules.fog_of_war = false
    return {
        "cam": cam,
        "cc": cc,
        "rules": rules,
        "saved_shroud": saved_shroud,
        "saved_fog": saved_fog,
    }


func _make_unit() -> Dictionary:
    var entity := Node3D.new()
    entity.name = "HoverUnit"
    entity.position = Vector3(0, 0.5, 0)
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    select_comp.name = "SelectComponent"
    entity.add_child(select_comp)
    _sm.add_child(entity)
    return {"entity": entity, "select_comp": select_comp}


func _make_resource() -> Dictionary:
    var entity := Node3D.new()
    entity.name = "Tiberium"
    entity.position = Vector3(0, 0.5, 4)
    var rc := Node.new()
    rc.name = "ResourceComponent"
    entity.add_child(rc)
    var hitbox := HITBOX_SCENE.instantiate() as Area3D
    hitbox.collision_layer = 1 << 16
    entity.add_child(hitbox)
    _sm.add_child(entity)
    return {"entity": entity}


func test_unit_hover_preview_clears_on_resource_takeover() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var setup := _setup_world()
    var cam := setup["cam"] as Camera3D
    var unit := _make_unit()
    var res := _make_resource()
    var sc := unit["select_comp"] as SelectComponent

    var mouse := MouseHandler.new()
    mouse.selection_manager = _sm
    mouse.camera_controller = setup["cc"]

    var unit_mouse_pos := cam.unproject_position((unit["entity"] as Node3D).global_position)
    mouse._handle_hover_preview(unit_mouse_pos)
    TestHelper.assert_true(
        sc.is_hovering, "hovering the unit sets its hover preview (setup branch reached)"
    )

    var res_mouse_pos := cam.unproject_position((res["entity"] as Node3D).global_position)
    mouse._handle_hover_preview(res_mouse_pos)
    TestHelper.assert_true(
        not sc.is_hovering, "moving onto a resource clears the unit's hover preview immediately"
    )
    (
        TestHelper
        . assert_true(
            _sm.hovered_entity == null,
            "SelectionManager drops the hovered unit when hover moves onto a resource",
        )
    )
    var same_node: bool = _sm.hovered_node == (res["entity"] as Node3D)
    (
        TestHelper
        . assert_true(
            same_node,
            "SelectionManager tracks the resource as the hovered node (tooltip target)",
        )
    )

    _sm.clear_hover_preview()
    _sm.deselect_all()
    unit["entity"].free()
    res["entity"].free()
    (setup["cc"] as Node).free()
    var rules := setup["rules"] as GlobalRules
    rules.shroud_enabled = setup["saved_shroud"]
    rules.fog_of_war = setup["saved_fog"]


func test_hover_resolves_cell_under_cursor_when_two_crystals_adjacent() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var setup := _setup_world()
    var cam := setup["cam"] as Camera3D
    var mouse := MouseHandler.new()
    mouse.selection_manager = _sm
    mouse.camera_controller = setup["cc"]

    var crystal_a := EntityFactory.create_entity("TIBERIUM_RIPARIUS")
    var crystal_b := EntityFactory.create_entity("TIBERIUM_RIPARIUS")
    if crystal_a == null or crystal_b == null:
        TestHelper.fail("EntityFactory must create TIBERIUM_RIPARIUS (setup branch reached)")
        return
    crystal_a.position = Vector3(0.0, 0.5, 0.0)
    crystal_b.position = Vector3(2.0, 0.5, 0.0)
    _sm.add_child(crystal_a)
    _sm.add_child(crystal_b)

    # Click inside crystal A's cell (x=0.9, still within half-cell 1.0) but far
    # enough from its center that a sub-cell interact hitbox (±0.75 for 1.5)
    # misses it and the click falls to the neighbor (or to ground). The interact
    # hitbox must cover the full cell so the cursor resolves to the cell under it.
    var probe := cam.unproject_position(Vector3(0.9, 0.0, 0.0))
    mouse._handle_hover_preview(probe)
    var resolved: Node3D = _sm.hovered_node
    var hit_a: bool = resolved == crystal_a
    (
        TestHelper
        . assert_true(
            hit_a,
            "hover over the edge of crystal A's cell resolves to A, not the neighbor",
        )
    )

    _sm.clear_hover_preview()
    crystal_a.free()
    crystal_b.free()
    (setup["cc"] as Node).free()
    var rules := setup["rules"] as GlobalRules
    rules.shroud_enabled = setup["saved_shroud"]
    rules.fog_of_war = setup["saved_fog"]


func test_flat_overlay_hitbox_does_not_steal_neighbor_cell() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var setup := _setup_world()
    var cam := setup["cam"] as Camera3D
    var mouse := MouseHandler.new()
    mouse.selection_manager = _sm
    mouse.camera_controller = setup["cc"]

    var crystal := EntityFactory.create_entity("TIBERIUM_RIPARIUS")
    if crystal == null:
        TestHelper.fail("EntityFactory must create TIBERIUM_RIPARIUS (setup branch reached)")
        return
    crystal.position = Vector3(0.0, 0.5, 0.0)
    _sm.add_child(crystal)

    # Probe a point in the neighbor cell on the far side of the crystal (cell
    # (0,-1), world (0.5, 0.5, -1.8)). The camera at (0,12,14) looks toward -Z,
    # so the crystal sits between the camera and this target: the angled ray
    # clips the crystal's hitbox top face at (0.44, 1.81, 0) — inside the
    # crystal's own cell — before reaching the target. A flat foundation slab
    # (0.01 tall) is below the ray the whole way over the footprint, so the
    # target resolves to the neighbor instead of the crystal.
    var probe := cam.unproject_position(Vector3(0.5, 0.5, -1.8))
    mouse._handle_hover_preview(probe)
    var resolved: Node3D = _sm.hovered_node
    (
        TestHelper
        . assert_true(
            resolved != crystal,
            "click aimed at the neighbor cell does not resolve to the crystal",
        )
    )

    _sm.clear_hover_preview()
    crystal.free()
    (setup["cc"] as Node).free()
    var rules := setup["rules"] as GlobalRules
    rules.shroud_enabled = setup["saved_shroud"]
    rules.fog_of_war = setup["saved_fog"]


func test_shroud_hover_detection_follows_rules() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var setup := _setup_world()
    var cam := setup["cam"] as Camera3D
    var mouse := MouseHandler.new()
    mouse.selection_manager = _sm
    mouse.camera_controller = setup["cc"]
    var rules := setup["rules"] as GlobalRules

    rules.shroud_enabled = true
    (
        TestHelper
        . assert_true(
            mouse._is_hovering_shrouded(),
            "with shroud enabled, unrevealed ground under the cursor is reported shrouded",
        )
    )

    rules.shroud_enabled = false
    (
        TestHelper
        . assert_true(
            not mouse._is_hovering_shrouded(),
            "with shroud disabled, ground under the cursor is not reported shrouded",
        )
    )

    rules.shroud_enabled = setup["saved_shroud"]
    rules.fog_of_war = setup["saved_fog"]
    mouse.free()
    (setup["cc"] as Node).free()


func test_hover_onto_non_selectable_unit_clears_previous_hover() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var setup := _setup_world()
    var cam := setup["cam"] as Camera3D
    var unit := _make_unit()
    var sc := unit["select_comp"] as SelectComponent

    var non := Node3D.new()
    non.name = "NonSelectableUnit"
    non.position = Vector3(0, 0.5, 3)
    var non_sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    non_sc.name = "SelectComponent"
    non_sc.is_selectable = false
    non.add_child(non_sc)
    _sm.add_child(non)

    var mouse := MouseHandler.new()
    mouse.selection_manager = _sm
    mouse.camera_controller = setup["cc"]

    mouse._handle_hover_preview(cam.unproject_position((unit["entity"] as Node3D).global_position))
    TestHelper.assert_true(sc.is_hovering, "setup: selectable unit is hovered")

    mouse._handle_hover_preview(cam.unproject_position(non.global_position))
    (
        TestHelper
        . assert_true(
            not sc.is_hovering,
            "moving onto a non-selectable unit clears the previous hover immediately",
        )
    )
    TestHelper.assert_true(_sm.hovered_entity == null, "no selectable hover target remains")
    TestHelper.assert_true(mouse._hovered_entity == null, "MouseHandler forgets the unit")

    _sm.clear_hover_preview()
    _sm.deselect_all()
    unit["entity"].free()
    non.free()
    (setup["cc"] as Node).free()
    var rules := setup["rules"] as GlobalRules
    rules.shroud_enabled = setup["saved_shroud"]
    rules.fog_of_war = setup["saved_fog"]
