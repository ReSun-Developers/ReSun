extends Node3D

## Asset browser — standalone dev tool (Run Scene / F6 / --scene). Browses a
## game's visual + audio assets by category, previews the selected asset with a
## mode-adaptive pane, and inspects 3D assets with stackable render overlays.
##
## The camera is a fixed, preview-owned projector at the gameplay isometric
## vantage (45 deg yaw, 30 deg down); only its projection (isometric/perspective)
## and zoom change. All rotation turns the asset, so the light and environment
## stay put. No gameplay camera, no gameplay panning, no map-bounds clamping.

const MODE_MODEL := 0
const MODE_TERRAIN := 1
const MODE_AUDIO := 2
const MODE_IMAGE := 3
const MODE_FX := 4

const CAM_ISOMETRIC := 0
const CAM_PERSPECTIVE := 1
const ISO_YAW_DEG := 45.0
const ISO_PITCH_DEG := 30.0
const YAW_STEP_DEG := 90.0
const MIN_ZOOM_DISTANCE := 1.0
const MAX_ZOOM_DISTANCE := 300.0
const MIN_ORTHO_SIZE := 1.0
const MAX_ORTHO_SIZE := 300.0
const AUTO_ROTATE_SPEED := 0.6
const PERSP_PITCH_LIMIT := 1.48
const GROUND_GRID_HALF_CELLS := 12

const OVERLAY_MESH := 0
const OVERLAY_FOOTPRINT := 1
const OVERLAY_COLLISION := 2
const OVERLAY_THEATER := 3
const OVERLAY_GROUND := 4
const OVERLAY_AXIS := 5
const OVERLAY_SELECT := 6
const _OVERLAY_NAMES := {
    OVERLAY_MESH: "Mesh",
    OVERLAY_FOOTPRINT: "Footprint",
    OVERLAY_COLLISION: "Collision",
    OVERLAY_THEATER: "Theater",
    OVERLAY_GROUND: "Ground",
    OVERLAY_AXIS: "Axis",
    OVERLAY_SELECT: "Select",
}

## Category registry. Each row: label, source dirs under each data_set root
## (or image_dirs for raw textures), expected script_class (`cls`), preview mode,
## and an optional EntityData.EntityType guard (`etype`) enforced at scan time
## from the resource header. Adding a category is one row. Entity categories
## still key off subdirectories (structures/infantry/vehicles/...) so faction
## nesting works; `etype` is a hard filter on top.
const CATEGORIES: Array = [
    {
        "label": "Terrain Objects",
        "dirs": ["terrain_objects"],
        "cls": "TerrainObject",
        "mode": MODE_TERRAIN,
    },
    {
        "label": "Buildings",
        "dirs": ["entities/structures"],
        "cls": "EntityData",
        "mode": MODE_MODEL,
        "etype": EntityData.EntityType.BUILDING,
    },
    {
        "label": "Infantry",
        "dirs": ["entities/infantry"],
        "cls": "EntityData",
        "mode": MODE_MODEL,
        "etype": EntityData.EntityType.INFANTRY,
    },
    {
        "label": "Vehicles",
        "dirs": ["entities/vehicles"],
        "cls": "EntityData",
        "mode": MODE_MODEL,
        "etype": EntityData.EntityType.VEHICLE,
    },
    {
        "label": "Aircraft",
        "dirs": ["entities/aircraft"],
        "cls": "EntityData",
        "mode": MODE_MODEL,
        "etype": EntityData.EntityType.AIRCRAFT,
    },
    {
        "label": "Terrain Props",
        "dirs": ["entities/terrain"],
        "cls": "EntityData",
        "mode": MODE_MODEL,
        "etype": EntityData.EntityType.TERRAIN,
    },
    {
        "label": "Overlays",
        "dirs": ["entities/overlay"],
        "cls": "EntityData",
        "mode": MODE_MODEL,
        "etype": EntityData.EntityType.OVERLAY,
    },
    {
        "label": "Smudges",
        "dirs": ["entities/smudge"],
        "cls": "EntityData",
        "mode": MODE_MODEL,
        "etype": EntityData.EntityType.SMUDGE,
    },
    {
        "label": "Art Entries",
        "dirs": ["art/vehicles", "art/infantry", "art/aircraft", "art/structures"],
        "cls": "ArtData",
        "mode": MODE_MODEL,
    },
    {
        "label": "Terrain Art",
        "dirs": ["art/terrain"],
        "cls": "TerrainArtData",
        "mode": MODE_MODEL,
    },
    {"label": "SFX", "dirs": ["audio"], "cls": "AudioData", "mode": MODE_AUDIO},
    {"label": "Voices", "dirs": ["audio"], "cls": "VoiceData", "mode": MODE_AUDIO},
    {"label": "FX", "dirs": ["fx"], "cls": "FxData", "mode": MODE_FX},
    {
        "label": "Cameos / UI",
        "image_dirs": ["assets/cameos", "assets/ui"],
        "mode": MODE_IMAGE,
    },
]

var _categories: Array[Dictionary] = []
var _category_index := 0
var _assets: Array[Dictionary] = []
var _asset_index := 0
var _filter_text := ""

var _camera_mode := CAM_ISOMETRIC
var _object_yaw := 0.0
var _object_pitch := 0.0
var _base_yaw_deg := 0.0
var _ortho_size := 20.0
var _distance := 12.0
var _auto_rotate := false
## Zoom is computed once (and on projection toggle), not on every asset change.
var _zoom_initialized := false
var _entity_data: EntityData = null

var _overlay_states: Dictionary = {
    OVERLAY_MESH: true,
    OVERLAY_FOOTPRINT: false,
    OVERLAY_COLLISION: false,
    OVERLAY_THEATER: false,
    OVERLAY_GROUND: false,
    OVERLAY_AXIS: true,
    OVERLAY_SELECT: true,
}
var _overlay_focus := OVERLAY_MESH

var _camera: Camera3D = null
var _object_root: Node3D = null
var _world_overlays: Node3D = null
var _glb_mesh_cache: Dictionary = {}
var _cached_materials: Dictionary = {}
var _audio_player: AudioStreamPlayer = null
var _current_resource: Resource = null
var _current_mode := MODE_MODEL
var _terrain_object: TerrainObject = null
var _foundation := Vector2i.ZERO
var _game_changed_connected := false
var _fog_was_enabled := true

var _preview_bounds := AABB()
var _object_center := Vector3.ZERO
var _terrain_min_height := 0
## Local Y of world ground (y=0) under ObjectRoot after placement/centering.
var _local_ground_y := 0.0

var _visual_node: Node3D = null
var _footprint_mesh: MeshInstance3D = null
var _collision_mesh: MeshInstance3D = null
var _theater_label: Label3D = null
var _ground_mesh: MeshInstance3D = null
var _axis_mesh: MeshInstance3D = null
var _highlight_mesh: MeshInstance3D = null
var _select_mesh: MeshInstance3D = null
var _health_bar_mesh: MeshInstance3D = null

var _hud: CanvasLayer = null
var _game_option: OptionButton = null
var _category_option: OptionButton = null
var _filter_edit: LineEdit = null
var _asset_option: OptionButton = null
var _camera_button: Button = null
var _overlay_buttons: Dictionary = {}
var _info_label: Label = null
var _cells_header: Label = null
var _cell_list: VBoxContainer = null
var _message_label: Label = null
var _image_rect: TextureRect = null
var _audio_row: HBoxContainer = null
var _fx_row: HBoxContainer = null
var _audio_label: Label = null
var _play_button: Button = null
var _stop_button: Button = null
var _auto_button: CheckButton = null
var _reset_rot_button: Button = null
var _theater_option: OptionButton = null


