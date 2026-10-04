extends Node

## TriggerEngine — the mission trigger runtime. Parses trigger definitions, routes
## occurrences to attached tags, evaluates dirty triggers once per logic tick,
## and dispatches actions through a deferred journal. See the `trigger-engine`
## capability and `openspec/changes/add-trigger-event-action-engine/design.md`.

signal mission_won(house: String)
signal mission_lost(house: String)
signal text_requested(text: String)
signal team_requested(team_id: String)
signal meteor_requested(waypoint: String)
signal damage_requested(amount: int)

const VOLATILE: int = 0
const SEMI_PERSISTENT: int = 1
const PERSISTENT: int = 2

const MAX_CASCADE_ITERATIONS: int = 8
const MAX_ACTIONS_PER_TICK: int = 256
const REVEAL_RADIUS: int = 9

var _defs: Dictionary = {}
var _order: Array[String] = []
var _rt: Dictionary = {}
var _dirty: Dictionary = {}
var _by_event: Dictionary = {}
var _general: Array[String] = []
var _house_lists: Dictionary = {}
var _cell_lists: Dictionary = {}
var _object_lists: Dictionary = {}
var _tag_owner: Dictionary = {}
var _journal: Array = []
var _actions_this_tick: int = 0
var _armed: bool = false
var _warned: Dictionary = {}

# Standing-condition bookkeeping, updated by notify_* hooks.
var _credits: Dictionary = {}
var _last_built: Dictionary = {}
var _built: Dictionary = {}
var _alive: Dictionary = {}
var _time_ready: Dictionary = {}
var _allow_win: Dictionary = {}


func _ready() -> void:
    MatchClock.tick.connect(_on_tick)
    MatchClock.deadline_reached.connect(_on_deadline)
    ScenarioState.mission_timer_expired.connect(_on_mission_timer_expired)
    EconomyManager.credits_changed.connect(_on_credits_changed)
    EntityPlacer.entity_placed.connect(_on_entity_placed)
    BuildingManager.building_placed.connect(_on_building_placed)
    ScenarioState.global_changed.connect(_on_global_changed)
    ScenarioState.local_changed.connect(_on_local_changed)


## Resolves the house (faction id) that owns a player slot, or "" when unknown.
static func house_for_player(player_id: int) -> String:
    var data: PlayerData = PlayerManager.get_player_data(player_id)
    return String(data.faction_id) if data else ""


## Resolves the house that owns an entity via its StatsComponent, or "".
static func house_for_entity(entity: Node) -> String:
    if entity == null or not is_instance_valid(entity):
        return ""
    var stats := entity.get_node_or_null("StatsComponent")
    if stats == null:
        return ""
    return house_for_player(int(stats.player_id))


func _on_credits_changed(
    player_id: int, new_balance: int, _reason: String, _category: String
) -> void:
    notify_credits(player_id, new_balance)


func _on_global_changed(_name: String, value: bool) -> void:
    offer(27 if value else 28, {})


func _on_local_changed(house_id: String, _name: String, value: bool) -> void:
    offer(36 if value else 37, {"house": house_id})


func _on_entity_placed(entity: Node3D, data: EntityData) -> void:
    if data == null:
        return
    notify_built(house_for_entity(entity), String(data.id), entity)


func _on_building_placed(building: Node3D, data: EntityData) -> void:
    if data == null:
        return
    notify_built(house_for_entity(building), String(data.id), building)


## Parses and arms trigger definitions. Returns false and arms nothing when any
## definition is invalid. `triggers_data` is the map's `triggers` array; `overlay`
## is an optional array of partial trigger entries that patch entries by id.
func arm(triggers_data: Array, overlay: Array = []) -> bool:
    reset()
    var merged: Array = triggers_data
    if not overlay.is_empty():
        merged = TriggerParser.merge_overlay(triggers_data, overlay)
    var parsed: Dictionary = (
        TriggerParser
        . parse(
            merged,
            ScenarioState.declared_globals(),
            ScenarioState.declared_locals(),
            ScenarioState.waypoint_ids(),
        )
    )
    var errors: Array = parsed["errors"]
    if not errors.is_empty():
        for message in errors:
            push_error("TriggerEngine: %s" % message)
        return false
    _defs = parsed["definitions"]
    _order.clear()
    for id in _defs.keys():
        _order.append(String(id))
    _order.sort()
    _build_indices()
    _armed = true
    _schedule_time_events()
    _warn_unimplemented()
    return true


