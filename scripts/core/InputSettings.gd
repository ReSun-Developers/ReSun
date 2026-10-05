extends Node

## Centralized input settings — per-game camera keybinds (a base [input] section
## plus [input.<game_id>] overrides) persisted through UserConfig, plus the
## edge-scroll toggle. A binding resolves game override → base → project.godot
## default, and rebinds InputMap whenever the active game changes.

## Emitted after InputMap bindings are re-applied (game switch or remap).
signal bindings_changed

const UserConfig := preload("res://scripts/core/UserConfig.gd")

const CONFIG_PATH: String = "user://settings.cfg"
const BASE_SECTION: String = "input"
const LEGACY_SECTION: String = "camera"
const LEGACY_KEYBINDS: String = "keybinds"
const CAMERA_ACTIONS: Array = ["camera_up", "camera_down", "camera_left", "camera_right"]

## Edge scroll toggle — controls both border panning and scroll cursor display.
var edge_scroll_enabled: bool = true

## Test seam: redirect persistence to a scratch file.
var _config_path: String = CONFIG_PATH
var _project_defaults: Dictionary = {}


func _ready() -> void:
    _capture_project_defaults()
    _load()
    GameContext.game_changed.connect(_on_game_changed)


## Writes a binding for `target` ("" = base, else a game id) and re-applies.
func remap_action(action: String, key_name: String, target: String = "") -> void:
    var keycode := OS.find_keycode_from_string(key_name)
    if keycode == KEY_NONE:
        push_error("[InputSettings] Invalid key name: %s" % key_name)
        return
    UserConfig.set_value(_config_path, _section_for(target), action, key_name)
    _apply_bindings()
    bindings_changed.emit()


## Human-readable key for the action's currently applied binding ("" if none).
func get_key_text(action: String) -> String:
    var events := InputMap.action_get_events(action)
    if events.is_empty():
        return ""
    var event := events[0]
    if event is InputEventKey:
        var keycode := DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
        return OS.get_keycode_string(keycode)
    return ""


## Stored base key name for an action ("" = none, use project default).
func get_base_binding(action: String) -> String:
    return String(UserConfig.get_value(_config_path, BASE_SECTION, action, ""))


## Stored override key name for a game ("" = inherited from base).
func get_game_binding(action: String, game_id: String) -> String:
    return String(UserConfig.get_value(_config_path, _section_for(game_id), action, ""))


## Effective key name for a game: override → base → "" (project default).
func resolve_key_name(action: String, game_id: String = "") -> String:
    var gid := game_id if not game_id.is_empty() else _active_game_id()
    var override := get_game_binding(action, gid)
    if not override.is_empty():
        return override
    return get_base_binding(action)


func _load() -> void:
    var cfg := UserConfig.read(_config_path)
    if cfg.has_section_key(BASE_SECTION, "edge_scroll_enabled"):
        edge_scroll_enabled = cfg.get_value(BASE_SECTION, "edge_scroll_enabled", true)
    elif cfg.has_section_key(LEGACY_SECTION, "edge_scroll_enabled"):
        edge_scroll_enabled = cfg.get_value(LEGACY_SECTION, "edge_scroll_enabled", true)
    _migrate_legacy_keybinds(cfg)
    _apply_bindings()


## Moves legacy [keybinds] entries into [input] when not already present.
func _migrate_legacy_keybinds(cfg: ConfigFile) -> void:
    if not cfg.has_section(LEGACY_KEYBINDS):
        return
    var migrated := {}
    for action in CAMERA_ACTIONS:
        if cfg.has_section_key(BASE_SECTION, action):
            continue
        if cfg.has_section_key(LEGACY_KEYBINDS, action):
            migrated[action] = cfg.get_value(LEGACY_KEYBINDS, action, "")
    if not migrated.is_empty():
        UserConfig.set_section(_config_path, BASE_SECTION, migrated)


func _apply_bindings() -> void:
    for action in CAMERA_ACTIONS:
        var key_name := resolve_key_name(action)
        InputMap.action_erase_events(action)
        if key_name.is_empty():
            _add_project_default(action)
            continue
        var keycode := OS.find_keycode_from_string(key_name)
        if keycode == KEY_NONE:
            push_warning("[InputSettings] Invalid key name for %s: %s" % [action, key_name])
            _add_project_default(action)
            continue
        var event := InputEventKey.new()
        event.physical_keycode = keycode as Key
        InputMap.action_add_event(action, event)


func _add_project_default(action: String) -> void:
    var event: InputEvent = _project_defaults.get(action)
    if event:
        InputMap.action_add_event(action, event)


func _capture_project_defaults() -> void:
    _project_defaults.clear()
    for action in CAMERA_ACTIONS:
        var events := InputMap.action_get_events(action)
        _project_defaults[action] = events[0] if not events.is_empty() else null


func _on_game_changed(_def: GameDefinition) -> void:
    _apply_bindings()
    bindings_changed.emit()


func _section_for(target: String) -> String:
    return BASE_SECTION if target.is_empty() else "%s.%s" % [BASE_SECTION, target]


func _active_game_id() -> String:
    return GameContext.current.id if GameContext.current else ""
