extends Node

## GameContext autoload — resolves the active GameDefinition and drives the
## content lifecycle. Registered FIRST in project.godot so every consumer
## (EntityFactory, TerrainCatalog, AudioManager) can pull the resolved game in
## its own _ready(); game_changed is only for runtime switches (select_game).
##
## Resolution order: --game CLI flag → persisted [game] id in
## user://settings.cfg → default ("ts").

signal game_changed(def: GameDefinition)
signal mission_started(mission: Mission)

const GAMES_ROOT: String = "res://games"
const DEFAULT_GAME_ID: String = "ts"
const DEFAULT_CONFIG_PATH: String = "user://settings.cfg"

## Active game definition, or null when no game is selected (unload, or boot
## before any game content exists). Set only through select_game.
var current: GameDefinition:
    get:
        return _current

## Active game's GlobalRules, or null when no game is selected.
var rules: GlobalRules:
    get:
        return _current.rules if _current else null

## Active mission, or null when no mission is running. Set only through
## start_mission; cleared whenever the game changes.
var current_mission: Mission = null

var _defs: Dictionary = {}
var _current: GameDefinition = null
## Test seam: redirect persistence to a scratch file.
var _config_path: String = DEFAULT_CONFIG_PATH


func _ready() -> void:
    _scan_games_root(GAMES_ROOT)
    var flag_id := extract_flag_id(OS.get_cmdline_args())
    if flag_id.is_empty():
        flag_id = extract_flag_id(OS.get_cmdline_user_args())
    var id := resolve_game_id(flag_id, _load_persisted_id(), _defs.keys())
    if _defs.has(id):
        var def: GameDefinition = _defs[id]
        if _validate_rules(def):
            _current = def
        else:
            push_error("GameContext: boot refused game '%s'; continuing without content" % id)
    else:
        push_warning(
            (
                "GameContext: no game '%s' found (%d discovered); booting without content"
                % [id, _defs.size()]
            )
        )


## All discovered game definitions, ordered by id.
func list_games() -> Array[GameDefinition]:
    var out: Array[GameDefinition] = []
    for id in _defs:
        out.append(_defs[id])
    out.sort_custom(func(a: GameDefinition, b: GameDefinition) -> bool: return a.id < b.id)
    return out


## True when the active game declares the feature. False when no game is loaded
## or the id is unknown — never errors.
func has_feature(id: String) -> bool:
    return _current.has_feature(id) if _current else false


## Selects a game: validates rules, resets consumer content (consumers re
## register from the new definition when they receive game_changed), emits.
## select_game("") unloads — consumers reset without re-registering.
## Unknown or invalid ids are refused and keep the current game.
func select_game(id: String) -> void:
    current_mission = null
    if id.is_empty():
        _current = null
        game_changed.emit(null)
        return
    if not _defs.has(id):
        push_error("GameContext: unknown game id '%s'" % id)
        return
    var def: GameDefinition = _defs[id]
    if not _validate_rules(def):
        return
    _current = def
    game_changed.emit(def)


## Starts a mission by id: resolves it through CampaignCatalog, stores it as
## current_mission, and emits mission_started. Unknown ids are refused and the
## current mission is left unchanged. start_mission("") clears the mission
## without emitting.
func start_mission(id: String) -> void:
    if id.is_empty():
        current_mission = null
        return
    var mission: Mission = CampaignCatalog.get_mission(id)
    if mission == null:
        push_error("GameContext: unknown mission id '%s'" % id)
        return
    current_mission = mission
    mission_started.emit(mission)


## Persists the game choice to [game] id in the settings file, preserving all
## other sections and keys.
func save_game_choice(id: String) -> void:
    var cfg := ConfigFile.new()
    cfg.load(_config_path)
    cfg.set_value("game", "id", id)
    var err := cfg.save(_config_path)
    if err != OK:
        push_warning("GameContext: failed to save game choice to %s" % _config_path)


## Extracts the value following a `--game` flag, or "" when absent.
## Static for testability — process args cannot be changed at runtime.
static func extract_flag_id(args: PackedStringArray) -> String:
    return extract_flag_value(args, "--game")


## Extracts the value following a `--mission` flag, or "" when absent.
static func extract_mission_id(args: PackedStringArray) -> String:
    return extract_flag_value(args, "--mission")


## Extracts the value following `flag`, or "" when the flag is absent or
## trailing. Static for testability.
static func extract_flag_value(args: PackedStringArray, flag: String) -> String:
    var idx := args.find(flag)
    if idx == -1 or idx + 1 >= args.size():
        return ""
    return args[idx + 1]