func reset() -> void:
    _defs.clear()
    _order.clear()
    _rt.clear()
    _dirty.clear()
    _by_event.clear()
    _general.clear()
    _house_lists.clear()
    _cell_lists.clear()
    _object_lists.clear()
    _tag_owner.clear()
    _journal.clear()
    _actions_this_tick = 0
    _armed = false
    _warned.clear()
    _credits.clear()
    _last_built.clear()
    _built.clear()
    _alive.clear()
    _time_ready.clear()
    _allow_win.clear()


func is_armed() -> bool:
    return _armed


func has_trigger(id: String) -> bool:
    return _rt.has(id)


func is_destroyed(id: String) -> bool:
    return _rt.has(id) and bool(_rt[id]["destroyed"])


func is_enabled(id: String) -> bool:
    return _rt.has(id) and bool(_rt[id]["enabled"])


func is_dirty(id: String) -> bool:
    return _dirty.has(id)


func is_latched(id: String, index: int) -> bool:
    return _rt.has(id) and bool(_rt[id]["latched"].has(index))


func is_marked(id: String, index: int) -> bool:
    return _rt.has(id) and bool(_rt[id]["marked"].has(index))


func allow_win_held(house: String) -> bool:
    return int(_allow_win.get(house, 0)) > 0


# --- occurrence routing -------------------------------------------------------


## Routes a temporal occurrence to reachable triggers, latching the matching event
## and marking them dirty. Does not evaluate. `payload` keys: `cell` (Vector2i),
## `object` (Node), `object_id` (String), `house` (String).
func offer(event_id: int, payload: Dictionary = {}) -> void:
    if not _armed:
        return
    var subscribers: Array = _by_event.get(event_id, [])
    for id in subscribers:
        var rt: Dictionary = _rt.get(id, {})
        if rt.is_empty() or bool(rt["destroyed"]) or not bool(rt["enabled"]):
            continue
        if not _reachable(id, payload):
            continue
        rt["last_payload"] = payload
        if _is_temporal(event_id):
            for index in _event_indices(id, event_id):
                rt["latched"][index] = true
        _dirty[id] = true


## Records a built entity for standing build/building-exists events.
func notify_built(owner: String, entity_id: String, _node: Node = null) -> void:
    if not _armed or owner.is_empty():
        return
    _last_built[owner] = entity_id
    var per_owner: Dictionary = _built.get(owner, {})
    per_owner[entity_id] = int(per_owner.get(entity_id, 0)) + 1
    _built[owner] = per_owner
    _alive[owner] = int(_alive.get(owner, 0)) + 1
    _mark_owner_dirty(owner)


## Records a destroyed entity and offers the destroyed events.
func notify_destroyed(owner: String, entity_id: String, node: Node = null) -> void:
    if not _armed:
        return
    if not owner.is_empty():
        var per_owner: Dictionary = _built.get(owner, {})
        per_owner[entity_id] = maxi(int(per_owner.get(entity_id, 0)) - 1, 0)
        _built[owner] = per_owner
        _alive[owner] = maxi(int(_alive.get(owner, 0)) - 1, 0)
        _mark_owner_dirty(owner)
    offer(7, {"object": node, "object_id": entity_id, "house": owner})
    offer(48, {"object": node, "object_id": entity_id, "house": owner})


func notify_credits(player_id: int, balance: int) -> void:
    if not _armed:
        return
    var data: PlayerData = PlayerManager.get_player_data(player_id)
    var owner: String = data.faction_id if data else ""
    if owner.is_empty():
        return
    _credits[owner] = balance
    _mark_owner_dirty(owner)


