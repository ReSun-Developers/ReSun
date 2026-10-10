extends Node

## PrerequisiteSystem autoload — tracks player-owned buildings and checks
## prerequisites for entity buildability.

signal prerequisites_changed(player_id: int)

## Why a type is not buildable. The gate reports the first failing reason in a
## fixed order, mirroring the sequential checks below.
enum BuildReason {
    NONE,
    NOT_BUILDABLE,
    NEVER,
    TECH_LEVEL,
    BUILD_LIMIT,
    PREREQUISITE,
    PREREQUISITE_NECESSARY,
    NO_FACTORY,
}

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


## Clears all owned-building counts for a fresh match, so a previous match's
## map-authored buildings do not carry over. Emits for every affected player.
func reset_for_match() -> void:
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


## One build decision for a player and type: whether it is buildable and, when
## not, the first failing gate as a `BuildReason`. Reports the type's cost and a
## raw `owned_factory` fact (whether the player owns a producing building for the
## type's queue) computed independently of the outcome, so consumers such as the
## debug direct-deploy fallback can trust it even when the cheat bypasses the gate.
## Affordability is intentionally not considered here.
func evaluate_build(player_id: int, entity_data: EntityData) -> Dictionary:
    var owned_factory := _owns_factory_for(player_id, entity_data)
    var reason := _first_failing_reason(player_id, entity_data, owned_factory)
    return {
        "enabled": reason == BuildReason.NONE,
        "reason": reason,
        "cost": entity_data.cost,
        "owned_factory": owned_factory,
    }


func can_build(player_id: int, entity_data: EntityData) -> bool:
    return bool(evaluate_build(player_id, entity_data)["enabled"])


## First gate that fails, in fixed order, or `NONE` when the type is buildable.
## The `no_prereqs` cheat bypasses every gate but never changes `owned_factory`.
func _first_failing_reason(player_id: int, entity_data: EntityData, owned_factory: bool) -> int:
    var reason := BuildReason.NONE
    if not Cheats.no_prereqs:
        var player := PlayerManager.get_player_data(player_id)
        if not entity_data.buildable:
            reason = BuildReason.NOT_BUILDABLE
        elif entity_data.tech_level == -1:
            reason = BuildReason.NEVER
        elif player == null or player.tech_level < entity_data.tech_level:
            reason = BuildReason.TECH_LEVEL
        elif (
            entity_data.build_limit > 0
            and get_build_count(player_id, entity_data.id) >= entity_data.build_limit
        ):
            reason = BuildReason.BUILD_LIMIT
        elif (
            entity_data.prerequisite.size() > 0
            and not _owns_any(player_id, entity_data.prerequisite)
        ):
            reason = BuildReason.PREREQUISITE
        elif not _owns_all(player_id, entity_data.prerequisite_necessary):
            reason = BuildReason.PREREQUISITE_NECESSARY
        elif not entity_data.buildable_queue.is_empty() and not owned_factory:
            reason = BuildReason.NO_FACTORY
    return reason


func _owns_any(player_id: int, entity_ids: PackedStringArray) -> bool:
    if not _player_buildings.has(player_id):
        return false
    var owned: Dictionary = _player_buildings[player_id]
    for eid: String in entity_ids:
        if owned.has(eid):
            return true
    return false


func _owns_all(player_id: int, entity_ids: PackedStringArray) -> bool:
    if entity_ids.is_empty():
        return true
    if not _player_buildings.has(player_id):
        return false
    var owned: Dictionary = _player_buildings[player_id]
    for eid: String in entity_ids:
        if not owned.has(eid):
            return false
    return true


## Whether the player owns a building whose `factory` matches the type's queue.
## False when the type has no queue (the `no_factory` gate then does not apply).
## Most structures carry `buildable_queue = "BuildingType"`, so they require owning
## the matching producer (the construction yard) like any produced type.
func _owns_factory_for(player_id: int, entity_data: EntityData) -> bool:
    if entity_data.buildable_queue.is_empty():
        return false
    if not _player_buildings.has(player_id):
        return false
    var owned: Dictionary = _player_buildings[player_id]
    for owned_eid: String in owned:
        var owned_data := EntityFactory.get_entity_data(owned_eid)
        if owned_data and owned_data.factory == entity_data.buildable_queue:
            return true
    return false


func get_build_count(player_id: int, entity_id: String) -> int:
    if not _player_buildings.has(player_id):
        return 0
    return _player_buildings[player_id].get(entity_id, 0)


func get_player_buildings(player_id: int) -> Dictionary:
    return _player_buildings.get(player_id, {})
