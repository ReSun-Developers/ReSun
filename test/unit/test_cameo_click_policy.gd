extends Node

# ProductionManager.handle_cameo_click routing tests (sidebar-ui-thinning).
# The click policy moved from Sidebar into ProductionManager; these tests pin
# the routing decisions (place-ready, retry-spawn, resume, stack, cancel,
# pause, direct-deploy fallback) as observable queue/ready-list state. Refund
# arithmetic itself is covered by test_production_manager.gd.

const PID: int = 214
const INFANTRY_ID: String = "test_click_infantry"
const FACTORY_ID: String = "test_click_barracks"

var _em: Node = null


func _pm() -> Node:
    var pm: Node = _em.get_node_or_null("/root/ProductionManager") if _em else null
    if not pm:
        TestHelper.fail("ProductionManager not reachable")
    return pm


func _make_infantry() -> EntityData:
    var data := EntityData.new()
    data.id = INFANTRY_ID
    data.entity_type = EntityData.EntityType.INFANTRY
    data.display_name = "Test Click Infantry"
    data.cost = 100
    # Pin resolved duration to 5.0 s regardless of cost/rules via the multiplier knob.
    data.build_time_mult = 5.0 / data.get_build_time()
    data.buildable_queue = "InfantryType"
    data.buildable = true
    data.tech_level = 1
    return data


func _make_factory() -> EntityData:
    var data := EntityData.new()
    data.id = FACTORY_ID
    data.entity_type = EntityData.EntityType.BUILDING
    data.display_name = "Test Click Barracks"
    data.factory = "InfantryType"
    data.buildable = true
    data.tech_level = 1
    return data


func _ensure_factory() -> void:
    var ps := _em.get_node_or_null("/root/PrerequisiteSystem")
    var ef := _em.get_node_or_null("/root/EntityFactory")
    var factory_data := _make_factory()
    if ef:
        ef._entity_cache[FACTORY_ID] = factory_data
    if ps:
        ps.register_building(PID, factory_data)


func _cleanup_factory() -> void:
    var ps := _em.get_node_or_null("/root/PrerequisiteSystem")
    var ef := _em.get_node_or_null("/root/EntityFactory")
    var factory_data: EntityData = ef._entity_cache.get(FACTORY_ID, null) if ef else null
    if ps and factory_data:
        ps.unregister_building(PID, factory_data)
    if ef:
        ef._entity_cache.erase(FACTORY_ID)


func _queue_key(pm: Node) -> String:
    return pm.get_queue_key(PID, "InfantryType")


func _cleanup_queue(pm: Node) -> void:
    var key := _queue_key(pm)
    if pm._queues.has(key) and not (pm._queues[key] as Array).is_empty():
        pm.cancel_production(PID, key, 0, 999)
    pm.cancel_ready_building(PID, INFANTRY_ID)
    pm.cancel_ready_spawn(PID, INFANTRY_ID)


func _count(pm: Node) -> int:
    var items: Array = pm.get_queue_items(_queue_key(pm))
    return 0 if items.is_empty() else (items[0] as ProductionQueue).count


func _paused(pm: Node) -> bool:
    var items: Array = pm.get_queue_items(_queue_key(pm))
    return false if items.is_empty() else (items[0] as ProductionQueue).is_paused


func _make_real_factory_node() -> FactoryComponent:
    # has_factory_for scans the "factories" group for FactoryComponent nodes;
    # a PrerequisiteSystem registration alone is not a factory node.
    var factory := FactoryComponent.new()
    factory.name = "TestClickFactory"
    factory.produces = ["InfantryType"]
    factory.player_id = PID
    _em.get_tree().root.add_child(factory)
    return factory


func test_left_click_starts_production() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    _ensure_factory()
    _em.add(PID, 100000, "test")
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_LEFT, false)
    TestHelper.assert_eq(_count(pm), 1, "left click starts one item")
    TestHelper.assert_true(not _paused(pm), "started item is active")
    _cleanup_queue(pm)
    _cleanup_factory()


