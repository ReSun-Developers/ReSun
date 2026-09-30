@tool
class_name CombatComponent extends Node3D

# TODO: Combat system is incomplete. When implemented, this component needs to:
# - Resolve WeaponData.projectile → ProjectileData for trajectory/visuals
# - Resolve WeaponData.warhead → WarheadData for damage type, armor multipliers, effects
# - Handle negative WeaponData.damage as healing (call HealthComponent.heal())
# - Apply WeaponData.ambient_damage for continuous-damage weapons (sonic, flame)
# - Check ProjectileData.targets_air / targets_ground for valid targets
# - Use ProjectileData.homing_turn_rate, arm_delay, sub_projectile_count
# - Use WarheadData.armor_damage_multipliers for per-armor damage calculation
# - Apply WarheadData.sets_on_fire, WarheadData.rocks_target, WarheadData.produces_sparks
# - Use ArtData fields: primary_fire_offset, barrel_length, sequence,
#   walk_frames, firing_frames, and the role-tagged animation clips, etc.

signal weapon_fired(weapon: WeaponData, target: Node3D)

## Instantiated for each shot when the weapon's projectile id resolves.
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/components/Projectile.tscn")

## World-space separation at which airborne attackers stop nudging each other.
const MIN_AIR_SEPARATION: float = 1.5

## Fallback logic rate: WeaponData.rate_of_fire is a rearm delay in logic
## frames; seconds_between_shots = rate_of_fire / rules.logic_fps, falling back
## to this when no rules are active.
const DEFAULT_LOGIC_FPS: float = 30.0

## Minimum seconds between chase re-plans; bounds re-plan cost to the enemy's
## actual motion rate (#284 budget) and stops target jitter from oscillating
## a MOVING leg.
const CHASE_REPLAN_MIN_INTERVAL: float = 0.15

## Backoff after a failed chase path, so an unreachable target does not retry
## pathfinding every physics tick.
const CHASE_RETRY_BACKOFF: float = 0.5

@export_group("Combat")
@export var weapons: Array[WeaponData] = []
@export var elite_weapons: Array[WeaponData] = []
@export var threat_posed: int = 0


## One firing channel per weapon mount group, or per body-mounted weapon. Each
## channel keeps its own cooldown and alignment state, so a unit can fire
## several weapons / turrets on independent schedules.
class FireChannel:
    var weapon: WeaponData = null
    ## Empty = body-mounted (whole body faces the target).
    var socket_ids: PackedStringArray = PackedStringArray()
    ## true = sockets yaw to aim; false = body must face the target.
    var yaw_free: bool = false
    var fire_mode: int = WeaponMountGroupData.FireMode.SALVO
    var fire_delay: float = 0.0
    var cooldown: float = 0.0
    var aimed: bool = false
    ## Wind-up accumulator for a SALVO fire_delay.
    var windup: float = 0.0
    ## Active STAGGER burst: index of the next socket to fire (-1 = none).
    var burst_index: int = -1
    var burst_timer: float = 0.0


var _channels: Array[FireChannel] = []
var _target: Node3D = null
## Engagement point in world space — the source of truth for a ground
## engagement (no entity) and the fallback for an entity one. Read through
## _engagement_pos(), never directly.
var _target_pos: Vector3 = Vector3.ZERO
## Whether the engagement was entered through an entity rather than a position.
## A freed entity reference compares equal to null but is still not a valid
## instance, so the tick-time validity check needs this to tell "the target
## vanished" apart from "there never was one".
var _target_is_entity: bool = false
## Target's foundation, resolved once on set_target so range/approach/facing can
## measure to the nearest footprint point without a node lookup per tick.
var _target_foundation: FoundationComponent = null
var _attack_active: bool = false
var _rotation_completed: bool = false
var _mc_connected: bool = false
var _combat_move: bool = false
## Stand-and-shoot: when true, never issue chase/approach moves; if the target
## leaves weapon range the engagement is cleared instead (Mode A guard #261).
var _hold_ground: bool = false
var _connected_health_target: Node3D = null
var _fire_count: int = 0
## Grid cell of the target when the current chase leg was planned. A leg is
## stale the moment the target leaves this cell, so the chase can re-plan
## obstacle-aware instead of walking a straight line through new blockers.
var _chase_leg_enemy_cell: Vector2i = Vector2i.ZERO
var _last_chase_replan_time: float = 0.0
var _chase_retry_after: float = 0.0
var _logged_unreachable: Node3D = null
## Sibling PowerComponent, resolved once — components attach before tree entry.
## Non-null only for entities that require power; the offline gate then holds
## fire while retaining the current target for seamless power restoration.
var _power_component: PowerComponent = null
var _power_resolved: bool = false
## Sibling TurretComponent, resolved once. Non-null only for entities whose art
## declares sockets; it owns the per-socket yaw used for aim and rendering.
var _turret: TurretComponent = null
var _turret_resolved: bool = false


