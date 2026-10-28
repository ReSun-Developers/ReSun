extends Node

# SelectComponent unit tests — refinery storage bar (3D mesh path)

const SELECT_COMPONENT_SCENE: PackedScene = preload("res://scenes/components/SelectComponent.tscn")


func _make_refinery_entity(player_id: int) -> Node3D:
    var entity := Node3D.new()
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.id = "GDI_REFINERY"
    stats.player_id = player_id
    entity.add_child(stats)
    var sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    sc.name = "SelectComponent"
    sc.select_box_type = SelectComponent.SelectBoxType.Structure
    entity.add_child(sc)
    return entity


func _make_non_refinery_entity(player_id: int = 0) -> Node3D:
    var entity := Node3D.new()
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.id = "GDI_POWER_PLANT"
    stats.player_id = player_id
    entity.add_child(stats)
    var sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    sc.name = "SelectComponent"
    sc.select_box_type = SelectComponent.SelectBoxType.Structure
    entity.add_child(sc)
    return entity


# Storage capacity is summed from owned buildings, registered by the production
# lifecycle (BuildingManager.building_placed → PrerequisiteSystem). Tests mirror
# that order: add_child first, then register.
func _stock_refinery(pid: int) -> void:
    var ps := EconomyManager.get_node_or_null("/root/PrerequisiteSystem")
    var data: EntityData = EntityFactory.get_entity_data("GDI_REFINERY")
    if ps and data:
        ps.register_building(pid, data)


func _unstock_refinery(pid: int) -> void:
    var ps := EconomyManager.get_node_or_null("/root/PrerequisiteSystem")
    var data: EntityData = EntityFactory.get_entity_data("GDI_REFINERY")
    if ps and data:
        ps.unregister_building(pid, data)


func test_refinery_builds_storage_bar():
    var pid := 1300
    EconomyManager.add(pid, 500, "test")
    var entity := _make_refinery_entity(pid)
    (Engine.get_main_loop() as SceneTree).root.add_child(entity)
    var sc := entity.get_node("SelectComponent") as SelectComponent
    (
        TestHelper
        . assert_true(
            is_instance_valid(sc._storage_bar),
            "refinery SelectComponent builds a storage bar",
        )
    )
    (
        TestHelper
        . assert_true(
            sc._storage_bar.name == "StorageBar",
            "storage bar node is named StorageBar",
        )
    )
    # Production order: the bar is built at add_child, before building_placed
    # registers the refinery, so capacity is still 0 at this point.
    (
        TestHelper
        . assert_true(
            sc._storage_bar.scale.x < 0.01,
            (
                "storage bar is empty before the building is registered: got %f"
                % sc._storage_bar.scale.x
            ),
        )
    )
    _stock_refinery(pid)
    (
        TestHelper
        . assert_true(
            absf(sc._storage_bar.scale.x - 0.5) < 0.001,
            (
                "registration re-scales the bar to balance/capacity: expected 0.5, got %f"
                % sc._storage_bar.scale.x
            ),
        )
    )
    var expected_z: float = 1.0 - SelectComponent.HEALTH_BAR_CUBE_SIZE / 2.0
    (
        TestHelper
        . assert_true(
            absf(sc._storage_bar.position.z - expected_z) < 0.001,
            (
                "storage bar sits on the south z edge: expected z %f, got %f"
                % [expected_z, sc._storage_bar.position.z]
            ),
        )
    )
    (
        TestHelper
        . assert_true(
            not sc._storage_bar.visible,
            "storage bar hidden until selected",
        )
    )
    _unstock_refinery(pid)
    entity.free()


func test_storage_bar_updates_on_credits_changed():
    var pid := 1301
    EconomyManager.add(pid, 500, "test")
    var entity := _make_refinery_entity(pid)
    (Engine.get_main_loop() as SceneTree).root.add_child(entity)
    var sc := entity.get_node("SelectComponent") as SelectComponent
    _stock_refinery(pid)
    EconomyManager.add(pid, 500, "harvest")
    (
        TestHelper
        . assert_true(
            absf(sc._storage_bar.scale.x - 1.0) < 0.001,
            (
                "storage bar fill updates after harvest: expected 1.0, got %f"
                % sc._storage_bar.scale.x
            ),
        )
    )
    _unstock_refinery(pid)
    entity.free()


func test_free_credits_do_not_fill_storage_bar():
    var pid := 1303
    EconomyManager.add(pid, 1000, "crate", "tiberium", true)
    var entity := _make_refinery_entity(pid)
    (Engine.get_main_loop() as SceneTree).root.add_child(entity)
    var sc := entity.get_node("SelectComponent") as SelectComponent
    _stock_refinery(pid)
    (
        TestHelper
        . assert_true(
            sc._storage_bar.scale.x < 0.01,
            (
                "free credits do not fill the storage bar: expected near 0, got %f"
                % sc._storage_bar.scale.x
            ),
        )
    )
    EconomyManager.add(pid, 500, "harvest")
    (
        TestHelper
        . assert_true(
            absf(sc._storage_bar.scale.x - 0.5) < 0.001,
            (
                "harvest income fills the bar alongside free credits: expected 0.5, got %f"
                % sc._storage_bar.scale.x
            ),
        )
    )
    _unstock_refinery(pid)
    entity.free()


