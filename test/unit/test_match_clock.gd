extends Node

# MatchClock — fixed-rate logic tick, deterministic deadlines, reset/pause.

const MATCH_CLOCK: GDScript = preload("res://scripts/core/MatchClock.gd")


func _make() -> Node:
    return MATCH_CLOCK.new()


func test_one_tick_per_interval() -> void:
    var clock := _make()
    var frames: Array[int] = []
    clock.tick.connect(func(frame: int) -> void: frames.append(frame))
    clock._process(MATCH_CLOCK.SECONDS_PER_TICK + 0.0001)
    TestHelper.assert_eq(frames.size(), 1, "one tick after one interval")
    TestHelper.assert_eq(clock.frame, 1, "frame counter is one")
    clock.free()


func test_decoupled_from_render_rate() -> void:
    var clock := _make()
    var frames: Array[int] = []
    clock.tick.connect(func(frame: int) -> void: frames.append(frame))
    clock._process(MATCH_CLOCK.SECONDS_PER_TICK * 4.0)
    TestHelper.assert_eq(frames.size(), 4, "long frame advances four ticks")
    TestHelper.assert_eq(clock.frame, 4, "frame counter is four")
    clock.free()


func test_no_tick_below_interval() -> void:
    var clock := _make()
    var frames: Array[int] = []
    clock.tick.connect(func(frame: int) -> void: frames.append(frame))
    clock._process(MATCH_CLOCK.SECONDS_PER_TICK * 0.4)
    TestHelper.assert_eq(frames.size(), 0, "no tick below one interval")
    TestHelper.assert_eq(clock.frame, 0, "frame counter unchanged")
    clock.free()


func test_deadline_fires_once() -> void:
    var clock := _make()
    var fired: Array[String] = []
    clock.deadline_reached.connect(func(key: String) -> void: fired.append(key))
    clock.schedule("a", 3)
    for i in 6:
        clock._process(MATCH_CLOCK.SECONDS_PER_TICK)
    TestHelper.assert_eq(fired, ["a"], "deadline fires exactly once")
    TestHelper.assert_true(not clock.has_deadline("a"), "deadline removed after firing")
    clock.free()


func test_cancelled_deadline_does_not_fire() -> void:
    var clock := _make()
    var fired: Array[String] = []
    clock.deadline_reached.connect(func(key: String) -> void: fired.append(key))
    clock.schedule("a", 2)
    TestHelper.assert_true(clock.cancel("a"), "cancel reports pending deadline")
    for i in 4:
        clock._process(MATCH_CLOCK.SECONDS_PER_TICK)
    TestHelper.assert_eq(fired.size(), 0, "cancelled deadline never fires")
    clock.free()


func test_same_frame_order_is_scheduling_order() -> void:
    var clock := _make()
    var fired: Array[String] = []
    clock.deadline_reached.connect(func(key: String) -> void: fired.append(key))
    clock.schedule("a", 2)
    clock.schedule("b", 2)
    for i in 3:
        clock._process(MATCH_CLOCK.SECONDS_PER_TICK)
    TestHelper.assert_eq(fired, ["a", "b"], "tie broken by scheduling order")
    clock.free()


func test_reschedule_replaces() -> void:
    var clock := _make()
    var fired_at: Array = []
    clock.deadline_reached.connect(func(key: String) -> void: fired_at.append([clock.frame, key]))
    clock.schedule("a", 1)
    clock.schedule("a", 3)
    for i in 5:
        clock._process(MATCH_CLOCK.SECONDS_PER_TICK)
    TestHelper.assert_eq(fired_at, [[3, "a"]], "only the later deadline fires")
    clock.free()


func test_reset_clears_frame_and_deadlines() -> void:
    var clock := _make()
    clock.schedule("a", 5)
    clock._process(MATCH_CLOCK.SECONDS_PER_TICK * 2.0)
    clock.reset()
    TestHelper.assert_eq(clock.frame, 0, "frame reset to zero")
    TestHelper.assert_true(not clock.has_deadline("a"), "pending deadlines cleared")
    clock.free()


func test_pause_blocks_ticks() -> void:
    var clock := _make()
    var frames: Array[int] = []
    clock.tick.connect(func(frame: int) -> void: frames.append(frame))
    clock.set_paused(true)
    clock._process(MATCH_CLOCK.SECONDS_PER_TICK * 3.0)
    TestHelper.assert_eq(frames.size(), 0, "paused clock does not tick")
    clock.set_paused(false)
    clock._process(MATCH_CLOCK.SECONDS_PER_TICK)
    TestHelper.assert_eq(frames.size(), 1, "resume ticks again")
    clock.free()


func test_max_ticks_per_frame_cap() -> void:
    var clock := _make()
    var frames: Array[int] = []
    clock.tick.connect(func(frame: int) -> void: frames.append(frame))
    clock._process(10.0)
    TestHelper.assert_eq(frames.size(), MATCH_CLOCK.MAX_TICKS_PER_FRAME, "ticks capped per frame")
    clock.free()


func test_reschedule_updates_same_frame_order() -> void:
    var clock := _make()
    var order: Array = []
    clock.deadline_reached.connect(func(key: String) -> void: order.append(key))
    clock.schedule("a", 2)
    clock.schedule("b", 2)
    clock.schedule("a", 2)
    for i in 3:
        clock._process(MATCH_CLOCK.SECONDS_PER_TICK)
    TestHelper.assert_eq(
        order, ["b", "a"], "rescheduling moves the key to the back of the tie order"
    )
    clock.free()