func configure(data: EntityData) -> void:
    weapons = data.weapons
    elite_weapons = data.elite_weapons
    threat_posed = data.threat_posed
    _build_channels(data.resolved_mount_groups(), data.art_data)


## Rebuilds firing channels from the given mount groups. A weapon not covered by
## a group becomes a body-mounted channel. Empty groups = all weapons body-mounted.
func _build_channels(groups: Array[WeaponMountGroupData], art_data: ArtData) -> void:
    _channels.clear()
    var covered: Dictionary = {}
    for group in groups:
        if group == null or group.weapon_index < 0 or group.weapon_index >= weapons.size():
            continue
        var weapon := weapons[group.weapon_index]
        if weapon == null:
            continue
        var channel := FireChannel.new()
        channel.weapon = weapon
        channel.socket_ids = group.socket_ids
        channel.fire_mode = group.fire_mode
        channel.fire_delay = group.fire_delay
        channel.yaw_free = _sockets_yaw_free(group.socket_ids, art_data)
        covered[group.weapon_index] = true
        _channels.append(channel)
    for i in weapons.size():
        if covered.has(i) or weapons[i] == null:
            continue
        var body_channel := FireChannel.new()
        body_channel.weapon = weapons[i]
        _channels.append(body_channel)


## Legacy/test helper: builds body-mounted channels from `weapons` and resets
## cooldowns. Production path is configure() → _build_channels().
func _init_cooldowns() -> void:
    var none: Array[WeaponMountGroupData] = []
    _build_channels(none, null)


## A group's sockets are all rotatable, or the group is body-facing.
func _sockets_yaw_free(socket_ids: PackedStringArray, art_data: ArtData) -> bool:
    if socket_ids.is_empty() or art_data == null:
        return false
    for socket_id in socket_ids:
        var socket := art_data.get_socket(socket_id)
        if socket == null or not socket.yaw_free:
            return false
    return true


func get_current_weapon() -> WeaponData:
    if _channels.is_empty():
        return null
    return _channels[0].weapon


func get_effective_damage(weapon: WeaponData) -> int:
    if not weapon:
        return 0
    var stats := get_parent().get_node_or_null("StatsComponent") as StatsComponent
    if not stats or stats.veteran_level <= 0:
        return weapon.damage
    var rules := GlobalRules.get_current()
    if not rules:
        return weapon.damage
    var mult := rules.get_veteran_combat_multiplier(stats.veteran_level)
    return roundi(weapon.damage * mult)


func get_weapon_count() -> int:
    return weapons.size()


func get_target() -> Node3D:
    return _target


## True while any engagement is live — an entity target or a ground position.
## Consumers that only care "is this unit busy attacking" must use this rather
## than get_target(), which is null for force-fire at the ground.
func is_engaged() -> bool:
    return _attack_active


## World point the engagement is firing at, for a target line drawn to it: the
## entity's own position for an entity target (its centre, tracked as it moves)
## or the ordered cell centre for a ground engagement. This is the centre, not
## the footprint-nearest aim point — range/facing use `_effective_target_pos()`.
func get_engagement_position() -> Vector3:
    return _engagement_pos()


func set_target(entity: Node3D, hold_ground: bool = false) -> void:
    if entity == null:
        # A null here would engage at whatever position the previous target left
        # behind. Use set_ground_target() for a position, clear_target() to end.
        push_error("CombatComponent: set_target(null) — use set_ground_target() or clear_target()")
        return
    _target = entity
    _target_is_entity = true
    _target_foundation = null
    _target_pos = entity.global_position
    # Match GuardComponent's classifier: only structures get footprint
    # geometry, so a multi-cell non-structure measures to its origin.
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    if stats and stats.is_structure():
        _target_foundation = entity.get_node_or_null("FoundationComponent") as FoundationComponent
    _begin_engagement(hold_ground)


