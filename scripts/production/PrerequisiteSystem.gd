extends Node

## PrerequisiteSystem autoload — tracks player-owned buildings and checks
## prerequisites for entity buildability.

signal prerequisites_changed(player_id: int)

## player_id → { entity_id → count }
var _player_buildings: Dictionary = {}


func _ready() -> void:
    GameContext.game_changed.connect(_on_game_changed)


## A runtime game switch replaces EntityFactory content; stale owned-building
## ids would otherwise linger and silently drop storage capacity to 0.
func _on_game_changed(_def: GameDefinition) -> void:
    var affected: Array = _player_buildings.keys()
    _player_buildings.clear()
    for player_id: int in affected:
        prerequisites_changed.emit(player_id)


func register_building(player_id: int, entity_data: EntityData) -> void:
    if not _player_buildings.has(player_id):
        _player_buildings[player_id] = {}
    var buildings: Dictionary = _player_buildings[player_id]
    var eid: String = entity_data.id
    buildings[eid] = buildings.get(eid, 0) + 1
    prerequisites_changed.emit(player_id)


func unregister_building(player_id: int, entity_data: EntityData) -> void:
    if not _player_buildings.has(player_id):
        return
    var buildings: Dictionary = _player_buildings[player_id]
    var eid: String = entity_data.id
    if buildings.has(eid):
        buildings[eid] -= 1
        if buildings[eid] <= 0:
            buildings.erase(eid)
    prerequisites_changed.emit(player_id)


func can_build(player_id: int, entity_data: EntityData) -> bool:
    # Cheat mode: bypass all checks
    if Cheats.no_prereqs:
        return true

    var result := true

    # Tech level check — -1 is never buildable; otherwise the house must
    # have reached the type's level.
    if entity_data.tech_level == -1:
        result = false
    elif result:
        var player := PlayerManager.get_player_data(player_id)
        if player == null or player.tech_level < entity_data.tech_level:
            result = false

    # Build limit check
    if result and entity_data.build_limit > 0:
        var count := get_build_count(player_id, entity_data.id)
        if count >= entity_data.build_limit:
            result = false

    # Prerequisite (OR) — must own at least one
    if result and entity_data.prerequisite.size() > 0:
        var has_one := false
        if _player_buildings.has(player_id):
            for prereq in entity_data.prerequisite:
                if _player_buildings[player_id].has(prereq):
                    has_one = true
                    break
        if not has_one:
            result = false

    # Prerequisite necessary (AND) — must own all
    if result:
        if _player_buildings.has(player_id):
            for prereq in entity_data.prerequisite_necessary:
                if not _player_buildings[player_id].has(prereq):
                    result = false
                    break
        elif entity_data.prerequisite_necessary.size() > 0:
            result = false

    # Factory check — must own a building that produces this queue type
    if result and not entity_data.buildable_queue.is_empty():
        var has_factory := false
        if _player_buildings.has(player_id):
            for owned_eid in _player_buildings[player_id]:
                var owned_data := EntityFactory.get_entity_data(owned_eid)
                if owned_data and owned_data.factory == entity_data.buildable_queue:
                    has_factory = true
                    break
        if not has_factory:
            result = false

    return result


func get_build_count(player_id: int, entity_id: String) -> int:
    if not _player_buildings.has(player_id):
        return 0
    return _player_buildings[player_id].get(entity_id, 0)


func get_player_buildings(player_id: int) -> Dictionary:
    return _player_buildings.get(player_id, {})
