extends Node

# ProductionManager tests — queue stacking, count param, cancel refund logic

# Injected by test runner (see run_tests.gd:_inject_autoloads)
var _em: Node = null

# FactoryComponent nodes created by speed-cache tests (cleaned up per test)
var _test_factories: Array = []

# Unique player ID to avoid state leakage
const PID := 200
# Separate ID for funding tests so leftover queues/balances from other suites
# cannot drain the credits these tests deposit.
const PID_FUND := 201


func _get_pm() -> Node:
    if _em == null:
        return null
    return _em.get_node_or_null("/root/ProductionManager")


func _make_infantry(id: String = "test_infantry", cost: int = 100) -> EntityData:
    var data := EntityData.new()
    data.id = id
    data.entity_type = EntityData.EntityType.INFANTRY
    data.display_name = "Test Infantry"
    data.cost = cost
    # Pin resolved duration to 5.0 s regardless of cost/rules via the multiplier knob.
    data.build_time_mult = 5.0 / data.get_build_time()
    data.buildable_queue = "InfantryType"
    data.buildable = true
    data.tech_level = 1
    return data


func _make_factory() -> EntityData:
    var data := EntityData.new()
    data.id = "test_barracks"
    data.entity_type = EntityData.EntityType.BUILDING
    data.display_name = "Test Barracks"
    data.factory = "InfantryType"
    data.buildable = true
    data.tech_level = 1
    return data


func _ensure_factory(pid: int = PID) -> void:
    if _em == null:
        return
    var ps := _em.get_node_or_null("/root/PrerequisiteSystem")
    if ps and ps.get_build_count(pid, "test_barracks") > 0:
        return
    var factory_data := _make_factory()
    var ef := _em.get_node_or_null("/root/EntityFactory")
    if ef:
        ef._entity_cache["test_barracks"] = factory_data
    if ps:
        ps.register_building(pid, factory_data)


func _cleanup_queue(pm: Node, queue_key: String) -> void:
    if not pm._queues.has(queue_key):
        return
    var queue: Array = pm._queues[queue_key]
    for item in queue:
        var pq: ProductionQueue = item as ProductionQueue
        if pq and pq.is_paused:
            pq.is_paused = false
    pm._queues.erase(queue_key)
    pm._active_index.erase(queue_key)


# --- production speed cache (D5) ---


## Create a real FactoryComponent in the scene tree so _ready joins the group.
func _make_factory_node(produces: Array[String] = ["InfantryType"]) -> FactoryComponent:
    var factory := FactoryComponent.new()
    factory.name = "TestFactory"
    factory.produces = produces
    factory.player_id = PID
    _em.get_tree().root.add_child(factory)
    _test_factories.append(factory)
    return factory


func _free_test_factories() -> void:
    for factory in _test_factories:
        if is_instance_valid(factory):
            factory.free()
    _test_factories.clear()


## Expected speed for a given factory count per the multiple-factory rule.
func _expected_speed(factory_count: int) -> float:
    var multiple_factory: float = 0.4
    var rules := GlobalRules.get_current()
    if rules:
        multiple_factory = rules.multiple_factory
    return 1.0 + (factory_count - 1) * multiple_factory


func test_production_speed_cached_until_invalidated():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    pm._speed_cache.clear()
    var key: String = pm.get_queue_key(PID, "InfantryType")
    _make_factory_node()
    var speed_one: float = pm._get_production_speed(key)
    if not pm._speed_cache.has(key):
        TestHelper.fail("first speed lookup should populate the cache")
        _free_test_factories()
        return
    # Cache hit reuses the value without re-scanning the group.
    var cached_speed: float = pm._get_production_speed(key)
    var cache_hit: bool = cached_speed == speed_one
    # Any factory added through the tree invalidates the cached speed.
    _make_factory_node()
    var recomputed_speed: float = pm._get_production_speed(key)
    var recomputed_after_add: bool = recomputed_speed == _expected_speed(2)
    (
        TestHelper
        . assert_true(
            cache_hit and recomputed_after_add,
            (
                "cache hit reuses the value, factory add invalidates: "
                + (
                    "expected %f then %f, got %f then %f"
                    % [_expected_speed(1), _expected_speed(2), cached_speed, recomputed_speed]
                )
            ),
        )
    )
    _free_test_factories()


func test_production_speed_recomputed_after_factory_added():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    pm._speed_cache.clear()
    var key: String = pm.get_queue_key(PID, "InfantryType")
    _make_factory_node()
    var speed_before: float = pm._get_production_speed(key)
    _make_factory_node()
    # Factories are buildings placed via BuildingManager, which unblocks the queue
    pm.clear_waiting_for_placement(PID)
    var speed_after: float = pm._get_production_speed(key)
    (
        TestHelper
        . assert_true(
            speed_before == _expected_speed(1) and speed_after == _expected_speed(2),
            (
                "speed recomputed when a factory is placed: expected %f/%f, got %f/%f"
                % [_expected_speed(1), _expected_speed(2), speed_before, speed_after]
            ),
        )
    )
    _free_test_factories()


