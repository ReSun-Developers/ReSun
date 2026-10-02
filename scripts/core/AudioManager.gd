extends Node

## AudioManager autoload — dynamic .tres loader and event-driven playback.
## Mirrors EntityFactory/TerrainCatalog data-set loading: register a directory,
## scan it recursively, cache AudioData/VoiceData by id. Missing ids or failed
## loads always warn and return silently — never crash gameplay.

const BUS_MASTER: String = "Master"
const BUS_MUSIC: String = "Music"
const BUS_SFX: String = "SFX"
const BUS_VOICE: String = "Voice"
const REQUIRED_BUSES: Array[String] = [BUS_MASTER, BUS_MUSIC, BUS_SFX, BUS_VOICE]
## Hard cap on concurrent copies of one sound id; past this the oldest copy is dropped.
const MAX_STACK_PER_ID: int = 12
## Live copies of one report entry at which weapon-fire rotates to the next
## entry in its sound_report list (original TS Report= behavior: the first
## entry is the individual report; stacked fire rotates to later entries).
## ponytail: knob, tune from playtesting.
const REPORT_STACK_PER_ID: int = 3
## Skip starting a sound id that already played within this window. Kills the
## density wall from high-ROF weapons (M1 carbine at 20/s × 20 units = 400
## spawns/s): stacked fire then sounds like a single weapon.
## ponytail: retrigger knob, tune from playtesting.
const RETRIGGER_INTERVAL_MS: float = 100.0
## Master bus compressor — gentle, pulls the whole mix down only when it gets
## busy, before the hard limiter (docs-recommended chain). Makeup gain
## restores the compressed level so loud transients sit back at the ceiling.
## ponytail: knobs, tune from playtesting.
const MASTER_COMPRESSOR_THRESHOLD_DB: float = -18.0
const MASTER_COMPRESSOR_RATIO: float = 2.0
const MASTER_COMPRESSOR_GAIN_DB: float = 8.0
## Master bus hard limiter — final ceiling below 0 dB so the mixed output can never clip.
## ponytail: ceiling knob, tune from playtesting.
const MASTER_LIMIT_CEILING_DB: float = -1.0
## SFX bus hard limiter — reels in busy combat stacks above the threshold.
const SFX_LIMIT_CEILING_DB: float = -1.0
## Voice bus compressor — keeps stacked voice lines at consistent volume.
const VOICE_COMPRESSOR_THRESHOLD_DB: float = -18.0
const VOICE_COMPRESSOR_RATIO: float = 2.0
const VOICE_COMPRESSOR_GAIN_DB: float = 8.0

## A `select` line is held briefly before playing. If an order acknowledgment
## (`move`/`attack`/`feedback`) for the same voice set arrives inside the window,
## the held select is discarded so the acknowledgment is the only line (GH #305).
## `0` disables deferral (play select immediately).
## ponytail: debounce knob, tune from playtesting.
var SELECT_DEBOUNCE_MS: float = 150.0

var _audio_cache: Dictionary = {}
var _voice_cache: Dictionary = {}
var _data_sets: Array[String] = []
var _active_players_by_id: Dictionary = {}
var _active_players_by_bus: Dictionary = {}
var _last_played_at: Dictionary = {}
## Deferred select lines, keyed by voice set: `{sound_id, remaining_seconds}`.
var _pending_select: Dictionary = {}
## Currently-playing select line per voice set, so a following acknowledgment can
## stop it in place — the debounce only covers a select still waiting to start.
var _active_select_by_voice: Dictionary = {}

## EVA "insufficient funds" line — announced when a build queue stalls for want
## of credits. Inert until an audio asset with this id is imported; the call
## below returns silently while it is absent.
const EVA_INSUFFICIENT_FUNDS: String = "EVA_INSUFFICIENT_FUNDS"


func _ready() -> void:
    # Keep running while the tree is paused so a deferred select can still flush
    # (the pause menu must not strand a pending voice line).
    process_mode = Node.PROCESS_MODE_ALWAYS
    _ensure_buses()
    GameContext.game_changed.connect(_on_game_changed)
    _load_from_context()
    var pm := get_node_or_null("/root/ProductionManager")
    if pm:
        pm.production_stalled.connect(_on_production_stalled)


