extends Node

# TriggerCatalog — numeric id lookup and arity contract.

const CATALOG: GDScript = preload("res://scripts/triggers/TriggerCatalog.gd")


func test_event_lookup_by_id() -> void:
    var destroyed: Variant = CATALOG.event(7)
    TestHelper.assert_true(destroyed != null, "event 7 exists")
    TestHelper.assert_eq(String(destroyed["key"]), "destroyed", "event 7 key")
    TestHelper.assert_eq(String(destroyed["kind"]), "temporal", "destroyed is temporal")
    TestHelper.assert_eq(CATALOG.event_arity(7), 0, "destroyed has no params")


func test_standing_event_lookup() -> void:
    var time_event: Variant = CATALOG.event(13)
    TestHelper.assert_true(time_event != null, "event 13 exists")
    TestHelper.assert_eq(String(time_event["kind"]), "standing", "time is standing")
    TestHelper.assert_eq(CATALOG.event_arity(13), 1, "time takes a seconds param")


func test_action_lookup_by_id() -> void:
    var win: Variant = CATALOG.action(1)
    TestHelper.assert_true(win != null, "action 1 exists")
    TestHelper.assert_eq(String(win["key"]), "win", "action 1 key")
    TestHelper.assert_eq(CATALOG.action_arity(1), 1, "win takes a house param")


func test_unknown_ids_return_null() -> void:
    TestHelper.assert_eq(CATALOG.event(999), null, "unknown event is null")
    TestHelper.assert_eq(CATALOG.action(999), null, "unknown action is null")
    TestHelper.assert_eq(CATALOG.event_arity(999), -1, "unknown event arity is -1")
