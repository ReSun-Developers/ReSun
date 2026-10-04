extends Node

# ScenarioState — global/local flags, waypoints, mission timer, reset.

const SCENARIO: GDScript = preload("res://scripts/core/ScenarioState.gd")
const MATCH_CLOCK: GDScript = preload("res://scripts/core/MatchClock.gd")


func _make() -> Node:
    var state: Node = SCENARIO.new()
    state.declare_variables(["FlagA", "FlagB"], ["LocalA"])
    return state


func test_set_and_read_global() -> void:
    var state := _make()
    TestHelper.assert_true(state.set_global("FlagA"), "set declared global")
    TestHelper.assert_true(state.get_global("FlagA"), "global reads true")
    TestHelper.assert_true(state.has_global("FlagA"), "global is declared")
    state.clear_global("FlagA")
    TestHelper.assert_true(not state.get_global("FlagA"), "cleared global reads false")
    state.free()


func test_global_change_is_edge_only() -> void:
    var state := _make()
    var changes: Array = []
    state.global_changed.connect(
        func(name: String, value: bool) -> void: changes.append([name, value])
    )
    state.set_global("FlagA")
    state.set_global("FlagA")
    state.clear_global("FlagA")
    TestHelper.assert_eq(changes, [["FlagA", true], ["FlagA", false]], "only real transitions emit")
    state.free()


func test_undeclared_global_rejected() -> void:
    var state := _make()
    TestHelper.assert_true(not state.set_global("Nope"), "undeclared global rejected")
    TestHelper.assert_true(not state.get_global("Nope"), "undeclared global reads false")
    state.free()


func test_locals_are_house_scoped() -> void:
    var state := _make()
    state.set_local("GDI", "LocalA")
    TestHelper.assert_true(state.get_local("GDI", "LocalA"), "GDI local set")
    TestHelper.assert_true(not state.get_local("Nod", "LocalA"), "Nod local untouched")
    TestHelper.assert_true(not state.set_local("GDI", "Missing"), "undeclared local rejected")
    state.free()


func test_waypoints_set_read_and_load() -> void:
    var state := _make()
    state.set_waypoint("A", Vector2i(70, 51))
    TestHelper.assert_eq(state.get_waypoint("A"), Vector2i(70, 51), "waypoint reads back")
    TestHelper.assert_true(state.has_waypoint("A"), "waypoint present")
    TestHelper.assert_eq(state.get_waypoint("Z"), null, "unknown waypoint is null")
    state.load_waypoints({"B": "1,2", "bad": "nope", "C": ""})
    TestHelper.assert_eq(state.get_waypoint("B"), Vector2i(1, 2), "good entry loads")
    TestHelper.assert_true(not state.has_waypoint("bad"), "malformed entry discarded")
    TestHelper.assert_true(not state.has_waypoint("C"), "empty entry discarded")
    state.free()


func test_timer_counts_down_and_expires() -> void:
    var state := _make()
    var clock: Node = MATCH_CLOCK.new()
    state.bind_clock(clock)
    var expired: Array = []
    state.mission_timer_expired.connect(func() -> void: expired.append(true))
    state.set_timer(3)
    state.start_timer()
    for i in MATCH_CLOCK.TICKS_PER_SECOND * 3:
        state._on_clock_tick(i)
    TestHelper.assert_eq(state.get_timer(), 0, "timer reached zero")
    TestHelper.assert_eq(expired.size(), 1, "expired emitted once")
    TestHelper.assert_true(not state.is_timer_running(), "timer stopped at expiry")
    state.free()
    clock.free()


func test_stopped_timer_does_not_advance() -> void:
    var state := _make()
    state.set_timer(5)
    state.stop_timer()
    state._on_clock_tick(1)
    TestHelper.assert_eq(state.get_timer(), 5, "stopped timer unchanged")
    state.free()


func test_add_timer_extends() -> void:
    var state := _make()
    state.set_timer(3)
    state.start_timer()
    state.add_timer(5)
    TestHelper.assert_eq(state.get_timer(), 8, "add extends remaining")
    state.free()


func test_reset_clears_everything() -> void:
    var state := _make()
    state.set_global("FlagA")
    state.set_local("GDI", "LocalA")
    state.set_waypoint("A", Vector2i(1, 1))
    state.set_timer(9)
    state.reset()
    TestHelper.assert_true(not state.get_global("FlagA"), "global cleared")
    TestHelper.assert_true(not state.has_waypoint("A"), "waypoint cleared")
    TestHelper.assert_eq(state.get_timer(), 0, "timer cleared")
    TestHelper.assert_true(not state.set_global("FlagA"), "declarations cleared")
    state.free()


func test_local_change_is_edge_only() -> void:
    var state := _make()
    var changes: Array = []
    state.local_changed.connect(
        func(house_id: String, name: String, value: bool) -> void:
            changes.append([house_id, name, value])
    )
    state.set_local("GDI", "LocalA")
    state.set_local("GDI", "LocalA")
    state.clear_local("GDI", "LocalA")
    TestHelper.assert_eq(changes.size(), 2, "only real local transitions emit")
    state.free()