func _ready() -> void:
    _camera = get_node_or_null("PreviewCamera") as Camera3D
    _object_root = get_node_or_null("ObjectRoot") as Node3D
    _world_overlays = get_node_or_null("WorldOverlays") as Node3D
    _hud = get_node_or_null("HUD") as CanvasLayer
    if _camera == null or _object_root == null or _world_overlays == null or _hud == null:
        push_error("AssetBrowser: scene missing PreviewCamera/ObjectRoot/WorldOverlays/HUD")
        return
    _audio_player = AudioStreamPlayer.new()
    _audio_player.name = "PreviewAudio"
    _audio_player.bus = "Master"
    add_child(_audio_player)
    _suppress_gameplay_overlays()
    GameContext.game_changed.connect(_on_game_changed)
    _game_changed_connected = true
    _build_world_overlays()
    _build_hud()
    _rebuild_games()
    _rebuild_theaters()
    _rebuild_categories()
    _apply_camera_transform()


func _exit_tree() -> void:
    if _game_changed_connected and GameContext.game_changed.is_connected(_on_game_changed):
        GameContext.game_changed.disconnect(_on_game_changed)
    _set_fog_overlay(_fog_was_enabled)


## The browser is a standalone dev scene: keep gameplay world overlays (the
## fog-of-war/shroud plane) from draping over the inspected asset. Restored on
## exit to whatever state was active when the browser entered.
func _suppress_gameplay_overlays() -> void:
    _fog_was_enabled = FogRenderer.set_overlay_enabled(false)


func _set_fog_overlay(enabled: bool) -> void:
    FogRenderer.set_overlay_enabled(enabled)


func _process(delta: float) -> void:
    if _auto_rotate:
        _object_yaw = wrapf(_object_yaw + delta * AUTO_ROTATE_SPEED, 0.0, TAU)
        _apply_object_transform()


func _unhandled_input(event: InputEvent) -> void:
    if _is_pointer_over_hud():
        return
    if event.is_action_pressed("asset_browser_next"):
        next_asset()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("asset_browser_prev"):
        prev_asset()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("asset_browser_rotate_left"):
        rotate_step(-YAW_STEP_DEG)
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("asset_browser_rotate_right"):
        rotate_step(YAW_STEP_DEG)
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("asset_browser_auto_rotate"):
        toggle_auto_rotate()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("asset_browser_camera_mode"):
        toggle_camera_mode()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("asset_browser_cycle_overlay"):
        cycle_overlay()
        get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            zoom(-1.0)
            get_viewport().set_input_as_handled()
        elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            zoom(1.0)
            get_viewport().set_input_as_handled()
    elif event is InputEventMouseMotion:
        var motion := event as InputEventMouseMotion
        if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _auto_rotate:
            rotate_free(-motion.relative.x * 0.57, motion.relative.y * 0.57)


# --- Public API (also exercised by tests) ---


func get_category_count() -> int:
    return _categories.size()


func get_category_label(index: int) -> String:
    if index < 0 or index >= _categories.size():
        return ""
    return String(_categories[index]["label"])


func get_asset_count() -> int:
    return _assets.size()


func get_asset_id(index: int) -> String:
    if index < 0 or index >= _assets.size():
        return ""
    return String(_assets[index]["id"])


func current_asset_id() -> String:
    return get_asset_id(_asset_index)


func get_preview_mode() -> int:
    return _current_mode


func current_category_label() -> String:
    return get_category_label(_category_index)


func current_game_id() -> String:
    return GameContext.current.id if GameContext.current else ""


func get_camera() -> Camera3D:
    return _camera


func get_object_root() -> Node3D:
    return _object_root


func get_world_overlays() -> Node3D:
    return _world_overlays


func get_zoom_distance() -> float:
    return _distance


func get_ortho_size() -> float:
    return _ortho_size


func get_camera_mode() -> int:
    return _camera_mode


func is_isometric() -> bool:
    return _camera_mode == CAM_ISOMETRIC


func get_yaw_degrees() -> float:
    return rad_to_deg(_object_yaw)


func get_pitch_degrees() -> float:
    return rad_to_deg(_object_pitch)


func is_auto_rotate() -> bool:
    return _auto_rotate


func get_overlay(state: int) -> bool:
    return bool(_overlay_states.get(state, false))


func get_overlay_node(state: int) -> Node3D:
    var nodes: Dictionary = {
        OVERLAY_MESH: _visual_node,
        OVERLAY_FOOTPRINT: _footprint_mesh,
        OVERLAY_COLLISION: _collision_mesh,
        OVERLAY_THEATER: _theater_label,
        OVERLAY_GROUND: _ground_mesh,
        OVERLAY_AXIS: _axis_mesh,
        OVERLAY_SELECT: _select_mesh,
    }
    var node: Node3D = nodes.get(state, null)
    return node


func select_category(index: int) -> void:
    if _categories.is_empty():
        return
    _category_index = clampi(index, 0, _categories.size() - 1)
    _asset_index = 0
    _rebuild_assets()
    _refresh_asset()


func select_asset(index: int) -> void:
    if _assets.is_empty():
        _asset_index = 0
        _clear_object_root()
        _show_message("No assets in %s" % current_category_label())
        return
    _asset_index = clampi(index, 0, _assets.size() - 1)
    _refresh_asset()


func next_asset() -> void:
    if _assets.is_empty():
        return
    select_asset((_asset_index + 1) % _assets.size())


func prev_asset() -> void:
    if _assets.is_empty():
        return
    select_asset((_asset_index - 1 + _assets.size()) % _assets.size())


func apply_filter(text: String) -> void:
    _filter_text = text.to_lower()
    var previous := current_asset_id()
    _rebuild_assets()
    var idx := 0
    for i in _assets.size():
        if String(_assets[i]["id"]) == previous:
            idx = i
            break
    select_asset(idx)


func zoom(direction: float) -> void:
    if is_isometric():
        _ortho_size = clampf(_ortho_size * (1.0 + 0.1 * direction), MIN_ORTHO_SIZE, MAX_ORTHO_SIZE)
    else:
        _distance = clampf(
            _distance * (1.0 + 0.1 * direction), MIN_ZOOM_DISTANCE, MAX_ZOOM_DISTANCE
        )
    _apply_camera_transform()


func rotate_step(degrees: float) -> void:
    _object_yaw = wrapf(_object_yaw + deg_to_rad(degrees), 0.0, TAU)
    _apply_object_transform()


## Snap the asset back to its authored base yaw (and clear pitch).
func reset_rotation() -> void:
    _object_yaw = deg_to_rad(_base_yaw_deg)
    _object_pitch = 0.0
    _apply_object_transform()


## Free-rotation entry point: yaw always applies; pitch only in perspective mode.
## Isometric keeps the asset upright (Y-only), matching the gameplay view.
func rotate_free(delta_yaw_deg: float, delta_pitch_deg: float) -> void:
    _object_yaw = wrapf(_object_yaw + deg_to_rad(delta_yaw_deg), 0.0, TAU)
    if _camera_mode == CAM_PERSPECTIVE:
        _object_pitch = clampf(
            _object_pitch + deg_to_rad(delta_pitch_deg), -PERSP_PITCH_LIMIT, PERSP_PITCH_LIMIT
        )
    _apply_object_transform()


func set_camera_mode(mode: int) -> void:
    _camera_mode = CAM_PERSPECTIVE if mode == CAM_PERSPECTIVE else CAM_ISOMETRIC
    if is_isometric():
        _object_pitch = 0.0
        _apply_object_transform()
    _compute_default_zoom()
    _zoom_initialized = true
    _apply_camera_transform()
    _sync_camera_button()


func toggle_camera_mode() -> void:
    set_camera_mode(CAM_PERSPECTIVE if is_isometric() else CAM_ISOMETRIC)


func set_overlay(state: int, enabled: bool) -> void:
    if not _overlay_states.has(state):
        return
    _overlay_states[state] = enabled
    _update_overlay_visibility()
    _sync_overlay_buttons()


func cycle_overlay() -> void:
    _overlay_focus = (_overlay_focus + 1) % _OVERLAY_NAMES.size()
    set_overlay(_overlay_focus, not get_overlay(_overlay_focus))


func toggle_auto_rotate() -> void:
    _auto_rotate = not _auto_rotate
    if _auto_button != null:
        _auto_button.set_pressed_no_signal(_auto_rotate)


func set_auto_rotate(value: bool) -> void:
    _auto_rotate = value
    if _auto_button != null:
        _auto_button.set_pressed_no_signal(value)


func play_current_audio() -> void:
    if _audio_player != null and _audio_player.stream != null:
        _audio_player.play()


