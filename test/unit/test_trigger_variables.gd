extends Node

# TriggerEngine variables, mission timer, and outcome actions.

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


func _text_sink(engine: Node) -> Array:
    var texts: Array = []
    engine.text_requested.connect(func(text: String) -> void: texts.append(text))
    return texts


func test_set_global_action() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("tS", [{"id": 7, "params": []}], [{"id": 28, "params": ["FlagA"]}])])
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_true(ScenarioState.get_global("FlagA"), "action set the global")
    engine.free()


func test_global_set_event() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("tV", [{"id": 27, "params": ["FlagA"]}], [{"id": 11, "params": ["g"]}])])
    var texts := _text_sink(engine)
    ScenarioState.set_global("FlagA")
    engine.offer(27, {})
    engine._on_tick(1)
    TestHelper.assert_eq(texts, ["g"], "global-set event fires")
    engine.free()


func test_local_event_is_house_scoped() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm(
        [_trigger("tV", [{"id": 36, "params": ["LocalA"]}], [{"id": 11, "params": ["n"]}], "Nod")]
    )
    var texts := _text_sink(engine)
    ScenarioState.set_local("GDI", "LocalA")
    engine.offer(36, {"house": "GDI"})
    engine._on_tick(1)
    TestHelper.assert_eq(texts.size(), 0, "other house's local does not fire")
    ScenarioState.set_local("Nod", "LocalA")
    engine.offer(36, {"house": "Nod"})
    engine._on_tick(2)
    TestHelper.assert_eq(texts, ["n"], "own house's local fires")
    engine.free()


func test_mission_timer_expired_event() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("tT", [{"id": 14, "params": []}], [{"id": 11, "params": ["exp"]}])])
    var texts := _text_sink(engine)
    engine._on_mission_timer_expired()
    engine._on_tick(1)
    TestHelper.assert_eq(texts, ["exp"], "timer-expired event fires")
    engine.free()


func test_set_timer_action_drives_scenario_state() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("tA", [{"id": 7, "params": []}], [{"id": 27, "params": [5]}])])
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_eq(ScenarioState.get_timer(), 5, "action set the mission timer")
    engine.free()


func test_win_action_emits_outcome() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("tW", [{"id": 7, "params": []}], [{"id": 1, "params": ["GDI"]}])])
    var won: Array = []
    engine.mission_won.connect(func(house: String) -> void: won.append(house))
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_eq(won, ["GDI"], "win emitted for the house")
    engine.free()


func test_allow_win_holds() -> void:
    _setup_state()
    var engine := _engine()
    engine.arm([_trigger("tAW", [{"id": 7, "params": []}], [{"id": 15, "params": ["GDI"]}])])
    engine.offer(7, {})
    engine._on_tick(1)
    TestHelper.assert_true(engine.allow_win_held("GDI"), "allow-win hold registered")
    engine._destroy_trigger("tAW")
    TestHelper.assert_true(
        not engine.allow_win_held("GDI"), "hold released when tag trigger destroyed"
    )
    engine.free()