# --- low power build rate ---


## Plant + heavy consumer so PID's grid sits in deficit with a known ratio.
func _add_power_entities(output: int, drain: int) -> Array:
    var grid := _em.get_node_or_null("/root/PowerGrid")
    if grid == null:
        return []
    var entities: Array = []
    if output > 0:
        entities.append(_make_power_entity(output, PID, false))
    if drain > 0:
        entities.append(_make_power_entity(-drain, PID, false))
    for entity in entities:
        _em.get_tree().root.add_child(entity)
    return entities


func _make_power_entity(power: int, pid: int, powered: bool) -> Node3D:
    var entity := Node3D.new()
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = pid
    entity.add_child(stats)
    var pc := PowerComponent.new()
    pc.name = "PowerComponent"
    pc.power = power
    pc.powered = powered
    entity.add_child(pc)
    return entity


func _expected_low_power_rate(output: int, drain: int) -> float:
    return 0.3 + (0.75 - 0.3) * (float(output) / float(drain))


func test_low_power_slows_production_speed():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    var grid := _em.get_node_or_null("/root/PowerGrid")
    if grid == null:
        TestHelper.fail("PowerGrid autoload missing")
        return
    pm._speed_cache.clear()
    var key: String = pm.get_queue_key(PID, "InfantryType")
    _make_factory_node()
    var entities := _add_power_entities(100, 150)
    if entities.is_empty():
        TestHelper.fail("PowerGrid not testable — entities not added")
        _free_test_factories()
        return
    var slowed: float = pm._get_production_speed(key)
    var expected: float = _expected_speed(1) * _expected_low_power_rate(100, 150)
    var rate_matches: bool = absf(slowed - expected) < 1e-6
    var grid_rate: float = grid.get_build_rate(PID)
    (
        TestHelper
        . assert_true(
            rate_matches and absf(grid_rate - _expected_low_power_rate(100, 150)) < 1e-6,
            (
                "deficit slows production by the interpolated rate: expected ~%f, got %f"
                % [expected, slowed]
            ),
        )
    )
    for entity in entities:
        entity.free()
    _free_test_factories()


func test_power_recovery_restores_full_speed():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    pm._speed_cache.clear()
    var key: String = pm.get_queue_key(PID, "InfantryType")
    _make_factory_node()
    var entities := _add_power_entities(0, 100)
    var slowed: float = pm._get_production_speed(key)
    for entity in entities:
        entity.free()
    var recovered: float = pm._get_production_speed(key)
    (
        TestHelper
        . assert_true(
            absf(slowed - _expected_speed(1) * 0.3) < 1e-6 and recovered == _expected_speed(1),
            "blackout rate 0.3, recovery returns full speed: got %f then %f" % [slowed, recovered],
        )
    )
    _free_test_factories()


func test_grid_state_change_invalidates_speed_cache():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    pm._speed_cache.clear()
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var entities := _add_power_entities(100, 150)
    _make_factory_node()
    pm._get_production_speed(key)
    var cached: bool = pm._speed_cache.has(key)
    # Destroying the producer emits grid_state_changed -> cache entry dropped.
    entities[0].free()
    var invalidated: bool = not pm._speed_cache.has(key)
    var refreshed: float = pm._get_production_speed(key)
    var expected: float = _expected_speed(1) * 0.3
    (
        TestHelper
        . assert_true(
            cached and invalidated and absf(refreshed - expected) < 1e-6,
            (
                "grid change drops the cached speed and the next lookup uses the new rate: "
                + "got refreshed %f, expected ~%f" % [refreshed, expected]
            ),
        )
    )
    entities[1].free()
    _free_test_factories()


func test_production_speed_recomputed_after_factory_destroyed():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    pm._speed_cache.clear()
    var key: String = pm.get_queue_key(PID, "InfantryType")
    _make_factory_node()
    var factory_b := _make_factory_node()
    var speed_before: float = pm._get_production_speed(key)
    factory_b.free()
    var cache_cleared: bool = pm._speed_cache.is_empty()
    var speed_after: float = pm._get_production_speed(key)
    (
        TestHelper
        . assert_true(
            (
                speed_before == _expected_speed(2)
                and cache_cleared
                and speed_after == _expected_speed(1)
            ),
            (
                "destroying a factory invalidates the cache: expected %f then %f, "
                + (
                    "got %f then %f"
                    % [_expected_speed(2), _expected_speed(1), speed_before, speed_after]
                )
            ),
        )
    )
    _free_test_factories()


func test_set_primary_invalidates_speed_cache():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    pm._speed_cache.clear()
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var factory_a := _make_factory_node()
    _make_factory_node()
    pm._get_production_speed(key)
    if pm._speed_cache.is_empty():
        TestHelper.fail("cache should be populated")
        _free_test_factories()
        return
    factory_a.set_primary()
    (
        TestHelper
        . assert_true(
            pm._speed_cache.is_empty(),
            "set_primary emits factories_changed and clears the speed cache",
        )
    )
    _free_test_factories()


