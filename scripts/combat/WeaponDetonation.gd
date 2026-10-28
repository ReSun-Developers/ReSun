class_name WeaponDetonation extends RefCounted

## One weapon impact: victim resolution, impact point, warhead damage, cell
## overlays, and the single impact report. Shared by instant fire and projectile
## arrival, so the two paths cannot drift.

## Twice the projectile contact distance; arrivals within it snap to the
## victim centre.
const SNAP_RADIUS: float = 2.0


## Typed outcome of one detonation.
class Impact:
    var position: Vector3 = Vector3.INF
    var victim: Node3D = null
    var damage: int = 0
    var entity_hit: bool = false
    var overlay_hit: bool = false


## Resolves one weapon impact. `target` is the entity target, or null for a
## ground shot where `ground_pos` is the ordered point. `arrival_pos` is the
## projectile's arrival position, or Vector3.INF for instant fire.
## `effective_damage` is the shooter's veteran-boosted base damage; a negative
## value falls back to `weapon.damage`.
static func detonate(
    weapon: WeaponData,
    shooter: Node3D,
    effective_damage: int,
    target: Node3D,
    ground_pos: Vector3 = Vector3.INF,
    arrival_pos: Vector3 = Vector3.INF
) -> Impact:
    var impact := Impact.new()
    if weapon == null:
        return impact
    var base_damage := effective_damage
    if base_damage < 0:
        base_damage = weapon.damage
    var victim := target
    var impact_pos := Vector3.INF
    if target == null:
        impact_pos = ground_pos if ground_pos.is_finite() else arrival_pos
        if not impact_pos.is_finite():
            return impact
        if SpatialHash.instance:
            victim = SpatialHash.instance.resolve_cell_victim(
                CellUtil.world_to_cell(impact_pos), impact_pos, shooter
            )
    else:
        impact_pos = _entity_impact_pos(target, shooter, arrival_pos)
    impact.position = impact_pos
    impact.victim = victim
    var resolved_damageable := false
    if is_instance_valid(victim) and not SpatialHash.is_overlay_entity(victim):
        var health := victim.get_node_or_null("HealthComponent") as HealthComponent
        if health:
            impact.entity_hit = true
            resolved_damageable = true
            impact.damage += health.take_damage(
                _damage_for(weapon, base_damage, victim), weapon.warhead, shooter, impact_pos
            )
    var warhead := _warhead(weapon.warhead)
    if warhead != null and SpatialHash.instance != null:
        var exclude: Node3D = victim if impact.entity_hit else null
        for overlay in SpatialHash.instance.find_cell_overlays(
            CellUtil.world_to_cell(impact_pos), warhead, exclude
        ):
            var overlay_node := overlay as Node3D
            if overlay_node == null:
                continue
            var overlay_health := (
                overlay_node.get_node_or_null("HealthComponent") as HealthComponent
            )
            if overlay_health == null:
                continue
            resolved_damageable = true
            var overlay_damage := _damage_for(weapon, base_damage, overlay_node)
            if overlay_damage <= 0:
                continue
            impact.damage += overlay_health.take_damage(
                overlay_damage, weapon.warhead, shooter, impact_pos
            )
            impact.overlay_hit = true
    if impact.damage > 0 or not resolved_damageable:
        _play_impact(weapon.warhead, impact_pos)
    return impact


## Impact point for an entity target: nearest footprint point for a structure,
## otherwise the victim centre (a close projectile arrival snaps onto it).
static func _entity_impact_pos(victim: Node3D, shooter: Node3D, arrival_pos: Vector3) -> Vector3:
    var stats := victim.get_node_or_null("StatsComponent") as StatsComponent
    if stats and stats.is_structure():
        var foundation := victim.get_node_or_null("FoundationComponent") as FoundationComponent
        if foundation and is_instance_valid(shooter):
            return foundation.nearest_world_point(shooter.global_position)
        if arrival_pos.is_finite():
            return arrival_pos
        return victim.global_position
    if arrival_pos.is_finite():
        if arrival_pos.distance_to(victim.global_position) <= SNAP_RADIUS:
            return victim.global_position
        return arrival_pos
    return victim.global_position


static func _damage_for(weapon: WeaponData, base_damage: int, victim: Node3D) -> int:
    var stats := victim.get_node_or_null("StatsComponent") as StatsComponent
    var armor := stats.armor if stats else "none"
    return GlobalRules.compute_warhead_damage(base_damage, weapon.warhead, armor)


static func _warhead(warhead_id: String) -> WarheadData:
    var rules := GlobalRules.get_current()
    return rules.get_warhead(warhead_id) if rules else null


static func _play_impact(warhead_id: String, position: Vector3) -> void:
    var main_loop := Engine.get_main_loop()
    if main_loop == null:
        return
    var fx: Node = main_loop.root.get_node_or_null("FxSystem")
    if fx != null and fx.has_method("play_impact"):
        fx.call("play_impact", warhead_id, position)
