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


## Minimal sellable/repairable building: FoundationComponent + BUILDING stats +
## HealthComponent. Foundation size is irrelevant to the generator's gate.
func _make_building(damaged: bool = false) -> Node3D:
    var building := Node3D.new()
    building.name = "Building"
    var foundation := FoundationComponent.new()
    foundation.name = "FoundationComponent"
    building.add_child(foundation)
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.entity_type = EntityData.EntityType.BUILDING
    building.add_child(stats)
    var health := HealthComponent.new()
    health.name = "HealthComponent"
    health.max_health = 100
    health.current_health = 50 if damaged else 100
    building.add_child(health)
    return building


func test_sell_order_suppresses_voice_event() -> void:
    var building := _make_building(false)
    var orders := SellOrderGenerator.new().get_orders(building, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(orders.size(), 1, "sellable building produces one order")
    if orders.size() == 1:
        TestHelper.assert_eq(
            orders[0].get("voice_event"), "", "sell order suppresses the voice event"
        )
    building.free()


func test_repair_order_suppresses_voice_event() -> void:
    var building := _make_building(true)
    var orders := RepairOrderGenerator.new().get_orders(building, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_eq(orders.size(), 1, "damaged building produces one order")
    if orders.size() == 1:
        TestHelper.assert_eq(
            orders[0].get("voice_event"), "", "repair order suppresses the voice event"
        )
    building.free()