# --- queue teardown when the final factory is lost (#342) ---


func test_losing_last_factory_cancels_active_queue_and_refunds_paid_credits() -> void:
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var key: String = pm.get_queue_key(PID, "InfantryType")
    _cleanup_queue(pm, key)
    _make_factory_node()
    var data := _make_infantry("test_factory_loss_active", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data)
    pm._process(1.0)
    var item: ProductionQueue = pm.get_queue_items(key)[0] as ProductionQueue
    var paid: int = int(item.deducted)
    var balance_before: int = _em.get_balance(PID)

    (_test_factories[0] as FactoryComponent).free()

    var queue_cancelled: bool = pm.get_queue_items(key).is_empty()
    var refunded: bool = _em.get_balance(PID) == balance_before + paid
    (
        TestHelper
        . assert_true(
            paid > 0 and queue_cancelled and refunded,
            "losing the last factory cancels active production and refunds %d paid credits" % paid,
        )
    )
    _free_test_factories()
    _cleanup_queue(pm, key)


func test_losing_one_of_two_factories_keeps_queue_running() -> void:
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var key: String = pm.get_queue_key(PID, "InfantryType")
    _cleanup_queue(pm, key)
    _make_factory_node()
    var factory_b := _make_factory_node()
    var data := _make_infantry("test_factory_loss_one_of_two", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data)
    pm._process(1.0)
    var balance_before: int = _em.get_balance(PID)

    factory_b.free()

    var items: Array = pm.get_queue_items(key)
    var kept: bool = items.size() == 1
    var not_refunded: bool = _em.get_balance(PID) == balance_before
    var speed_recomputed: bool = pm._get_production_speed(key) == _expected_speed(1)
    (
        TestHelper
        . assert_true(
            kept and not_refunded and speed_recomputed,
            "losing one of two factories keeps the queue and recomputes one-factory speed",
        )
    )
    _cleanup_queue(pm, key)
    _free_test_factories()


func test_losing_last_factory_cancels_paused_queue() -> void:
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var key: String = pm.get_queue_key(PID, "InfantryType")
    _cleanup_queue(pm, key)
    _make_factory_node()
    var data := _make_infantry("test_factory_loss_paused", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data)
    pm._process(1.0)
    pm.pause_production(key, 0)
    var item: ProductionQueue = pm.get_queue_items(key)[0] as ProductionQueue
    var paid: int = int(item.deducted)
    var balance_before: int = _em.get_balance(PID)

    (_test_factories[0] as FactoryComponent).free()

    (
        TestHelper
        . assert_true(
            pm.get_queue_items(key).is_empty() and _em.get_balance(PID) == balance_before + paid,
            "losing the last factory cancels and refunds paused production",
        )
    )
    _free_test_factories()
    _cleanup_queue(pm, key)


func test_losing_factory_cancels_each_unsupported_queue_type() -> void:
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    var infantry_key: String = pm.get_queue_key(PID, "InfantryType")
    var vehicle_key: String = pm.get_queue_key(PID, "VehicleType")
    _cleanup_queue(pm, infantry_key)
    _cleanup_queue(pm, vehicle_key)
    _make_factory_node(["InfantryType", "VehicleType"])
    var infantry := _make_infantry("test_factory_loss_infantry", 100)
    var vehicle := _make_infantry("test_factory_loss_vehicle", 150)
    vehicle.entity_type = EntityData.EntityType.VEHICLE
    vehicle.buildable_queue = "VehicleType"
    var infantry_item := ProductionQueue.new(infantry, 1)
    var vehicle_item := ProductionQueue.new(vehicle, 1)
    infantry_item.deducted = 30.0
    vehicle_item.deducted = 45.0
    pm._queues[infantry_key] = [infantry_item]
    pm._queues[vehicle_key] = [vehicle_item]
    pm._active_index[infantry_key] = 0
    pm._active_index[vehicle_key] = 0
    var setup_paid: bool = _em.deduct(PID, 75, "test_setup")
    if not setup_paid:
        TestHelper.fail("setup must deduct the credits represented by the test queues")
        _free_test_factories()
        _cleanup_queue(pm, infantry_key)
        _cleanup_queue(pm, vehicle_key)
        return
    var balance_before: int = _em.get_balance(PID)

    (_test_factories[0] as FactoryComponent).free()

    (
        TestHelper
        . assert_true(
            (
                pm.get_queue_items(infantry_key).is_empty()
                and pm.get_queue_items(vehicle_key).is_empty()
                and _em.get_balance(PID) == balance_before + 75
            ),
            "losing a multi-queue factory cancels and refunds every unsupported queue",
        )
    )
    _free_test_factories()
    _cleanup_queue(pm, infantry_key)
    _cleanup_queue(pm, vehicle_key)