## Announce a stalled build queue. Local player only, suppressed by the no-cost
## cheat, and silent (no warning) while the EVA asset is not yet imported.
func _on_production_stalled(queue_key: String) -> void:
    if int(queue_key.get_slice(":", 0)) != PlayerManager.get_local_player_id():
        return
    var debug_menu := get_tree().get_first_node_in_group("debug_menu")
    if debug_menu and debug_menu.no_cost:
        return
    if get_audio_data(EVA_INSUFFICIENT_FUNDS) == null:
        return
    play_sound(EVA_INSUFFICIENT_FUNDS)


## Registers audio data from the active game's layer roots. Pulled at _ready
## (boot-time game_changed fires before this autoload exists) and re-run on
## every runtime game switch.
func _load_from_context() -> void:
    reset_content()
    var def := GameContext.current
    if def == null:
        return
    for root in def.data_sets:
        register_data_set(root.trim_suffix("/") + "/audio/")


func _on_game_changed(_def: GameDefinition) -> void:
    _load_from_context()


## Clears all registered audio content. Called before every (re)registration.
## Active players and retrigger windows are left alone; deferred selects are
## dropped, since their voice sets no longer resolve.
func reset_content() -> void:
    _audio_cache.clear()
    _voice_cache.clear()
    _data_sets.clear()
    _pending_select.clear()
    _active_select_by_voice.clear()


func _ensure_buses() -> void:
    for bus_name in REQUIRED_BUSES:
        if AudioServer.get_bus_index(bus_name) == -1:
            AudioServer.add_bus()
            AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
    _ensure_bus_effects()


## Install the loudness-ceiling effects once per bus. Idempotent: a bus that
## already carries an effect of the same class is left untouched. Master chain
## is compressor → hard limiter (docs recommendation: compress before the
## limiter's ceiling so the limiter stays subtle).
func _ensure_bus_effects() -> void:
    _add_bus_effect_if_missing(
        BUS_MASTER,
        _make_compressor(
            MASTER_COMPRESSOR_THRESHOLD_DB, MASTER_COMPRESSOR_RATIO, MASTER_COMPRESSOR_GAIN_DB
        ),
    )
    _add_bus_effect_if_missing(BUS_MASTER, _make_limiter(MASTER_LIMIT_CEILING_DB))
    _add_bus_effect_if_missing(BUS_SFX, _make_limiter(SFX_LIMIT_CEILING_DB))
    _add_bus_effect_if_missing(
        BUS_VOICE,
        _make_compressor(
            VOICE_COMPRESSOR_THRESHOLD_DB, VOICE_COMPRESSOR_RATIO, VOICE_COMPRESSOR_GAIN_DB
        ),
    )


func _add_bus_effect_if_missing(bus_name: String, effect: AudioEffect) -> void:
    var bus_idx := AudioServer.get_bus_index(bus_name)
    if bus_idx == -1:
        return
    for effect_idx in AudioServer.get_bus_effect_count(bus_idx):
        var existing: AudioEffect = AudioServer.get_bus_effect(bus_idx, effect_idx)
        if existing.get_class() == effect.get_class():
            return
    AudioServer.add_bus_effect(bus_idx, effect)


func _make_compressor(threshold_db: float, ratio: float, gain_db: float) -> AudioEffect:
    var effect := AudioEffectCompressor.new()
    effect.threshold = threshold_db
    effect.ratio = ratio
    effect.gain = gain_db
    return effect


func _make_limiter(ceiling_db: float) -> AudioEffect:
    var effect := AudioEffectHardLimiter.new()
    effect.ceiling_db = ceiling_db
    return effect


func register_data_set(path: String) -> void:
    if _data_sets.has(path):
        return
    _data_sets.append(path)
    _scan_directory(path)


func _scan_directory(path: String) -> void:
    var dir := DirAccess.open(path)
    if not dir:
        push_warning("AudioManager: Cannot open directory: %s" % path)
        return
    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        var resource_path := file_name.trim_suffix(".remap")
        if resource_path.ends_with(".tres"):
            var full_path := path + resource_path
            var resource := load(full_path)
            if resource is AudioData:
                _audio_cache[resource.id] = resource
            elif resource is VoiceData:
                _voice_cache[resource.id] = resource
        elif dir.current_is_dir() and not file_name.begins_with("."):
            _scan_directory(path + file_name + "/")
        file_name = dir.get_next()
    dir.list_dir_end()


