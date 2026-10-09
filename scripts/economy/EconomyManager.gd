extends Node

signal credits_changed(player_id: int, new_balance: int, reason: String, category: String)
signal insufficient_funds(player_id: int, cost: int, balance: int)

const DEFAULT_CATEGORY := "tiberium"

## Last category resolved from active rules — the fallback when no rules load.
var _last_category: String = DEFAULT_CATEGORY


## The active game's primary resource category. Caches the last resolved value
## so callers keep a sensible category when rules are unloaded.
func get_default_category() -> String:
    var rules := EntityFactory.get_global_rules()
    if rules and not rules.primary_resource_category.is_empty():
        _last_category = rules.primary_resource_category
    return _last_category


func get_balance(player_id: int, category: String = "") -> int:
    var data := _get_player_data(player_id)
    if category != "":
        return int(data.stored_by_category.get(category, 0))
    var total := data.free_credits
    for cat: String in data.stored_by_category:
        if _is_displayable(cat):
            total += int(data.stored_by_category[cat])
    return total


func can_afford(player_id: int, cost: int) -> bool:
    return get_balance(player_id) >= cost


func deduct(player_id: int, cost: int, reason: String, category: String = "") -> bool:
    if category.is_empty():
        category = get_default_category()
    # Cheat mode: no cost
    if Cheats.no_cost:
        return true

    var data := _get_player_data(player_id)
    var total := get_balance(player_id)
    if total < cost:
        insufficient_funds.emit(player_id, cost, total)
        return false
    # Spend stored credits first; the deficit comes from free credits.
    var stored := int(data.stored_by_category.get(category, 0))
    var taken_from_stored := mini(cost, stored)
    data.stored_by_category[category] = stored - taken_from_stored
    data.free_credits -= cost - taken_from_stored
    credits_changed.emit(player_id, get_balance(player_id), reason, category)
    return true


func add(
    player_id: int,
    amount: int,
    reason: String,
    category: String = "",
    is_free: bool = false,
) -> void:
    if category.is_empty():
        category = get_default_category()
    var data := _get_player_data(player_id)
    if is_free:
        data.free_credits += amount
    else:
        data.stored_by_category[category] = int(data.stored_by_category.get(category, 0)) + amount
    credits_changed.emit(player_id, get_balance(player_id), reason, category)


func get_storage_capacity(player_id: int, category: String = "") -> int:
    if category.is_empty():
        category = get_default_category()
    # Capacity is the sum of each owned building's declared share for the category.
    # ponytail: no cache — small owned set, runs on credits_changed not per frame.
    var capacity := 0
    var owned: Dictionary = PrerequisiteSystem.get_player_buildings(player_id)
    for entity_id: String in owned:
        var data := EntityFactory.get_entity_data(entity_id)
        if data == null:
            continue
        capacity += int(data.storage_capacity.get(category, 0)) * int(owned[entity_id])
    return capacity


func _is_displayable(category: String) -> bool:
    var rules := EntityFactory.get_global_rules()
    if not rules:
        return true
    var rt: ResourceType = rules.get_resource_type(category)
    if not rt:
        for id: String in rules.resource_types:
            var candidate: ResourceType = rules.resource_types[id]
            if candidate.category == category:
                rt = candidate
                break
    return rt.display_in_hud if rt else true


func _get_player_data(player_id: int) -> PlayerData:
    return PlayerManager.get_player_data(player_id)