func stop_audio() -> void:
    if _audio_player != null:
        _audio_player.stop()


func is_audio_playing() -> bool:
    return _audio_player != null and _audio_player.playing


## Replays the current asset. For an FX effect this plays it again from the
## start; for other modes it re-runs their preview.
func replay_asset() -> void:
    _refresh_asset()


# --- Game / category / asset rebuilds ---


func _on_game_changed(_def: GameDefinition) -> void:
    _glb_mesh_cache.clear()
    _rebuild_games()
    _rebuild_theaters()
    _rebuild_categories()


func _rebuild_games() -> void:
    if _game_option == null:
        return
    _game_option.clear()
    var games := GameContext.list_games()
    for i in games.size():
        var def := games[i]
        var label := def.display_name if not def.display_name.is_empty() else def.id
        _game_option.add_item(label, i)
        if GameContext.current != null and def.id == GameContext.current.id:
            _game_option.select(i)
    _game_option.disabled = games.size() <= 1


func _rebuild_theaters() -> void:
    if _theater_option == null:
        return
    _theater_option.clear()
    var theaters := TerrainCatalog.get_all_theaters()
    var ids: Array[String] = []
    for id in theaters:
        ids.append(String(id))
    ids.sort()
    var active := TerrainCatalog.get_active_theater_id()
    var active_idx := 0
    for i in ids.size():
        var th: TheaterData = theaters[ids[i]]
        var label := th.display_name if not th.display_name.is_empty() else th.id
        _theater_option.add_item("%s (%s)" % [label, th.id], i)
        _theater_option.set_item_metadata(i, th.id)
        if th.id == active:
            active_idx = i
    if _theater_option.item_count > 0:
        _theater_option.select(active_idx)
    _theater_option.disabled = _theater_option.item_count <= 1


func _on_theater_selected(index: int) -> void:
    if _theater_option == null:
        return
    var id := str(_theater_option.get_item_metadata(index))
    if id.is_empty() or id == TerrainCatalog.get_active_theater_id():
        return
    TerrainCatalog.set_active_theater(id)
    _refresh_asset()


func _rebuild_categories() -> void:
    _categories.clear()
    if _category_option == null:
        return
    _category_option.clear()
    for cat in CATEGORIES:
        if not _category_has_source(cat):
            push_warning("AssetBrowser: no source for category '%s'" % cat["label"])
            continue
        _categories.append(cat)
        _category_option.add_item(String(cat["label"]))
    if _categories.is_empty():
        if _asset_option != null:
            _asset_option.clear()
        _show_message("No assets for game '%s'" % current_game_id())
        return
    _category_option.select(0)
    _category_index = 0
    _asset_index = 0
    _rebuild_assets()
    _refresh_asset()


func _category_has_source(cat: Dictionary) -> bool:
    for root in _data_set_roots():
        for d in cat.get("dirs", []):
            if DirAccess.open(_join(root, d)) != null:
                return true
        for d in cat.get("image_dirs", []):
            if DirAccess.open(_join(root, d)) != null:
                return true
    return false


func _rebuild_assets() -> void:
    _assets.clear()
    if _category_option == null or _categories.is_empty():
        return
    var cat := _categories[_category_index]
    _assets = _scan_category(cat)
    var filtered: Array[Dictionary] = []
    for entry in _assets:
        if _filter_text.is_empty() or String(entry["id"]).to_lower().contains(_filter_text):
            filtered.append(entry)
    _assets = filtered
    _asset_option.clear()
    for entry in _assets:
        _asset_option.add_item(String(entry["id"]))
    if _asset_option.item_count > 0:
        _asset_option.select(0)


func _data_set_roots() -> Array[String]:
    var roots: Array[String] = []
    if GameContext.current == null:
        return roots
    for root in GameContext.current.data_sets:
        var r := String(root).trim_suffix("/")
        if not r.is_empty():
            roots.append(r)
    return roots


static func _join(root: String, sub: String) -> String:
    return root.trim_suffix("/") + "/" + sub.trim_prefix("/").trim_suffix("/") + "/"


func _scan_category(cat: Dictionary) -> Array[Dictionary]:
    var found: Dictionary = {}
    var etype := int(cat.get("etype", -1))
    for root in _data_set_roots():
        for d in cat.get("dirs", []):
            _scan_tres(_join(root, d), String(cat.get("cls", "")), found, etype)
        for d in cat.get("image_dirs", []):
            _scan_images(_join(root, d), found)
    var out: Array[Dictionary] = []
    for key in found:
        out.append(found[key])
    out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
    return out


func _scan_tres(
    dir_path: String, cls_filter: String, found: Dictionary, etype_filter: int = -1
) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        if file_name.begins_with("."):
            file_name = dir.get_next()
            continue
        if dir.current_is_dir():
            _scan_tres(dir_path.path_join(file_name) + "/", cls_filter, found, etype_filter)
        else:
            var resource_path := file_name.trim_suffix(".remap")
            if not resource_path.ends_with(".tres"):
                file_name = dir.get_next()
                continue
            var disk_path := dir_path.path_join(file_name)
            var load_path := dir_path.path_join(resource_path)
            if not cls_filter.is_empty() and _tres_class(disk_path) != cls_filter:
                file_name = dir.get_next()
                continue
            if etype_filter >= 0 and _tres_entity_type(disk_path) != etype_filter:
                file_name = dir.get_next()
                continue
            var id := _tres_id(disk_path)
            found[id] = {"id": id, "path": load_path}
        file_name = dir.get_next()
    dir.list_dir_end()


func _scan_images(dir_path: String, found: Dictionary) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        if file_name.begins_with("."):
            file_name = dir.get_next()
            continue
        if not dir.current_is_dir() and _is_image(file_name):
            var id := file_name.get_basename()
            found[id] = {"id": id, "path": dir_path.path_join(file_name)}
        file_name = dir.get_next()
    dir.list_dir_end()


static func _is_image(file_name: String) -> bool:
    var ext := file_name.get_extension().to_lower()
    return ext in ["png", "jpg", "jpeg", "webp", "svg", "bmp"]


## Reads only the resource header (script_class + id) so listing stays lazy:
## the full resource is loaded on selection, never while scanning.
static func _tres_header(path: String) -> String:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return ""
    var header := f.get_buffer(512).get_string_from_utf8()
    f.close()
    return header


static func _tres_class(path: String) -> String:
    var header := _tres_header(path)
    var idx := header.find('script_class="')
    if idx == -1:
        return ""
    var rest := header.substr(idx + 14)
    var end := rest.find('"')
    if end == -1:
        return ""
    return rest.substr(0, end)


## Reads the authored `id = "..."` from anywhere in the resource. Sub-resources
## (SpriteFrames, materials) can push the [resource] block past the 512-byte
## `_tres_header` cap, so this reads the whole file instead. Falls back to the
## file basename when no id is present.
static func _tres_id(path: String) -> String:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return path.get_file().get_basename()
    var content := f.get_as_text()
    f.close()
    var idx := content.find('\nid = "')
    if idx == -1:
        return path.get_file().get_basename()
    var rest := content.substr(idx + 7)
    var end := rest.find('"')
    if end == -1:
        return path.get_file().get_basename()
    var id := rest.substr(0, end)
    return id if not id.is_empty() else path.get_file().get_basename()


## Reads `entity_type = N` from the resource header (0-based EntityType enum).
## Returns -1 when absent so non-entity resources never match a filter.
static func _tres_entity_type(path: String) -> int:
    var header := _tres_header(path)
    var idx := header.find("\nentity_type = ")
    if idx == -1:
        return -1
    var rest := header.substr(idx + 15)
    var end := 0
    while end < rest.length() and rest[end] >= "0" and rest[end] <= "9":
        end += 1
    if end == 0:
        return -1
    return int(rest.substr(0, end))


# --- Preview ---


