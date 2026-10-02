extends Node3D

## MissionMap — generic data-driven mission scene. Instances MapBase01 and loads
## the active mission's map JSON through MapLoader, then applies the mission's
## home-cell camera override on top of the map's start-location framing.


func _ready() -> void:
    var mission: Mission = GameContext.current_mission
    if mission == null:
        push_warning("MissionMap: no active mission; nothing to load")
        return
    var path: String = mission.map_path
    if path.is_empty() or not FileAccess.file_exists(path):
        push_error("MissionMap: mission '%s' map not found: %s" % [mission.id, path])
        return
    MapLoader.load_map_into(path, self)
    _attach_map_config(path)
    _apply_home_cell(mission.home_cell)


## Builds a MapConfig node from the map JSON's optional top-level "players"
## array so the map's per-player overrides participate in mission boot. No-op
## when the map defines no players. Fields mirror MapConfig.PlayerConfig.
func _attach_map_config(path: String) -> void:
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        return
    var json := JSON.parse_string(file.get_as_text()) as Dictionary
    file.close()
    if json == null:
        return
    var entries: Array = json.get("players", []) as Array
    if entries.is_empty():
        return
    var config := MapConfig.new()
    config.name = "MapConfig"
    for entry in entries:
        var entry_dict := entry as Dictionary
        if entry_dict == null:
            continue
        var player_config := MapConfig.PlayerConfig.new()
        player_config.player_id = int(entry_dict.get("player_id", 0))
        player_config.display_name = String(entry_dict.get("display_name", ""))
        player_config.faction_id = String(entry_dict.get("faction_id", ""))
        player_config.team_id = int(entry_dict.get("team_id", 0))
        player_config.spawn_index = int(entry_dict.get("spawn_index", 0))
        player_config.is_bot = bool(entry_dict.get("is_bot", false))
        player_config.starting_credits = int(entry_dict.get("starting_credits", -1))
        player_config.power_output = int(entry_dict.get("power_output", -1))
        var color_value: Variant = entry_dict.get("color")
        if color_value is Array and (color_value as Array).size() == 4:
            var arr: Array = color_value
            player_config.color = Color(arr[0], arr[1], arr[2], arr[3])
        var units_value: Variant = entry_dict.get("starting_units")
        if units_value is Array:
            player_config.starting_units = PackedStringArray(units_value)
        config.players.append(player_config)
    add_child(config)


## Centers the camera on the mission's home cell when it is a valid "x,y".
## An empty value defers to the map's own start-location framing.
func _apply_home_cell(home_cell: String) -> void:
    if home_cell.is_empty():
        return
    var parts := home_cell.split(",")
    if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
        push_warning("MissionMap: invalid home_cell '%s'" % home_cell)
        return
    BoundsSystem.center_camera_on_cell(Vector2i(parts[0].to_int(), parts[1].to_int()))
