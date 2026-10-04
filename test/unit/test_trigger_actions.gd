extends Node

# TriggerEngine action dispatch — control actions, deferred journal, budget.

const ENGINE: GDScript = preload("res://scripts/triggers/TriggerEngine.gd")


func _setup_state() -> void:
    ScenarioState.reset()
    ScenarioState.declare_variables(["FlagA"], ["LocalA"])
    ScenarioState.load_waypoints({"WP": "5,5"})
    MatchClock.reset()


func _engine() -> Node:
    return ENGINE.new()


func _trigger(id: String, events: Array, actions: Array, owner: String = "GDI") -> Dictionary:
    return {
        "id": id,
        "owner": owner,
        "enabled": true,
        "tags": [{"id": "tag_%s" % id, "persistence": 2, "attach": "general"}],
        "events": events,
        "actions": actions,
    }


func test_disable_action_stops_firing() -> void:
    _setup_state()
    var engine := _engine()
    (
        engine
        . arm(
            [
                _trigger("tA", [{"id": 7, "params": []}], [{"id": 54, "params": ["tB"]}]),
                _trigger("tB", [{"id": 6, "params": []}], [{"id": 11, "params": ["b"]}]),
            ]
        )
    )
    var texts: Array = []
    engine.text_requested.connect(func(text: String) -> void: texts.append(text))
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_true(not engine.is_enabled("tB"), "tB disabled by action")
    engine.offer(6, {})
    engine._on_tick(2)
    TestHelper.assert_eq(texts.size(), 0, "disabled trigger does not fire")
    engine.free()


func test_force_action_fires_without_events() -> void:
    _setup_state()
    var engine := _engine()
    (
        engine
        . arm(
            [
                _trigger("tA", [{"id": 7, "params": []}], [{"id": 22, "params": ["tB"]}]),
                _trigger("tB", [{"id": 1, "params": []}], [{"id": 11, "params": ["forced"]}]),
            ]
        )
    )
    var texts: Array = []
    engine.text_requested.connect(func(text: String) -> void: texts.append(text))
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_eq(texts, ["forced"], "forced trigger fires without its event")
    engine.free()


func test_destroy_trigger_action() -> void:
    _setup_state()
    var engine := _engine()
    (
        engine
        . arm(
            [
                _trigger("tA", [{"id": 7, "params": []}], [{"id": 12, "params": ["tB"]}]),
                _trigger("tB", [{"id": 6, "params": []}], [{"id": 11, "params": ["b"]}]),
            ]
        )
    )
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_true(engine.is_destroyed("tB"), "destroyed by id")
    engine.free()


func test_action_budget_caps_dispatch() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("tA", [{"id": 7, "params": []}], [{"id": 11, "params": ["z"]}])])
    var texts: Array = []
    engine.text_requested.connect(func(text: String) -> void: texts.append(text))
    var commands: Array = []
    for i in 300:
        commands.append({"trigger_id": "tA", "action": {"id": 11, "params": ["z"]}, "payload": {}})
    engine._actions_this_tick = 0
    engine._journal = commands
    engine._drain_journal()
    TestHelper.assert_eq(texts.size(), ENGINE.MAX_ACTIONS_PER_TICK, "dispatch capped at budget")
    engine.free()


func test_destroy_tag_action() -> void:
    _setup_state()
    var engine := _engine()
    (
        engine
        . arm(
            [
                _trigger("tA", [{"id": 7, "params": []}], [{"id": 70, "params": ["tag_tB"]}]),
                _trigger("tB", [{"id": 6, "params": []}], [{"id": 11, "params": ["b"]}]),
            ]
        )
    )
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_true(engine.is_destroyed("tB"), "destroy_tag removes the trigger")
    engine.free()


func test_lose_action_emits_outcome() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("tL", [{"id": 7, "params": []}], [{"id": 2, "params": ["GDI"]}])])
    var lost: Array = []
    engine.mission_lost.connect(func(house: String) -> void: lost.append(house))
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_eq(lost, ["GDI"], "lose emitted for the house")
    engine.free()


func test_mutual_force_cascade_is_bounded() -> void:
    _setup_state()
    var engine := _engine()
    (
        engine
        . arm(
            [
                _trigger("tA", [{"id": 7, "params": []}], [{"id": 22, "params": ["tB"]}]),
                _trigger("tB", [{"id": 7, "params": []}], [{"id": 22, "params": ["tA"]}]),
            ]
        )
    )
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_true(
        (engine._journal as Array).is_empty(), "journal is drained/cleared after a bounded cascade"
    )
    engine.free()