func _refresh_asset() -> void:
    _hide_all_previews()
    _current_resource = null
    if _assets.is_empty():
        _clear_object_root()
        _show_message("No assets in %s" % current_category_label())
        _update_info(null)
        return
    _current_mode = int(_categories[_category_index]["mode"])
    var path := String(_assets[_asset_index]["path"])
    _rename_asset_option()
    match _current_mode:
        MODE_MODEL:
            _preview_model(path)
        MODE_TERRAIN:
            _preview_terrain(path)
        MODE_AUDIO:
            _preview_audio(path)
        MODE_IMAGE:
            _preview_image(path)
        MODE_FX:
            _preview_fx(path)
    _update_info(_current_resource)


func _preview_model(path: String) -> void:
    var res := load(path) as Resource
    _current_resource = res
    var model_path := ""
    var placeholder := Vector3.ZERO
    if res is EntityData:
        var data := res as EntityData
        _entity_data = data
        _foundation = data.foundation
        if data.art_data != null:
            model_path = data.art_data.model_path
            placeholder = data.art_data.placeholder_size
    elif res is ArtData:
        var art := res as ArtData
        _foundation = art.foundation
        model_path = art.model_path
        placeholder = art.placeholder_size
    elif res is TerrainArtData:
        _preview_terrain_art(res as TerrainArtData)
        return
    else:
        _show_message("No preview for %s" % path.get_file())
        return
    _preview_model_path(model_path, placeholder)


func _preview_model_path(model_path: String, placeholder_size: Vector3) -> void:
    if not model_path.is_empty() and ResourceLoader.exists(model_path):
        var scene := load(model_path) as PackedScene
        if scene != null:
            var instance := scene.instantiate()
            instance.name = "ModelInstance"
            _object_root.add_child(instance)
            _visual_node = instance as Node3D
            _finalize_object()
            return
    var size := placeholder_size
    if size == Vector3.ZERO and _foundation != Vector2i.ZERO:
        size = Vector3(
            _foundation.x * CellUtil.CELL_SIZE,
            CellUtil.CELL_SIZE,
            _foundation.y * CellUtil.CELL_SIZE
        )
    if size != Vector3.ZERO:
        _show_placeholder_box(size)
        return
    _show_message("No model or placeholder for selection")


func _show_placeholder_box(size: Vector3) -> void:
    var box := BoxMesh.new()
    box.size = size
    var mi := MeshInstance3D.new()
    mi.name = "PlaceholderBox"
    mi.mesh = box
    mi.position = Vector3(0.0, size.y * 0.5, 0.0)
    _object_root.add_child(mi)
    _visual_node = mi
    _finalize_object()


func _preview_terrain_art(art: TerrainArtData) -> void:
    var resolution := art.resolve(art.id, TerrainCatalog.get_active_theater_id())
    if not resolution.valid or resolution.glb_path.is_empty():
        _show_message("No art model for %s" % art.id)
        return
    var scene := _get_glb_scene(resolution.glb_path)
    if scene == null:
        _show_message("Cannot load %s" % resolution.glb_path)
        return
    var probe := scene.instantiate()
    var template := _find_mesh_node(probe, resolution.submesh_id)
    if template == null:
        probe.free()
        _show_message("Submesh '%s' missing" % resolution.submesh_id)
        return
    var mi := MeshInstance3D.new()
    mi.name = "TerrainArtMesh_" + art.id
    mi.mesh = template.mesh
    for i in template.mesh.get_surface_count():
        var mat := template.mesh.surface_get_material(i)
        if mat != null:
            mi.mesh.surface_set_material(i, mat)
    probe.free()
    _base_yaw_deg = resolution.rotation
    _object_root.add_child(mi)
    _visual_node = mi
    _finalize_object()


func _preview_terrain(path: String) -> void:
    var res := load(path) as TerrainObject
    _current_resource = res
    if res == null:
        _show_message("Terrain object failed to load")
        return
    var resolution := TerrainCatalog.resolve_art(res.id, TerrainCatalog.get_active_theater_id())
    if not resolution.valid or resolution.glb_path.is_empty():
        _show_message("No terrain art for %s" % res.id)
        return
    var mesh_name := resolution.submesh_id
    var scene := _get_glb_scene(resolution.glb_path)
    if scene == null:
        _show_message("Cannot load %s" % resolution.glb_path)
        return
    var probe := scene.instantiate()
    var template := _find_mesh_node(probe, mesh_name)
    if template == null:
        probe.free()
        _show_message("Submesh '%s' missing in %s" % [mesh_name, resolution.glb_path.get_file()])
        return
    var mi := MeshInstance3D.new()
    mi.name = "TerrainMesh_" + res.id
    mi.mesh = template.mesh
    for i in template.mesh.get_surface_count():
        var mat := template.mesh.surface_get_material(i)
        if mat != null:
            mi.mesh.surface_set_material(i, mat)
    probe.free()
    _terrain_object = res
    _terrain_min_height = int(TerrainObject.footprint_bounds(res).position.y)
    _base_yaw_deg = resolution.rotation
    _object_root.add_child(mi)
    _visual_node = mi
    _finalize_object()


func _preview_audio(path: String) -> void:
    var res := load(path) as Resource
    _current_resource = res
    _audio_player.stream = null
    var label := path.get_file()
    var stream_path := ""
    if res is AudioData:
        var audio := res as AudioData
        label = audio.id
        stream_path = audio.path
    elif res is VoiceData:
        var voice := res as VoiceData
        label = voice.id
        var ids: Array[String] = voice.select
        if ids.is_empty():
            ids = voice.move
        if not ids.is_empty():
            var clip := AudioManager.get_audio_data(ids[0])
            if clip != null:
                stream_path = clip.path
    if not stream_path.is_empty() and ResourceLoader.exists(stream_path):
        _audio_player.stream = load(stream_path) as AudioStream
    _audio_row.visible = true
    var stream_note := "no playable stream"
    if not stream_path.is_empty():
        stream_note = "stream: " + stream_path
    _audio_label.text = label + "\n" + stream_note
    _update_audio_buttons()


func _preview_image(path: String) -> void:
    if not ResourceLoader.exists(path):
        _show_message("Texture missing: %s" % path.get_file())
        return
    var tex := load(path) as Texture2D
    if tex == null:
        _show_message("Not a texture: %s" % path.get_file())
        return
    _current_resource = tex
    _image_rect.texture = tex
    _image_rect.visible = true


## Plays the selected FxData on the preview stage. Effects ignore fog gating in
## the browser (no gameplay grid here) and parent under the object root so they
## are cleared with the rest of the preview.
func _preview_fx(path: String) -> void:
    var effect := load(path) as FxData
    _current_resource = effect
    if effect == null:
        _show_message("Not an FxData: %s" % path.get_file())
        return
    var errors := effect.validate()
    if not errors.is_empty():
        _show_message("Invalid FX: %s" % path.get_file())
        return
    var node := FxSystem.play(effect, Transform3D(Basis(), Vector3.ZERO), true, _object_root)
    if node == null:
        _show_message("FX did not play: %s" % path.get_file())
        return
    _visual_node = node
    _fx_row.visible = true


func _get_glb_scene(path: String) -> PackedScene:
    if _glb_mesh_cache.has(path):
        return _glb_mesh_cache[path]
    var scene := load(path) as PackedScene
    if scene != null:
        _glb_mesh_cache[path] = scene
    return scene


func _find_mesh_node(root: Node, mesh_name: String) -> MeshInstance3D:
    if root is MeshInstance3D:
        var mi := root as MeshInstance3D
        if String(mi.name).trim_suffix("_3D") == mesh_name:
            return mi
    for child in root.get_children():
        var found := _find_mesh_node(child, mesh_name)
        if found != null:
            return found
    return null


# --- Placement, framing, camera ---


