extends Node

# TriggerEngine standing bookkeeping: credits at mission start, and structure
# counts when a structure leaves the world by sale or undeploy rather than death.

var _bm: Node = null
var _pm: Node = null


func _guard() -> bool:
    if _bm == null or _pm == null:
        TestHelper.fail("BuildingManager/PlayerManager not injected")
        return false
    return true


func _house() -> String:
    return TriggerEngine.house_for_player(PlayerManager.get_local_player_id())


func _credits_trigger(threshold: int) -> Dictionary:
    return {
        "id": "credits",
        "owner": _house(),
        "enabled": true,
        "tags": [{"id": "tag_credits", "persistence": 2, "attach": "general"}],
        "events": [{"id": 12, "params": [threshold]}],
        "actions": [{"id": 11, "params": ["rich"]}],
    }


func _structure_trigger() -> Dictionary:
    return {
        "id": "structure",
        "owner": _house(),
        "enabled": true,
        "tags": [{"id": "tag_structure", "persistence": 2, "attach": "general"}],
        "events": [{"id": 32, "params": ["TEST_STRUCT"]}],
        "actions": [{"id": 11, "params": ["built"]}],
    }


func _exists_with_flag_trigger() -> Dictionary:
    return {
        "id": "exists",
        "owner": _house(),
        "enabled": true,
        "tags": [{"id": "tag_exists", "persistence": 2, "attach": "general"}],
        "events": [{"id": 32, "params": ["TEST_STRUCT"]}, {"id": 27, "params": ["SoldFlag"]}],
        "actions": [{"id": 11, "params": ["exists"]}],
    }


func _destroyed_trigger() -> Dictionary:
    return {
        "id": "destroyed",
        "owner": _house(),
        "enabled": true,
        "tags": [{"id": "tag_destroyed", "persistence": 2, "attach": "general"}],
        "events": [{"id": 7, "params": []}, {"id": 48, "params": []}],
        "actions": [{"id": 11, "params": ["dead"]}],
    }


func _connect_texts(texts: Array) -> Callable:
    var callback := func(text: String) -> void: texts.append(text)
    TriggerEngine.text_requested.connect(callback)
    return callback


func _snapshot_balance(player_id: int) -> Dictionary:
    var data := PlayerManager.get_player_data(player_id)
    return {"free": data.free_credits, "stored": data.stored_by_category.duplicate()}


func _restore_balance(player_id: int, saved: Dictionary) -> void:
    var data := PlayerManager.get_player_data(player_id)
    data.free_credits = int(saved["free"])
    data.stored_by_category = saved["stored"]


func _set_balance(player_id: int, amount: int) -> Dictionary:
    var saved := _snapshot_balance(player_id)
    var data := PlayerManager.get_player_data(player_id)
    data.stored_by_category.clear()
    data.free_credits = amount
    return saved


func _structure_data() -> EntityData:
    var data := EntityData.new()
    data.id = "TEST_STRUCT"
    data.cost = 100
    return data


func _register_structure(nodes: Array) -> Array:
    var saved: Array = _bm._buildings.duplicate()
    _bm._buildings.clear()
    for node in nodes:
        (
            _bm
            . _buildings
            . append(
                {
                    "node": node,
                    "type": _structure_data(),
                    "origin": Vector2i(5, 5),
                    "cells": [] as Array,
                    "player_id": PlayerManager.get_local_player_id(),
                }
            )
        )
    return saved


func _count(house: String) -> int:
    return int(TriggerEngine._alive.get(house, 0))


func _built(house: String) -> int:
    return int((TriggerEngine._built.get(house, {}) as Dictionary).get("TEST_STRUCT", 0))


func test_credits_trigger_reads_starting_balance_at_arm() -> void:
    if not _guard():
        return
    var house := _house()
    TestHelper.assert_true(not house.is_empty(), "test house resolves")
    var player_id := PlayerManager.get_local_player_id()
    var saved := _set_balance(player_id, 5000)
    TestHelper.assert_eq(EconomyManager.get_balance(player_id), 5000, "starting balance is 5000")
    TriggerEngine.arm([_credits_trigger(1000)])
    var texts: Array = []
    var callback := _connect_texts(texts)
    TriggerEngine._on_tick(1)
    TestHelper.assert_eq(
        texts, ["rich"], "credits threshold at or below starting balance fires on the first tick"
    )
    TriggerEngine.text_requested.disconnect(callback)
    _restore_balance(player_id, saved)
    TriggerEngine.reset()


