extends Node

var editor: Node3D = null

## Map-level `players` array preserved from the last loaded map so an editor
## re-save does not drop it (the editor does not author players yet).
var _loaded_players: Array = []

## Optional scripting block (`triggers` / `waypoints` / `variables`) preserved
## from the last loaded map so an editor re-save does not drop it.
var _loaded_scripting: Dictionary = {}

var _save_dialog: FileDialog
var _load_dialog: FileDialog


func setup(ui: CanvasLayer) -> void:
    _save_dialog = FileDialog.new()
    _save_dialog.name = "SaveDialog"
    _save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
    _save_dialog.access = FileDialog.ACCESS_FILESYSTEM
    _save_dialog.filters = PackedStringArray(["*.json ; JSON Files"])
    _save_dialog.file_selected.connect(_on_save_file_selected)
    ui.add_child(_save_dialog)
    _load_dialog = FileDialog.new()
    _load_dialog.name = "LoadDialog"
    _load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    _load_dialog.access = FileDialog.ACCESS_FILESYSTEM
    _load_dialog.filters = PackedStringArray(["*.json ; JSON Files"])
    _load_dialog.file_selected.connect(_on_load_file_selected)
    ui.add_child(_load_dialog)


func on_save_pressed() -> void:
    _save_dialog.popup_centered(Vector2i(400, 300))


func on_load_pressed() -> void:
    _load_dialog.popup_centered(Vector2i(400, 300))


func _on_save_file_selected(path: String) -> void:
    var entities_array: Array[Dictionary] = []
    for cell_key in editor._painted_entities:
        var entry: Dictionary = editor._painted_entities[cell_key]
        var data: Dictionary = entry.get("data", {})
        var entity_entry := build_entity_entry(data)
        entity_entry["cell"] = cell_key
        entities_array.append(entity_entry)
    var extra: Dictionary = {
        "entities": entities_array,
        "start_locations": editor._player_start_tool.save_data(),
    }
    if not _loaded_players.is_empty():
        extra["players"] = _loaded_players
    _merge_loaded_scripting(extra)
    TerrainSystem.export_to_json(path, extra)


## Copies non-empty preserved scripting keys into the export payload so a
## round-trip keeps `triggers`, `waypoints`, and `variables`.
func _merge_loaded_scripting(extra: Dictionary) -> void:
    for key in MapLoader.SCRIPTING_KEYS:
        var value: Variant = _loaded_scripting.get(key)
        if value is Array and not (value as Array).is_empty():
            extra[key] = value
        elif value is Dictionary and not (value as Dictionary).is_empty():
            extra[key] = value


## Serializes one tracked-entity data dict into its JSON map entry. A `house_id`
## is written as-is; the legacy `player_id` alias is filled from the house index
## only when the entity carries no explicit slot.
static func build_entity_entry(data: Dictionary) -> Dictionary:
    var entity_entry: Dictionary = {
        "id": data.get("id", ""),
    }
    if data.has("player_id"):
        entity_entry["player_id"] = int(data["player_id"])
    if data.has("house_id"):
        entity_entry["house_id"] = data["house_id"]
        if not entity_entry.has("player_id"):
            var house_index := Houses.index_for(String(data["house_id"]))
            if house_index >= 0:
                entity_entry["player_id"] = house_index
    if data.has("rotation_y"):
        entity_entry["rotation_y"] = data["rotation_y"]
    if data.has("current_health"):
        entity_entry["current_health"] = data["current_health"]
    for key in MapLoader.OVERRIDE_KEYS:
        if data.has(key):
            entity_entry[key] = data[key]
    return entity_entry


func _read_start_locations(path: String) -> Array:
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        return []
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if (
        parsed is Dictionary
        and parsed.has("start_locations")
        and parsed["start_locations"] is Array
    ):
        return parsed["start_locations"] as Array
    return []


## Top-level `players` array from a map JSON, or [] when absent.
func _read_players(path: String) -> Array:
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        return []
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if parsed is Dictionary and parsed.has("players") and parsed["players"] is Array:
        return parsed["players"] as Array
    return []


func _on_load_file_selected(path: String) -> void:
    for key in editor._painted_entities:
        var node := editor._painted_entities[key].get("node") as Node3D
        if is_instance_valid(node):
            node.queue_free()
    editor._painted_entities.clear()
    var loaded := MapLoader.load_map_into(path, editor)
    editor._player_start_tool.load_data(_read_start_locations(path))
    _loaded_players = _read_players(path)
    _loaded_scripting = MapLoader.read_scripting(path)
    for entry in loaded:
        var key: String = entry.get("key", "")
        if key.is_empty():
            continue
        var node: Node3D = entry.get("node") as Node3D
        var data: Dictionary = entry.get("data", {})
        editor._painted_entities[key] = {"node": node, "data": data}
        if not is_instance_valid(node):
            continue
        var entity_id: String = data.get("id", "")
        var entity_data := EntityFactory.get_entity_data(entity_id)
        if not entity_data:
            continue
        var select_comp := EditorSelectComponent.new()
        select_comp.name = "EditorSelectComponent"
        node.add_child(select_comp)
        select_comp.configure(entity_data, key, editor._painted_entities[key])
