extends Node

# Trigger offers from engine notify hooks: build and destroyed occurrences.

const ENGINE: GDScript = preload("res://scripts/triggers/TriggerEngine.gd")


func _engine() -> Node:
    ScenarioState.reset()
    ScenarioState.declare_variables([], [])
    ScenarioState.load_waypoints({})
    MatchClock.reset()
    return ENGINE.new()


func _text_sink(engine: Node) -> Array:
    var texts: Array = []
    engine.text_requested.connect(func(text: String) -> void: texts.append(text))
    return texts


func test_build_event_satisfied_by_notify_built() -> void:
    var engine := _engine()
    (
        engine
        . arm(
            [
                {
                    "id": "b",
                    "owner": "GDI",
                    "enabled": true,
                    "tags": [{"id": "tb", "persistence": 2, "attach": "general"}],
                    "events": [{"id": 19, "params": ["GACNST"]}],
                    "actions": [{"id": 11, "params": ["built"]}],
                }
            ]
        )
    )
    var texts := _text_sink(engine)
    engine.notify_built("GDI", "GACNST", null)
    engine._on_tick(1)
    TestHelper.assert_eq(texts, ["built"], "build occurrence satisfies the build event")
    engine.free()


func test_destroyed_event_satisfied_by_notify_destroyed() -> void:
    var engine := _engine()
    (
        engine
        . arm(
            [
                {
                    "id": "d",
                    "owner": "GDI",
                    "enabled": true,
                    "tags": [{"id": "td", "persistence": 0, "attach": "general"}],
                    "events": [{"id": 7, "params": []}],
                    "actions": [{"id": 11, "params": ["dead"]}],
                }
            ]
        )
    )
    var texts := _text_sink(engine)
    engine.notify_destroyed("GDI", "E1", null)
    engine._on_tick(1)
    TestHelper.assert_eq(texts, ["dead"], "destroyed occurrence satisfies the destroyed event")
    engine.free()