func _finalize_object() -> void:
    _preview_bounds = _object_bounds()
    _object_center = _preview_bounds.get_center()
    if _preview_bounds.size == Vector3.ZERO:
        _object_center = Vector3.ZERO
    _center_object_children(_object_center)
    # Buildings sit on foundation center in gameplay (cell_origin_to_world);
    # put that center at (fw/2, ·, fh/2) so the foundation spans world 0..fw.
    # Other assets keep AABB-min at the origin. Y always grounds AABB min at 0.
    # Children stay centered so root rotation pivots on the bounds center.
    var size := _preview_bounds.size
    var root := Vector3.ZERO
    if size != Vector3.ZERO:
        root.y = size.y * 0.5
        if _entity_data != null and _foundation.x > 0 and _foundation.y > 0:
            root.x = float(_foundation.x) * CellUtil.CELL_SIZE * 0.5
            root.z = float(_foundation.y) * CellUtil.CELL_SIZE * 0.5
        else:
            root.x = size.x * 0.5
            root.z = size.z * 0.5
    _object_root.position = root
    _local_ground_y = -root.y
    _object_yaw = deg_to_rad(_base_yaw_deg)
    _object_pitch = 0.0
    _apply_object_transform()
    _build_object_overlays()
    _world_overlays.visible = true
    _update_overlay_visibility()
    # Keep the user's zoom across asset changes; frame only the first time.
    if not _zoom_initialized:
        _compute_default_zoom()
        _zoom_initialized = true
    _apply_camera_transform()


func _center_object_children(center: Vector3) -> void:
    for child in _object_root.get_children():
        if child is Node3D:
            (child as Node3D).position -= center


func _object_bounds() -> AABB:
    var boxes: Array[AABB] = []
    _collect_bounds(_object_root, Transform3D.IDENTITY, boxes)
    if boxes.is_empty():
        return AABB()
    var merged: AABB = boxes[0]
    for i in range(1, boxes.size()):
        merged = merged.merge(boxes[i])
    return merged


func _collect_bounds(node: Node, xform: Transform3D, out: Array[AABB]) -> void:
    if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
        out.append(_transformed_aabb((node as MeshInstance3D).mesh.get_aabb(), xform))
    for child in node.get_children():
        var child_xform := xform
        if child is Node3D:
            child_xform = xform * (child as Node3D).transform
        _collect_bounds(child, child_xform, out)


static func _transformed_aabb(box: AABB, xform: Transform3D) -> AABB:
    var result := AABB(xform * box.position, Vector3.ZERO)
    for i in 8:
        result = result.expand(xform * box.get_endpoint(i))
    return result


func _apply_object_transform() -> void:
    if _object_root == null:
        return
    if is_isometric():
        _object_root.rotation = Vector3(0.0, _object_yaw, 0.0)
    else:
        _object_root.rotation = Vector3(_object_pitch, _object_yaw, 0.0)


func _camera_direction() -> Vector3:
    var pitch := deg_to_rad(ISO_PITCH_DEG)
    var yaw := deg_to_rad(ISO_YAW_DEG)
    return Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))


func _ortho_camera_distance() -> float:
    var span := _preview_bounds.size.length()
    return clampf(span * 2.0 + 50.0, 50.0, 400.0)


func _compute_default_zoom() -> void:
    var radius := maxf(_preview_bounds.size.length() * 0.5, 0.5)
    if is_isometric():
        _ortho_size = clampf(2.0 * radius * 1.6, MIN_ORTHO_SIZE, MAX_ORTHO_SIZE)
    else:
        var half_fov := deg_to_rad(_camera.fov) * 0.5
        _distance = clampf(
            radius / maxf(tan(half_fov), 0.01) * 1.6, MIN_ZOOM_DISTANCE, MAX_ZOOM_DISTANCE
        )


func _apply_camera_transform() -> void:
    if _camera == null:
        return
    var target := _object_root.position if _object_root != null else Vector3.ZERO
    _camera.projection = (
        Camera3D.PROJECTION_ORTHOGONAL if is_isometric() else Camera3D.PROJECTION_PERSPECTIVE
    )
    if is_isometric():
        _camera.size = _ortho_size
    var dist := _ortho_camera_distance() if is_isometric() else _distance
    var position := target + _camera_direction() * dist
    _camera.global_position = position
    if not position.is_equal_approx(target):
        _camera.look_at(target, Vector3.UP)


# --- Render overlays ---


func _build_object_overlays() -> void:
    _build_footprint_overlay()
    _build_collision_overlay()
    _build_theater_overlay()
    _build_select_preview()
    _apply_overlay_offset()


func _apply_overlay_offset() -> void:
    # Collision/highlight and terrain cell footprint are authored in pre-center
    # space; shift them into the centered root. Foundation and select preview
    # are already authored centered on the root (position stays zero).
    for node in [_collision_mesh, _highlight_mesh]:
        if node != null:
            node.position = -_object_center
    if _terrain_object != null and _footprint_mesh != null:
        _footprint_mesh.position = -_object_center
    elif _footprint_mesh != null:
        _footprint_mesh.position = Vector3.ZERO


func _build_footprint_overlay() -> void:
    if _terrain_object != null:
        _build_terrain_footprint(_terrain_object)
    else:
        _build_foundation_footprint()


func _build_terrain_footprint(obj: TerrainObject) -> void:
    var immesh := ImmediateMesh.new()
    var mat := _line_material("browser_footprint", Color(0.0, 1.0, 1.0, 1.0))
    for key in obj.cells:
        var parts: PackedStringArray = String(key).split(",")
        if parts.size() != 2:
            continue
        var x := int(parts[0])
        var z := int(parts[1])
        var entry: Variant = obj.cells.get(key, {})
        var corners: Array = entry.get("corners", []) if entry is Dictionary else []
        var c0 := _corner_local(x, z, 0, corners)
        var c1 := _corner_local(x, z, 1, corners)
        var c2 := _corner_local(x, z, 2, corners)
        var c3 := _corner_local(x, z, 3, corners)
        var b0 := _cell_corner_local(x, z, 0, 0.0)
        var b1 := _cell_corner_local(x, z, 1, 0.0)
        var b2 := _cell_corner_local(x, z, 2, 0.0)
        var b3 := _cell_corner_local(x, z, 3, 0.0)
        immesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
        immesh.surface_add_vertex(c0)
        immesh.surface_add_vertex(c1)
        immesh.surface_add_vertex(c1)
        immesh.surface_add_vertex(c2)
        immesh.surface_add_vertex(c2)
        immesh.surface_add_vertex(c3)
        immesh.surface_add_vertex(c3)
        immesh.surface_add_vertex(c0)
        immesh.surface_add_vertex(b0)
        immesh.surface_add_vertex(b1)
        immesh.surface_add_vertex(b1)
        immesh.surface_add_vertex(b2)
        immesh.surface_add_vertex(b2)
        immesh.surface_add_vertex(b3)
        immesh.surface_add_vertex(b3)
        immesh.surface_add_vertex(b0)
        immesh.surface_add_vertex(c0)
        immesh.surface_add_vertex(b0)
        immesh.surface_add_vertex(c1)
        immesh.surface_add_vertex(b1)
        immesh.surface_add_vertex(c2)
        immesh.surface_add_vertex(b2)
        immesh.surface_add_vertex(c3)
        immesh.surface_add_vertex(b3)
        immesh.surface_end()
    var mi := MeshInstance3D.new()
    mi.name = "FootprintGrid"
    mi.mesh = immesh
    mi.material_override = mat
    _object_root.add_child(mi)
    _footprint_mesh = mi


func _build_foundation_footprint() -> void:
    if _foundation.x <= 0 or _foundation.y <= 0:
        return
    var cs := CellUtil.CELL_SIZE
    var sx := float(_foundation.x) * cs
    var sz := float(_foundation.y) * cs
    var hx := sx * 0.5
    var hz := sz * 0.5
    var y := _local_ground_y + 0.02
    var immesh := ImmediateMesh.new()
    var mat := _line_material("browser_footprint", Color(0.0, 1.0, 1.0, 1.0))
    immesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
    for i in _foundation.x + 1:
        var x := -hx + float(i) * cs
        immesh.surface_add_vertex(Vector3(x, y, -hz))
        immesh.surface_add_vertex(Vector3(x, y, hz))
    for j in _foundation.y + 1:
        var z := -hz + float(j) * cs
        immesh.surface_add_vertex(Vector3(-hx, y, z))
        immesh.surface_add_vertex(Vector3(hx, y, z))
    immesh.surface_end()
    var mi := MeshInstance3D.new()
    mi.name = "FoundationGrid"
    mi.mesh = immesh
    mi.material_override = mat
    _object_root.add_child(mi)
    _footprint_mesh = mi