func test_credits_trigger_fires_at_exact_balance() -> void:
    if not _guard():
        return
    var player_id := PlayerManager.get_local_player_id()
    var saved := _set_balance(player_id, 5000)
    TriggerEngine.arm([_credits_trigger(5000)])
    var texts: Array = []
    var callback := _connect_texts(texts)
    TriggerEngine._on_tick(1)
    TestHelper.assert_eq(texts, ["rich"], "credits threshold equal to the balance fires")
    TriggerEngine.text_requested.disconnect(callback)
    _restore_balance(player_id, saved)
    TriggerEngine.reset()


func test_credits_trigger_waits_above_starting_balance() -> void:
    if not _guard():
        return
    var player_id := PlayerManager.get_local_player_id()
    var saved := _set_balance(player_id, 5000)
    TriggerEngine.arm([_credits_trigger(9000)])
    var texts: Array = []
    var callback := _connect_texts(texts)
    TriggerEngine._on_tick(1)
    TestHelper.assert_eq(texts.size(), 0, "threshold above starting balance stays silent")
    EconomyManager.add(player_id, 5000, "test", "", true)
    TriggerEngine._on_tick(2)
    TestHelper.assert_eq(texts, ["rich"], "threshold fires once the balance reaches it")
    TriggerEngine.text_requested.disconnect(callback)
    _restore_balance(player_id, saved)
    TriggerEngine.reset()


func test_shared_house_reads_local_balance() -> void:
    if not _guard():
        return
    var local_id := PlayerManager.get_local_player_id()
    var local := PlayerManager.get_player_data(local_id)
    var house := String(local.faction_id)
    TestHelper.assert_true(not house.is_empty(), "test house resolves")
    var saved_players: Dictionary = _pm._players.duplicate()
    var saved_local_id: int = _pm._local_player_id
    var saved_balance := _snapshot_balance(local_id)
    local.stored_by_category.clear()
    local.free_credits = 5000
    var shared := PlayerData.new()
    shared.player_id = 99
    shared.faction_id = house
    shared.free_credits = 9000
    _pm._players[99] = shared
    TriggerEngine.arm([_credits_trigger(6000)])
    TestHelper.assert_eq(
        int(TriggerEngine._credits.get(house, 0)), 5000, "shared house seeds the local balance"
    )
    var texts: Array = []
    var callback := _connect_texts(texts)
    TriggerEngine._on_tick(1)
    TestHelper.assert_eq(
        texts.size(), 0, "shared-house credits do not read another player's balance"
    )
    TriggerEngine.text_requested.disconnect(callback)
    _restore_balance(local_id, saved_balance)
    _pm._players = saved_players
    _pm._local_player_id = saved_local_id
    TriggerEngine.reset()


func test_arm_leaves_non_credits_standing_trigger_clean() -> void:
    if not _guard():
        return
    ScenarioState.reset()
    ScenarioState.declare_variables(["SoldFlag"], [])
    var player_id := PlayerManager.get_local_player_id()
    var saved := _set_balance(player_id, 5000)
    (
        TriggerEngine
        . arm(
            [
                _credits_trigger(1000),
                {
                    "id": "flag",
                    "owner": _house(),
                    "enabled": true,
                    "tags": [{"id": "tag_flag", "persistence": 2, "attach": "general"}],
                    "events": [{"id": 27, "params": ["SoldFlag"]}],
                    "actions": [{"id": 11, "params": ["flag"]}],
                },
            ]
        )
    )
    TestHelper.assert_eq(
        int(TriggerEngine._credits.get(_house(), 0)), 5000, "mirror is seeded at arm"
    )
    TestHelper.assert_true(TriggerEngine.is_dirty("credits"), "credits trigger is queued at arm")
    TestHelper.assert_true(not TriggerEngine.is_dirty("flag"), "non-credits trigger stays clean")
    TriggerEngine.reset()
    TestHelper.assert_true(TriggerEngine._credits.is_empty(), "reset clears the seeded mirror")
    TestHelper.assert_true(TriggerEngine._dirty.is_empty(), "reset clears the dirty set")
    _restore_balance(player_id, saved)
    ScenarioState.reset()


