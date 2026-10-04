class_name TriggerParser
extends RefCounted

## TriggerParser — parses and validates a map `triggers` array into trigger
## definitions. Validation is all-or-nothing: any error is collected and the
## caller must reject the whole set. See the `trigger-engine` capability.

const ATTACH_KINDS: Array[String] = ["general", "house", "cell", "object"]
const MIN_PERSISTENCE: int = 0
const MAX_PERSISTENCE: int = 2


## Returns `{definitions: Dictionary, errors: Array[String], tag_ids: Array[String]}`.
## `global_names`/`local_names`/`waypoint_ids` are the declared names used to
## resolve references.
static func parse(
    triggers_data: Array,
    global_names: Array,
    local_names: Array,
    waypoint_ids: Array,
) -> Dictionary:
    var errors: Array[String] = []
    var seen_ids: Dictionary = {}
    var tag_ids: Array[String] = []

    for entry in triggers_data:
        var raw: Dictionary = entry as Dictionary
        if raw == null:
            errors.append("trigger entry is not an object")
            continue
        var id := String(raw.get("id", ""))
        if id.is_empty():
            errors.append("trigger entry has an empty id")
            continue
        if seen_ids.has(id):
            errors.append("duplicate trigger id '%s'" % id)
            continue
        seen_ids[id] = true
        var raw_tags: Variant = raw.get("tags", [])
        if raw_tags is Array:
            for tag in raw_tags:
                var tag_id := String((tag as Dictionary).get("id", ""))
                if not tag_id.is_empty() and not tag_ids.has(tag_id):
                    tag_ids.append(tag_id)

    var definitions: Dictionary = {}
    for entry in triggers_data:
        var raw: Dictionary = entry as Dictionary
        if raw == null:
            continue
        var id := String(raw.get("id", ""))
        if id.is_empty() or definitions.has(id):
            continue
        var def := _parse_one(
            raw, global_names, local_names, waypoint_ids, seen_ids, tag_ids, errors
        )
        if not def.is_empty():
            definitions[id] = def
    return {"definitions": definitions, "errors": errors, "tag_ids": tag_ids}


static func _parse_one(
    raw: Dictionary,
    global_names: Array,
    local_names: Array,
    waypoint_ids: Array,
    trigger_ids: Dictionary,
    tag_ids: Array,
    errors: Array[String],
) -> Dictionary:
    var id := String(raw.get("id", ""))
    var def := {
        "id": id,
        "owner": String(raw.get("owner", "")),
        "name": String(raw.get("name", "")),
        "enabled": bool(raw.get("enabled", true)),
        "difficulty": _parse_difficulty(raw.get("difficulty", [])),
        "pass_on": bool(raw.get("pass_on", false)),
        "tags": [],
        "events": [],
        "actions": [],
    }

    var tags: Array = []
    var raw_tags: Variant = raw.get("tags", [])
    if raw_tags is Array and not (raw_tags as Array).is_empty():
        for tag_entry in raw_tags:
            var tag := _parse_tag(tag_entry as Dictionary, id, errors)
            if not tag.is_empty():
                tags.append(tag)
    if tags.is_empty():
        errors.append("trigger '%s' has no tags and can never be armed" % id)
    def["tags"] = tags

    var events: Array = []
    var raw_events: Variant = raw.get("events", [])
    if raw_events is Array:
        for ev_entry in raw_events:
            var ev := _parse_event(ev_entry as Dictionary, id, global_names, local_names, errors)
            if not ev.is_empty():
                events.append(ev)
    if events.is_empty():
        errors.append("trigger '%s' has no events" % id)
    def["events"] = events

    var actions: Array = []
    var raw_actions: Variant = raw.get("actions", [])
    if raw_actions is Array:
        for act_entry in raw_actions:
            var act := _parse_action(
                act_entry as Dictionary,
                id,
                global_names,
                local_names,
                waypoint_ids,
                trigger_ids,
                tag_ids,
                errors
            )
            if not act.is_empty():
                actions.append(act)
    def["actions"] = actions

    return def


static func _parse_difficulty(value: Variant) -> Array:
    if value is Array and (value as Array).size() == 3:
        var flags: Array = value
        return [bool(flags[0]), bool(flags[1]), bool(flags[2])]
    return [true, true, true]


static func _parse_tag(raw: Dictionary, trigger_id: String, errors: Array[String]) -> Dictionary:
    if raw == null:
        errors.append("trigger '%s' has a non-object tag" % trigger_id)
        return {}
    var persistence := int(raw.get("persistence", 0))
    if persistence < MIN_PERSISTENCE or persistence > MAX_PERSISTENCE:
        errors.append("trigger '%s' tag persistence %d out of range" % [trigger_id, persistence])
        return {}
    var attach := String(raw.get("attach", "general"))
    if not ATTACH_KINDS.has(attach):
        errors.append("trigger '%s' tag attach '%s' unknown" % [trigger_id, attach])
        return {}
    var holders: Array = []
    if attach == "cell":
        var raw_cells: Variant = raw.get("cells", [])
        if not (raw_cells is Array) or (raw_cells as Array).is_empty():
            errors.append("trigger '%s' cell tag has no cells" % trigger_id)
            return {}
        for cell_text in raw_cells:
            var cell: Variant = _parse_cell(String(cell_text))
            if cell == null:
                errors.append("trigger '%s' has malformed cell '%s'" % [trigger_id, cell_text])
                return {}
            holders.append({"type": "cell", "cell": cell})
    elif attach == "object":
        var object_id := String(raw.get("object", ""))
        if object_id.is_empty():
            errors.append("trigger '%s' object tag has no object id" % trigger_id)
            return {}
        holders.append({"type": "object", "id": object_id})
    return {
        "id": String(raw.get("id", "")),
        "persistence": persistence,
        "attach": attach,
        "holders": holders,
    }