func test_factory_loss_keeps_completed_building_ready_for_placement() -> void:
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    var data := _make_infantry("test_factory_loss_ready", 100)
    data.entity_type = EntityData.EntityType.BUILDING
    pm._add_ready_to_place(PID, data, 100.0)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var queued_data := _make_infantry("test_factory_loss_queued_beside_ready", 50)
    pm._queues[key] = [ProductionQueue.new(queued_data, 1)]
    pm._active_index[key] = 0
    _make_factory_node()
    var balance_before: int = _em.get_balance(PID)

    (_test_factories[0] as FactoryComponent).free()

    (
        TestHelper
        . assert_true(
            (
                pm.is_ready_to_place(PID, data.id)
                and pm.get_queue_items(key).is_empty()
                and _em.get_balance(PID) == balance_before
            ),
            "factory loss tears down its queue but keeps a completed building ready for placement",
        )
    )
    pm._ready_to_place.erase(PID)
    _cleanup_queue(pm, key)
    _free_test_factories()


func test_factory_loss_cancels_each_item_once_and_emits_one_refresh() -> void:
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    var key: String = pm.get_queue_key(PID, "InfantryType")
    _cleanup_queue(pm, key)
    _make_factory_node()
    var first := ProductionQueue.new(_make_infantry("test_factory_loss_first", 100), 2)
    var second := ProductionQueue.new(_make_infantry("test_factory_loss_second", 100), 1)
    var ready := _make_infantry("test_factory_loss_ready_in_batch", 40)
    first.deducted = 20.0
    second.deducted = 35.0
    pm._queues[key] = [first, second]
    pm._active_index[key] = 0
    pm._add_ready_to_spawn(ready, PID, key)
    _em.add(PID, 95, "test_setup_funds")
    if not _em.deduct(PID, 95, "test_setup_paid"):
        TestHelper.fail("setup must deduct queued and completed items' paid credits")
        _free_test_factories()
        _cleanup_queue(pm, key)
        return
    var balance_before: int = _em.get_balance(PID)
    var refreshes := [0]
    var on_cancelled := func(changed_key: String) -> void:
        if changed_key == key:
            refreshes[0] += 1
    pm.production_cancelled.connect(on_cancelled)

    (_test_factories[0] as FactoryComponent).free()

    pm.production_cancelled.disconnect(on_cancelled)
    (
        TestHelper
        . assert_true(
            (
                pm.get_queue_items(key).is_empty()
                and not pm.is_ready_to_spawn(PID, ready.id)
                and _em.get_balance(PID) == balance_before + 95
                and refreshes[0] == 1
            ),
            "factory loss batches queued and ready refunds into one refresh",
        )
    )
    _free_test_factories()
    _cleanup_queue(pm, key)


func test_factory_loss_refunds_completed_unit_waiting_to_spawn() -> void:
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _make_factory_node()
    var data := _make_infantry("test_factory_loss_ready_spawn", 100)
    _em.add(PID, data.cost, "test_setup_ready_spawn")
    if not _em.deduct(PID, data.cost, "test_ready_spawn_paid"):
        TestHelper.fail("setup must pay for the completed unit")
        _free_test_factories()
        return
    pm._add_ready_to_spawn(data, PID, pm.get_queue_key(PID, data.buildable_queue))
    var balance_before: int = _em.get_balance(PID)

    (_test_factories[0] as FactoryComponent).free()

    (
        TestHelper
        . assert_true(
            (
                not pm.is_ready_to_spawn(PID, data.id)
                and _em.get_balance(PID) == balance_before + data.cost
            ),
            "factory loss removes a completed waiting unit and refunds its full paid cost",
        )
    )
    pm._ready_to_spawn.erase(PID)
    _free_test_factories()


func test_factory_announces_owner_after_initial_sync() -> void:
    if _em == null:
        TestHelper.fail("autoloads not available")
        return
    var parent := Node3D.new()
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = PID
    parent.add_child(stats)
    var factory := FactoryComponent.new()
    factory.name = "FactoryComponent"
    factory.produces = ["InfantryType"]
    parent.add_child(factory)
    var announced_owner := [-2]
    var on_factories_changed := func() -> void: announced_owner[0] = factory.player_id
    factory.factories_changed.connect(on_factories_changed)

    _em.get_tree().root.add_child(parent)

    (
        TestHelper
        . assert_true(
            factory.player_id == PID and announced_owner[0] == PID,
            "the first factories_changed announcement exposes the synchronized owner",
        )
    )
    parent.free()


# --- start_production count parameter ---