## Ground engagement: fire at a world position with no entity target. The
## engagement repeats on cooldown until a player move, the Stop command, or the
## shooter's death — a position never invalidates itself.
func set_ground_target(pos: Vector3, hold_ground: bool = false) -> void:
    _target = null
    _target_is_entity = false
    _target_foundation = null
    # Fire at the cell centre, not the exact click: the impact point stays put
    # whether or not an entity stands there. Y is kept so a deck-level pick
    # still aims at the deck surface.
    var center := CellUtil.cell_to_world(CellUtil.world_to_cell(pos))
    _target_pos = Vector3(center.x, pos.y, center.z)
    _begin_engagement(hold_ground)


## Shared engagement entry: both set_target() and set_ground_target() reset the
## same runtime state, stop the current move and, unless hold-ground, approach.
func _begin_engagement(hold_ground: bool) -> void:
    _attack_active = true
    _rotation_completed = false
    _hold_ground = hold_ground
    _chase_retry_after = 0.0
    _logged_unreachable = null
    _reset_channel_runtime()
    _connect_mc_signal()
    _connect_health_signal()
    var mc := get_parent().get_node_or_null("MovementController") as MovementController
    if mc:
        if mc.is_airborne_jumpjet():
            mc.cancel_move_retain_vertical()
        else:
            mc.stop()
    if not hold_ground:
        _move_toward_target(true)


func clear_target() -> void:
    _disconnect_health_signal()
    _target = null
    _target_is_entity = false
    _target_pos = Vector3.ZERO
    _target_foundation = null
    _attack_active = false
    _rotation_completed = false
    _hold_ground = false
    _logged_unreachable = null
    _reset_channel_runtime()


## Clears per-channel burst/wind-up state when the engagement changes.
func _reset_channel_runtime() -> void:
    for channel in _channels:
        channel.burst_index = -1
        channel.burst_timer = 0.0
        channel.windup = 0.0
        channel.aimed = false


func validate(data: EntityData) -> PackedStringArray:
    var errors: PackedStringArray = []
    if data.weapons.is_empty():
        errors.append("CombatComponent: '%s' has no weapons" % data.id)
    for weapon in data.weapons:
        if weapon:
            var weapon_errors := weapon.validate()
            for err in weapon_errors:
                errors.append("CombatComponent: '%s' - %s" % [data.id, err])
    return errors


func get_cursor_for_target(target: Node3D, _target_cell: Vector2i) -> CursorState.Type:
    if not target or weapons.is_empty():
        return CursorState.Type.DEFAULT
    var stats := target.get_node_or_null("StatsComponent") as StatsComponent
    if stats and stats.player_id >= 0:
        if PlayerManager.is_enemy(stats.player_id, PlayerManager.get_local_player_id()):
            return CursorState.Type.ATTACK
    return CursorState.Type.DEFAULT


func get_order_for_target(
    target: Node3D,
    _target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary,
) -> OrderResult:
    if weapons.is_empty():
        return null
    var queued: bool = modifiers.get(OrderResult.MOD_QUEUED, false)
    # Force-fire bypasses both the "is there a target at all" test and the
    # ownership test: ground cells, allies, own units and neutrals are all
    # legal targets while the modifier is held.
    if modifiers.get(OrderResult.MOD_FORCE_ATTACK, false):
        if target == null:
            return OrderResult.new(
                CursorState.Type.ATTACK,
                30,
                null,
                target_pos,
                queued,
                func(): set_ground_target(target_pos),
                VoiceData.EVENT_ATTACK,
            )
        return OrderResult.new(
            CursorState.Type.ATTACK,
            30,
            target,
            target_pos,
            queued,
            func(): _attack(target),
            VoiceData.EVENT_ATTACK,
        )
    if target == null:
        return null
    var stats := target.get_node_or_null("StatsComponent") as StatsComponent
    if stats and stats.player_id >= 0:
        var local_id := PlayerManager.get_local_player_id()
        if PlayerManager.is_enemy(stats.player_id, local_id):
            return OrderResult.new(
                CursorState.Type.ATTACK,
                30,
                target,
                target_pos,
                queued,
                func(): _attack(target),
                VoiceData.EVENT_ATTACK,
            )
    return null


func _attack(target: Node3D) -> void:
    set_target(target)