func test_storage_bar_visible_on_select_and_hover():
    var pid := 1302
    EconomyManager.add(pid, 500, "test")
    var entity := _make_refinery_entity(pid)
    (Engine.get_main_loop() as SceneTree).root.add_child(entity)
    var sc := entity.get_node("SelectComponent") as SelectComponent
    _stock_refinery(pid)
    sc.set_is_selected(true)
    (
        TestHelper
        . assert_true(
            sc._storage_bar.visible,
            "storage bar visible when selected",
        )
    )
    sc.set_is_selected(false)
    sc.set_is_hovering(true)
    (
        TestHelper
        . assert_true(
            sc._storage_bar.visible,
            "storage bar visible when hovered",
        )
    )
    sc.set_is_hovering(false)
    (
        TestHelper
        . assert_true(
            not sc._storage_bar.visible,
            "storage bar hidden when neither selected nor hovered",
        )
    )
    _unstock_refinery(pid)
    entity.free()


func test_storage_bar_rescales_when_capacity_changes():
    var pid := 1304
    EconomyManager.add(pid, 500, "harvest")
    var entity := _make_refinery_entity(pid)
    (Engine.get_main_loop() as SceneTree).root.add_child(entity)
    var sc := entity.get_node("SelectComponent") as SelectComponent
    _stock_refinery(pid)
    (
        TestHelper
        . assert_true(
            absf(sc._storage_bar.scale.x - 0.5) < 0.001,
            (
                "bar scales to balance/capacity at one storage building: expected 0.5, got %f"
                % sc._storage_bar.scale.x
            ),
        )
    )
    # A second storage building doubles capacity → same balance fills half as much.
    _stock_refinery(pid)
    (
        TestHelper
        . assert_true(
            absf(sc._storage_bar.scale.x - 0.25) < 0.001,
            "bar re-scales when capacity grows: expected 0.25, got %f" % sc._storage_bar.scale.x,
        )
    )
    _unstock_refinery(pid)
    _unstock_refinery(pid)
    entity.free()


func test_non_refinery_builds_no_storage_bar():
    var entity := _make_non_refinery_entity()
    (Engine.get_main_loop() as SceneTree).root.add_child(entity)
    var sc := entity.get_node("SelectComponent") as SelectComponent
    (
        TestHelper
        . assert_true(
            not is_instance_valid(sc._storage_bar),
            "non-refinery structure builds no storage bar",
        )
    )
    entity.free()


# ========================================
# Selectability group registration (#451)
# ========================================


func _make_group_entity(select_box_type: int) -> Node3D:
    var entity := Node3D.new()
    var sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    sc.name = "SelectComponent"
    sc.select_box_type = select_box_type
    entity.add_child(sc)
    return entity


func test_non_selectable_unit_joins_only_entities_group():
    var entity := _make_group_entity(SelectComponent.SelectBoxType.Vehicle)
    var sc := entity.get_node("SelectComponent") as SelectComponent
    sc.is_selectable = false
    sc.is_drag_selectable = false
    (Engine.get_main_loop() as SceneTree).root.add_child(entity)
    var result := (
        entity.is_in_group("entities")
        and not entity.is_in_group("selectable")
        and not entity.is_in_group("drag_selectable")
    )
    entity.free()
    TestHelper.assert_true(result, "non-selectable unit joins only the entities group")


func test_drag_opt_out_keeps_click_selectable_group():
    var entity := _make_group_entity(SelectComponent.SelectBoxType.Vehicle)
    var sc := entity.get_node("SelectComponent") as SelectComponent
    sc.is_selectable = true
    sc.is_drag_selectable = false
    (Engine.get_main_loop() as SceneTree).root.add_child(entity)
    var result := (
        entity.is_in_group("selectable")
        and not entity.is_in_group("drag_selectable")
        and entity.is_in_group("entities")
    )
    entity.free()
    TestHelper.assert_true(result, "drag opt-out stays in selectable but not drag_selectable")


func test_structure_joins_selectable_but_not_drag():
    var entity := _make_group_entity(SelectComponent.SelectBoxType.Structure)
    (Engine.get_main_loop() as SceneTree).root.add_child(entity)
    var result := (
        entity.is_in_group("selectable")
        and entity.is_in_group("entities")
        and not entity.is_in_group("drag_selectable")
    )
    entity.free()
    TestHelper.assert_true(result, "structure joins selectable/entities but never drag_selectable")


func test_non_selectable_structure_joins_only_entities_group():
    var entity := _make_group_entity(SelectComponent.SelectBoxType.Structure)
    var sc := entity.get_node("SelectComponent") as SelectComponent
    sc.is_selectable = false
    (Engine.get_main_loop() as SceneTree).root.add_child(entity)
    var result := (
        entity.is_in_group("entities")
        and not entity.is_in_group("selectable")
        and not entity.is_in_group("drag_selectable")
    )
    entity.free()
    TestHelper.assert_true(result, "non-selectable structure joins only the entities group")
