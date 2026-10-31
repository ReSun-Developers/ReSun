class_name ProjectileController extends Area3D

## Runtime projectile: flies from the muzzle toward its target and hands its
## typed damage to WeaponDetonation on arrival. Flight behavior is picked from
## ProjectileData flags (teleport-detonate for invisible, straight/homing
## flight otherwise) — one controller, data-driven branches, mirroring how
## MovementController resolves locomotors.

## Emitted at the detonation point after damage has been forwarded.
signal impacted(position: Vector3)

## Detonation trigger: within this distance of the target counts as contact.
const SNAP_DISTANCE: float = 1.0

## Fallback degrees/second per unit of ProjectileData.homing_turn_rate when no
## rules are active.
const DEFAULT_TURN_DEG_PER_SEC_PER_UNIT: float = 60.0

var _data: ProjectileData
var _weapon: WeaponData
var _shooter: Node3D
var _shooter_player_id: int = -1
## Shooter's veteran-boosted damage, resolved at fire time. Negative means the
## caller supplied none, so the weapon's base damage is used.
var _effective_damage: int = -1
var _target: Node3D
## Ordered impact point. Always valid: for an entity target it tracks the
## entity, for a ground (force-fire) shot it is the point the player picked.
var _last_known_target_pos: Vector3 = Vector3.ZERO
## True when the shot was ordered at a position rather than an entity, so it
## detonates on arrival instead of vanishing when the entity is gone.
var _ground_shot: bool = false
var _heading: Vector3 = Vector3.FORWARD
var _speed: float = 0.0
var _max_range: float = 0.0
var _traveled: float = 0.0
var _age_frames: int = 0
var _armed: bool = false
var _detonated: bool = false
var _prev_target_dist: float = -1.0
var _target_mask: int = 0
var _spawn_origin: Vector3 = Vector3.ZERO
var _has_spawn_origin: bool = false

@onready var _cast: ShapeCast3D = $ShapeCast3D
@onready var _visual: Node3D = $Visual


## Configures the projectile before it enters the tree. Call once. Node
## children are applied in _ready, so setup only stores pure values.
## `target_pos` is the ordered impact point; pass it for ground shots so the
## projectile has somewhere to fly when there is no entity to track.
func setup(
    data: ProjectileData,
    weapon: WeaponData,
    shooter: Node3D,
    target: Node3D,
    target_pos: Vector3 = Vector3.INF,
    effective_damage: int = -1,
) -> void:
    _data = data
    _weapon = weapon
    _shooter = shooter
    _target = target
    _effective_damage = effective_damage if effective_damage >= 0 else weapon.damage
    _speed = resolve_speed(data, weapon, GlobalRules.get_current())
    _max_range = weapon.attack_range * CellUtil.CELL_SIZE
    if target:
        _last_known_target_pos = target.global_position
        # Combat stops a building attacker at weapon range from the nearest
        # footprint edge, but the projectile flies to the (further) footprint
        # centre. Extend reach by the half-diagonal so the centre stays inside
        # max range; without this a physical shot fizzles before the wall.
        var stats := target.get_node_or_null("StatsComponent") as StatsComponent
        var fc := target.get_node_or_null("FoundationComponent") as FoundationComponent
        if stats and stats.is_structure() and fc:
            var hx := fc.foundation.x * CellUtil.CELL_SIZE * 0.5
            var hz := fc.foundation.y * CellUtil.CELL_SIZE * 0.5
            _max_range += Vector2(hx, hz).length()
    elif target_pos.is_finite():
        _last_known_target_pos = target_pos
        _ground_shot = true
    var shooter_stats := (
        shooter.get_node_or_null("StatsComponent") as StatsComponent if shooter else null
    )
    _shooter_player_id = shooter_stats.player_id if shooter_stats else -1
    if data.targets_ground:
        _target_mask |= HitboxComponent.LAYER_HITBOX_GROUND | HitboxComponent.LAYER_HITBOX_BUILDING
    if data.targets_air:
        _target_mask |= HitboxComponent.LAYER_HITBOX_AIR


## Overrides the spawn position (e.g. a turret muzzle world position) before the
## projectile enters the tree. Without it, _ready falls back to shooter + FLH.
func set_spawn_origin(origin: Vector3) -> void:
    _spawn_origin = origin
    _has_spawn_origin = true


## Speed precedence: ProjectileData.speed_override > WeaponData.speed > rules default.
static func resolve_speed(data: ProjectileData, weapon: WeaponData, rules: GlobalRules) -> float:
    if data and data.speed_override > 0.0:
        return data.speed_override
    if weapon and weapon.speed > 0.0:
        return weapon.speed
    if rules:
        return rules.default_projectile_speed
    return 0.0


func _ready() -> void:
    _cast.collision_mask = _target_mask
    if _data.is_invisible:
        _visual.visible = false
        set_physics_process(false)
        _teleport_detonate()
        return
    _apply_tint()
    global_position = (
        _spawn_origin if _has_spawn_origin else _shooter.global_transform * _weapon.fire_offset
    )
    _aim_heading_at_target()


## Points the heading at the impact point from the spawn position. Without this
## the heading stays at Vector3.FORWARD: non-guided projectiles fly pure -Z and
## guided ones instantly overshoot-detonate when the target starts out behind
## them (distance increases during the first frames). Falls back to the ordered
## position so ground shots aim somewhere too.
func _aim_heading_at_target() -> void:
    var aim := _last_known_target_pos
    if is_instance_valid(_target):
        aim = _target.global_position
    var to_target := aim - global_position
    if not to_target.is_zero_approx():
        _heading = to_target.normalized()