func _physics_process(delta: float) -> void:
    if Engine.is_editor_hint():
        return
    _resolve_siblings()
    if _power_component and not _power_component.is_online:
        # Powered down: hold fire and freeze the engagement — no acquisition,
        # no shots, no chase moves. The target is kept so restoration resumes.
        return
    if not _attack_active:
        return
    # An entity target can vanish (freed node); a ground position cannot, so
    # the validity check must not apply to it or the engagement clears each tick.
    # Note a freed entity reads as `== null`, so the entity/ground distinction
    # comes from _target_is_entity rather than from the reference itself.
    if _target_is_entity and not is_instance_valid(_target):
        clear_target()
        return
    if _channels.is_empty():
        clear_target()
        return
    if not _target_in_range():
        if _hold_ground:
            clear_target()
        else:
            # Keep turrets trained on the target while closing, so they track
            # continuously instead of freezing until the target re-enters range.
            _aim_turrets(delta)
            _move_toward_target()
        return
    var close := _horizontal_distance() <= CellUtil.CELL_SIZE
    # Body-facing is evaluated once per tick for body/fixed channels so
    # face_toward is not advanced multiple times in one frame.
    var body_aligned := true
    if _needs_body_facing() and not close:
        body_aligned = _is_facing_target(delta)
    for channel in _channels:
        _tick_channel(channel, delta, body_aligned, close)


## Resolves sibling components once, lazily (components attach before tree entry).
func _resolve_siblings() -> void:
    if _turret_resolved and _power_resolved:
        return
    var parent := get_parent()
    if parent == null:
        return
    if not _turret_resolved:
        _turret_resolved = true
        _turret = parent.get_node_or_null("TurretComponent") as TurretComponent
    if not _power_resolved:
        _power_resolved = true
        _power_component = parent.get_node_or_null("PowerComponent") as PowerComponent


## Whether any channel requires the body to face the target.
func _needs_body_facing() -> bool:
    for channel in _channels:
        if not channel.yaw_free:
            return true
    return false


## Slews every yaw-free mount at the target. Used on the chase path (target out
## of range); in-range ticks aim via _tick_channel.
func _aim_turrets(delta: float) -> void:
    if _turret == null or not _attack_active:
        return
    for channel in _channels:
        if not channel.yaw_free:
            continue
        for socket_id in channel.socket_ids:
            _turret.slew(socket_id, _effective_target_pos(), delta)


## Raw engagement point: the entity's origin while one is held, otherwise the
## ordered ground position (or this entity when idle, so no caller ever reads a
## stale coordinate).
func _engagement_pos() -> Vector3:
    if is_instance_valid(_target):
        return _target.global_position
    if _attack_active:
        return _target_pos
    return global_position


## Engagement point on the target: the nearest point of a building's foundation
## footprint so range/approach/facing stop at the wall instead of the footprint
## center. Point targets (units, 1x1 buildings) and ground positions use the
## entity origin / ordered position directly.
func _effective_target_pos() -> Vector3:
    if _target_foundation and is_instance_valid(_target_foundation):
        return _target_foundation.nearest_world_point(global_position)
    return _engagement_pos()


func _horizontal_distance() -> float:
    if not _attack_active:
        return INF
    var to_target := _effective_target_pos() - global_position
    return Vector3(to_target.x, 0.0, to_target.z).length()


## In range of the longest-reaching weapon; each channel then checks its own
## weapon range inside _tick_channel.
func _target_in_range() -> bool:
    var weapon := _longest_range_weapon()
    if weapon == null:
        return false
    return _horizontal_distance() <= weapon.attack_range * CellUtil.CELL_SIZE


func _longest_range_weapon() -> WeaponData:
    var best: WeaponData = null
    for channel in _channels:
        if channel.weapon and (best == null or channel.weapon.attack_range > best.attack_range):
            best = channel.weapon
    return best