func test_start_production_default_count():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data := _make_infantry("test_default", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    (
        TestHelper
        . assert_true(
            items.size() == 1,
            "default count creates 1 item: expected 1 item, got %d" % items.size(),
        )
    )
    _cleanup_queue(pm, key)


func test_start_production_count_5():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data := _make_infantry("test_count5", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data, 5)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.size() == 0:
        TestHelper.fail("expected 1 item, got 0")
        _cleanup_queue(pm, key)
        return
    var pq: ProductionQueue = items[0] as ProductionQueue
    (
        TestHelper
        . assert_true(
            pq.count == 5,
            "count=5 creates stack of 5: expected count 5, got %d" % pq.count,
        )
    )
    _cleanup_queue(pm, key)


func test_start_production_stacking_increments():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data := _make_infantry("test_stack", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data)
    pm.start_production(PID, data)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.size() == 0:
        TestHelper.fail("expected 1 item, got 0")
        _cleanup_queue(pm, key)
        return
    var pq: ProductionQueue = items[0] as ProductionQueue
    (
        TestHelper
        . assert_true(
            items.size() == 1 and pq.count == 2,
            (
                "stacking increments count to 2: expected 1 item count=2, got %d items count=%d"
                % [items.size(), pq.count]
            ),
        )
    )
    _cleanup_queue(pm, key)


func test_start_production_stacking_adds_5():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data := _make_infantry("test_stack5", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data, 3)
    pm.start_production(PID, data, 5)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.size() == 0:
        TestHelper.fail("expected 1 item, got 0")
        _cleanup_queue(pm, key)
        return
    var pq: ProductionQueue = items[0] as ProductionQueue
    (
        TestHelper
        . assert_true(
            pq.count == 8,
            "stacking adds 3+5=8: expected count 8, got %d" % pq.count,
        )
    )
    _cleanup_queue(pm, key)


func test_start_production_stacking_caps_at_max():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data := _make_infantry("test_cap", 100)
    _em.add(PID, 5000, "test")
    pm.start_production(PID, data, 24)
    pm.start_production(PID, data, 5)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.size() == 0:
        TestHelper.fail("expected 1 item, got 0")
        _cleanup_queue(pm, key)
        return
    var pq: ProductionQueue = items[0] as ProductionQueue
    (
        TestHelper
        . assert_true(
            pq.count == pm.MAX_STACK,
            "count capped at MAX_STACK: expected %d, got %d" % [pm.MAX_STACK, pq.count],
        )
    )
    _cleanup_queue(pm, key)


func test_start_production_different_entities_not_stacked():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data_a := _make_infantry("test_a", 100)
    var data_b := _make_infantry("test_b", 200)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data_a)
    pm.start_production(PID, data_b)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    (
        TestHelper
        . assert_true(
            items.size() == 2,
            "different entities create separate entries: expected 2 entries, got %d" % items.size(),
        )
    )
    _cleanup_queue(pm, key)


# --- cancel_production refund logic ---