func _physics_process(delta: float) -> void:
    if _detonated or is_queued_for_deletion() or not _data or not _weapon:
        return
    _age_frames += 1
    if _age_frames > _data.arm_delay:
        _armed = true
    var advance := _speed * delta
    _traveled += advance
    var target_pos := _last_known_target_pos
    var target_valid := is_instance_valid(_target)
    if target_valid:
        target_pos = _target.global_position
        _last_known_target_pos = target_pos
    if (target_valid or _ground_shot) and _data.is_guided:
        _steer_toward(target_pos, delta)
    if not _armed:
        # Unarmed projectiles ignore every hitbox: no cast, no proximity.
        global_position += _heading * advance
        _update_visual_facing()
        return
    # Sweep the segment about to be traveled BEFORE moving, so fast
    # projectiles cannot tunnel through thin hitboxes.
    var hit_victim := _cast_along_motion(_heading * advance)
    if hit_victim:
        _detonate_on(hit_victim)
        return
    global_position += _heading * advance
    _update_visual_facing()
    if not target_valid:
        var remaining := global_position.distance_to(_last_known_target_pos)
        # Ground shots have no live target to invalidate them, so they must be
        # consumed at max range; otherwise a non-converging guided ground shot
        # orbits forever (the entity-path range guard below is unreachable).
        if _ground_shot and _traveled >= _max_range:
            queue_free()
        # Reached the point, or started past it and moved away from it.
        elif remaining <= advance or (_prev_target_dist >= 0.0 and remaining > _prev_target_dist):
            if _ground_shot:
                _detonate_on(null)
            else:
                # The entity this shot was aimed at is gone: consume the shot
                # without a blast, the long-standing behaviour for a dead target.
                queue_free()
        else:
            _prev_target_dist = remaining
        return
    var dist := global_position.distance_to(target_pos)
    if dist <= SNAP_DISTANCE:
        _detonate_on(_target)
        return
    if _prev_target_dist >= 0.0 and dist > _prev_target_dist:
        _detonate_on(_target)
        return
    _prev_target_dist = dist
    if _traveled >= _max_range:
        queue_free()


## Invisible family: no flight. Jump onto the impact point and detonate at once —
## the same tick the legacy hitscan path applied damage, so behavior is
## preserved exactly. No physics-frame dependency.
func _teleport_detonate() -> void:
    if is_instance_valid(_target):
        global_position = _target.global_position
        _last_known_target_pos = global_position
        _detonate_on(_target)
    elif _ground_shot:
        global_position = _last_known_target_pos
        _detonate_on(null)
    else:
        queue_free()


## Turns the heading toward the target, capped by the data's turn rate.
func _steer_toward(target_pos: Vector3, delta: float) -> void:
    var desired := (target_pos - global_position).normalized()
    if desired.is_zero_approx():
        return
    var angle := _heading.angle_to(desired)
    if angle <= 0.001:
        _heading = desired
        return
    var rules := GlobalRules.get_current()
    var turn_scale: float = (
        rules.homing_turn_per_sec_per_unit if rules else DEFAULT_TURN_DEG_PER_SEC_PER_UNIT
    )
    var max_angle := deg_to_rad(_data.homing_turn_rate * turn_scale) * delta
    if max_angle <= 0.0 or angle <= max_angle:
        _heading = desired
        return
    _heading = _heading.slerp(desired, max_angle / angle).normalized()


## Sweeps the collision shape along this frame's motion; returns the closest
## valid victim entity, or null. Segment casts cannot be tunneled through.
func _cast_along_motion(motion: Vector3) -> Node3D:
    if motion.is_zero_approx():
        return null
    _cast.target_position = motion
    _cast.force_shapecast_update()
    var best: Node3D = null
    var best_dist := motion.length() + 0.001
    for i in _cast.get_collision_count():
        var collider: Object = _cast.get_collider(i)
        var area := collider as Area3D
        if not area:
            continue
        var entity := area.get_parent() as Node3D
        if not entity or not _is_valid_victim(entity):
            continue
        var point: Vector3 = _cast.get_collision_point(i)
        var dist := global_position.distance_to(point)
        if dist < best_dist:
            best_dist = dist
            best = entity
    return best


## Shooter and same-team victims are immune; enemies, neutrals, and statless
## nodes detonate the projectile normally.
func _is_valid_victim(entity: Node3D) -> bool:
    if entity == _shooter:
        return false
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    if stats and stats.player_id >= 0 and _shooter_player_id >= 0:
        if not PlayerManager.is_enemy(_shooter_player_id, stats.player_id):
            return false
    return true


## Hands the detonation to WeaponDetonation, emits impacted with the resolved
## impact point, and frees the projectile. `victim` may be null: a ground shot
## then resolves the impact cell's occupant (the shooter excluded, allies
## included) and, failing that, hits nothing but the cell's overlays.
func _detonate_on(victim: Node3D) -> void:
    if _detonated:
        return
    _detonated = true
    var impact := WeaponDetonation.detonate(
        _weapon, _shooter, _effective_damage, victim, _last_known_target_pos, global_position
    )
    impacted.emit(impact.position)
    queue_free()


func _apply_tint() -> void:
    var mesh := _visual as MeshInstance3D
    if not mesh:
        return
    var mat := mesh.get_surface_override_material(0) as StandardMaterial3D
    if mat:
        mat.albedo_color = _data.tint_color


## Faces the visual along the heading. Near-vertical headings are skipped:
## look_at cannot resolve an up vector parallel to the view direction (AA
## engaging a target directly overhead).
func _update_visual_facing() -> void:
    if not _data.rotates_to_face or _heading.is_zero_approx():
        return
    if absf(_heading.y) > 0.999:
        return
    var to := global_position + _heading
    if global_position.distance_squared_to(to) <= 0.0001:
        return
    _visual.look_at(to, Vector3.UP)