func _build_collision_overlay() -> void:
    if _preview_bounds.size == Vector3.ZERO:
        return
    var lo := _preview_bounds.position
    var hi := _preview_bounds.position + _preview_bounds.size
    var corners := [
        lo,
        Vector3(hi.x, lo.y, lo.z),
        Vector3(hi.x, lo.y, hi.z),
        Vector3(lo.x, lo.y, hi.z),
        Vector3(lo.x, hi.y, lo.z),
        Vector3(hi.x, hi.y, lo.z),
        hi,
        Vector3(lo.x, hi.y, hi.z),
    ]
    var edges := [
        [0, 1],
        [1, 2],
        [2, 3],
        [3, 0],
        [4, 5],
        [5, 6],
        [6, 7],
        [7, 4],
        [0, 4],
        [1, 5],
        [2, 6],
        [3, 7],
    ]
    var immesh := ImmediateMesh.new()
    var mat := _line_material("browser_collision", Color(1.0, 1.0, 0.0, 1.0))
    immesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
    for edge in edges:
        immesh.surface_add_vertex(corners[edge[0]])
        immesh.surface_add_vertex(corners[edge[1]])
    immesh.surface_end()
    var mi := MeshInstance3D.new()
    mi.name = "CollisionBox"
    mi.mesh = immesh
    mi.material_override = mat
    _object_root.add_child(mi)
    _collision_mesh = mi


func _build_theater_overlay() -> void:
    var label := Label3D.new()
    label.name = "ContextLabel"
    label.text = _context_label_text()
    label.pixel_size = 0.01
    label.font_size = 64
    label.no_depth_test = true
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.position = Vector3(0.0, _local_ground_y + _preview_bounds.size.y + 1.5, 0.0)
    _object_root.add_child(label)
    _theater_label = label


func _context_label_text() -> String:
    var theater := TerrainCatalog.get_active_theater_id()
    if _terrain_object != null:
        return "%s\nTheater: %s" % [_terrain_object.id, theater]
    if _entity_data != null:
        return "%s\nTheater: %s" % [_entity_data.id, theater]
    return "%s\nTheater: %s" % [current_asset_id(), theater]


## Selection outline + full health-bar preview for building/unit entities —
## Mirrors SelectComponent: structure brackets + segmented health bar along Z
## at the top-left of the select box (same axes/rotation as gameplay).
func _build_select_preview() -> void:
    if _entity_data == null:
        return
    var etype := _entity_data.entity_type
    if (
        etype == EntityData.EntityType.TERRAIN
        or etype == EntityData.EntityType.OVERLAY
        or etype == EntityData.EntityType.SMUDGE
    ):
        return
    var box := _select_box_size()
    if box == Vector3.ZERO:
        return
    var min_y := _local_ground_y + 0.01
    var max_y := _local_ground_y + box.y
    _select_mesh = MeshInstance3D.new()
    _select_mesh.name = "SelectPreview"
    _select_mesh.mesh = _build_select_box_mesh(box, min_y, max_y)
    _select_mesh.material_override = _line_material("browser_select", Color.WHITE)
    _select_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _object_root.add_child(_select_mesh)

    if etype != EntityData.EntityType.BUILDING:
        return
    _health_bar_mesh = _build_structure_health_bar(box, max_y)
    if _health_bar_mesh != null:
        _object_root.add_child(_health_bar_mesh)


func _select_box_size() -> Vector3:
    if _entity_data != null and _entity_data.entity_type == EntityData.EntityType.BUILDING:
        return Vector3(
            float(_foundation.x) * CellUtil.CELL_SIZE,
            maxf(_entity_data.height, 1.0),
            float(_foundation.y) * CellUtil.CELL_SIZE,
        )
    if _preview_bounds.size != Vector3.ZERO:
        var s := _preview_bounds.size
        return Vector3(maxf(s.x, 1.0), maxf(s.y, 1.0), maxf(s.z, 1.0))
    return Vector3.ZERO


## Gameplay structure select box: corner feet + top L-brackets (SelectComponent).
## Y range is ground-relative (min_y..max_y in local ObjectRoot space).
func _build_select_box_mesh(box: Vector3, min_y: float, max_y: float) -> ImmediateMesh:
    var hx := box.x * 0.5
    var hz := box.z * 0.5
    var x_len := minf(box.x * 0.25, 1.0)
    var y_len := minf(box.y * 0.25, 0.5)
    var z_len := minf(box.z * 0.25, 1.0)
    var corners := [
        Vector3(-hx, min_y, -hz),
        Vector3(hx, min_y, -hz),
        Vector3(-hx, min_y, hz),
        Vector3(hx, min_y, hz),
    ]
    var immesh := ImmediateMesh.new()
    immesh.surface_begin(Mesh.PRIMITIVE_LINES)
    for c: Vector3 in corners:
        var sx := 1.0 if c.x < 0.0 else -1.0
        var sz := 1.0 if c.z < 0.0 else -1.0
        var foot := [
            [c, c + Vector3(0, y_len, 0)],
            [c, c + Vector3(sx * x_len, 0, 0)],
            [c, c + Vector3(0, 0, sz * z_len)],
        ]
        for pair in foot:
            immesh.surface_add_vertex(pair[0])
            immesh.surface_add_vertex(pair[1])
        var top := Vector3(c.x, max_y, c.z)
        var top_pairs := [
            [top, top + Vector3(0, -y_len, 0)],
            [top, top + Vector3(sx * x_len, 0, 0)],
            [top, top + Vector3(0, 0, sz * z_len)],
        ]
        for pair in top_pairs:
            immesh.surface_add_vertex(pair[0])
            immesh.surface_add_vertex(pair[1])
    immesh.surface_end()
    return immesh


## Structure health bar exactly as SelectComponent._build_segmented_bar(span_is_x=false):
## full-depth span along Z, cross-section at the left edge, Y at the select-box top,
## fill BoxMesh rotated -90° about Y so its long axis follows Z.
func _build_structure_health_bar(box: Vector3, max_y: float) -> MeshInstance3D:
    const CUBE := 0.33333333
    var hx := box.x * 0.5
    var hz := box.z * 0.5
    var y_lo := max_y - CUBE
    var y_hi := max_y
    var length := box.z
    var fill := MeshInstance3D.new()
    fill.name = "HealthBarPreview"
    fill.mesh = BoxMesh.new()
    fill.scale = Vector3(maxf(length, 0.001), CUBE - 0.02, CUBE - 0.02)
    fill.position = Vector3(-hx + CUBE * 0.5, (y_lo + y_hi) * 0.5, -hz + length * 0.5)
    fill.rotation_degrees.y = -90.0
    var mat := ORMMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color.GREEN
    fill.material_override = mat
    fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return fill


func _update_overlay_visibility() -> void:
    if _object_root == null:
        return
    var is_3d := _current_mode == MODE_MODEL or _current_mode == MODE_TERRAIN
    for state in [
        OVERLAY_MESH, OVERLAY_FOOTPRINT, OVERLAY_COLLISION, OVERLAY_THEATER, OVERLAY_SELECT
    ]:
        var node := get_overlay_node(state)
        if node != null:
            var on := is_3d and get_overlay(state)
            if state == OVERLAY_SELECT and _health_bar_mesh != null:
                _health_bar_mesh.visible = on
            node.visible = on
    for state in [OVERLAY_GROUND, OVERLAY_AXIS]:
        var node := get_overlay_node(state)
        if node != null:
            node.visible = is_3d and get_overlay(state)


func _line_material(name: String, color: Color) -> ORMMaterial3D:
    if _cached_materials.has(name):
        return _cached_materials[name]
    var mat := ORMMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color = color
    _cached_materials[name] = mat
    return mat


func _corner_local(x: int, z: int, corner_index: int, corners: Array) -> Vector3:
    var h := 0.0
    if corners.size() == 4:
        h = float(int(corners[corner_index]) - _terrain_min_height) * TerrainSystem.HEIGHT_STEP
    return _cell_corner_local(x, z, corner_index, h)


