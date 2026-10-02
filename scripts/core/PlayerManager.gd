extends Node

const _MAP_CONFIG_SCRIPT_PATH: String = "res://scripts/data/MapConfig.gd"

## Emitted after the player roster is (re)built — mission start, map-config load,
## or default init. Consumers holding a per-player value (e.g. the credit HUD)
## resync on this instead of trusting whatever was on screen before the rebuild.
signal players_changed

var _players: Dictionary = {}
var _local_player_id: int = 0


func get_local_player_id() -> int:
    return _local_player_id


func get_player_data(player_id: int) -> PlayerData:
    if not _players.has(player_id):
        var data := PlayerData.new()
        data.player_id = player_id
        _players[player_id] = data
    return _players[player_id] as PlayerData


func is_enemy(a_id: int, b_id: int) -> bool:
    var a := get_player_data(a_id)
    var b := get_player_data(b_id)
    return a.team_id != b.team_id


## True when `entity` is controlled by the local player (`local_id`). Entities
## without a StatsComponent, or with `player_id < 0` (neutral), count as local.
## Single source of the ownership rule shared by SelectionManager and
## UnitOrderGenerator. Invalid nodes are not local.
static func is_entity_local(entity: Node3D, local_id: int) -> bool:
    if not is_instance_valid(entity):
        return false
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    if not stats:
        return true
    return stats.player_id < 0 or stats.player_id == local_id


func get_all_players() -> Array[PlayerData]:
    var result: Array[PlayerData] = []
    for key in _players:
        result.append(_players[key] as PlayerData)
    return result


func get_players_by_team(team_id: int) -> Array[PlayerData]:
    var result: Array[PlayerData] = []
    for key in _players:
        var data := _players[key] as PlayerData
        if data.team_id == team_id:
            result.append(data)
    return result


func _ready() -> void:
    var map_config: Node = _find_map_config()
    if map_config:
        _init_from_map_config(map_config)
    else:
        _init_defaults()


func _find_map_config() -> Node:
    var tree := get_tree()
    if not tree:
        return null
    var root := tree.current_scene
    if not root:
        return null
    var config_script: GDScript = load(_MAP_CONFIG_SCRIPT_PATH) as GDScript
    if not config_script:
        return null
    for child in root.get_children():
        if child.get_script() == config_script:
            return child
    return null


func _init_from_map_config(config: Node) -> void:
    var rules: GlobalRules = _get_global_rules()
    var player_configs: Array = config.get("players") as Array
    for pc in player_configs:
        var pc_node = pc
        if not pc_node:
            continue
        var default_credits: int = rules.starting_credits if rules else 0
        var pc_credits: int = pc_node.get("starting_credits")
        var credits: int = pc_credits if pc_credits >= 0 else default_credits
        var data := _make_player(
            pc_node.get("player_id"),
            pc_node.get("faction_id"),
            pc_node.get("color"),
            pc_node.get("team_id"),
            pc_node.get("spawn_index"),
            pc_node.get("display_name"),
            pc_node.get("is_bot"),
            credits,
        )
        _players[data.player_id] = data
        if not data.is_bot and _local_player_id == 0:
            _local_player_id = data.player_id

    if _local_player_id == 0 and not _players.is_empty():
        var first_id: int = _players.keys()[0] as int
        var first: PlayerData = _players[first_id] as PlayerData
        if first.is_bot:
            push_warning("[PlayerManager] All players are bots, setting local player to first bot")
            _local_player_id = first_id
    players_changed.emit()


## Rebuilds players for a mission start. Resolves per-player values with
## precedence mission > map > GlobalRules: the mission's `starting_credits` /
## `player_house` win when set, else the map's (MapConfig) override, else the
## active game's rules. This is the single entry point future map-defined
## player lists route through.
func begin_mission(mission: Mission, map_config: Node = null) -> void:
    if mission == null:
        return
    _players.clear()
    _local_player_id = 0

    var rules: GlobalRules = _get_global_rules()
    var global_credits: int = rules.starting_credits if rules else 10000
    var credits := resolve_starting_credits(
        mission.starting_credits, _map_starting_credits(map_config), global_credits
    )
    var tech_level := resolve_tech_level(mission.tech_level, rules.tech_level if rules else 10)

    var playable := _get_playable_factions()
    var human_house := mission.player_house
    if human_house.is_empty():
        human_house = _map_player_house(map_config)
    var human_faction := _faction_for_house(human_house, playable, 0)
    var ai_faction := _faction_for_house("", playable, 1)

    var human := _make_player(
        0,
        human_faction.id if human_faction else "",
        human_faction.color if human_faction else Color.WHITE,
        1,
        0,
        "Player",
        false,
        credits,
    )
    _players[0] = human
    _local_player_id = 0

    var ai := _make_player(
        1,
        ai_faction.id if ai_faction else "",
        ai_faction.color if ai_faction else Color.WHITE,
        2,
        1,
        "AI Opponent",
        true,
        global_credits,
    )
    _players[1] = ai
    human.tech_level = tech_level
    ai.tech_level = tech_level
    players_changed.emit()


