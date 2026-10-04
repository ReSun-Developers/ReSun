extends Node

# TriggerEngine — arming, offers, evaluation, persistence, remembering.

const ENGINE: GDScript = preload("res://scripts/triggers/TriggerEngine.gd")


func _setup_state() -> void:
    ScenarioState.reset()
    ScenarioState.declare_variables(["FlagA", "FlagB"], ["LocalA"])
    ScenarioState.load_waypoints({"WP": "5,5"})
    MatchClock.reset()


func _engine() -> Node:
    return ENGINE.new()


func _trigger(
    id: String,
    events: Array,
    actions: Array,
    persistence: int = 2,
    attach: String = "general",
    owner: String = "GDI",
    enabled: bool = true,
    cells: Array = []
) -> Dictionary:
    var tag := {"id": "tag_%s" % id, "persistence": persistence, "attach": attach}
    if attach == "cell":
        tag["cells"] = cells
    return {
        "id": id,
        "owner": owner,
        "enabled": enabled,
        "tags": [tag],
        "events": events,
        "actions": actions,
    }


func _text_sink(engine: Node) -> Array:
    var texts: Array = []
    engine.text_requested.connect(func(text: String) -> void: texts.append(text))
    return texts


func test_arm_and_reset() -> void:
    _setup_state()
    var engine := _engine()
    (
        TestHelper
        . assert_true(
            engine.arm([_trigger("t1", [{"id": 7, "params": []}], [{"id": 11, "params": ["x"]}])]),
            "valid triggers arm",
        )
    )
    TestHelper.assert_true(engine.has_trigger("t1"), "trigger present")
    engine.reset()
    TestHelper.assert_true(not engine.has_trigger("t1"), "reset clears triggers")
    TestHelper.assert_true(not engine.is_armed(), "reset disarms")
    engine.free()


func test_invalid_definitions_arm_nothing() -> void:
    _setup_state()
    var engine := _engine()
    (
        TestHelper
        . assert_true(
            not engine.arm([_trigger("t1", [{"id": 999, "params": []}], [])]),
            "unknown event rejects the set",
        )
    )
    TestHelper.assert_true(not engine.has_trigger("t1"), "nothing armed on rejection")
    engine.free()


func test_offer_latches_and_dirties() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("t1", [{"id": 7, "params": []}], [{"id": 11, "params": ["x"]}])])
    engine.offer(7, {})
    TestHelper.assert_true(engine.is_dirty("t1"), "subscribed offer marks dirty")
    TestHelper.assert_true(engine.is_latched("t1", 0), "matching event latched")
    engine.free()


func test_unsubscribed_offer_untouched() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("t1", [{"id": 7, "params": []}], [{"id": 11, "params": ["x"]}])])
    engine.offer(6, {})
    TestHelper.assert_true(not engine.is_dirty("t1"), "unrelated event ignored")
    TestHelper.assert_true(not engine.is_latched("t1", 0), "nothing latched")
    engine.free()


func test_fires_when_all_events_satisfied() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("t1", [{"id": 7, "params": []}], [{"id": 11, "params": ["hi"]}])])
    var texts := _text_sink(engine)
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_eq(texts, ["hi"], "fired once")
    engine.free()


func test_partial_satisfaction_does_not_fire() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm(
        [
            _trigger(
                "t1",
                [{"id": 7, "params": []}, {"id": 6, "params": []}],
                [{"id": 11, "params": ["x"]}]
            )
        ]
    )
    var texts := _text_sink(engine)
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_eq(texts.size(), 0, "missing event blocks fire")
    engine.free()


func test_disabled_does_not_fire_until_enabled() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm(
        [
            _trigger(
                "t1",
                [{"id": 7, "params": []}],
                [{"id": 11, "params": ["x"]}],
                2,
                "general",
                "GDI",
                false
            )
        ]
    )
    var texts := _text_sink(engine)
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_eq(texts.size(), 0, "disabled trigger silent")
    engine._set_enabled("t1", true)
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_eq(texts.size(), 1, "fires after enable")
    engine.free()


func test_volatile_fires_once_then_destroyed() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("t1", [{"id": 7, "params": []}], [{"id": 11, "params": ["x"]}], 0)])
    var texts := _text_sink(engine)
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_true(engine.is_destroyed("t1"), "volatile destroyed after fire")
    engine.offer(7, {})
    engine._on_tick(2)
    TestHelper.assert_eq(texts.size(), 1, "volatile fires once")
    engine.free()


func test_persistent_repeats() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("t1", [{"id": 7, "params": []}], [{"id": 11, "params": ["x"]}], 2)])
    var texts := _text_sink(engine)
    engine.offer(7, {})
    engine._on_tick(1)
    engine.offer(7, {})
    engine._on_tick(2)
    TestHelper.assert_eq(texts.size(), 2, "persistent fires each satisfying tick")
    engine.free()


