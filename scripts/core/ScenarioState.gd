extends Node

## ScenarioState — mission-scoped scripting state: global flags, per-house local
## flags, a waypoint registry, and the mission timer. Reset between matches so no
## state leaks. See the `scenario-state` capability.

signal global_changed(name: String, value: bool)
signal local_changed(house_id: String, name: String, value: bool)
signal mission_timer_expired

const MATCH_CLOCK: GDScript = preload("res://scripts/core/MatchClock.gd")

var _clock: Node = null
var _declared_globals: Dictionary = {}
var _declared_locals: Dictionary = {}
var _globals: Dictionary = {}
var _locals: Dictionary = {}
var _waypoints: Dictionary = {}
var _timer_ticks: int = 0
var _timer_running: bool = false


func _ready() -> void:
    bind_clock(MatchClock)


## Connects the mission timer to a clock. Safe to call with null to detach.
func bind_clock(clock: Node) -> void:
    if _clock and is_instance_valid(_clock) and _clock.tick.is_connected(_on_clock_tick):
        _clock.tick.disconnect(_on_clock_tick)
    _clock = clock
    if _clock and not _clock.tick.is_connected(_on_clock_tick):
        _clock.tick.connect(_on_clock_tick)


## Declares the mission's variable name tables. Clears prior declarations and
## their values. Call after [method reset] when a mission starts.
func declare_variables(globals: Array, locals: Array) -> void:
    _declared_globals.clear()
    _globals.clear()
    for name in globals:
        var key: String = String(name)
        _declared_globals[key] = true
        _globals[key] = false
    _declared_locals.clear()
    _locals.clear()
    for name in locals:
        _declared_locals[String(name)] = true


func set_global(name: String) -> bool:
    if not _declared_globals.has(name):
        push_warning("ScenarioState: undeclared global '%s'" % name)
        return false
    if bool(_globals.get(name, false)):
        return true
    _globals[name] = true
    global_changed.emit(name, true)
    return true


func clear_global(name: String) -> bool:
    if not _declared_globals.has(name):
        push_warning("ScenarioState: undeclared global '%s'" % name)
        return false
    if not bool(_globals.get(name, false)):
        return true
    _globals[name] = false
    global_changed.emit(name, false)
    return true


func get_global(name: String) -> bool:
    return bool(_globals.get(name, false))


func has_global(name: String) -> bool:
    return _declared_globals.has(name)


func set_local(house_id: String, name: String) -> bool:
    if not _declared_locals.has(name):
        push_warning("ScenarioState: undeclared local '%s'" % name)
        return false
    var house: Dictionary = _locals.get(house_id, {})
    if bool(house.get(name, false)):
        return true
    house[name] = true
    _locals[house_id] = house
    local_changed.emit(house_id, name, true)
    return true


func clear_local(house_id: String, name: String) -> bool:
    if not _declared_locals.has(name):
        push_warning("ScenarioState: undeclared local '%s'" % name)
        return false
    var house: Dictionary = _locals.get(house_id, {})
    if not bool(house.get(name, false)):
        return true
    house[name] = false
    local_changed.emit(house_id, name, false)
    return true


func get_local(house_id: String, name: String) -> bool:
    var house: Dictionary = _locals.get(house_id, {})
    return bool(house.get(name, false))


func has_local(name: String) -> bool:
    return _declared_locals.has(name)


func set_waypoint(id: String, cell: Vector2i) -> void:
    _waypoints[id] = cell


func get_waypoint(id: String) -> Variant:
    return _waypoints.get(id, null)


func declared_globals() -> Array:
    return _declared_globals.keys()


func declared_locals() -> Array:
    return _declared_locals.keys()


func waypoint_ids() -> Array:
    return _waypoints.keys()


func has_waypoint(id: String) -> bool:
    return _waypoints.has(id)


## Loads waypoints from a `{id: "x,y"}` object. Malformed values are discarded
## with a diagnostic; the rest load.
func load_waypoints(data: Dictionary) -> void:
    for id in data:
        var parsed: Variant = parse_cell(String(data[id]))
        if parsed == null:
            push_warning("ScenarioState: malformed waypoint '%s' -> '%s'" % [id, data[id]])
            continue
        set_waypoint(String(id), parsed)


static func parse_cell(text: String) -> Variant:
    var parts := text.split(",")
    if (
        parts.size() != 2
        or not parts[0].strip_edges().is_valid_int()
        or not parts[1].strip_edges().is_valid_int()
    ):
        return null
    return Vector2i(parts[0].strip_edges().to_int(), parts[1].strip_edges().to_int())


func start_timer() -> void:
    _timer_running = _timer_ticks > 0


func stop_timer() -> void:
    _timer_running = false


func set_timer(seconds: int) -> void:
    _timer_ticks = maxi(seconds, 0) * MATCH_CLOCK.TICKS_PER_SECOND


func add_timer(seconds: int) -> void:
    _timer_ticks = maxi(_timer_ticks + seconds * MATCH_CLOCK.TICKS_PER_SECOND, 0)


func get_timer() -> int:
    return int(ceil(float(_timer_ticks) / float(MATCH_CLOCK.TICKS_PER_SECOND)))


func is_timer_running() -> bool:
    return _timer_running


func _on_clock_tick(_frame: int) -> void:
    if not _timer_running:
        return
    _timer_ticks -= 1
    if _timer_ticks <= 0:
        _timer_ticks = 0
        _timer_running = false
        mission_timer_expired.emit()


## Clears declarations, flags, waypoints, and the timer. Used when a match starts.
func reset() -> void:
    _declared_globals.clear()
    _declared_locals.clear()
    _globals.clear()
    _locals.clear()
    _waypoints.clear()
    _timer_ticks = 0
    _timer_running = false