## Effective starting credits: mission override > map override > global rules.
## A value of -1 at either override layer means "inherit". Static for
## testability.
static func resolve_starting_credits(
    mission_credits: int, map_credits: int, global_credits: int
) -> int:
    if mission_credits >= 0:
        return mission_credits
    if map_credits >= 0:
        return map_credits
    return global_credits


## Current tech level: a non-negative mission override wins, else the rules default.
static func resolve_tech_level(mission_level: int, rules_level: int) -> int:
    if mission_level >= 0:
        return mission_level
    return rules_level


## Faction for a house id, falling back to the playable roster at
## `fallback_index` when the house is empty or unknown. Returns null when the
## roster has no entry at that index.
func _faction_for_house(house_id: String, playable: Array[Faction], fallback_index: int) -> Faction:
    if not house_id.is_empty():
        var faction := FactionCatalog.get_faction(house_id) as Faction
        if faction:
            return faction
        push_warning("[PlayerManager] mission player_house '%s' not found" % house_id)
    if fallback_index < playable.size():
        return playable[fallback_index]
    return null


## The map's local-player credit override, or -1 when the map config is absent
## or lists no local player. The map layer of mission > map > global.
func _map_starting_credits(map_config: Node) -> int:
    var entry := _map_local_player_config(map_config)
    if entry == null:
        return -1
    return int(entry.get("starting_credits"))


## The map's local-player house id, or "" when absent.
func _map_player_house(map_config: Node) -> String:
    var entry := _map_local_player_config(map_config)
    if entry == null:
        return ""
    return String(entry.get("faction_id"))


## The MapConfig player entry for the local player, or null.
func _map_local_player_config(map_config: Node) -> Object:
    if map_config == null:
        return null
    var player_configs: Array = map_config.get("players") as Array
    if player_configs == null:
        return null
    for pc in player_configs:
        if pc and int(pc.get("player_id")) == _local_player_id:
            return pc
    return null


func _make_player(
    player_id: int,
    faction_id: String,
    color: Color,
    team_id: int,
    spawn_index: int,
    display_name: String,
    is_bot: bool,
    credits: int,
) -> PlayerData:
    var data := PlayerData.new()
    data.player_id = player_id
    data.faction_id = faction_id
    data.color = color
    data.team_id = team_id
    data.spawn_index = spawn_index
    data.display_name = display_name
    data.is_bot = is_bot
    data.free_credits = credits
    var rules: GlobalRules = _get_global_rules()
    data.tech_level = rules.tech_level if rules else 10
    return data


func _init_defaults() -> void:
    var rules: GlobalRules = _get_global_rules()
    var starting_credits: int = rules.starting_credits if rules else 10000
    var tech_level: int = rules.tech_level if rules else 10

    var playable := _get_playable_factions()
    var human_faction: Faction = playable[0] if playable.size() > 0 else null
    var ai_faction: Faction = playable[1] if playable.size() > 1 else null

    var human := _make_player(
        0,
        human_faction.id if human_faction else "",
        human_faction.color if human_faction else Color.WHITE,
        1,
        0,
        "Player",
        false,
        starting_credits,
    )
    _players[0] = human

    var ai := _make_player(
        1,
        ai_faction.id if ai_faction else "",
        ai_faction.color if ai_faction else Color.WHITE,
        2,
        1,
        "AI Opponent",
        true,
        starting_credits,
    )
    _players[1] = ai
    human.tech_level = tech_level
    ai.tech_level = tech_level

    _local_player_id = 0
    players_changed.emit()


## The default-roster factions (ascending order), or [] when the roster is empty.
func _get_playable_factions() -> Array[Faction]:
    var out: Array[Faction] = []
    for faction in FactionCatalog.get_playable():
        out.append(faction as Faction)
    return out


func _get_global_rules() -> GlobalRules:
    return GameContext.rules