func test_left_click_with_shift_stacks_five() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    _ensure_factory()
    _em.add(PID, 100000, "test")
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_LEFT, false)
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_LEFT, true)
    TestHelper.assert_eq(_count(pm), 6, "shift left click stacks five onto the existing one")
    _cleanup_queue(pm)
    _cleanup_factory()


func test_right_click_pauses_active_item() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    _ensure_factory()
    _em.add(PID, 100000, "test")
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_LEFT, false)
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_RIGHT, false)
    TestHelper.assert_true(_paused(pm), "right click pauses the active item")
    _cleanup_queue(pm)
    _cleanup_factory()


func test_left_click_resumes_paused_item() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    _ensure_factory()
    _em.add(PID, 100000, "test")
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_LEFT, false)
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_RIGHT, false)
    TestHelper.assert_true(_paused(pm), "setup: item paused")
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_LEFT, false)
    TestHelper.assert_true(not _paused(pm), "left click resumes the paused item")
    TestHelper.assert_eq(_count(pm), 1, "resume does not stack a new item")
    _cleanup_queue(pm)
    _cleanup_factory()


func test_right_click_cancels_paused_item() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    _ensure_factory()
    _em.add(PID, 100000, "test")
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_LEFT, false)
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_RIGHT, false)
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_RIGHT, false)
    TestHelper.assert_true(
        (pm.get_queue_items(_queue_key(pm)) as Array).is_empty(),
        "second right click cancels the paused item"
    )
    _cleanup_queue(pm)
    _cleanup_factory()


func test_right_click_with_shift_cancels_up_to_five() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    _ensure_factory()
    _em.add(PID, 100000, "test")
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_LEFT, false)
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_LEFT, true)
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_RIGHT, true)
    TestHelper.assert_eq(_count(pm), 1, "shift right click cancels five of six")
    _cleanup_queue(pm)
    _cleanup_factory()


func _make_ready_building() -> EntityData:
    var building := EntityData.new()
    building.id = INFANTRY_ID
    building.entity_type = EntityData.EntityType.BUILDING
    building.display_name = "Test Ready Building"
    building.buildable_queue = "BuildingType"
    building.buildable = true
    building.tech_level = 1
    return building


func test_left_click_on_ready_building_enters_build_mode() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    pm._add_ready_to_place(PID, _make_ready_building(), 0.0)
    pm.handle_cameo_click(PID, _make_ready_building(), MOUSE_BUTTON_LEFT, false)
    var bm := _em.get_node_or_null("/root/BuildingManager")
    TestHelper.assert_true(
        bm != null and bm.is_build_mode, "left click on ready building enters build mode"
    )
    if bm and bm.is_build_mode:
        bm.exit_build_mode()
    _cleanup_queue(pm)


func test_right_click_on_ready_building_refunds() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    pm._add_ready_to_place(PID, _make_ready_building(), 500.0)
    pm.handle_cameo_click(PID, _make_ready_building(), MOUSE_BUTTON_RIGHT, false)
    TestHelper.assert_true(
        not pm.is_ready_to_place(PID, INFANTRY_ID), "right click on ready building refunds it"
    )
    _cleanup_queue(pm)


func test_cancelled_placement_keeps_ready_entry() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    pm._add_ready_to_place(PID, _make_ready_building(), 0.0)
    pm.handle_cameo_click(PID, _make_ready_building(), MOUSE_BUTTON_LEFT, false)
    var bm := _em.get_node_or_null("/root/BuildingManager")
    TestHelper.assert_true(bm != null and bm.is_build_mode, "setup: placement armed")
    if bm and bm.is_build_mode:
        bm.exit_build_mode()
    TestHelper.assert_true(
        pm.is_ready_to_place(PID, INFANTRY_ID),
        "cancelling placement keeps the paid entry ready (#339)"
    )
    _cleanup_queue(pm)