# --- evaluation ---------------------------------------------------------------


func _on_tick(_frame: int) -> void:
    if not _armed:
        return
    _actions_this_tick = 0
    var iterations := 0
    while (
        (not _dirty.is_empty() or not _journal.is_empty()) and iterations < MAX_CASCADE_ITERATIONS
    ):
        _evaluate_dirty()
        _drain_journal()
        iterations += 1
    if not _dirty.is_empty() or not _journal.is_empty():
        push_warning(
            (
                "TriggerEngine: cascade budget exhausted; dropped %d triggers / %d actions"
                % [_dirty.size(), _journal.size()]
            )
        )
        _dirty.clear()
        _journal.clear()


func _evaluate_dirty() -> void:
    var ids: Array = _dirty.keys()
    ids.sort()
    _dirty.clear()
    for id in ids:
        if _rt.has(id):
            _evaluate(id)


func _evaluate(id: String) -> void:
    var rt: Dictionary = _rt[id]
    if bool(rt["destroyed"]) or not bool(rt["enabled"]):
        return
    var def: Dictionary = _defs[id]
    var events: Array = def["events"]
    if events.is_empty():
        return
    var all_ok := true
    var has_temporal := false
    var remembering: bool = int(rt["persistence"]) == PERSISTENT
    for i in range(events.size() - 1, -1, -1):
        var ev: Dictionary = events[i]
        var temporal := _is_temporal(int(ev["id"]))
        if temporal:
            has_temporal = true
        if _event_satisfied(id, rt, i, ev):
            if remembering and temporal:
                rt["marked"][i] = true
        else:
            all_ok = false
    # A trigger made only of standing conditions fires on the rising edge of its
    # combined condition, so a held-true condition does not re-fire it every tick.
    var should_fire := all_ok
    if all_ok and not has_temporal:
        should_fire = not bool(rt["was_ready"])
    rt["was_ready"] = all_ok
    if should_fire:
        _fire(id, rt, def)
    rt["latched"].clear()


func _event_satisfied(id: String, rt: Dictionary, index: int, ev: Dictionary) -> bool:
    var event_id := int(ev["id"])
    if _is_temporal(event_id):
        return bool(rt["latched"].has(index)) or bool(rt["marked"].has(index))
    return _standing_satisfied(id, index, event_id, ev["params"])


func _standing_satisfied(id: String, index: int, event_id: int, params: Array) -> bool:
    var owner: String = _defs[id]["owner"]
    var result := false
    match event_id:
        12:
            result = int(_credits.get(owner, 0)) >= int(params[0])
        13:
            result = bool(_time_ready.get(id, {}).get(index, false))
        19:
            result = String(_last_built.get(owner, "")) == String(params[0])
        27:
            result = ScenarioState.get_global(String(params[0]))
        28:
            result = not ScenarioState.get_global(String(params[0]))
        32:
            result = int((_built.get(owner, {}) as Dictionary).get(String(params[0]), 0)) > 0
        36:
            result = ScenarioState.get_local(owner, String(params[0]))
        37:
            result = not ScenarioState.get_local(owner, String(params[0]))
    return result


func _fire(id: String, rt: Dictionary, def: Dictionary) -> void:
    var persistence := int(rt["persistence"])
    if persistence == SEMI_PERSISTENT:
        if not _semi_should_fire(rt):
            return
    for action in def["actions"]:
        _journal.append({"trigger_id": id, "action": action, "payload": rt["last_payload"]})
    if persistence == VOLATILE or persistence == SEMI_PERSISTENT:
        _destroy_trigger(id)
    else:
        rt["latched"].clear()
        rt["marked"].clear()
        _schedule_time_trigger(id)


## Semi-persistent tags fire only on the last remaining holder. Returns true when
## the trigger should fire now; otherwise detaches one holder and returns false.
func _semi_should_fire(rt: Dictionary) -> bool:
    var holders: Array = rt["holders"]
    if holders.is_empty():
        return false
    var payload: Dictionary = rt["last_payload"]
    var match_index := _matching_holder(holders, payload)
    if match_index < 0:
        return false
    if holders.size() > 1:
        holders.remove_at(match_index)
        return false
    return true