func test_sold_structure_drops_trigger_counts() -> void:
    if not _guard():
        return
    var house := _house()
    var player_id := PlayerManager.get_local_player_id()
    var saved_balance := _snapshot_balance(player_id)
    TriggerEngine.arm([_structure_trigger()])
    var node := Node3D.new()
    TriggerEngine.notify_built(house, "TEST_STRUCT", node)
    var saved_registry := _register_structure([node])
    TestHelper.assert_eq(_count(house), 1, "structure is counted alive before the sale")
    TestHelper.assert_eq(_built(house), 1, "structure is counted built before the sale")
    var sold: bool = _bm.sell_building(node)
    TestHelper.assert_true(sold, "sell succeeds")
    TestHelper.assert_eq(_count(house), 0, "sold structure is no longer alive")
    TestHelper.assert_eq(_built(house), 0, "sold structure is no longer built")
    _bm._buildings.assign(saved_registry)
    _restore_balance(player_id, saved_balance)
    TriggerEngine.reset()


func test_undeployed_structure_drops_trigger_counts() -> void:
    if not _guard():
        return
    var house := _house()
    TriggerEngine.arm([_structure_trigger()])
    var node := Node3D.new()
    TriggerEngine.notify_built(house, "TEST_STRUCT", node)
    var saved_registry := _register_structure([node])
    TestHelper.assert_eq(_count(house), 1, "structure is counted alive before undeploy")
    TestHelper.assert_eq(_built(house), 1, "structure is counted built before undeploy")
    _bm.unregister_building_entity(node)
    TestHelper.assert_eq(_count(house), 0, "undeployed structure is no longer alive")
    TestHelper.assert_eq(_built(house), 0, "undeployed structure is no longer built")
    _bm._buildings.assign(saved_registry)
    node.free()
    TriggerEngine.reset()


func test_removing_uncounted_structure_keeps_counted_sibling() -> void:
    if not _guard():
        return
    var house := _house()
    var player_id := PlayerManager.get_local_player_id()
    var saved_balance := _snapshot_balance(player_id)
    TriggerEngine.arm([_structure_trigger()])
    var counted := Node3D.new()
    TriggerEngine.notify_built(house, "TEST_STRUCT", counted)
    var uncounted := Node3D.new()
    var saved_registry := _register_structure([counted, uncounted])
    TestHelper.assert_eq(_count(house), 1, "counted structure is alive")
    var sold: bool = _bm.sell_building(uncounted)
    TestHelper.assert_true(sold, "uncounted structure sells")
    TestHelper.assert_eq(_count(house), 1, "uncounted removal leaves the counted sibling alive")
    TestHelper.assert_eq(_built(house), 1, "uncounted removal leaves the counted sibling built")
    _bm._buildings.assign(saved_registry)
    _restore_balance(player_id, saved_balance)
    counted.free()
    TriggerEngine.reset()


func test_destroyed_structure_drops_trigger_counts() -> void:
    if not _guard():
        return
    var house := _house()
    TriggerEngine.arm([_structure_trigger()])
    var node := Node3D.new()
    TriggerEngine.notify_built(house, "TEST_STRUCT", node)
    TestHelper.assert_eq(_count(house), 1, "structure is counted alive before destruction")
    TestHelper.assert_eq(_built(house), 1, "structure is counted built before destruction")
    TriggerEngine.notify_destroyed(house, "TEST_STRUCT", node)
    TestHelper.assert_eq(_count(house), 0, "destroyed structure is no longer alive")
    TestHelper.assert_eq(_built(house), 0, "destroyed structure is no longer built")
    node.free()
    TriggerEngine.reset()