static func _cell_corner_local(x: int, z: int, corner_index: int, height: float) -> Vector3:
    var offsets: Array[Vector2] = [
        Vector2(0.0, 0.0),
        Vector2(CellUtil.CELL_SIZE, 0.0),
        Vector2(CellUtil.CELL_SIZE, CellUtil.CELL_SIZE),
        Vector2(0.0, CellUtil.CELL_SIZE),
    ]
    var o: Vector2 = offsets[corner_index]
    return Vector3(x * CellUtil.CELL_SIZE + o.x, height, z * CellUtil.CELL_SIZE + o.y)


func _highlight_cell(cell_key: String) -> void:
    if _highlight_mesh != null:
        _object_root.remove_child(_highlight_mesh)
        _highlight_mesh.queue_free()
        _highlight_mesh = null
    if _terrain_object == null:
        return
    var parts: PackedStringArray = cell_key.split(",")
    if parts.size() != 2:
        return
    var x := int(parts[0])
    var z := int(parts[1])
    var entry: Variant = _terrain_object.cells.get(cell_key, {})
    var corners: Array = entry.get("corners", []) if entry is Dictionary else []
    var top := [
        _corner_local(x, z, 0, corners),
        _corner_local(x, z, 1, corners),
        _corner_local(x, z, 2, corners),
        _corner_local(x, z, 3, corners),
    ]
    var bottom := [
        _cell_corner_local(x, z, 0, 0.0),
        _cell_corner_local(x, z, 1, 0.0),
        _cell_corner_local(x, z, 2, 0.0),
        _cell_corner_local(x, z, 3, 0.0),
    ]
    var immesh := ImmediateMesh.new()
    var mat := _line_material("browser_highlight", Color(0.0, 1.0, 0.2, 1.0))
    immesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
    for i in 4:
        immesh.surface_add_vertex(top[i])
        immesh.surface_add_vertex(top[(i + 1) % 4])
        immesh.surface_add_vertex(bottom[i])
        immesh.surface_add_vertex(bottom[(i + 1) % 4])
        immesh.surface_add_vertex(top[i])
        immesh.surface_add_vertex(bottom[i])
    immesh.surface_end()
    _highlight_mesh = MeshInstance3D.new()
    _highlight_mesh.name = "CellHighlight"
    _highlight_mesh.mesh = immesh
    _highlight_mesh.material_override = mat
    _object_root.add_child(_highlight_mesh)
    _highlight_mesh.position = -_object_center
    _highlight_mesh.visible = get_overlay(OVERLAY_FOOTPRINT)


func _build_world_overlays() -> void:
    if _world_overlays == null:
        return
    var cs := CellUtil.CELL_SIZE
    var n := GROUND_GRID_HALF_CELLS
    var immesh := ImmediateMesh.new()
    var grid_mat := _line_material("browser_ground_grid", Color(1.0, 1.0, 1.0, 0.22))
    immesh.surface_begin(Mesh.PRIMITIVE_LINES, grid_mat)
    for i in range(-n, n + 1):
        var offset := float(i) * cs
        var edge := float(n) * cs
        immesh.surface_add_vertex(Vector3(offset, 0.0, -edge))
        immesh.surface_add_vertex(Vector3(offset, 0.0, edge))
        immesh.surface_add_vertex(Vector3(-edge, 0.0, offset))
        immesh.surface_add_vertex(Vector3(edge, 0.0, offset))
    immesh.surface_end()
    _ground_mesh = MeshInstance3D.new()
    _ground_mesh.name = "GroundGrid"
    _ground_mesh.mesh = immesh
    _ground_mesh.material_override = grid_mat
    _world_overlays.add_child(_ground_mesh)

    var axis := ImmediateMesh.new()
    var x_mat := _line_material("browser_axis_x", Color(1.0, 0.2, 0.2, 1.0))
    var z_mat := _line_material("browser_axis_z", Color(0.2, 0.2, 1.0, 1.0))
    var len := 6.0
    axis.surface_begin(Mesh.PRIMITIVE_LINES, x_mat)
    axis.surface_add_vertex(Vector3(0.0, 0.02, 0.0))
    axis.surface_add_vertex(Vector3(len, 0.02, 0.0))
    axis.surface_end()
    axis.surface_begin(Mesh.PRIMITIVE_LINES, z_mat)
    axis.surface_add_vertex(Vector3(0.0, 0.02, 0.0))
    axis.surface_add_vertex(Vector3(0.0, 0.02, len))
    axis.surface_end()
    _axis_mesh = MeshInstance3D.new()
    _axis_mesh.name = "AxisLines"
    _axis_mesh.mesh = axis
    _world_overlays.add_child(_axis_mesh)
    _world_overlays.visible = false


# --- Object root / HUD helpers ---


func _clear_object_root() -> void:
    for child in _object_root.get_children():
        _object_root.remove_child(child)
        child.queue_free()
    _object_root.position = Vector3.ZERO
    _object_root.rotation = Vector3.ZERO
    _preview_bounds = AABB()
    _object_center = Vector3.ZERO
    _local_ground_y = 0.0
    _terrain_object = null
    _entity_data = null
    _foundation = Vector2i.ZERO
    _base_yaw_deg = 0.0
    _visual_node = null
    _footprint_mesh = null
    _collision_mesh = null
    _theater_label = null
    _highlight_mesh = null
    _select_mesh = null
    _health_bar_mesh = null


func _hide_all_previews() -> void:
    _clear_object_root()
    if _image_rect != null:
        _image_rect.visible = false
    if _audio_row != null:
        _audio_row.visible = false
    if _fx_row != null:
        _fx_row.visible = false
    if _message_label != null:
        _message_label.visible = false
    if _world_overlays != null:
        _world_overlays.visible = false
    _clear_cell_list()
    stop_audio()


func _show_message(text: String) -> void:
    push_warning("AssetBrowser: " + text)
    if _message_label != null:
        _message_label.text = text
        _message_label.visible = true


func _rename_asset_option() -> void:
    if _asset_option != null and _asset_index < _asset_option.item_count:
        _asset_option.select(_asset_index)


func _update_audio_buttons() -> void:
    if _play_button != null:
        _play_button.disabled = _audio_player.stream == null
    if _stop_button != null:
        _stop_button.disabled = _audio_player.stream == null


func _update_info(resource: Resource) -> void:
    if _info_label == null:
        return
    if resource == null:
        _info_label.text = (
            "Asset: (none)\nGame: %s\nCategory: %s" % [current_game_id(), current_category_label()]
        )
        _clear_cell_list()
        return
    var lines: PackedStringArray = []
    lines.append("Game: %s" % current_game_id())
    lines.append("Category: %s" % current_category_label())
    lines.append("Asset: %s" % current_asset_id())
    var script: Script = resource.get_script() as Script
    if script != null:
        lines.append("Type: %s" % script.resource_path.get_file())
    for prop in resource.get_property_list():
        if not (prop["usage"] & PROPERTY_USAGE_EDITOR):
            continue
        var name := String(prop["name"])
        if name.begins_with("_"):
            continue
        var value: Variant = resource.get(name)
        lines.append("%s = %s" % [name, str(value)])
    _info_label.text = "\n".join(lines)
    if _terrain_object != null:
        _rebuild_cell_list(_terrain_object)
    else:
        _clear_cell_list()


func _clear_cell_list() -> void:
    if _cells_header != null:
        _cells_header.visible = false
    if _cell_list == null:
        return
    for child in _cell_list.get_children():
        _cell_list.remove_child(child)
        child.queue_free()


func _rebuild_cell_list(obj: TerrainObject) -> void:
    if _cell_list == null or _cells_header == null:
        return
    _clear_cell_list()
    var keys: Array = obj.cells.keys()
    keys.sort_custom(_cell_key_less)
    for key in keys:
        var entry: Variant = obj.cells.get(key, {})
        var cell: Dictionary = {}
        if entry is Dictionary:
            cell = entry
        var corners: Array = cell.get("corners", [])
        var land := String(cell.get("land", ""))
        var crease := String(cell.get("crease", ""))
        var slope := int(cell.get("slope", 0))
        var row := Button.new()
        row.text = (
            "%s  %s  corners %s  crease %s  slope %d" % [key, land, str(corners), crease, slope]
        )
        row.alignment = HORIZONTAL_ALIGNMENT_LEFT
        row.pressed.connect(_highlight_cell.bind(String(key)))
        _cell_list.add_child(row)
    _cells_header.visible = not keys.is_empty()