func test_reclick_after_cancel_reenters_placement_without_charge() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    _em.add(PID, 100000, "test")
    var balance_before: int = _em.get_balance(PID)
    pm._add_ready_to_place(PID, _make_ready_building(), 0.0)
    pm.handle_cameo_click(PID, _make_ready_building(), MOUSE_BUTTON_LEFT, false)
    var bm := _em.get_node_or_null("/root/BuildingManager")
    if bm and bm.is_build_mode:
        bm.exit_build_mode()
    TestHelper.assert_true(pm.is_ready_to_place(PID, INFANTRY_ID), "setup: entry survived cancel")
    pm.handle_cameo_click(PID, _make_ready_building(), MOUSE_BUTTON_LEFT, false)
    TestHelper.assert_true(
        bm != null and bm.is_build_mode, "re-click after cancel re-enters placement"
    )
    TestHelper.assert_true(
        (pm.get_queue_items(pm.get_queue_key(PID, "BuildingType")) as Array).is_empty(),
        "re-click after cancel starts no production (#339)"
    )
    TestHelper.assert_eq(_em.get_balance(PID), balance_before, "re-click expends no credits")
    if bm and bm.is_build_mode:
        bm.exit_build_mode()
    _cleanup_queue(pm)


func test_reclick_while_placing_is_a_noop() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    pm._add_ready_to_place(PID, _make_ready_building(), 0.0)
    pm.handle_cameo_click(PID, _make_ready_building(), MOUSE_BUTTON_LEFT, false)
    var bm := _em.get_node_or_null("/root/BuildingManager")
    TestHelper.assert_true(bm != null and bm.is_build_mode, "setup: placement armed")
    pm.handle_cameo_click(PID, _make_ready_building(), MOUSE_BUTTON_LEFT, false)
    TestHelper.assert_true(
        bm != null and bm.is_build_mode, "re-click while placing does not toggle placement off"
    )
    if bm and bm.is_build_mode:
        bm.exit_build_mode()
    _cleanup_queue(pm)


func test_consume_ready_building_removes_entry() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    pm._add_ready_to_place(PID, _make_ready_building(), 0.0)
    TestHelper.assert_true(pm.is_ready_to_place(PID, INFANTRY_ID), "setup: entry ready")
    pm.consume_ready_building(PID, INFANTRY_ID)
    TestHelper.assert_true(
        not pm.is_ready_to_place(PID, INFANTRY_ID),
        "consume removes the entry once the building lands (#339)"
    )
    pm.consume_ready_building(PID, INFANTRY_ID)
    _cleanup_queue(pm)


func test_right_click_on_ready_spawn_cancels() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    _ensure_factory()
    pm._add_ready_to_spawn(_make_infantry(), PID, _queue_key(pm))
    TestHelper.assert_true(pm.is_ready_to_spawn(PID, INFANTRY_ID), "setup: unit ready to spawn")
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_RIGHT, false)
    TestHelper.assert_true(
        not pm.is_ready_to_spawn(PID, INFANTRY_ID), "right click on ready spawn cancels it"
    )
    _cleanup_queue(pm)
    _cleanup_factory()


func test_direct_deploy_fallback_without_factory() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    Cheats.no_prereqs = true
    var placer := _em.get_node_or_null("/root/EntityPlacer")
    placer.exit_placing_mode()
    # No factory registered → the cameo click arms a direct-deploy session.
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_LEFT, false)
    TestHelper.assert_true(placer.is_placing(), "no factory + no prereqs arms direct deploy")
    TestHelper.assert_true(
        (pm.get_queue_items(_queue_key(pm)) as Array).is_empty(),
        "direct deploy does not start production"
    )
    placer.exit_placing_mode()
    _cleanup_queue(pm)


func test_factory_present_starts_production_instead() -> void:
    var pm := _pm()
    if not pm:
        return
    _cleanup_queue(pm)
    _ensure_factory()
    var factory_node := _make_real_factory_node()
    Cheats.no_prereqs = true
    var placer := _em.get_node_or_null("/root/EntityPlacer")
    placer.exit_placing_mode()
    pm.handle_cameo_click(PID, _make_infantry(), MOUSE_BUTTON_LEFT, false)
    TestHelper.assert_true(not placer.is_placing(), "factory present → no direct deploy")
    TestHelper.assert_eq(_count(pm), 1, "factory present → production starts")
    factory_node.free()
    _cleanup_queue(pm)
    _cleanup_factory()