func test_sale_does_not_offer_destroyed_events() -> void:
    if not _guard():
        return
    var house := _house()
    var player_id := PlayerManager.get_local_player_id()
    var saved_balance := _snapshot_balance(player_id)
    TriggerEngine.arm([_destroyed_trigger()])
    var texts: Array = []
    var callback := _connect_texts(texts)
    var sold_node := Node3D.new()
    TriggerEngine.notify_built(house, "TEST_STRUCT", sold_node)
    var saved_registry := _register_structure([sold_node])
    var sold: bool = _bm.sell_building(sold_node)
    TestHelper.assert_true(sold, "sale succeeds")
    TriggerEngine._on_tick(1)
    TestHelper.assert_eq(texts.size(), 0, "sale does not offer the destroyed events")
    var victim := Node3D.new()
    TriggerEngine.notify_built(house, "TEST_STRUCT", victim)
    TriggerEngine.notify_destroyed(house, "TEST_STRUCT", victim)
    TriggerEngine._on_tick(2)
    TestHelper.assert_eq(texts, ["dead"], "destruction still offers the destroyed events")
    _bm._buildings.assign(saved_registry)
    _restore_balance(player_id, saved_balance)
    victim.free()
    TriggerEngine.text_requested.disconnect(callback)
    TriggerEngine.reset()


func test_double_removal_does_not_decrement_or_offer_destroyed() -> void:
    if not _guard():
        return
    var house := _house()
    var player_id := PlayerManager.get_local_player_id()
    var saved_balance := _snapshot_balance(player_id)
    TriggerEngine.arm([_destroyed_trigger()])
    var texts: Array = []
    var callback := _connect_texts(texts)
    var node := Node3D.new()
    var sibling := Node3D.new()
    TriggerEngine.notify_built(house, "TEST_STRUCT", node)
    TriggerEngine.notify_built(house, "TEST_STRUCT", sibling)
    var saved_registry := _register_structure([node])
    TestHelper.assert_eq(_count(house), 2, "two structures are counted alive")
    TestHelper.assert_eq(_built(house), 2, "two structures are counted built")
    var sold: bool = _bm.sell_building(node)
    TestHelper.assert_true(sold, "sale succeeds")
    TestHelper.assert_eq(_count(house), 1, "sale removes one of the two structures")
    TestHelper.assert_eq(_built(house), 1, "sale removes one of the two built counts")
    TriggerEngine.notify_destroyed(house, "TEST_STRUCT", node)
    TriggerEngine._on_tick(1)
    TestHelper.assert_eq(_count(house), 1, "a second removal does not decrement again")
    TestHelper.assert_eq(_built(house), 1, "a second removal does not decrement the built count")
    TestHelper.assert_eq(texts.size(), 0, "a second removal does not offer destroyed events")
    _bm._buildings.assign(saved_registry)
    _restore_balance(player_id, saved_balance)
    sibling.free()
    TriggerEngine.text_requested.disconnect(callback)
    TriggerEngine.reset()


func test_sold_structure_clears_building_exists_condition() -> void:
    if not _guard():
        return
    ScenarioState.reset()
    ScenarioState.declare_variables(["SoldFlag"], [])
    var house := _house()
    var player_id := PlayerManager.get_local_player_id()
    var saved_balance := _snapshot_balance(player_id)
    TriggerEngine.arm([_exists_with_flag_trigger()])
    var texts: Array = []
    var callback := _connect_texts(texts)
    var node := Node3D.new()
    TriggerEngine.notify_built(house, "TEST_STRUCT", node)
    var saved_registry := _register_structure([node])
    TestHelper.assert_eq(_built(house), 1, "building-exists condition is satisfied before the sale")
    var sold: bool = _bm.sell_building(node)
    TestHelper.assert_true(sold, "sale succeeds")
    ScenarioState.set_global("SoldFlag")
    TriggerEngine.offer(27, {})
    TriggerEngine._on_tick(1)
    TestHelper.assert_eq(texts.size(), 0, "sold structure no longer satisfies building-exists")
    _bm._buildings.assign(saved_registry)
    _restore_balance(player_id, saved_balance)
    TriggerEngine.text_requested.disconnect(callback)
    ScenarioState.reset()
    TriggerEngine.reset()
