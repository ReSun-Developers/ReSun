extends Node

# OrderSystem mode-state API tests (sidebar-ui-thinning, order-system spec).
# Mode state is derived from the active generator's type — sell/repair modes
# are armed via set_generator and reset via cancel, and generator_changed
# notifies UI so buttons sync themselves without imperative un-press calls.
# Every test restores the unit generator so the shared autoload is clean.

var _ts: Node = null
var _set_count: int = 0
var _cancel_count: int = 0


func _watch() -> void:
    var os := _os()
    _set_count = 0
    _cancel_count = 0
    os.generator_changed.connect(_on_generator_changed)


func _unwatch() -> void:
    _os().generator_changed.disconnect(_on_generator_changed)


func _on_generator_changed() -> void:
    _set_count += 1


func _os() -> Node:
    # The runner never adds this suite to the tree, so resolve the autoload
    # through an injected in-tree sibling (_ts = TerrainSystem), not /root.
    var os: Node = _ts.get_node_or_null("/root/OrderSystem") if _ts else null
    if not os:
        TestHelper.fail("OrderSystem autoload not reachable")
    return os


func _reset_mode() -> void:
    _os().cancel()


func test_sell_mode_derives_from_generator_type() -> void:
    var os := _os()
    if not os:
        return
    _reset_mode()
    _watch()
    os.set_generator(SellOrderGenerator.new())
    _unwatch()
    TestHelper.assert_true(os.is_sell_mode(), "sell generator arms sell mode")
    TestHelper.assert_true(os.is_action_mode(), "sell generator is an action mode")
    TestHelper.assert_true(not os.is_repair_mode(), "sell generator is not repair mode")
    _reset_mode()


func test_repair_mode_derives_from_generator_type() -> void:
    var os := _os()
    if not os:
        return
    _reset_mode()
    os.set_generator(RepairOrderGenerator.new())
    TestHelper.assert_true(os.is_repair_mode(), "repair generator arms repair mode")
    TestHelper.assert_true(os.is_action_mode(), "repair generator is an action mode")
    TestHelper.assert_true(not os.is_sell_mode(), "repair generator is not sell mode")
    _reset_mode()


func test_cancel_resets_to_unit_generator() -> void:
    var os := _os()
    if not os:
        return
    os.set_generator(SellOrderGenerator.new())
    os.cancel()
    TestHelper.assert_true(not os.is_action_mode(), "cancel clears action mode")
    TestHelper.assert_true(
        os.active_generator == UnitOrderGenerator.get_instance(),
        "cancel restores the unit order generator singleton"
    )


func test_generator_changed_emits_on_set_and_cancel() -> void:
    var os := _os()
    if not os:
        return
    _reset_mode()
    _watch()
    os.set_generator(SellOrderGenerator.new())
    var after_set: int = _set_count
    os.cancel()
    var after_cancel: int = _set_count
    _unwatch()
    TestHelper.assert_eq(after_set, 1, "set_generator emits generator_changed once")
    TestHelper.assert_eq(after_cancel, 2, "cancel emits generator_changed after the set")


func test_set_generator_replaces_previous_generator() -> void:
    var os := _os()
    if not os:
        return
    _reset_mode()
    os.set_generator(SellOrderGenerator.new())
    os.set_generator(RepairOrderGenerator.new())
    TestHelper.assert_true(os.is_repair_mode(), "second set_generator replaces the first")
    TestHelper.assert_true(not os.is_sell_mode(), "sell mode no longer active after replace")
    _reset_mode()


## Factory-built 1x1 structure, so the fixture matches real spawn output.
func _make_building(damaged: bool = false, owner_id: int = -1) -> Node3D:
    var ef: Node = _ts.get_node_or_null("/root/EntityFactory") if _ts else null
    if not ef:
        TestHelper.fail("EntityFactory autoload not reachable")
        return null
    var building := ef.create_entity("GDI_SILO") as Node3D
    if not building:
        TestHelper.fail("EntityFactory could not create GDI_SILO")
        return null
    var stats := building.get_node_or_null("StatsComponent") as StatsComponent
    if stats:
        stats.player_id = PlayerManager.get_local_player_id() if owner_id < 0 else owner_id
    var health := building.get_node_or_null("HealthComponent") as HealthComponent
    if health:
        health.max_health = 100
        health.current_health = 50 if damaged else 100
    return building


func test_sell_order_suppresses_voice_event() -> void:
    var building := _make_building(false)
    if building == null:
        return
    var orders := SellOrderGenerator.new().get_orders(building, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(orders.size(), 1, "sellable building produces one order")
    if orders.size() == 1:
        TestHelper.assert_eq(
            orders[0].get("voice_event"), "", "sell order suppresses the voice event"
        )
    building.free()


func test_enemy_building_not_sellable() -> void:
    var building := _make_building(false, PlayerManager.get_local_player_id() + 1)
    if building == null:
        return
    var orders := SellOrderGenerator.new().get_orders(building, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(orders.size(), 0, "enemy-owned building produces no sell order")
    building.free()


func test_repair_order_suppresses_voice_event() -> void:
    var building := _make_building(true)
    if building == null:
        return
    var orders := RepairOrderGenerator.new().get_orders(building, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(orders.size(), 1, "damaged building produces one order")
    if orders.size() == 1:
        TestHelper.assert_eq(
            orders[0].get("voice_event"), "", "repair order suppresses the voice event"
        )
    building.free()