static func _parse_event(
    raw: Dictionary,
    trigger_id: String,
    global_names: Array,
    local_names: Array,
    errors: Array[String]
) -> Dictionary:
    if raw == null:
        errors.append("trigger '%s' has a non-object event" % trigger_id)
        return {}
    var event_id := int(raw.get("id", -1))
    var meta: Variant = TriggerCatalog.event(event_id)
    if meta == null:
        errors.append("trigger '%s' names unknown event id %d" % [trigger_id, event_id])
        return {}
    var params: Array = raw.get("params", [])
    if params.size() != (meta.params as Array).size():
        errors.append(
            (
                "trigger '%s' event %d expects %d params, got %d"
                % [trigger_id, event_id, (meta.params as Array).size(), params.size()]
            )
        )
        return {}
    if not _check_event_refs(meta, params, trigger_id, global_names, local_names, errors):
        return {}
    return {"id": event_id, "params": params}


static func _check_event_refs(
    meta: Dictionary,
    params: Array,
    trigger_id: String,
    global_names: Array,
    local_names: Array,
    errors: Array[String]
) -> bool:
    var decl: Array = meta.params
    for i in decl.size():
        var type: String = decl[i].type
        if type == "global" and not global_names.has(str(params[i])):
            errors.append(
                "trigger '%s' references undeclared global '%s'" % [trigger_id, params[i]]
            )
            return false
        if type == "local" and not local_names.has(str(params[i])):
            errors.append("trigger '%s' references undeclared local '%s'" % [trigger_id, params[i]])
            return false
    return true


static func _parse_action(
    raw: Dictionary,
    trigger_id: String,
    global_names: Array,
    local_names: Array,
    waypoint_ids: Array,
    trigger_ids: Dictionary,
    tag_ids: Array,
    errors: Array[String],
) -> Dictionary:
    if raw == null:
        errors.append("trigger '%s' has a non-object action" % trigger_id)
        return {}
    var action_id := int(raw.get("id", -1))
    var meta: Variant = TriggerCatalog.action(action_id)
    if meta == null:
        errors.append("trigger '%s' names unknown action id %d" % [trigger_id, action_id])
        return {}
    var params: Array = raw.get("params", [])
    if params.size() != (meta.params as Array).size():
        errors.append(
            (
                "trigger '%s' action %d expects %d params, got %d"
                % [trigger_id, action_id, (meta.params as Array).size(), params.size()]
            )
        )
        return {}
    if not _check_action_refs(
        meta,
        params,
        trigger_id,
        global_names,
        local_names,
        waypoint_ids,
        trigger_ids,
        tag_ids,
        errors
    ):
        return {}
    return {"id": action_id, "params": params}


static func _check_action_refs(
    meta: Dictionary,
    params: Array,
    trigger_id: String,
    global_names: Array,
    local_names: Array,
    waypoint_ids: Array,
    trigger_ids: Dictionary,
    tag_ids: Array,
    errors: Array[String],
) -> bool:
    var decl: Array = meta.params
    for i in decl.size():
        var type: String = decl[i].type
        var value: String = str(params[i])
        if type == "waypoint" and not waypoint_ids.has(value):
            errors.append(
                "trigger '%s' action references unknown waypoint '%s'" % [trigger_id, value]
            )
            return false
        if type == "global" and not global_names.has(value):
            errors.append(
                "trigger '%s' action references undeclared global '%s'" % [trigger_id, value]
            )
            return false
        if type == "local" and not local_names.has(value):
            errors.append(
                "trigger '%s' action references undeclared local '%s'" % [trigger_id, value]
            )
            return false
        if type == "trigger" and not trigger_ids.has(value):
            errors.append(
                "trigger '%s' action references unknown trigger '%s'" % [trigger_id, value]
            )
            return false
        if type == "tag" and not tag_ids.has(value):
            errors.append("trigger '%s' action references unknown tag '%s'" % [trigger_id, value])
            return false
    return true


## Merges an overlay array of trigger entries into `triggers_data` by trigger id.
## Keys present on an overlay entry replace the base entry's; base entries the
## overlay does not name are returned unchanged. New ids are appended.
static func merge_overlay(triggers_data: Array, overlay: Array) -> Array:
    var by_id: Dictionary = {}
    var order: Array = []
    for entry in triggers_data:
        var base: Dictionary = entry as Dictionary
        if base == null or not base.has("id"):
            continue
        var id := String(base["id"])
        by_id[id] = base.duplicate(true)
        order.append(id)
    for entry in overlay:
        var patch: Dictionary = entry as Dictionary
        if patch == null or not patch.has("id"):
            continue
        var patch_id := String(patch["id"])
        if by_id.has(patch_id):
            var target: Dictionary = by_id[patch_id]
            for key in patch:
                if key != "id":
                    target[key] = patch[key]
        else:
            by_id[patch_id] = patch.duplicate(true)
            order.append(patch_id)
    var out: Array = []
    for id in order:
        out.append(by_id[id])
    return out


static func _parse_cell(text: String) -> Variant:
    var parts := text.split(",")
    if parts.size() != 2:
        return null
    if not parts[0].strip_edges().is_valid_int() or not parts[1].strip_edges().is_valid_int():
        return null
    return Vector2i(parts[0].strip_edges().to_int(), parts[1].strip_edges().to_int())