func _matching_holder(holders: Array, payload: Dictionary) -> int:
    for i in holders.size():
        var holder: Dictionary = holders[i]
        if holder["type"] == "cell" and payload.has("cell") and holder["cell"] == payload["cell"]:
            return i
        if (
            holder["type"] == "object"
            and payload.has("object_id")
            and holder["id"] == payload["object_id"]
        ):
            return i
    return -1


# --- action dispatch ----------------------------------------------------------


func _drain_journal() -> void:
    var commands: Array = _journal
    _journal = []
    for command in commands:
        if _actions_this_tick >= MAX_ACTIONS_PER_TICK:
            push_warning("TriggerEngine: action budget exhausted; dropping queued actions")
            break
        _actions_this_tick += 1
        _dispatch(command)


func _dispatch(command: Dictionary) -> void:
    var trigger_id: String = command["trigger_id"]
    var action: Dictionary = command["action"]
    var payload: Dictionary = command["payload"]
    var params: Array = action["params"]
    var owner: String = _defs.get(trigger_id, {}).get("owner", "")
    match int(action["id"]):
        1:
            mission_won.emit(String(params[0]))
        2:
            mission_lost.emit(String(params[0]))
        4, 7:
            _warn_unimplemented_action(int(action["id"]))
            team_requested.emit(String(params[0]))
        11:
            text_requested.emit(String(params[0]))
        12:
            _destroy_trigger(String(params[0]))
        15:
            _allow_win[String(params[0])] = int(_allow_win.get(String(params[0]), 0)) + 1
        16:
            _reveal_all(String(params[0]))
        17:
            _reveal_waypoint(String(params[0]))
        19:
            AudioManager.play_sound(String(params[0]))
        21:
            AudioManager.play_voice(String(params[0]), "")
        22:
            _force_trigger(String(params[0]))
        23:
            ScenarioState.start_timer()
        24:
            ScenarioState.stop_timer()
        27:
            ScenarioState.set_timer(int(params[0]))
        28:
            ScenarioState.set_global(String(params[0]))
        29:
            ScenarioState.clear_global(String(params[0]))
        32:
            _kill_attached(payload)
        43:
            _warn_unimplemented_action(43)
            meteor_requested.emit(String(params[0]))
        48:
            _center_viewpoint(String(params[0]))
        53:
            _set_enabled(String(params[0]), true)
        54:
            _set_enabled(String(params[0]), false)
        56:
            ScenarioState.set_local(owner, String(params[0]))
        57:
            ScenarioState.clear_local(owner, String(params[0]))
        63:
            _damage_attached(payload, int(params[0]))
        70:
            _destroy_tag(String(params[0]))
        _:
            _warn_unimplemented_action(int(action["id"]))


func _force_trigger(id: String) -> void:
    if not _rt.has(id):
        return
    var rt: Dictionary = _rt[id]
    if bool(rt["destroyed"]) or not bool(rt["enabled"]):
        return
    for action in _defs[id]["actions"]:
        _journal.append({"trigger_id": id, "action": action, "payload": {}})


func _set_enabled(id: String, value: bool) -> void:
    if not _rt.has(id) or bool(_rt[id]["destroyed"]):
        return
    _rt[id]["enabled"] = value
    if value:
        _schedule_time_trigger(id)
    else:
        _rt[id]["latched"].clear()
        _rt[id]["marked"].clear()


func _destroy_trigger(id: String) -> void:
    if not _rt.has(id):
        return
    _rt[id]["destroyed"] = true
    _rt[id]["enabled"] = false
    _rt[id]["latched"].clear()
    _rt[id]["marked"].clear()
    _dirty.erase(id)
    var owner: String = _defs[id]["owner"]
    if int(_allow_win.get(owner, 0)) > 0:
        _allow_win[owner] = int(_allow_win[owner]) - 1