func test_semi_persistent_fires_on_last_holder() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm(
        [
            _trigger(
                "t1",
                [{"id": 1, "params": []}],
                [{"id": 11, "params": ["x"]}],
                1,
                "cell",
                "GDI",
                true,
                ["1,1", "2,2"]
            )
        ]
    )
    var texts := _text_sink(engine)
    engine.offer(1, {"cell": Vector2i(1, 1)})
    engine._on_tick(1)
    TestHelper.assert_eq(texts.size(), 0, "first holder does not fire")
    engine.offer(1, {"cell": Vector2i(2, 2)})
    engine._on_tick(2)
    TestHelper.assert_eq(texts.size(), 1, "last holder fires")
    engine.free()


func test_remembering_combines_across_offers() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm(
        [
            _trigger(
                "t1",
                [{"id": 7, "params": []}, {"id": 6, "params": []}],
                [{"id": 11, "params": ["x"]}],
                2
            )
        ]
    )
    var texts := _text_sink(engine)
    engine.offer(7, {})
    engine._on_tick(1)
    engine.offer(6, {})
    engine._on_tick(2)
    TestHelper.assert_eq(texts.size(), 1, "persistent tag remembers across offers")
    engine.free()


func test_volatile_does_not_remember() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm(
        [
            _trigger(
                "t1",
                [{"id": 7, "params": []}, {"id": 6, "params": []}],
                [{"id": 11, "params": ["x"]}],
                0
            )
        ]
    )
    var texts := _text_sink(engine)
    engine.offer(7, {})
    engine._on_tick(1)
    engine.offer(6, {})
    engine._on_tick(2)
    TestHelper.assert_eq(texts.size(), 0, "volatile requires one offer")
    engine.free()


func test_cell_scope_filters_offers() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm(
        [
            _trigger(
                "t1",
                [{"id": 1, "params": []}],
                [{"id": 11, "params": ["x"]}],
                2,
                "cell",
                "GDI",
                true,
                ["1,1"]
            )
        ]
    )
    engine.offer(1, {"cell": Vector2i(9, 9)})
    TestHelper.assert_true(not engine.is_dirty("t1"), "offer for another cell ignored")
    engine.free()


func test_time_event_fires_after_deadline() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("t1", [{"id": 13, "params": [2]}], [{"id": 11, "params": ["boom"]}], 2)])
    var texts := _text_sink(engine)
    engine._on_deadline("time:t1:0")
    engine._on_tick(1)
    TestHelper.assert_eq(texts, ["boom"], "elapsed-time event fires")
    engine.free()


func test_credits_standing_event() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("t1", [{"id": 12, "params": [500]}], [{"id": 11, "params": ["rich"]}], 2)])
    var texts := _text_sink(engine)
    engine._credits["GDI"] = 500
    engine.offer(12, {"house": "GDI"})
    engine._on_tick(1)
    TestHelper.assert_eq(texts, ["rich"], "standing credit event fires")
    engine.free()


func test_standing_persistent_fires_once_per_hold() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("t1", [{"id": 12, "params": [500]}], [{"id": 11, "params": ["rich"]}], 2)])
    var texts := _text_sink(engine)
    engine._credits["GDI"] = 500
    engine.offer(12, {})
    engine._on_tick(1)
    engine.offer(12, {})
    engine._on_tick(2)
    TestHelper.assert_eq(texts.size(), 1, "a held standing condition does not re-fire every offer")
    engine.free()


func test_semi_persistent_general_never_fires() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm(
        [_trigger("t1", [{"id": 7, "params": []}], [{"id": 11, "params": ["x"]}], 1, "general")]
    )
    var texts := _text_sink(engine)
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_eq(texts.size(), 0, "semi-persistent with no holders never fires")
    engine.free()


func test_destroyed_any_event_offered() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("t1", [{"id": 48, "params": []}], [{"id": 11, "params": ["any"]}], 0)])
    var texts := _text_sink(engine)
    engine.notify_destroyed("GDI", "E1", null)
    engine._on_tick(1)
    TestHelper.assert_eq(texts, ["any"], "destroyed_any fires on any destroy")
    engine.free()


func test_second_tag_cell_is_reachable() -> void:
    _setup_state()
    var engine := _engine()
    (
        engine
        . arm(
            [
                {
                    "id": "t1",
                    "owner": "GDI",
                    "enabled": true,
                    "tags":
                    [
                        {"id": "a", "persistence": 2, "attach": "cell", "cells": ["1,1"]},
                        {"id": "b", "persistence": 2, "attach": "cell", "cells": ["2,2"]},
                    ],
                    "events": [{"id": 1, "params": []}],
                    "actions": [{"id": 11, "params": ["x"]}],
                }
            ]
        )
    )
    engine.offer(1, {"cell": Vector2i(2, 2)})
    TestHelper.assert_true(engine.is_dirty("t1"), "offer is reachable through the second tag")
    engine.free()


func test_arm_applies_overlay() -> void:
    _setup_state()
    var engine := _engine()
    (
        engine
        . arm(
            [_trigger("t1", [{"id": 7, "params": []}], [{"id": 11, "params": ["base"]}])],
            [{"id": "t1", "actions": [{"id": 11, "params": ["override"]}]}],
        )
    )
    var texts := _text_sink(engine)
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_eq(texts, ["override"], "overlay replaced the trigger's actions")
    engine.free()