## Advances one channel: aim (every tick, so turrets track continuously), then
## fire subject to that channel's own cooldown, range, and fire discipline.
func _tick_channel(channel: FireChannel, delta: float, body_aligned: bool, close: bool) -> void:
    channel.cooldown = maxf(channel.cooldown - delta, 0.0)

    # Continue an in-flight STAGGER burst regardless of cooldown.
    if channel.burst_index >= 0:
        channel.burst_timer -= delta
        if channel.burst_timer <= 0.0:
            _fire_socket(channel, channel.burst_index)
            channel.burst_index += 1
            if channel.burst_index >= channel.socket_ids.size():
                channel.burst_index = -1
                channel.cooldown = _rof_seconds(channel.weapon)
            else:
                channel.burst_timer = maxf(channel.fire_delay, 0.0)
        return

    if channel.yaw_free and _turret:
        var aimed := true
        for socket_id in channel.socket_ids:
            if not _turret.slew(socket_id, _effective_target_pos(), delta):
                aimed = false
        channel.aimed = aimed
    else:
        channel.aimed = body_aligned
    if close:
        channel.aimed = true

    if channel.cooldown > 0.0:
        channel.windup = 0.0
        return
    if not _channel_in_range(channel):
        return
    if not channel.aimed:
        channel.windup = 0.0
        return

    # SALVO wind-up before the volley.
    if channel.fire_mode == WeaponMountGroupData.FireMode.SALVO and channel.fire_delay > 0.0:
        channel.windup += delta
        if channel.windup < channel.fire_delay:
            return

    channel.windup = 0.0
    _fire_channel(channel)


func _channel_in_range(channel: FireChannel) -> bool:
    if channel.weapon == null:
        return false
    return _horizontal_distance() <= channel.weapon.attack_range * CellUtil.CELL_SIZE


## Fires a channel's socket(s) per its fire discipline. SALVO and single-socket
## groups fire immediately; STAGGER schedules the rest of the burst.
func _fire_channel(channel: FireChannel) -> void:
    if channel.socket_ids.is_empty():
        _fire_weapon(channel.weapon, _target)
        channel.cooldown = _rof_seconds(channel.weapon)
        return
    if channel.fire_mode == WeaponMountGroupData.FireMode.STAGGER and channel.socket_ids.size() > 1:
        _fire_socket(channel, 0)
        channel.burst_index = 1
        channel.burst_timer = maxf(channel.fire_delay, 0.0)
        return
    for i in channel.socket_ids.size():
        _fire_socket(channel, i)
    channel.cooldown = _rof_seconds(channel.weapon)


func _fire_socket(channel: FireChannel, index: int) -> void:
    var muzzle := Vector3.INF
    var muzzle_basis := Basis()
    if _turret and index < channel.socket_ids.size():
        var muzzle_xform := _turret.get_muzzle_world_transform(channel.socket_ids[index])
        muzzle = muzzle_xform.origin
        muzzle_basis = muzzle_xform.basis
    _fire_weapon(channel.weapon, _target, muzzle, muzzle_basis)


func _rof_seconds(weapon: WeaponData) -> float:
    var rules := GlobalRules.get_current()
    var logic_fps: float = rules.logic_fps if rules else DEFAULT_LOGIC_FPS
    var base := maxf(weapon.rate_of_fire, 0.001) / logic_fps
    if not rules:
        return base
    var parent := get_parent()
    if parent == null:
        return base
    var stats := parent.get_node_or_null("StatsComponent") as StatsComponent
    if stats == null or stats.veteran_level <= 0:
        return base
    return base / rules.get_veteran_rof_multiplier(stats.veteran_level)


## Body-facing gate for body-mounted / fixed-socket weapons. Returns true when
## the attacker is aligned (or exempt): no MovementController sibling (buildings,
## speed = 0) — exempt means rotation is complete, so fire is never gated —
## or idle / waiting, where the body slews via face_toward so blocked
## attackers keep shooting once aligned. A live MOVING / ROTATING leg owns
## the yaw, so the gate holds fire for those ticks instead; the shot comes
## after the leg ends and the body has slewed onto the target.
func _is_facing_target(delta: float) -> bool:
    var entity := get_parent() as Node3D
    if not entity:
        _rotation_completed = true
        return true
    var mc := entity.get_node_or_null("MovementController") as MovementController
    if not mc:
        _rotation_completed = true
        return true
    if mc.is_moving() and not mc.is_waiting():
        return false
    _rotation_completed = mc.face_toward(_effective_target_pos(), delta)
    return _rotation_completed


func _fire_weapon(
    weapon: WeaponData,
    target: Node3D,
    muzzle_origin: Vector3 = Vector3.INF,
    muzzle_basis: Basis = Basis()
) -> void:
    if not muzzle_origin.is_finite():
        muzzle_origin = _body_muzzle_origin(weapon)
    var projectile_data: ProjectileData = _resolve_projectile(weapon)
    if projectile_data:
        _spawn_projectile(projectile_data, weapon, target, muzzle_origin)
    else:
        _apply_hitscan_damage(weapon, target)
    _fire_count += 1
    _play_fire_sound(weapon)
    _play_muzzle_fx(weapon, muzzle_origin, muzzle_basis)
    weapon_fired.emit(weapon, target)