func _destroy_tag(tag_id: String) -> void:
    if _tag_owner.has(tag_id):
        _destroy_trigger(String(_tag_owner[tag_id]))


func _kill_attached(payload: Dictionary) -> void:
    var node: Variant = payload.get("object", null)
    if node is Node and is_instance_valid(node):
        var health := (node as Node).get_node_or_null("HealthComponent")
        if health and health.has_method("kill"):
            health.kill()


func _damage_attached(payload: Dictionary, amount: int) -> void:
    var node: Variant = payload.get("object", null)
    if node is Node and is_instance_valid(node):
        var health := (node as Node).get_node_or_null("HealthComponent")
        if health and health.has_method("take_damage"):
            health.take_damage(amount, "trigger", null, (node as Node3D).global_position)


func _reveal_all(house: String) -> void:
    for player_id in _players_for_house(house):
        ShroudSystem.explore_all(player_id)


func _reveal_waypoint(waypoint: String) -> void:
    var cell: Variant = ScenarioState.get_waypoint(waypoint)
    if cell == null:
        return
    for player_id in _players_for_house(""):
        ShroudSystem.explore_area(player_id, cell, REVEAL_RADIUS)


func _center_viewpoint(waypoint: String) -> void:
    var cell: Variant = ScenarioState.get_waypoint(waypoint)
    if cell != null:
        BoundsSystem.center_camera_on_cell(cell)


func _players_for_house(house: String) -> Array[int]:
    var out: Array[int] = []
    for data in PlayerManager.get_all_players():
        if house.is_empty() or String(data.faction_id) == house:
            out.append(int(data.player_id))
    if out.is_empty():
        out.append(PlayerManager.get_local_player_id())
    return out


# --- clock and library helpers ------------------------------------------------


func _on_deadline(key: String) -> void:
    if not key.begins_with("time:"):
        return
    var parts := key.split(":")
    if parts.size() != 3:
        return
    var id := parts[1]
    var index := parts[2].to_int()
    if not _rt.has(id) or bool(_rt[id]["destroyed"]):
        return
    var ready: Dictionary = _time_ready.get(id, {})
    ready[index] = true
    _time_ready[id] = ready
    _dirty[id] = true


func _on_mission_timer_expired() -> void:
    offer(14, {})


## Schedules every live trigger's elapsed-time countdowns (called on arm).
func _schedule_time_events() -> void:
    for id in _order:
        _schedule_time_trigger(id)


## Schedules one trigger's elapsed-time countdowns, one deadline per TIME event
## keyed by event index. Called on arm, enable and after a persistent fire.
func _schedule_time_trigger(id: String) -> void:
    if not _rt.has(id) or bool(_rt[id]["destroyed"]) or not bool(_rt[id]["enabled"]):
        return
    var events: Array = _defs[id]["events"]
    var ready: Dictionary = _time_ready.get(id, {})
    for i in events.size():
        if int(events[i]["id"]) != 13:
            continue
        ready[i] = false
        var seconds: int = maxi(int((events[i]["params"] as Array)[0]), 0)
        MatchClock.schedule("time:%s:%d" % [id, i], seconds * MatchClock.TICKS_PER_SECOND)
    _time_ready[id] = ready


func _mark_owner_dirty(owner: String) -> void:
    for id in _house_lists.get(owner, []):
        if _is_live(id):
            _dirty[id] = true
    for id in _general:
        if _is_live(id):
            _dirty[id] = true


func _is_live(id: String) -> bool:
    return _rt.has(id) and not bool(_rt[id]["destroyed"]) and bool(_rt[id]["enabled"])


# --- indexing and validation --------------------------------------------------