func get_audio_data(id: String) -> AudioData:
    return _audio_cache.get(id, null) as AudioData


## Live copy count for one sound id (read-only view of the tracking state).
func get_active_count(id: String) -> int:
    return (_active_players_by_id.get(id, []) as Array).size()


## Effective retrigger window for a sound: its own override when set (> 0),
## else the global RETRIGGER_INTERVAL_MS default.
func _effective_retrigger_ms(audio: AudioData) -> float:
    return audio.retrigger_ms if audio.retrigger_ms > 0.0 else RETRIGGER_INTERVAL_MS


func get_voice_data(id: String) -> VoiceData:
    return _voice_cache.get(id, null) as VoiceData


## Stacking-driven weapon report selection (original TS Report= behavior):
## walk the list in order and play the first entry whose live copies are below
## REPORT_STACK_PER_ID; unknown ids warn and fall through; when every entry is
## saturated, the last entry plays. No-op on an empty list.
func play_report(ids: PackedStringArray, position: Vector3 = Vector3.INF) -> void:
    if ids.is_empty():
        return
    for i in ids.size():
        var id := ids[i].strip_edges()
        if id.is_empty():
            continue
        if get_audio_data(id) == null:
            push_warning("AudioManager: Unknown sound id in report list: %s" % id)
            continue
        if get_active_count(id) < REPORT_STACK_PER_ID:
            play_sound(id, position)
            return
    play_sound(ids[ids.size() - 1].strip_edges(), position)


## Random selection among a report list (original TS AnimList / Explosion
## behavior): pick one known id at random and play it. Unknown or empty entries
## warn and are skipped; a list with no known ids plays nothing. Used for
## one-shot events (warhead impacts, deaths) where stacking rotation does not fit.
func play_random(ids: PackedStringArray, position: Vector3 = Vector3.INF) -> void:
    var known: Array[String] = []
    for raw in ids:
        var id := raw.strip_edges()
        if id.is_empty():
            continue
        if get_audio_data(id) == null:
            push_warning("AudioManager: Unknown sound id in random list: %s" % id)
            continue
        known.append(id)
    if known.is_empty():
        return
    play_sound(known[randi() % known.size()], position)


## Play a sound id. Returns the created player (null when the id is unknown,
## unloadable, or throttled) so callers such as play_voice can track it.
func play_sound(id: String, position: Vector3 = Vector3.INF) -> Node:
    var audio := get_audio_data(id)
    if not audio:
        push_warning("AudioManager: Unknown sound id: %s" % id)
        return null
    if audio.path.is_empty() or not ResourceLoader.exists(audio.path):
        push_warning("AudioManager: Missing audio file for id %s: %s" % [id, audio.path])
        return null
    var stream := load(audio.path) as AudioStream
    if not stream:
        push_warning("AudioManager: Failed to load audio stream for id %s: %s" % [id, audio.path])
        return null

    var now_ms := Time.get_ticks_msec()
    if now_ms - (_last_played_at.get(id, -1) as int) < _effective_retrigger_ms(audio):
        return null
    _last_played_at[id] = now_ms

    var active := _active_players_by_id.get(id, []) as Array
    if active.size() >= MAX_STACK_PER_ID:
        var oldest := active.pop_front() as Node
        _stop_player(id, oldest)
    _active_players_by_id[id] = active

    var spatial := audio.is_spatial and position != Vector3.INF
    if spatial:
        var player3d := AudioStreamPlayer3D.new()
        player3d.stream = stream
        player3d.bus = audio.bus
        player3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
        add_child(player3d)
        var viewport_rect := _viewport_rect()
        if viewport_rect.size == Vector2.ZERO:
            # No camera (headless/UI) — positional at the source, no falloff.
            player3d.global_position = position
        else:
            # RTS rule: full volume while on screen, fall off beyond the
            # viewport edge (distance from the camera past the edge).
            # ponytail: unit_size is the falloff knob, tune from playtesting.
            player3d.unit_size = maxf(viewport_rect.size.y, 1.0) * 0.5
            player3d.global_position = _falloff_position(
                position, viewport_rect, _listener_position()
            )
        player3d.play()
        _track_player(id, player3d, active)
        return player3d
    var player := AudioStreamPlayer.new()
    player.stream = stream
    player.bus = audio.bus
    add_child(player)
    player.play()
    _track_player(id, player, active)
    return player


