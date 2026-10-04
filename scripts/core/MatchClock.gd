extends Node

## MatchClock — the fixed-rate logic clock and integer deadline scheduler.
##
## Advances a frame counter at exactly [constant TICKS_PER_SECOND] logic ticks per
## second, decoupled from the render rate, and fires named deadlines scheduled a
## whole number of frames ahead. This is the single time source for simulation and
## mission scripting; consumers should never read wall-clock deltas directly.

signal tick(frame: int)
signal deadline_reached(key: String)

const TICKS_PER_SECOND: int = 30
const SECONDS_PER_TICK: float = 1.0 / 30.0
## Upper bound on ticks advanced in one rendered frame, to avoid a spiral of
## death on a long stall. Excess accumulated time is discarded with a warning.
const MAX_TICKS_PER_FRAME: int = 30

var frame: int = 0

var _accumulator: float = 0.0
var _paused: bool = false
var _deadlines: Dictionary = {}
var _deadline_order: Dictionary = {}
var _next_order: int = 0
var _due: Array[String] = []


func _process(delta: float) -> void:
    if _paused:
        return
    _accumulator += delta
    var advanced := 0
    while _accumulator >= SECONDS_PER_TICK and advanced < MAX_TICKS_PER_FRAME:
        _accumulator -= SECONDS_PER_TICK
        _advance_one_tick()
        advanced += 1
    if advanced >= MAX_TICKS_PER_FRAME and _accumulator >= SECONDS_PER_TICK:
        _accumulator = 0.0
        push_warning(
            (
                "MatchClock: exceeded %d ticks in one frame; discarded excess time"
                % MAX_TICKS_PER_FRAME
            )
        )


## Advances exactly one logic tick: collects due deadlines, emits [signal tick],
## then emits [signal deadline_reached] for each due key in deterministic order.
func _advance_one_tick() -> void:
    frame += 1
    _collect_due()
    tick.emit(frame)
    for key in _due:
        deadline_reached.emit(key)
    _due.clear()


func _collect_due() -> void:
    _due.clear()
    for key in _deadlines:
        if int(_deadlines[key]) <= frame:
            _due.append(key)
    _due.sort_custom(_due_before)
    for key in _due:
        _deadlines.erase(key)
        _deadline_order.erase(key)


func _due_before(a: String, b: String) -> bool:
    var da: int = int(_deadlines[a])
    var db: int = int(_deadlines[b])
    if da != db:
        return da < db
    return int(_deadline_order.get(a, 0)) < int(_deadline_order.get(b, 0))


## Schedules [param key] to fire [param frames_ahead] logic frames from now,
## replacing any pending deadline for the same key. A zero lead fires on the next
## tick. Emits [signal deadline_reached] once for the key.
func schedule(key: String, frames_ahead: int) -> void:
    if key.is_empty():
        push_warning("MatchClock: schedule ignored for empty key")
        return
    var lead: int = maxi(frames_ahead, 0)
    _deadline_order[key] = _next_order
    _next_order += 1
    _deadlines[key] = frame + lead


## Cancels a pending deadline. Returns true when one was pending.
func cancel(key: String) -> bool:
    if not _deadlines.has(key):
        return false
    _deadlines.erase(key)
    _deadline_order.erase(key)
    return true


func has_deadline(key: String) -> bool:
    return _deadlines.has(key)


func get_deadline_frame(key: String) -> int:
    return int(_deadlines.get(key, -1))


## Sets or clears paused state. While paused the clock does not advance. Any
## partial accumulator is preserved so resume continues where it left off.
func set_paused(value: bool) -> void:
    _paused = value


func is_paused() -> bool:
    return _paused


## Clears the frame counter and every pending deadline. Used when a match starts.
func reset() -> void:
    frame = 0
    _accumulator = 0.0
    _deadlines.clear()
    _deadline_order.clear()
    _next_order = 0
    _due.clear()