func _build_indices() -> void:
    for id in _order:
        var def: Dictionary = _defs[id]
        var first_tag: Dictionary = def["tags"][0]
        var holders: Array = []
        var is_general := false
        var is_house := false
        for tag in def["tags"]:
            match String(tag["attach"]):
                "general":
                    is_general = true
                "house":
                    is_house = true
                "cell", "object":
                    holders.append_array(tag["holders"])
        var rt := {
            "enabled": bool(def["enabled"]),
            "latched": {},
            "marked": {},
            "destroyed": false,
            "last_payload": {},
            "was_ready": false,
            "persistence": int(first_tag["persistence"]),
            "general": is_general,
            "house": is_house,
            "holders": holders,
        }
        _rt[id] = rt
        _time_ready[id] = {}
        for ev in def["events"]:
            var list: Array = _by_event.get(int(ev["id"]), [])
            if not list.has(id):
                list.append(id)
            _by_event[int(ev["id"])] = list
        for tag in def["tags"]:
            _register_tag(id, tag)


func _register_tag(id: String, tag: Dictionary) -> void:
    var tag_id := String(tag["id"])
    if not tag_id.is_empty():
        _tag_owner[tag_id] = id
    match String(tag["attach"]):
        "general":
            if not _general.has(id):
                _general.append(id)
        "house":
            var owner: String = _defs[id]["owner"]
            var list: Array = _house_lists.get(owner, [])
            if not list.has(id):
                list.append(id)
            _house_lists[owner] = list
        "cell":
            for holder in tag["holders"]:
                var key := _cell_key(holder["cell"])
                var cell_list: Array = _cell_lists.get(key, [])
                if not cell_list.has(id):
                    cell_list.append(id)
                _cell_lists[key] = cell_list
        "object":
            for holder in tag["holders"]:
                var object_list: Array = _object_lists.get(String(holder["id"]), [])
                if not object_list.has(id):
                    object_list.append(id)
                _object_lists[String(holder["id"])] = object_list


func _reachable(id: String, payload: Dictionary) -> bool:
    var rt: Dictionary = _rt[id]
    if bool(rt["general"]):
        return true
    if bool(rt["house"]):
        if payload.is_empty():
            return true
        if String(payload.get("house", "")) == String(_defs[id]["owner"]):
            return true
    var holders: Array = rt["holders"]
    if payload.has("cell") and _holder_has_cell(holders, payload["cell"]):
        return true
    if payload.has("object_id") and _holder_has_object(holders, String(payload["object_id"])):
        return true
    return false


func _holder_has_cell(holders: Array, cell: Vector2i) -> bool:
    for holder in holders:
        if holder["type"] == "cell" and holder["cell"] == cell:
            return true
    return false


func _holder_has_object(holders: Array, object_id: String) -> bool:
    for holder in holders:
        if holder["type"] == "object" and String(holder["id"]) == object_id:
            return true
    return false


func _event_indices(id: String, event_id: int) -> Array[int]:
    var out: Array[int] = []
    var events: Array = _defs[id]["events"]
    for i in events.size():
        if int(events[i]["id"]) == event_id:
            out.append(i)
    return out


func _is_temporal(event_id: int) -> bool:
    var meta: Variant = TriggerCatalog.event(event_id)
    return meta != null and String(meta["kind"]) == "temporal"


func _cell_key(cell: Vector2i) -> String:
    return "%d,%d" % [cell.x, cell.y]


func _warn_unimplemented() -> void:
    for id in _order:
        for ev in _defs[id]["events"]:
            var meta: Variant = TriggerCatalog.event(int(ev["id"]))
            if meta != null and not bool(meta["implemented"]):
                _warn_once("event %d is validated but not yet implemented" % int(ev["id"]))
        for action in _defs[id]["actions"]:
            var ameta: Variant = TriggerCatalog.action(int(action["id"]))
            if ameta != null and not bool(ameta["implemented"]):
                _warn_once("action %d is validated but not yet implemented" % int(action["id"]))


func _warn_unimplemented_action(action_id: int) -> void:
    _warn_once("action %d is validated but not yet implemented" % action_id)


func _warn_once(message: String) -> void:
    if _warned.has(message):
        return
    _warned[message] = true
    push_warning("TriggerEngine: %s" % message)