static func _cell_key_less(a: Variant, b: Variant) -> bool:
    var pa: PackedStringArray = String(a).split(",")
    var pb: PackedStringArray = String(b).split(",")
    if pa.size() != 2 or pb.size() != 2:
        return String(a) < String(b)
    if int(pa[0]) != int(pb[0]):
        return int(pa[0]) < int(pb[0])
    return int(pa[1]) < int(pb[1])


func _is_pointer_over_hud() -> bool:
    # Only swallow input over interactive HUD chrome (selectors/buttons), not the
    # always-on info panel — otherwise resting the mouse there kills shortcuts.
    var hovered := get_viewport().gui_get_hovered_control()
    if hovered == null:
        return false
    return hovered is BaseButton or hovered is LineEdit or hovered is OptionButton


# --- HUD construction ---


func _build_hud() -> void:
    var top := HBoxContainer.new()
    top.name = "TopBar"
    top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    top.offset_left = 8.0
    top.offset_top = 8.0
    top.offset_right = -8.0
    _hud.add_child(top)

    _game_option = OptionButton.new()
    _game_option.tooltip_text = "Active game"
    _game_option.item_selected.connect(_on_game_selected)
    top.add_child(_game_option)

    _category_option = OptionButton.new()
    _category_option.tooltip_text = "Asset category"
    _category_option.item_selected.connect(select_category)
    top.add_child(_category_option)

    _filter_edit = LineEdit.new()
    _filter_edit.placeholder_text = "Filter..."
    _filter_edit.custom_minimum_size = Vector2(160, 0)
    _filter_edit.text_changed.connect(apply_filter)
    top.add_child(_filter_edit)

    _asset_option = OptionButton.new()
    _asset_option.tooltip_text = "Asset"
    _asset_option.item_selected.connect(select_asset)
    top.add_child(_asset_option)

    var prev := Button.new()
    prev.text = "<"
    prev.tooltip_text = "Previous asset (Left arrow)"
    prev.pressed.connect(prev_asset)
    top.add_child(prev)

    var next := Button.new()
    next.text = ">"
    next.tooltip_text = "Next asset (Right arrow)"
    next.pressed.connect(next_asset)
    top.add_child(next)

    var rotate_left := Button.new()
    rotate_left.text = "Rot -90"
    rotate_left.tooltip_text = "Rotate asset 90 degrees left (Q)"
    rotate_left.pressed.connect(func() -> void: rotate_step(-YAW_STEP_DEG))
    top.add_child(rotate_left)

    var rotate_right := Button.new()
    rotate_right.text = "Rot +90"
    rotate_right.tooltip_text = "Rotate asset 90 degrees right (E)"
    rotate_right.pressed.connect(func() -> void: rotate_step(YAW_STEP_DEG))
    top.add_child(rotate_right)

    _auto_button = CheckButton.new()
    _auto_button.text = "Auto"
    _auto_button.tooltip_text = "Auto-rotate asset (T)"
    _auto_button.toggled.connect(func(on: bool) -> void: _auto_rotate = on)
    top.add_child(_auto_button)

    _reset_rot_button = Button.new()
    _reset_rot_button.text = "Reset Rot"
    _reset_rot_button.tooltip_text = "Reset asset rotation to authored facing"
    _reset_rot_button.pressed.connect(reset_rotation)
    top.add_child(_reset_rot_button)

    _theater_option = OptionButton.new()
    _theater_option.tooltip_text = "Active theater (terrain art)"
    _theater_option.item_selected.connect(_on_theater_selected)
    top.add_child(_theater_option)

    _build_overlay_hud()

    _message_label = Label.new()
    _message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
    _message_label.offset_top = 80.0
    _message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _message_label.visible = false
    _hud.add_child(_message_label)

    _image_rect = TextureRect.new()
    _image_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _image_rect.visible = false
    _hud.add_child(_image_rect)

    _audio_row = HBoxContainer.new()
    _audio_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
    _audio_row.offset_bottom = -24.0
    _audio_row.visible = false
    _hud.add_child(_audio_row)

    _audio_label = Label.new()
    _audio_row.add_child(_audio_label)

    _play_button = Button.new()
    _play_button.text = "Play"
    _play_button.pressed.connect(play_current_audio)
    _audio_row.add_child(_play_button)

    _stop_button = Button.new()
    _stop_button.text = "Stop"
    _stop_button.pressed.connect(stop_audio)
    _audio_row.add_child(_stop_button)

    _fx_row = HBoxContainer.new()
    _fx_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
    _fx_row.offset_bottom = -24.0
    _fx_row.visible = false
    _hud.add_child(_fx_row)

    var replay_button := Button.new()
    replay_button.text = "Replay"
    replay_button.tooltip_text = "Play the effect again"
    replay_button.pressed.connect(replay_asset)
    _fx_row.add_child(replay_button)

    var panel := PanelContainer.new()
    panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
    panel.offset_left = -360.0
    panel.offset_top = 80.0
    panel.offset_right = -8.0
    panel.offset_bottom = -8.0
    _hud.add_child(panel)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 8)
    margin.add_theme_constant_override("margin_right", 8)
    margin.add_theme_constant_override("margin_top", 8)
    margin.add_theme_constant_override("margin_bottom", 8)
    panel.add_child(margin)

    var vbox := VBoxContainer.new()
    margin.add_child(vbox)

    var info_scroll := ScrollContainer.new()
    info_scroll.custom_minimum_size = Vector2(340, 0)
    info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(info_scroll)

    _info_label = Label.new()
    _info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _info_label.custom_minimum_size = Vector2(330, 0)
    info_scroll.add_child(_info_label)

    _cells_header = Label.new()
    _cells_header.text = "Cells (click to highlight)"
    _cells_header.visible = false
    vbox.add_child(_cells_header)

    var cell_scroll := ScrollContainer.new()
    cell_scroll.custom_minimum_size = Vector2(0, 160)
    vbox.add_child(cell_scroll)

    _cell_list = VBoxContainer.new()
    _cell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cell_scroll.add_child(_cell_list)

    # Image preview sits behind every control so it never hides the selectors.
    _hud.move_child(_image_rect, 0)


func _build_overlay_hud() -> void:
    var row := HBoxContainer.new()
    row.name = "OverlayRow"
    row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    row.offset_left = 8.0
    row.offset_top = 44.0
    row.offset_right = -8.0
    _hud.add_child(row)

    _camera_button = Button.new()
    _camera_button.tooltip_text = "Toggle isometric / perspective (C)"
    _camera_button.pressed.connect(toggle_camera_mode)
    row.add_child(_camera_button)
    _sync_camera_button()

    for state in [
        OVERLAY_MESH,
        OVERLAY_FOOTPRINT,
        OVERLAY_COLLISION,
        OVERLAY_THEATER,
        OVERLAY_GROUND,
        OVERLAY_AXIS,
        OVERLAY_SELECT
    ]:
        var cb := CheckButton.new()
        cb.text = String(_OVERLAY_NAMES[state])
        cb.button_pressed = get_overlay(state)
        cb.tooltip_text = "Toggle %s overlay (F cycles)" % String(_OVERLAY_NAMES[state])
        cb.toggled.connect(func(on: bool, s: int = state) -> void: set_overlay(s, on))
        row.add_child(cb)
        _overlay_buttons[state] = cb


func _sync_camera_button() -> void:
    if _camera_button != null:
        _camera_button.text = "Iso" if is_isometric() else "Persp"


func _sync_overlay_buttons() -> void:
    for state in _overlay_buttons:
        var cb: CheckButton = _overlay_buttons[state]
        if cb.is_pressed() != get_overlay(state):
            cb.set_pressed_no_signal(get_overlay(state))


func _on_game_selected(index: int) -> void:
    if _game_option == null or index < 0 or index >= _game_option.item_count:
        return
    var games := GameContext.list_games()
    if index < games.size():
        var id := games[index].id
        if GameContext.current == null or GameContext.current.id != id:
            GameContext.select_game(id)