func test_cancel_single_item_refunds():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data := _make_infantry("test_refund", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.size() == 0:
        TestHelper.fail("expected 1 item, got 0")
        return
    var pq: ProductionQueue = items[0] as ProductionQueue
    pq.deducted = 40.0
    var balance_before: int = _em.get_balance(PID)
    pm.cancel_production(PID, key, 0)
    var balance_after: int = _em.get_balance(PID)
    (
        TestHelper
        . assert_true(
            balance_after == balance_before + 40,
            (
                "single item cancel refunds deducted amount: expected balance %d, got %d"
                % [balance_before + 40, balance_after]
            ),
        )
    )
    _cleanup_queue(pm, key)


func test_cancel_stacked_decrement_no_refund():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data := _make_infantry("test_norefund", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data, 5)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.size() == 0:
        TestHelper.fail("expected 1 item, got 0")
        return
    var pq: ProductionQueue = items[0] as ProductionQueue
    pq.deducted = 50.0
    var balance_before: int = _em.get_balance(PID)
    pm.cancel_production(PID, key, 0, 1)
    var balance_after: int = _em.get_balance(PID)
    var refund := balance_after - balance_before
    (
        TestHelper
        . assert_true(
            pq.count == 4 and balance_after == balance_before,
            (
                "stacked decrement: count=4, no refund: expected count=4 "
                + "no refund, got count=%d refund=%d" % [pq.count, refund]
            ),
        )
    )
    _cleanup_queue(pm, key)


func test_cancel_stacked_by_5_no_refund():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data := _make_infantry("test_cancel5", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data, 10)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.size() == 0:
        TestHelper.fail("expected 1 item, got 0")
        return
    var pq: ProductionQueue = items[0] as ProductionQueue
    pq.deducted = 80.0
    var balance_before: int = _em.get_balance(PID)
    pm.cancel_production(PID, key, 0, 5)
    var balance_after: int = _em.get_balance(PID)
    var refund := balance_after - balance_before
    (
        TestHelper
        . assert_true(
            pq.count == 5 and balance_after == balance_before,
            (
                "cancel 5 from 10: count=5, no refund: expected count=5 "
                + "no refund, got count=%d refund=%d" % [pq.count, refund]
            ),
        )
    )
    _cleanup_queue(pm, key)


func test_cancel_stacked_force_removes_and_refunds():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data := _make_infantry("test_force", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data, 3)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.size() == 0:
        TestHelper.fail("expected 1 item, got 0")
        return
    var pq: ProductionQueue = items[0] as ProductionQueue
    pq.deducted = 60.0
    var balance_before: int = _em.get_balance(PID)
    pm.cancel_production(PID, key, 0, 5)
    var balance_after: int = _em.get_balance(PID)
    var remaining: Array = pm.get_queue_items(key)
    var refund := balance_after - balance_before
    var n_items := remaining.size()
    (
        TestHelper
        . assert_true(
            remaining.size() == 0 and balance_after == balance_before + 60,
            (
                "force cancel (count>=item.count) removes and refunds: expected 0 items "
                + "refund=60, got %d items refund=%d" % [n_items, refund]
            ),
        )
    )
    _cleanup_queue(pm, key)


func test_cancel_entire_queue_cleans_up():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data := _make_infantry("test_cleanup", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    pm.cancel_production(PID, key, 0)
    var items: Array = pm.get_queue_items(key)
    (
        TestHelper
        . assert_true(
            items.size() == 0,
            "queue cleaned up after last item removed: expected 0 items, got %d" % items.size(),
        )
    )
    _cleanup_queue(pm, key)


# --- pause / resume ---


func test_pause_and_resume():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data := _make_infantry("test_pauses", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.size() == 0:
        TestHelper.fail("expected 1 item, got 0")
        return
    var pq: ProductionQueue = items[0] as ProductionQueue
    var ok := true
    if pq.is_paused:
        ok = false
    pm.pause_production(key, 0)
    if not pq.is_paused:
        ok = false
    pm.resume_production(key, 0)
    if pq.is_paused:
        ok = false
    (
        TestHelper
        . assert_true(
            ok,
            "pause and resume toggle is_paused: pause/resume did not toggle correctly",
        )
    )
    _cleanup_queue(pm, key)


# --- cancel on paused items (right-click behavior) ---


func test_cancel_paused_single_removes():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data := _make_infantry("test_cancel_paused", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.size() == 0:
        TestHelper.fail("expected 1 item, got 0")
        return
    var pq: ProductionQueue = items[0] as ProductionQueue
    pq.deducted = 30.0
    pm.pause_production(key, 0)
    var balance_before: int = _em.get_balance(PID)
    pm.cancel_production(PID, key, 0, 1)
    var balance_after: int = _em.get_balance(PID)
    var remaining: Array = pm.get_queue_items(key)
    var refund := balance_after - balance_before
    var n_items := remaining.size()
    (
        TestHelper
        . assert_true(
            remaining.size() == 0 and balance_after == balance_before + 30,
            (
                "cancel paused single item removes and refunds: expected 0 items "
                + "refund=30, got %d items refund=%d" % [n_items, refund]
            ),
        )
    )
    _cleanup_queue(pm, key)


func test_cancel_paused_stacked_decrements():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data := _make_infantry("test_cancel_paused_stack", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data, 5)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.size() == 0:
        TestHelper.fail("expected 1 item, got 0")
        return
    var pq: ProductionQueue = items[0] as ProductionQueue
    pq.deducted = 40.0
    pm.pause_production(key, 0)
    var balance_before: int = _em.get_balance(PID)
    pm.cancel_production(PID, key, 0, 1)
    var balance_after: int = _em.get_balance(PID)
    var refund := balance_after - balance_before
    (
        TestHelper
        . assert_true(
            pq.count == 4 and balance_after == balance_before,
            (
                "cancel paused stacked item decrements count, no refund: expected count=4 "
                + "no refund, got count=%d refund=%d" % [pq.count, refund]
            ),
        )
    )
    _cleanup_queue(pm, key)


func test_cancel_active_single_removes():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory()
    var data := _make_infantry("test_cancel_active", 100)
    _em.add(PID, 500, "test")
    pm.start_production(PID, data)
    var key: String = pm.get_queue_key(PID, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.size() == 0:
        TestHelper.fail("expected 1 item, got 0")
        return
    var pq: ProductionQueue = items[0] as ProductionQueue
    pq.deducted = 25.0
    var balance_before: int = _em.get_balance(PID)
    pm.cancel_production(PID, key, 0, 1)
    var balance_after: int = _em.get_balance(PID)
    var remaining: Array = pm.get_queue_items(key)
    var refund := balance_after - balance_before
    var n_items := remaining.size()
    (
        TestHelper
        . assert_true(
            remaining.size() == 0 and balance_after == balance_before + 25,
            (
                "cancel active single item removes and refunds: expected 0 items "
                + "refund=25, got %d items refund=%d" % [n_items, refund]
            ),
        )
    )
    _cleanup_queue(pm, key)


func test_queue_key_format():
    var pm := _get_pm()
    if pm == null:
        TestHelper.fail("ProductionManager not available")
        return
    var key: String = pm.get_queue_key(0, "InfantryType")
    (
        TestHelper
        . assert_true(
            key == "0:InfantryType",
            "queue key format is player_id:factory_type: expected '0:InfantryType', got '%s'" % key,
        )
    )


func test_queue_key_different_players():
    var pm := _get_pm()
    if pm == null:
        TestHelper.fail("ProductionManager not available")
        return
    var key0: String = pm.get_queue_key(0, "InfantryType")
    var key1: String = pm.get_queue_key(1, "InfantryType")
    (
        TestHelper
        . assert_true(
            key0 != key1,
            "different players have different keys: player 0 and 1 have same key",
        )
    )


# --- build-mode unblock is scoped to the exiting player ---


func test_build_mode_unblock_scoped_to_player():
    var pm := _get_pm()
    if pm == null:
        TestHelper.fail("ProductionManager not available")
        return
    pm._waiting_for_placement["200:InfantryType"] = true
    pm._waiting_for_placement["201:InfantryType"] = true
    pm._on_build_mode_changed(false, 200)
    var this_player: bool = pm._waiting_for_placement["200:InfantryType"] == false
    var other_player: bool = pm._waiting_for_placement["201:InfantryType"] == true
    pm._waiting_for_placement.erase("200:InfantryType")
    pm._waiting_for_placement.erase("201:InfantryType")
    (
        TestHelper
        . assert_true(
            this_player and other_player,
            "build-mode exit must unblock only the exiting player",
        )
    )


# --- ready-to-place tracks and refunds the deducted amount ---


func test_get_ready_buildings_returns_entity_data():
    var pm := _get_pm()
    if pm == null:
        TestHelper.fail("ProductionManager not available")
        return
    var data := _make_infantry("test_ready_shape", 100)
    data.entity_type = EntityData.EntityType.BUILDING
    pm._add_ready_to_place(PID, data, 100.0)
    var ready: Array = pm.get_ready_buildings(PID)
    var ok: bool = ready.size() == 1 and (ready[0] as EntityData).id == "test_ready_shape"
    pm._ready_to_place.erase(PID)
    (
        TestHelper
        . assert_true(
            ok,
            "get_ready_buildings must return the placed EntityData entry",
        )
    )


func test_cancel_ready_building_refunds_tracked_amount():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    var data := _make_infantry("test_ready_refund", 500)
    data.entity_type = EntityData.EntityType.BUILDING
    data.buildable_queue = "BuildingType"
    # Only 320 was actually deducted before completion.
    pm._add_ready_to_place(PID, data, 320.0)
    var balance_before: int = _em.get_balance(PID)
    pm.cancel_ready_building(PID, "test_ready_refund")
    var balance_after: int = _em.get_balance(PID)
    (
        TestHelper
        . assert_true(
            balance_after == balance_before + 320,
            "cancel ready building must refund the tracked deducted amount",
        )
    )


func test_cancel_stacked_ready_building_refunds_paid():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    var data := _make_infantry("test_stacked_ready", 100)
    data.entity_type = EntityData.EntityType.BUILDING
    data.buildable_queue = "BuildingType"
    var key: String = pm.get_queue_key(PID, "BuildingType")
    # Queue a stacked building (count > 1) that has been fully paid for.
    var item := ProductionQueue.new(data, 2)
    item.deducted = 100.0
    pm._queues[key] = [item]
    pm._active_index[key] = 0
    # Completing one item resets item.deducted for the next in the stack; the
    # ready building must still track the amount actually paid (100, not 0).
    pm._complete_item(key, 0)
    var balance_before: int = _em.get_balance(PID)
    pm.cancel_ready_building(PID, "test_stacked_ready")
    var balance_after: int = _em.get_balance(PID)
    var refund := balance_after - balance_before
    (
        TestHelper
        . assert_true(
            refund == 100,
            "cancel stacked ready building must refund the paid amount",
        )
    )
    _cleanup_queue(pm, key)
    pm._ready_to_place.erase(PID)
    pm.clear_waiting_for_placement(PID)


# --- fallback exit cell returns null when nothing free is found ---


func test_find_exit_cell_null_when_none_distinct():
    var pm := _get_pm()
    if pm == null:
        TestHelper.fail("ProductionManager not available")
        return
    if SpatialHash.instance == null:
        TestHelper.fail("SpatialHash.instance unavailable in headless")
        return
    var factory := Node3D.new()
    factory.position = Vector3.ZERO
    # With no distinct free cell resolvable, the fallback returns null rather
    # than the factory's own cell.
    var result: Variant = pm._find_exit_cell(factory)
    factory.free()
    (
        TestHelper
        . assert_true(
            result == null,
            "_find_exit_cell must return null instead of the center cell",
        )
    )


# --- get_build_time derives from the build-speed factor ---


func test_get_build_time_from_build_speed():
    var data := _make_infantry("test_build_time", 1000)
    data.build_time_mult = 1.0
    var t: float = data.get_build_time()
    # TS rules.ini [General] BuildSpeed=.4: cost(1000) * 0.4 * 60 / 1000 = 24.0
    (
        TestHelper
        . assert_true(
            is_equal_approx(t, 24.0),
            "get_build_time must compute from the TS default build-speed factor",
        )
    )


# --- pay-as-you-build funding (production-pay-as-you-build) ---


## Force PID_FUND's balance to an exact value, isolated from earlier suites' deposits.
func _set_balance(amount: int) -> void:
    var pmgr := _em.get_node_or_null("/root/PlayerManager")
    if pmgr == null:
        return
    var pd: PlayerData = pmgr.get_player_data(PID_FUND)
    pd.free_credits = amount
    pd.stored_by_category.clear()


func test_start_production_with_zero_balance_queues():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory(PID_FUND)
    _set_balance(0)
    var data := _make_infantry("test_zero_balance", 100)
    var started: bool = pm.start_production(PID_FUND, data)
    var key: String = pm.get_queue_key(PID_FUND, "InfantryType")
    (
        TestHelper
        . assert_true(
            started and pm.get_queue_items(key).size() == 1,
            "a zero-balance player can still queue a build (pay-as-you-build)",
        )
    )
    _cleanup_queue(pm, key)


func test_starved_queue_stalls_then_resumes():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory(PID_FUND)
    _set_balance(0)
    var data := _make_infantry("test_starved", 100)
    pm.start_production(PID_FUND, data)
    var key: String = pm.get_queue_key(PID_FUND, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.is_empty():
        TestHelper.fail("expected the starved item to be queued")
        return
    var pq: ProductionQueue = items[0] as ProductionQueue

    var stalled := [0]
    var resumed := [0]
    var on_stalled := func(k: String) -> void:
        if k == key:
            stalled[0] += 1
    var on_resumed := func(k: String) -> void:
        if k == key:
            resumed[0] += 1
    pm.production_stalled.connect(on_stalled)
    pm.production_resumed.connect(on_resumed)

    # cost 100 over a pinned 5s build => 20 credits owed per 1s tick; balance 0.
    pm._process(1.0)
    var held: bool = pq.deducted == 0 and is_zero_approx(pq.progress)
    pm._process(1.0)
    var once: bool = stalled[0] == 1
    _em.add(PID_FUND, 500, "test")
    pm._process(1.0)
    var advanced: bool = pq.progress > 0.0 and resumed[0] == 1

    pm.production_stalled.disconnect(on_stalled)
    pm.production_resumed.disconnect(on_resumed)
    (
        TestHelper
        . assert_true(
            held and once and advanced,
            (
                "starved queue holds, emits one stall, then resumes: held=%s once=%s advanced=%s"
                % [held, once, advanced]
            ),
        )
    )
    _cleanup_queue(pm, key)


## Regression: a long starvation must not bank an un-payable debt. A small
## deposit after many starved frames must resume the queue instead of freezing.
func test_small_deposit_resumes_long_starved_queue():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory(PID_FUND)
    _set_balance(0)
    var data := _make_infantry("test_starved_small", 100)
    pm.start_production(PID_FUND, data)
    var key: String = pm.get_queue_key(PID_FUND, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.is_empty():
        TestHelper.fail("expected the starved item to be queued")
        return
    var pq: ProductionQueue = items[0] as ProductionQueue

    # ~100 frames at 60fps of starvation: a buggy carry would demand ~32 credits.
    for _i in range(100):
        pm._process(0.016)
    var frozen: float = pq.progress
    _em.add(PID_FUND, 5, "test")
    for _i in range(100):
        pm._process(0.016)
    (
        TestHelper
        . assert_true(
            pq.progress > frozen,
            (
                "a small deposit resumes a long-starved queue (frozen=%f now=%f)"
                % [frozen, pq.progress]
            ),
        )
    )
    _cleanup_queue(pm, key)


func test_completion_withheld_while_underpaid():
    var pm := _get_pm()
    if pm == null or _em == null:
        TestHelper.fail("autoloads not available")
        return
    _ensure_factory(PID_FUND)
    _set_balance(0)
    var data := _make_infantry("test_underpaid", 100)
    pm.start_production(PID_FUND, data)
    var key: String = pm.get_queue_key(PID_FUND, "InfantryType")
    var items: Array = pm.get_queue_items(key)
    if items.is_empty():
        TestHelper.fail("expected the item to be queued")
        return
    var pq: ProductionQueue = items[0] as ProductionQueue
    pq.progress = 1.0
    pq.deducted = 60

    var completed := [0]
    var on_done := func(k: String, _d: EntityData) -> void:
        if k == key:
            completed[0] += 1
    pm.production_completed.connect(on_done)

    pm._complete_item(key, 0)
    var withheld: bool = pm.get_queue_items(key).size() == 1 and completed[0] == 0
    _em.add(PID_FUND, 100, "test")
    pm._complete_item(key, 0)
    var done: bool = completed[0] == 1
    pm.production_completed.disconnect(on_done)
    (
        TestHelper
        . assert_true(
            withheld and done,
            (
                "completion is withheld while underpaid, then completes: withheld=%s done=%s"
                % [withheld, done]
            ),
        )
    )
    _cleanup_queue(pm, key)
    pm._ready_to_spawn.erase(PID_FUND)