## Resolution order: flag → persisted → default. Unknown ids log a push_error
## naming the id and fall through to the next source. Static for testability.
static func resolve_game_id(flag_id: String, persisted_id: String, known_ids: Array) -> String:
    if not flag_id.is_empty():
        if known_ids.has(flag_id):
            return flag_id
        push_error("GameContext: unknown game id '%s' (--game), falling back" % flag_id)
    if not persisted_id.is_empty():
        if known_ids.has(persisted_id):
            return persisted_id
        push_error("GameContext: unknown persisted game id '%s', falling back" % persisted_id)
    return DEFAULT_GAME_ID


## Cross-game entity-id collision check. Flags an id defined in two dirs where
## neither defining game lists the other's dir (borrowed roots are layering,
## not collisions). Returns one error per colliding (id, game pair), naming
## both games and the id. Runs on demand — never part of every boot.
static func validate_id_collisions(defs: Array[GameDefinition]) -> Array[String]:
    var errors: Array[String] = []
    var id_dirs: Dictionary = {}  # entity id -> { entities dir: true }
    var dirs_of: Dictionary = {}  # def id -> { entities dir: true }
    for def in defs:
        dirs_of[def.id] = {}
        for root in def.data_sets:
            var entities_dir := root.trim_suffix("/") + "/entities/"
            dirs_of[def.id][entities_dir] = true
            for entity_id in _scan_entity_ids(entities_dir):
                if not id_dirs.has(entity_id):
                    id_dirs[entity_id] = {}
                id_dirs[entity_id][entities_dir] = true
    for entity_id: String in id_dirs:
        var dirs: Array = id_dirs[entity_id].keys()
        if dirs.size() < 2:
            continue
        for i in defs.size():
            var a: GameDefinition = defs[i]
            for j in range(i + 1, defs.size()):
                var b: GameDefinition = defs[j]
                if _pair_collides(dirs, dirs_of[a.id], dirs_of[b.id]):
                    errors.append(
                        (
                            "Entity id '%s' is defined by both game '%s' and game '%s'"
                            % [entity_id, a.id, b.id]
                        )
                    )
    return errors


## True when a claims d1 exclusively and b claims d2 exclusively (d1 != d2):
## neither game lists the other's defining dir, so last-wins cannot explain it.
static func _pair_collides(dirs: Array, a_dirs: Dictionary, b_dirs: Dictionary) -> bool:
    for d1: String in dirs:
        if not a_dirs.has(d1) or b_dirs.has(d1):
            continue
        for d2: String in dirs:
            if d2 == d1 or not b_dirs.has(d2) or a_dirs.has(d2):
                continue
            return true
    return false


static func _scan_entity_ids(path: String) -> Array[String]:
    var ids: Array[String] = []
    var dir := DirAccess.open(path)
    if not dir:
        return ids
    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        var resource_path := file_name.trim_suffix(".remap")
        if resource_path.ends_with(".tres"):
            var resource := load(path.path_join(resource_path))
            if resource is EntityData:
                ids.append((resource as EntityData).id)
        elif dir.current_is_dir() and not file_name.begins_with("."):
            ids.append_array(_scan_entity_ids(path.path_join(file_name)))
        file_name = dir.get_next()
    dir.list_dir_end()
    return ids


func _scan_games_root(root: String) -> void:
    var dir := DirAccess.open(root)
    if not dir:
        return
    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        if dir.current_is_dir() and not file_name.begins_with("."):
            var def_path := root.path_join(file_name + "/game.tres")
            if ResourceLoader.exists(def_path):
                var def := load(def_path) as GameDefinition
                if def == null:
                    push_error("GameContext: %s is not a GameDefinition" % def_path)
                elif def.id != file_name:
                    push_error(
                        (
                            "GameContext: id '%s' does not match directory '%s' — skipped"
                            % [def.id, file_name]
                        )
                    )
                else:
                    _defs[def.id] = def
        file_name = dir.get_next()
    dir.list_dir_end()


func _load_persisted_id() -> String:
    var cfg := ConfigFile.new()
    if cfg.load(_config_path) != OK:
        return ""
    return String(cfg.get_value("game", "id", ""))


func _validate_rules(def: GameDefinition) -> bool:
    if def.rules == null:
        push_error("GameContext: game '%s' has no rules resource" % def.id)
        return false
    var errors := def.rules.validate_locomotor_keys()
    errors.append_array(def.rules.validate_warhead_armor_keys())
    if not errors.is_empty():
        push_error("GameContext: game '%s' rules invalid: %s" % [def.id, ", ".join(errors)])
        return false
    return true