## Voice playback is commander radio chatter, always centered on the camera.
## It routes through play_sound, so stacked identical voices share the same
## loudness budget as any other stacked sound.
##
## A `select` line is deferred by `SELECT_DEBOUNCE_MS` (keyed by voice set) so a
## following order acknowledgment can supersede it, and an acknowledgment also
## stops a select that has already started — so select and acknowledgment never
## overlap. `die` is exempt: death cries are never deferred and never cancel a
## select.
func play_voice(voice_id: String, event_name: String) -> void:
    var voice := get_voice_data(voice_id)
    if not voice:
        push_warning("AudioManager: Unknown voice id: %s" % voice_id)
        return
    # An incoming command acknowledgment supersedes this voice set's pending
    # select even when the acknowledgment itself has no playable variant — the
    # request, not the sound, cancels the deferred line. `die` is exempt.
    if event_name != VoiceData.EVENT_SELECT and event_name != VoiceData.EVENT_DIE:
        _pending_select.erase(voice_id)
    var variants := voice.get_event(event_name)
    if variants.is_empty():
        return
    var chosen := variants[randi() % variants.size()]
    if event_name == VoiceData.EVENT_SELECT:
        if SELECT_DEBOUNCE_MS > 0.0:
            _queue_pending_select(voice_id, chosen)
        else:
            _play_select(voice_id, chosen)
        return
    if event_name == VoiceData.EVENT_DIE:
        play_sound(chosen, _listener_position())
        return
    # A command acknowledgment stops this speaker's in-flight select so the two
    # lines never overlap, then plays.
    _stop_active_select(voice_id)
    play_sound(chosen, _listener_position())


## Defer a select line. Repeated selects for one voice set coalesce into a single
## slot: the chosen variant refreshes but the original deadline is kept, so a
## rapid burst still flushes one line at the first window's end.
func _queue_pending_select(voice_id: String, sound_id: String) -> void:
    if _pending_select.has(voice_id):
        (_pending_select[voice_id] as Dictionary)["sound_id"] = sound_id
        return
    _pending_select[voice_id] = {"sound_id": sound_id, "remaining": SELECT_DEBOUNCE_MS / 1000.0}


## Start a select line and remember it as the voice set's active select, so a
## later acknowledgment can stop it in place.
func _play_select(voice_id: String, sound_id: String) -> void:
    _stop_active_select(voice_id)
    var player := play_sound(sound_id, _listener_position())
    if player:
        _active_select_by_voice[voice_id] = player
        player.set_meta("select_voice_set", voice_id)


## Stop the voice set's currently-playing select line, if any.
func _stop_active_select(voice_id: String) -> void:
    var player: Node = _active_select_by_voice.get(voice_id, null) as Node
    _active_select_by_voice.erase(voice_id)
    if player and is_instance_valid(player):
        _stop_player(player.get_meta("sound_id", "") as String, player)


## Flush deferred select lines whose debounce window has elapsed. A select that
## was superseded by an acknowledgment is never reached because play_voice erased
## it. Runs only while a select is pending.
func _process(delta: float) -> void:
    if _pending_select.is_empty():
        return
    for voice_id in _pending_select.keys():
        var entry: Dictionary = _pending_select[voice_id]
        entry["remaining"] = float(entry["remaining"]) - delta
        if float(entry["remaining"]) <= 0.0:
            _pending_select.erase(voice_id)
            _play_select(voice_id, entry["sound_id"] as String)


## Track a new copy on its bus. The whole bus stack is rebalanced so N
## concurrent copies — same or different ids — share one copy's loudness
## budget (each at -20·log10(N) dB).
func _track_player(id: String, player: Node, active: Array) -> void:
    active.append(player)
    var audio := get_audio_data(id)
    player.set_meta("stack_base_db", audio.volume_db)
    player.set_meta("sound_id", id)
    var bus_players := _active_players_by_bus.get(audio.bus, []) as Array
    bus_players.append(player)
    _active_players_by_bus[audio.bus] = bus_players
    _renormalize_bus(bus_players)
    player.connect("finished", _on_player_finished.bind(id, player))