## Body-mounted muzzle: the entity transform composed with the weapon's local
## fire offset (FLH), so the offset rotates with the body. Per-unit ArtData FLH
## belongs to #326.
func _body_muzzle_origin(weapon: WeaponData) -> Vector3:
    var shooter := get_parent() as Node3D
    if shooter == null:
        return global_transform * weapon.fire_offset
    return shooter.global_transform * weapon.fire_offset


## Resolves weapon.projectile through the GlobalRules registry; null when the
## id is empty or unresolvable, which falls back to direct hitscan damage.
func _resolve_projectile(weapon: WeaponData) -> ProjectileData:
    if weapon.projectile.is_empty():
        return null
    var rules := GlobalRules.get_current()
    if not rules:
        return null
    return rules.get_projectile(weapon.projectile)


func _spawn_projectile(
    data: ProjectileData, weapon: WeaponData, target: Node3D, muzzle_origin: Vector3
) -> void:
    var shooter := get_parent() as Node3D
    if not shooter:
        return
    var projectile := PROJECTILE_SCENE.instantiate() as ProjectileController
    if not projectile:
        return
    projectile.setup(data, weapon, shooter, target, _engagement_pos())
    projectile.set_spawn_origin(muzzle_origin)
    var container: Node = null
    var tree := shooter.get_tree()
    if tree:
        container = tree.current_scene
    if not container:
        container = shooter.get_parent()
    if not container:
        push_error("CombatComponent: no container for projectile spawn — shot consumed")
        projectile.free()
        return
    container.add_child(projectile)


func _apply_hitscan_damage(weapon: WeaponData, target: Node3D) -> void:
    # Impact point, not aim point: a building reads on the nearest footprint
    # point (so effects land on the wall), a ground shot on the cell centre.
    var impact_pos := _engagement_pos() if target == null else _victim_impact_pos(target)
    var victim := target
    if victim == null and SpatialHash.instance:
        # Ground engagement: the shot lands on the cell's occupant instead.
        victim = SpatialHash.instance.resolve_cell_victim(
            CellUtil.world_to_cell(impact_pos), impact_pos, get_parent() as Node3D
        )
    var entity_hit := false
    if victim != null and not SpatialHash.is_overlay_entity(victim):
        var health := victim.get_node_or_null("HealthComponent") as HealthComponent
        if health:
            entity_hit = true
            var target_stats := victim.get_node_or_null("StatsComponent") as StatsComponent
            var target_armor := target_stats.armor if target_stats else "none"
            var damage := GlobalRules.compute_warhead_damage(
                get_effective_damage(weapon), weapon.warhead, target_armor
            )
            health.take_damage(damage, weapon.warhead, get_parent() as Node3D, impact_pos)
    # An overlay (tiberium/bridge/ice) is left to the warhead-gated overlay pass:
    # a warhead without the matching flag deals no damage but the impact effect
    # still plays through the fallback below.
    var overlay_hit := _damage_cell_overlays(weapon, impact_pos, victim if entity_hit else null)
    if not entity_hit and not overlay_hit:
        EntityFactory.play_impact_effects_at(weapon.warhead, impact_pos)


## World point a direct hit on `entity` reads on: the nearest footprint point of
## a structure facing the shooter, otherwise the entity origin.
func _victim_impact_pos(entity: Node3D) -> Vector3:
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    if stats and stats.is_structure():
        var fc := entity.get_node_or_null("FoundationComponent") as FoundationComponent
        if fc:
            return fc.nearest_world_point(global_position)
    return entity.global_position


## Applies the warhead's cell-overlay damage (bridge, ice, tiberium) at the
## impact cell. Returns true when at least one overlay took the hit, so the
## caller knows whether the warhead's own impact effects already played through
## the damage choke point.
func _damage_cell_overlays(weapon: WeaponData, impact_pos: Vector3, exclude: Node3D) -> bool:
    if SpatialHash.instance == null:
        return false
    var rules := GlobalRules.get_current()
    if rules == null:
        return false
    var warhead := rules.get_warhead(weapon.warhead)
    if warhead == null:
        return false
    var shooter := get_parent() as Node3D
    var applied := false
    for overlay in SpatialHash.instance.find_cell_overlays(
        CellUtil.world_to_cell(impact_pos), warhead, exclude
    ):
        var health := overlay.get_node_or_null("HealthComponent") as HealthComponent
        if health == null:
            continue
        var overlay_stats := overlay.get_node_or_null("StatsComponent") as StatsComponent
        var overlay_armor := overlay_stats.armor if overlay_stats else "none"
        var damage := GlobalRules.compute_warhead_damage(
            get_effective_damage(weapon), weapon.warhead, overlay_armor
        )
        if damage <= 0:
            continue
        health.take_damage(damage, weapon.warhead, shooter)
        applied = true
    return applied


