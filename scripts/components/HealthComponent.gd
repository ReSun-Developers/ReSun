class_name HealthComponent extends Node3D

signal health_changed(new_health: int, old_health: int)
signal damage_taken(damage_amount: int, damage_type: String)
signal healed(heal_amount: int)
signal health_zero
## Emitted on death with the last recorded attacker (null when killerless).
signal killed(killer: Node3D)

@export_range(0, 65535) var max_health: int = 100
@export_range(0, 65535) var current_health: int = 100:
    set(value):
        var old_health = current_health
        current_health = clampi(value, 0, max_health)
        if old_health != current_health:
            health_changed.emit(current_health, old_health)

## Last entity to deal damage to this one, used for kill credit.
var last_attacker: Node3D = null
## World point the damage landed at, when the caller knows it (a weapon impact).
## Vector3.INF when unknown; impact-effect placement falls back to the entity
## origin, so non-combat damage (crush, drowning) stays unchanged.
var last_impact_pos: Vector3 = Vector3.INF


func configure(data: EntityData) -> void:
    if data.strength > 0:
        max_health = data.strength
        current_health = data.spawn_health if data.spawn_health > 0 else data.strength


func take_damage(
    damage: int, damage_type: String = "", source: Node3D = null, impact_pos: Vector3 = Vector3.INF
) -> int:
    if damage <= 0 or current_health <= 0:
        return 0
    last_attacker = source
    last_impact_pos = impact_pos
    var applied := _apply_veteran_armor(damage)
    current_health -= applied
    damage_taken.emit(applied, damage_type)
    if current_health <= 0:
        health_zero.emit()
        killed.emit(last_attacker)
    return applied


func _apply_veteran_armor(damage: int) -> int:
    var parent := get_parent()
    if parent == null:
        return damage
    var stats := parent.get_node_or_null("StatsComponent") as StatsComponent
    if not stats or stats.veteran_level <= 0:
        return damage
    var rules := GlobalRules.get_current()
    if not rules:
        return damage
    var mult := rules.get_veteran_armor_multiplier(stats.veteran_level)
    return maxi(0, roundi(damage * mult))


func heal(amount: int) -> void:
    if amount <= 0:
        return
    var old_value = current_health
    current_health = clampi(current_health + amount, 0, max_health)
    if current_health > old_value:
        healed.emit(current_health - old_value)


func is_full_health() -> bool:
    return current_health >= max_health


func get_health_ratio() -> float:
    return float(current_health) / float(max_health) if max_health > 0 else 0.0


func reset_health() -> void:
    var old_value = current_health
    current_health = max_health
    if old_value != current_health:
        healed.emit(current_health - old_value)


func kill(source: Node3D = null) -> void:
    if current_health <= 0:
        return
    if source:
        last_attacker = source
    current_health = 0
    health_zero.emit()
    killed.emit(last_attacker)
