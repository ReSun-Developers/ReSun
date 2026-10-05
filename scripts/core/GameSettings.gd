extends Node

## GameSettings autoload — per-game gameplay/interface toggles stored under
## `[game_settings.<game_id>]` in user://settings.cfg and applied whenever the
## active game changes.

## Emitted after the active game's toggles are (re)applied, and on each change.
signal setting_changed(game_id: String, key: String, value: Variant)

const UserConfig := preload("res://scripts/core/UserConfig.gd")

const CONFIG_PATH: String = "user://settings.cfg"
const SECTION_PREFIX: String = "game_settings"

## Toggle registry: id -> {default, description}. One source of truth for the
## Options view and the consumers.
const REGISTRY: Dictionary = {
    "move_target_line":
    {"default": true, "description": "Show move target lines for selected units"},
}

## Test seam: redirect persistence to a scratch file.
var _config_path: String = CONFIG_PATH
var _values: Dictionary = {}


func _ready() -> void:
    GameContext.game_changed.connect(_on_game_changed)
    _load(_active_game_id())


# --- Public API -------------------------------------------------------------


func registry() -> Dictionary:
    return REGISTRY


## Current value for the active game (registry default when unset).
func get_value(key: String) -> Variant:
    return _values.get(key, REGISTRY.get(key, {}).get("default", null))


## Stores a toggle for the active game, applies it, and notifies.
func set_value(key: String, value: Variant) -> void:
    if not REGISTRY.has(key):
        push_error("[GameSettings] Unknown toggle: %s" % key)
        return
    var game_id := _active_game_id()
    _values[key] = value
    UserConfig.set_value(_config_path, _section(game_id), key, value)
    setting_changed.emit(game_id, key, value)


func _on_game_changed(_def: GameDefinition) -> void:
    _load(_active_game_id())


func _load(game_id: String) -> void:
    _values.clear()
    for key in REGISTRY:
        _values[key] = UserConfig.get_value(
            _config_path, _section(game_id), key, REGISTRY[key]["default"]
        )


func _section(game_id: String) -> String:
    return "%s.%s" % [SECTION_PREFIX, game_id]


func _active_game_id() -> String:
    return GameContext.current.id if GameContext.current else ""
