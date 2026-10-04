class_name TriggerCatalog
extends RefCounted

## TriggerCatalog — the single source of truth for trigger event and action numeric
## ids, their parameter arity, and which are implemented. Numeric ids are serialized
## identities: never reorder or reuse one. Adding an entry is a row here plus a
## handler in TriggerEngine.

## Event metadata: `{key, kind, params, implemented}` where `kind` is `standing` or
## `temporal` and `params` is an array of `{name, type}`. `type` is one of
## `int`, `string`, `entity`, `global`, `local`.
static var EVENTS: Dictionary = {
    1: _event("player_entered", "temporal", [], true),
    6: _event("attacked", "temporal", [], false),
    7: _event("destroyed", "temporal", [], true),
    11: _event("all_destroyed", "temporal", [], false),
    12: _event("credits", "standing", [_param("value", "int")], true),
    13: _event("time", "standing", [_param("seconds", "int")], true),
    14: _event("mission_timer_expired", "temporal", [], true),
    19: _event("build", "standing", [_param("entity", "entity")], true),
    27: _event("global_set", "standing", [_param("variable", "global")], true),
    28: _event("global_clear", "standing", [_param("variable", "global")], true),
    32: _event("building_exists", "standing", [_param("entity", "entity")], true),
    36: _event("local_set", "standing", [_param("variable", "local")], true),
    37: _event("local_clear", "standing", [_param("variable", "local")], true),
    48: _event("destroyed_any", "temporal", [], true),
    51: _event("random_time", "standing", [_param("max_seconds", "int")], false),
}

## Action metadata: `{key, params, implemented}`.
static var ACTIONS: Dictionary = {
    1: _action("win", [_param("house", "house")], true),
    2: _action("lose", [_param("house", "house")], true),
    4: _action("create_team", [_param("team", "string")], false),
    7: _action("reinforcements", [_param("team", "string")], false),
    11: _action("text_trigger", [_param("text", "string")], true),
    12: _action("destroy_trigger", [_param("trigger", "trigger")], true),
    15: _action("allow_win", [_param("house", "house")], true),
    16: _action("reveal_all", [_param("house", "house")], true),
    17: _action("reveal_some", [_param("waypoint", "waypoint")], true),
    19: _action("play_sound", [_param("sound", "string")], true),
    21: _action("play_speech", [_param("voice", "string")], true),
    22: _action("force_trigger", [_param("trigger", "trigger")], true),
    23: _action("start_timer", [], true),
    24: _action("stop_timer", [], true),
    27: _action("set_timer", [_param("seconds", "int")], true),
    28: _action("set_global", [_param("variable", "global")], true),
    29: _action("clear_global", [_param("variable", "global")], true),
    32: _action("destroy_object", [], true),
    43: _action("meteor_impact", [_param("waypoint", "waypoint")], false),
    48: _action("center_viewpoint", [_param("waypoint", "waypoint")], true),
    53: _action("enable_trigger", [_param("trigger", "trigger")], true),
    54: _action("disable_trigger", [_param("trigger", "trigger")], true),
    56: _action("set_local", [_param("variable", "local")], true),
    57: _action("clear_local", [_param("variable", "local")], true),
    63: _action("damage", [_param("amount", "int")], true),
    70: _action("destroy_tag", [_param("tag", "tag")], true),
}


static func _event(key: String, kind: String, params: Array, implemented: bool) -> Dictionary:
    return {"key": key, "kind": kind, "params": params, "implemented": implemented}


static func _action(key: String, params: Array, implemented: bool) -> Dictionary:
    return {"key": key, "params": params, "implemented": implemented}


static func _param(name: String, type: String) -> Dictionary:
    return {"name": name, "type": type}


static func event(id: int) -> Variant:
    return EVENTS.get(id, null)


static func action(id: int) -> Variant:
    return ACTIONS.get(id, null)


static func event_arity(id: int) -> int:
    var meta: Variant = EVENTS.get(id, null)
    return (meta.params as Array).size() if meta != null else -1


static func action_arity(id: int) -> int:
    var meta: Variant = ACTIONS.get(id, null)
    return (meta.params as Array).size() if meta != null else -1