func _play_fire_sound(weapon: WeaponData) -> void:
    var report := weapon.sound_report
    if report.is_empty():
        return
    AudioManager.play_report(report.split(",", false), global_position)


## Plays the weapon's one-shot muzzle effect at the world muzzle transform
## (origin + socket yaw for turret mounts, identity basis for body mounts), so
## directional particle effects fire along the barrel. Fog gating lives in
## FxSystem.
func _play_muzzle_fx(weapon: WeaponData, muzzle_origin: Vector3, muzzle_basis: Basis) -> void:
    if weapon == null or weapon.muzzle_fx == null:
        return
    FxSystem.play(weapon.muzzle_fx, Transform3D(muzzle_basis, muzzle_origin))


func _move_toward_target(force: bool = false) -> void:
    var entity := get_parent() as Node3D
    if not entity:
        return
    var mc := entity.get_node_or_null("MovementController") as MovementController
    if not mc:
        return
    if not force and not _should_replan(mc):
        return
    var weapon := _longest_range_weapon()
    if not weapon:
        return
    var range_world := weapon.attack_range * CellUtil.CELL_SIZE
    var target_pos := _effective_target_pos()
    var to_target := target_pos - global_position
    var horizontal_distance := Vector3(to_target.x, 0.0, to_target.z).length()
    if horizontal_distance <= range_world:
        return
    var stop_pos: Vector3
    if mc.is_airborne_jumpjet():
        # Shortest air path: approach the target head-on to weapon range,
        # then nudge off any airborne jumpjets already there so the group
        # spreads dynamically instead of stacking on one point.
        var approach_dir := Vector3(to_target.x, 0.0, to_target.z).normalized()
        var base_pos := target_pos - approach_dir * range_world
        stop_pos = (
            base_pos
            + _air_repulsion(entity.global_position, _nearby_airborne_jumpjets(entity), range_world)
        )
        # Never push an attacker out of firing range: pull any overshoot
        # back onto the range circle so it fires on arrival instead of
        # bouncing back to re-approach.
        var stop_offset := target_pos - stop_pos
        if stop_offset.length() > range_world:
            stop_pos = target_pos - stop_offset.normalized() * range_world
    else:
        var angle := atan2(to_target.x, to_target.z)
        stop_pos = target_pos - Vector3(sin(angle) * range_world, 0.0, cos(angle) * range_world)
        # A chase stop can land inside a building footprint when the enemy hugs
        # a wall: relocate to the nearest passable cell so the destination is
        # never blocked before the move is even issued.
        stop_pos = CellUtil.cell_to_world(
            mc.find_nearest_free_cell(CellUtil.world_to_cell(stop_pos))
        )
        # Relocation can push the stop beyond weapon range (short-range units).
        # Pull it back inside the range circle so the attacker fires on arrival
        # instead of idling out of range and re-planning forever. If it still
        # cannot be kept in range and passable, back off like a failed path.
        var re_to_target := target_pos - stop_pos
        var re_dist := Vector3(re_to_target.x, 0.0, re_to_target.z).length()
        if re_dist > range_world + 0.01:
            var approach := Vector3(to_target.x, 0.0, to_target.z).normalized()
            var inner := maxf(range_world - CellUtil.CELL_SIZE, range_world * 0.5)
            stop_pos = target_pos - approach * inner
            stop_pos = CellUtil.cell_to_world(
                mc.find_nearest_free_cell(CellUtil.world_to_cell(stop_pos))
            )
            var re2 := Vector3(target_pos.x - stop_pos.x, 0.0, target_pos.z - stop_pos.z).length()
            if re2 > range_world + 0.01:
                _chase_retry_after = _now() + CHASE_RETRY_BACKOFF
                return
    _combat_move = true
    _chase_leg_enemy_cell = CellUtil.world_to_cell(_engagement_pos())
    _last_chase_replan_time = _now()
    mc.set_target_position(stop_pos, false, true)