## Stop and release a tracked player: stop playback, drop it from the per-id and
## per-bus stacks, and free it. Godot's stop() never emits `finished`, so the
## untracking must be explicit here.
func _stop_player(id: String, player: Node) -> void:
    if not is_instance_valid(player):
        return
    player.call("stop")
    _untrack_player(id, player)
    var active := _active_players_by_id.get(id, []) as Array
    active.erase(player)
    if active.is_empty():
        _active_players_by_id.erase(id)
    player.queue_free()


## Scale every active copy on a bus by the bus's total concurrent count, so a
## stacked mix — across ids — sums to exactly one instance's loudness.
func _renormalize_bus(bus_players: Array) -> void:
    var count: int = bus_players.size()
    if count == 0:
        return
    var stack_db: float = linear_to_db(1.0 / float(count))
    for player: Node in bus_players:
        var base_db: float = player.get_meta("stack_base_db", 0.0) as float
        player.set("volume_db", base_db + stack_db)


## Remove a copy from its bus stack and rebalance the survivors.
func _untrack_player(id: String, player: Node) -> void:
    var audio := get_audio_data(id)
    if not audio or not is_instance_valid(player):
        return
    var bus_players := _active_players_by_bus.get(audio.bus, []) as Array
    bus_players.erase(player)
    if bus_players.is_empty():
        _active_players_by_bus.erase(audio.bus)
    else:
        _renormalize_bus(bus_players)


func _on_player_finished(id: String, player: Node) -> void:
    _untrack_player(id, player)
    if is_instance_valid(player):
        var voice_set := player.get_meta("select_voice_set", "") as String
        if not voice_set.is_empty() and _active_select_by_voice.get(voice_set, null) == player:
            _active_select_by_voice.erase(voice_set)
        player.queue_free()
    var active := _active_players_by_id.get(id, []) as Array
    active.erase(player)
    if active.is_empty():
        _active_players_by_id.erase(id)


## World-space viewport footprint: the 4 screen corners unprojected to the
## ground plane. Zero-size rect signals "no camera" (headless/UI contexts).
func _viewport_rect() -> Rect2:
    var viewport := get_viewport()
    var camera := viewport.get_camera_3d() if viewport else null
    if not camera or not camera.is_inside_tree():
        return Rect2()
    var ground := Plane(Vector3.UP, 0.0)
    var screen_rect := viewport.get_visible_rect()
    var corners: Array[Vector2] = [
        screen_rect.position,
        screen_rect.position + Vector2(screen_rect.size.x, 0.0),
        screen_rect.position + screen_rect.size,
        screen_rect.position + Vector2(0.0, screen_rect.size.y),
    ]
    var min_p: Vector2 = Vector2.INF
    var max_p: Vector2 = Vector2.INF * -1.0
    var hit_count := 0
    for corner in corners:
        var hit: Variant = ground.intersects_ray(
            camera.project_ray_origin(corner), camera.project_ray_normal(corner)
        )
        if hit == null:
            continue
        var p: Vector3 = hit
        min_p.x = minf(min_p.x, p.x)
        min_p.y = minf(min_p.y, p.z)
        max_p.x = maxf(max_p.x, p.x)
        max_p.y = maxf(max_p.y, p.z)
        hit_count += 1
    if hit_count < 3:
        return Rect2()
    return Rect2(min_p, max_p - min_p)


## Distance from a world position past the viewport rectangle (0 when on screen).
func _excess_distance(world_position: Vector3, viewport_rect: Rect2) -> float:
    var center := viewport_rect.get_center()
    var excess := Vector2(
        maxf(absf(world_position.x - center.x) - viewport_rect.size.x * 0.5, 0.0),
        maxf(absf(world_position.z - center.y) - viewport_rect.size.y * 0.5, 0.0),
    )
    return excess.length()


## Position for a spatial player: on the listener-relative bearing of the source
## at distance `excess`, so the engine's attenuation applies only off-screen.
func _falloff_position(world_position: Vector3, viewport_rect: Rect2, listener: Vector3) -> Vector3:
    var excess := _excess_distance(world_position, viewport_rect)
    if excess <= 0.0:
        return listener
    var dir := Vector3(world_position.x - listener.x, 0.0, world_position.z - listener.z)
    if dir.length_squared() < 0.0001:
        return listener
    return listener + dir.normalized() * excess


func _listener_position() -> Vector3:
    var camera := get_viewport().get_camera_3d() if get_viewport() else null
    if camera and camera.is_inside_tree():
        return camera.global_position
    return Vector3.ZERO
