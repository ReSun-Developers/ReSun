extends Node

## FxSystem autoload — plays one-shot `FxData` effects and gates them against
## fog of war for the local player.
##
## One-shot lifetime is a deterministic accumulator ticked by `_process`, so
## behavior is identical headless and testable. Particle effects additionally
## free on the engine's `finished` signal (accurate in-game; a no-op headless,
## where the accumulator remains the fallback).

## Minimum resolved lifetime so a zero/empty effect still frees in bounded time.
const MIN_DURATION: float = 0.05

## Default derived sprite lifetime when frames are missing.
const DEFAULT_SPRITE_TIME: float = 1.0

## Ceiling on a fog-frozen effect's total age before it is freed anyway, so a
## cell that never gets revealed cannot retain effects forever.
## ponytail: retention cap, raise if effects should survive very long fog.
const MAX_FROZEN_AGE: float = 30.0

## Particle fallback multiplier over `lifetime`. A one-shot's emission can
## spread across up to `lifetime` (explosiveness 0) and the last particle then
## lives a full `lifetime`, so `2 * lifetime` bounds every explosiveness value.
const PARTICLE_DURATION_CEILING: float = 2.0

## Live effects: each entry is
## {node: Node3D, time_left: float, age: float, frozen: bool, ignore_fog: bool}.
var _active: Array[Dictionary] = []


func _ready() -> void:
    ShroudSystem.state_changed.connect(_on_shroud_changed)


## Plays `fx` once at `global_transform`. Returns the spawned node, or `null`
## when the effect is invalid, has no valid parent, or is fog-gated.
## `ignore_fog` (editor previews) bypasses the spawn gate and freeze; `parent`
## overrides the default gameplay parent (used by the asset browser stage).
func play(
    fx: FxData, global_transform: Transform3D, ignore_fog := false, parent: Node = null
) -> Node3D:
    if fx == null:
        push_warning("FxSystem: play called with a null FxData")
        return null
    var errors := fx.validate()
    if not errors.is_empty():
        push_warning("FxSystem: invalid effect: %s" % ", ".join(errors))
        return null
    var host: Node = parent if parent != null else _effect_parent()
    if host == null:
        return null
    # Gate only when a shroud grid exists: scenes without one (pre-boot, tests)
    # must not suppress effects.
    if (
        not ignore_fog
        and ShroudSystem.is_grid_ready()
        and not ShroudSystem.is_cell_visible_to_local(
            CellUtil.world_to_cell(global_transform.origin)
        )
    ):
        return null
    var node := _build(fx)
    if node == null:
        return null
    node.layers = 1
    _add_light(node, fx)
    host.add_child(node)
    node.global_transform = global_transform
    var entry := {
        "node": node,
        "time_left": resolve_duration(fx),
        "age": 0.0,
        "frozen": false,
        "ignore_fog": ignore_fog,
    }
    _active.append(entry)
    _apply_visibility(entry)
    if node is GPUParticles3D:
        node.finished.connect(_free_effect.bind(node))
        # Started after the hook is connected so a short one-shot cannot finish
        # before the engine can report it.
        node.emitting = true
    return node


func active_count() -> int:
    return _active.size()


## One-shot lifetime in seconds: explicit `duration`, else the sprite clip
## length, else for particles `spawn_duration + lifetime` (a looping emitter
## plus the last particle spawned), else the ceiling `2 * lifetime` (see
## PARTICLE_DURATION_CEILING), clamped to a positive minimum.
static func resolve_duration(fx: FxData) -> float:
    if fx == null:
        return MIN_DURATION
    if fx.duration > 0.0:
        return fx.duration
    if fx.kind == FxData.Kind.SPRITE:
        return maxf(_sprite_animation_length(fx), MIN_DURATION)
    if fx.spawn_duration > 0.0:
        return maxf(fx.spawn_duration + fx.lifetime, MIN_DURATION)
    return maxf(fx.lifetime * PARTICLE_DURATION_CEILING, MIN_DURATION)


func _process(delta: float) -> void:
    var i := _active.size() - 1
    while i >= 0:
        var entry := _active[i]
        var node: Node3D = entry["node"]
        if not is_instance_valid(node) or node.is_queued_for_deletion():
            _active.remove_at(i)
            i -= 1
            continue
        entry["age"] = float(entry["age"]) + delta
        if float(entry["age"]) >= MAX_FROZEN_AGE:
            _free_entry(i)
            i -= 1
            continue
        if not entry["frozen"]:
            var time_left := float(entry["time_left"]) - delta
            if time_left <= 0.0:
                _free_entry(i)
                i -= 1
                continue
            entry["time_left"] = time_left
        i -= 1


## Frees the effect node at `_active[index]` and drops the entry.
func _free_entry(index: int) -> void:
    var node: Node3D = _active[index]["node"]
    if is_instance_valid(node):
        node.queue_free()
    _active.remove_at(index)


## Early-frees a particle effect on the engine `finished` signal (accurate
## in-game; the duration accumulator remains the fallback path).
func _free_effect(node: Node) -> void:
    for i in _active.size():
        if _active[i]["node"] == node:
            _free_entry(i)
            return