## World-space positions of airborne jumpjets within the 3x3 cells around the
## entity, used to spread attacking jumpjets without hard reservation.
func _nearby_airborne_jumpjets(entity: Node3D) -> Array[Vector3]:
    var result: Array[Vector3] = []
    var cell := CellUtil.world_to_cell(entity.global_position)
    for dx in range(-1, 2):
        for dz in range(-1, 2):
            for entry in SpatialHash.instance.get_entries(cell + Vector2i(dx, dz)):
                var other := entry.node as Node3D
                if not is_instance_valid(other) or other == entity:
                    continue
                var other_mc := entry.mc as MovementController
                if other_mc and other_mc.is_airborne_jumpjet():
                    result.append(other.global_position)
    return result


## Push vector away from close airborne jumpjets, linearly tapering to zero at
## MIN_AIR_SEPARATION and capped so a cluster stays near attack range.
func _air_repulsion(from: Vector3, neighbors: Array[Vector3], range_world: float) -> Vector3:
    var push := Vector3.ZERO
    for other in neighbors:
        var diff := from - other
        diff.y = 0.0
        var dist := diff.length()
        if dist > 0.01 and dist < MIN_AIR_SEPARATION:
            push += diff / dist * (1.0 - dist / MIN_AIR_SEPARATION)
    var cap := minf(MIN_AIR_SEPARATION, range_world * 0.25)
    return push.limit_length(cap)


func _connect_mc_signal() -> void:
    if _mc_connected:
        return
    var entity := get_parent() as Node3D
    if not entity:
        return
    var mc := entity.get_node_or_null("MovementController") as MovementController
    if mc:
        mc.arrived.connect(_on_movement_arrived)
        mc.movement_started.connect(_on_movement_started)
        mc.pathfinding_failed.connect(_on_pathfinding_failed)
        _mc_connected = true


func _connect_health_signal() -> void:
    # Disconnect unconditionally and first: an entity → ground transition leaves
    # _target null, so bailing before the disconnect would leave the previous
    # entity's health_zero wired up — and its death would then clear_target()
    # out from under the player's ground engagement.
    _disconnect_health_signal()
    if not _target:
        return
    _connected_health_target = _target
    var hc := _target.get_node_or_null("HealthComponent") as HealthComponent
    if hc:
        hc.health_zero.connect(_on_target_health_zero)


func _disconnect_health_signal() -> void:
    if not _connected_health_target or not is_instance_valid(_connected_health_target):
        _connected_health_target = null
        return
    var hc := _connected_health_target.get_node_or_null("HealthComponent") as HealthComponent
    if hc and hc.health_zero.is_connected(_on_target_health_zero):
        hc.health_zero.disconnect(_on_target_health_zero)
    _connected_health_target = null


func _on_target_health_zero() -> void:
    clear_target()


func _on_movement_arrived(_position: Vector3) -> void:
    pass


func _on_movement_started() -> void:
    if _combat_move:
        _combat_move = false
        return
    clear_target()


func _on_pathfinding_failed() -> void:
    # A failed move never emits movement_started, so clear the combat-approach
    # flag here to avoid it consuming a later move order's signal.
    _combat_move = false
    _chase_retry_after = _now() + CHASE_RETRY_BACKOFF
    if is_instance_valid(_target) and _logged_unreachable != _target:
        _logged_unreachable = _target
        push_warning(
            (
                "[CombatComponent] chase pathfinding failed; target unreachable (retry in %.2fs)"
                % CHASE_RETRY_BACKOFF
            )
        )


## Whether a fresh approach move may be issued right now. Always true when the
## controller is idle or waiting; for a real MOVING/ROTATING leg only when the
## target has left the cell the leg was planned against (stale geometry) and the
## re-plan throttle has elapsed. False during the failed-path retry backoff.
func _should_replan(mc: MovementController) -> bool:
    var now := _now()
    if now < _chase_retry_after:
        return false
    if not _attack_active:
        return false
    if not mc.is_moving() or mc.is_waiting():
        return true
    if now - _last_chase_replan_time < CHASE_REPLAN_MIN_INTERVAL:
        return false
    return CellUtil.world_to_cell(_engagement_pos()) != _chase_leg_enemy_cell


func _now() -> float:
    return Time.get_ticks_msec() / 1000.0