## Re-evaluates every live effect when the shroud grid changes, so effects
## entering or leaving local visibility freeze or resume.
func _on_shroud_changed(_dirty: PackedInt32Array) -> void:
    for entry in _active:
        _apply_visibility(entry)


func _apply_visibility(entry: Dictionary) -> void:
    var node: Node3D = entry["node"]
    if not is_instance_valid(node):
        return
    if entry.get("ignore_fog", false) or not ShroudSystem.is_grid_ready():
        entry["frozen"] = false
        node.visible = true
        _set_running(node, true)
        return
    var visible_now := ShroudSystem.is_cell_visible_to_local(
        CellUtil.world_to_cell(node.global_position)
    )
    entry["frozen"] = not visible_now
    node.visible = visible_now
    _set_running(node, visible_now)


## Pauses/resumes the effect's playback. Both primitives expose `speed_scale`;
## zero freezes them without losing play state.
func _set_running(node: Node3D, running: bool) -> void:
    if node is AnimatedSprite3D or node is GPUParticles3D:
        node.speed_scale = 1.0 if running else 0.0


## Default parent for gameplay effects: the match World root's Effects container,
## falling back to the current scene then the scene tree root when no World exists
## (headless tests, pre-boot). The `play` `parent` argument still overrides this.
func _effect_parent() -> Node:
    return World.spawn_container(World.Bucket.EFFECTS)


func _build(fx: FxData) -> Node3D:
    match fx.kind:
        FxData.Kind.SPRITE:
            return _build_sprite(fx)
        FxData.Kind.PARTICLES:
            return _build_particles(fx)
    return null


func _build_sprite(fx: FxData) -> Node3D:
    var sprite := AnimatedSprite3D.new()
    sprite.sprite_frames = fx.sprite_frames
    sprite.pixel_size = fx.pixel_size
    sprite.modulate = fx.modulate
    sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    sprite.shaded = false
    var animation := resolve_animation(fx)
    if not String(animation).is_empty():
        sprite.animation = animation
        sprite.play()
    return sprite


func _build_particles(fx: FxData) -> Node3D:
    var particles := GPUParticles3D.new()
    particles.process_material = fx.process_material
    particles.draw_pass_1 = _build_particle_mesh(fx)
    particles.amount = fx.amount
    particles.lifetime = fx.lifetime
    particles.explosiveness = fx.explosiveness
    # A spawn window longer than a particle's life needs a looping emitter the
    # timer keeps alive; a burst emits its whole window inside one cycle.
    particles.one_shot = fx.spawn_duration <= 0.0
    particles.local_coords = fx.local_coords
    # Started in play() after the finished hook is connected.
    particles.emitting = false
    return particles


## Particle draw primitive, sized by `quad_size`: a camera-facing `QuadMesh`,
## or a flat triangle `ArrayMesh` for debris-style sparks.
func _build_particle_mesh(fx: FxData) -> Mesh:
    if fx.particle_shape == FxData.ParticleShape.TRIANGLE:
        var s := fx.quad_size
        var mesh := ArrayMesh.new()
        var arrays: Array = []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
            [
                Vector3(-s * 0.5, -s * 0.5, 0.0),
                Vector3(s * 0.5, -s * 0.5, 0.0),
                Vector3(0.0, s * 0.5, 0.0)
            ]
        )
        arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(
            [Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)]
        )
        arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(
            [Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1)]
        )
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        if fx.draw_material != null:
            mesh.surface_set_material(0, fx.draw_material)
        return mesh
    var quad := QuadMesh.new()
    quad.size = Vector2(fx.quad_size, fx.quad_size)
    if fx.draw_material != null:
        quad.material = fx.draw_material
    return quad


## Adds the effect's optional point light as a child, so it is freed with the
## effect and is disabled by the fog-freeze visibility toggle.
## ponytail: one transient point light per shot; pooling (#456) is the scale-out.
func _add_light(node: Node3D, fx: FxData) -> void:
    if fx.light_energy <= 0.0:
        return
    var light := OmniLight3D.new()
    light.light_color = fx.light_color
    light.light_energy = fx.light_energy
    light.omni_range = fx.light_range
    light.shadow_enabled = false
    light.layers = 1
    node.add_child(light)


## The animation to play: the authored name when present, else the first
## animation in the frames resource, else empty.
static func resolve_animation(fx: FxData) -> StringName:
    if fx == null or fx.sprite_frames == null:
        return &""
    if not String(fx.animation).is_empty() and fx.sprite_frames.has_animation(fx.animation):
        return fx.animation
    var names := fx.sprite_frames.get_animation_names()
    if names.size() > 0:
        return StringName(names[0])
    return &""


static func _sprite_animation_length(fx: FxData) -> float:
    if fx.sprite_frames == null:
        return DEFAULT_SPRITE_TIME
    var animation := resolve_animation(fx)
    if String(animation).is_empty():
        return DEFAULT_SPRITE_TIME
    var speed := fx.sprite_frames.get_animation_speed(animation)
    if speed <= 0.0:
        speed = 1.0
    var total := 0.0
    for i in fx.sprite_frames.get_frame_count(animation):
        total += fx.sprite_frames.get_frame_duration(animation, i)
    return total / speed
