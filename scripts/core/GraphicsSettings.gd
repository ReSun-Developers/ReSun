extends Node

## GraphicsSettings autoload — the global rendering *and display* schema, the
## Low/Medium/High/Ultra presets, persistence through UserConfig, and the
## applier that drives the live viewport, window, environment, directional
## light, cloud-shadow overlay, and rendering server.
##
## Two domains share this autoload: `graphics` quality fields (the only fields
## the presets cover) and `display` fields (window mode and resolution, never
## preset-driven). Restart-only fields are stored and applied at boot only;
## every other field applies live. `settings_changed` fires once per user change
## (a preset is one batch) and once for the boot application.

signal settings_changed(changed: PackedStringArray)

const UserConfig := preload("res://scripts/core/UserConfig.gd")

const CONFIG_PATH: String = "user://settings.cfg"
const SECTION: String = "graphics"
const PRESET_KEY: String = "preset"

const DOMAIN_GRAPHICS: String = "graphics"
const DOMAIN_DISPLAY: String = "display"

## Preset-picker sentinel shown when the field values match no named preset.
const CUSTOM_PRESET: String = "custom"

## Common window resolutions offered in the picker (filtered to the screen).
const COMMON_RESOLUTIONS: Array = ["1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"]

## Field id -> metadata. One source of truth for the UI, the presets, and the
## applier. `values` is an Array of options, `"number"` (a min/max/step scalar),
## or `"resolutions"` (a dynamic list). `option_labels` prettifies Array values.
const SCHEMA: Dictionary = {
    "aa":
    {
        "label": "Antialiasing",
        "description": "Edge smoothing. SMAA is cheap; MSAA costs more.",
        "domain": DOMAIN_GRAPHICS,
        "values": ["off", "msaa2x", "msaa4x", "smaa", "smaa_msaa"],
        "option_labels":
        {
            "off": "Off",
            "msaa2x": "MSAA 2x",
            "msaa4x": "MSAA 4x",
            "smaa": "SMAA",
            "smaa_msaa": "SMAA + MSAA",
        },
        "default": "off",
        "restart_only": false,
    },
    "shadow_quality":
    {
        "label": "Shadow quality",
        "description": "Directional shadow map size and filtering. Applies live.",
        "domain": DOMAIN_GRAPHICS,
        "values": ["off", "low", "medium", "high"],
        "option_labels": {"off": "Off", "low": "Low", "medium": "Medium", "high": "High"},
        "default": "off",
        "restart_only": false,
    },
    "cloud_shadows":
    {
        "label": "Cloud shadows",
        "description": "Drifting cloud shadows across the terrain.",
        "domain": DOMAIN_GRAPHICS,
        "values": [true, false],
        "default": false,
        "restart_only": false,
    },
    "gi":
    {
        "label": "Global illumination",
        "description": "SDFGI bounced light. Expensive; High raises the cascade count.",
        "domain": DOMAIN_GRAPHICS,
        "values": ["off", "sdfgi", "high"],
        "option_labels": {"off": "Off", "sdfgi": "SDFGI", "high": "High"},
        "default": "off",
        "restart_only": false,
    },
    "tonemap":
    {
        "label": "Tone mapping",
        "description": "How HDR light is mapped to the screen.",
        "domain": DOMAIN_GRAPHICS,
        "values": ["linear", "reinhard", "filmic", "aces"],
        "option_labels":
        {"linear": "Linear", "reinhard": "Reinhard", "filmic": "Filmic", "aces": "ACES"},
        "default": "filmic",
        "restart_only": false,
    },
    "exposure":
    {
        "label": "Exposure",
        "description": "Scene brightness multiplier.",
        "domain": DOMAIN_GRAPHICS,
        "values": "number",
        "min": 0.0,
        "max": 4.0,
        "step": 0.05,
        "default": 1.0,
        "restart_only": false,
    },
    "texture_quality":
    {
        "label": "Texture quality",
        "description": "Texture filtering sharpness. Applied at the next launch.",
        "domain": DOMAIN_GRAPHICS,
        "values": ["low", "medium", "high"],
        "option_labels": {"low": "Low", "medium": "Medium", "high": "High"},
        "default": "low",
        "restart_only": true,
    },
    "window_mode":
    {
        "label": "Window mode",
        "description": "Windowed, borderless fullscreen, or exclusive fullscreen.",
        "domain": DOMAIN_DISPLAY,
        "values": ["windowed", "borderless", "fullscreen"],
        "option_labels":
        {"windowed": "Windowed", "borderless": "Borderless", "fullscreen": "Fullscreen"},
        "default": "windowed",
        "restart_only": false,
    },
    "resolution":
    {
        "label": "Resolution",
        "description":
        "Window size when windowed. Fullscreen always uses the monitor's native resolution.",
        "domain": DOMAIN_DISPLAY,
        "values": "resolutions",
        "default": "1920x1080",
        "restart_only": false,
    },
}

const PRESETS: Dictionary = {
    "low":
    {
        "aa": "off",
        "shadow_quality": "off",
        "cloud_shadows": false,
        "gi": "off",
        "tonemap": "filmic",
        "exposure": 1.0,
        "texture_quality": "low",
    },
    "medium":
    {
        "aa": "msaa2x",
        "shadow_quality": "low",
        "cloud_shadows": true,
        "gi": "off",
        "tonemap": "filmic",
        "exposure": 1.0,
        "texture_quality": "medium",
    },
    "high":
    {
        "aa": "smaa",
        "shadow_quality": "high",
        "cloud_shadows": true,
        "gi": "sdfgi",
        "tonemap": "filmic",
        "exposure": 1.0,
        "texture_quality": "high",
    },
    "ultra":
    {
        "aa": "smaa_msaa",
        "shadow_quality": "high",
        "cloud_shadows": true,
        "gi": "high",
        "tonemap": "filmic",
        "exposure": 1.0,
        "texture_quality": "high",
    },
}

const SHADOW_ATLAS: Dictionary = {"off": 1024, "low": 1024, "medium": 2048, "high": 4096}
## DirectionalLight3D shadow mode per quality (0 = orthogonal, 1/2 = PSSM).
const SHADOW_MODE: Dictionary = {"low": 1, "medium": 2, "high": 0}

var _values: Dictionary = {}
var _preset: String = "low"
var _config_path: String = CONFIG_PATH
var _reapply_queued: bool = false
var _boot_applied: bool = false


func _ready() -> void:
    _load()
    get_tree().node_added.connect(_on_node_added)
    _queue_reapply()


# --- Public API -------------------------------------------------------------


## The graphics-domain schema (the fields the presets cover).
func schema() -> Dictionary:
    return _domain(DOMAIN_GRAPHICS)


## The display-domain schema (window mode + resolution).
func display_schema() -> Dictionary:
    return _domain(DOMAIN_DISPLAY)


## Every schema field, both domains.
func all_schema() -> Dictionary:
    return SCHEMA


func preset_names() -> PackedStringArray:
    var names := PackedStringArray()
    for name in PRESETS:
        names.append(name)
    return names


func is_restart_only(field: String) -> bool:
    return bool(SCHEMA.get(field, {}).get("restart_only", false))


func get_value(field: String) -> Variant:
    return _values.get(field, SCHEMA.get(field, {}).get("default", null))


## The last preset written, or the fresh-install Low. May not match current
## values; use `matching_preset()` for the picker state.
func current_preset() -> String:
    return _preset


## The named preset whose values equal every graphics field, else `custom`.
func matching_preset() -> String:
    for name in PRESETS:
        if _matches_preset(name):
            return name
    return CUSTOM_PRESET


## Sets one field, persists it, applies it (unless restart-only), and notifies.
func set_value(field: String, value: Variant) -> void:
    if not SCHEMA.has(field):
        push_error("[GraphicsSettings] Unknown field: %s" % field)
        return
    var checked: Variant = _validate(field, value)
    if checked == null:
        return
    if _values.get(field) == checked:
        return
    _values[field] = checked
    UserConfig.set_value(_config_path, SECTION, field, checked)
    _apply_fields(PackedStringArray([field]))
    settings_changed.emit(PackedStringArray([field]))


## Applies a named preset to every graphics field atomically, persists, notifies once.
func apply_preset(name: String) -> void:
    if not PRESETS.has(name):
        push_error("[GraphicsSettings] Unknown preset: %s" % name)
        return
    var changed := PackedStringArray()
    var to_write := {}
    var values: Dictionary = PRESETS[name]
    for field in values:
        if get_value(field) != values[field]:
            changed.append(field)
        _values[field] = values[field]
        to_write[field] = values[field]
    _preset = name
    to_write[PRESET_KEY] = name
    UserConfig.set_section(_config_path, SECTION, to_write)
    _apply_fields(changed)
    settings_changed.emit(changed)


## Applies stored live settings to whatever scene nodes are currently present.
func apply_all() -> void:
    _apply_fields(PackedStringArray(_values.keys()))


## Resolutions selectable on this machine: common sizes within the screen plus
## the stored value so it always round-trips.
func resolution_options() -> PackedStringArray:
    var options := PackedStringArray()
    var screen := Vector2i.ZERO
    if not _is_headless():
        screen = DisplayServer.screen_get_size()
    for text in COMMON_RESOLUTIONS:
        var size := _parse_resolution(text)
        if screen == Vector2i.ZERO or (size.x <= screen.x and size.y <= screen.y):
            options.append(text)
    var current := String(get_value("resolution"))
    if not current.is_empty() and not options.has(current):
        options.append(current)
    return options


# --- Appliers ---------------------------------------------------------------


func _apply_fields(fields: PackedStringArray) -> void:
    if fields.has("aa"):
        _apply_aa()
    if fields.has("shadow_quality"):
        _apply_shadow()
    if fields.has("cloud_shadows"):
        _apply_cloud_shadows()
    if fields.has("gi") or fields.has("tonemap") or fields.has("exposure"):
        _apply_environment()
    if fields.has("window_mode") or fields.has("resolution"):
        _apply_display()


func _apply_aa() -> void:
    var vp := get_viewport()
    if vp == null:
        return
    match String(get_value("aa")):
        "msaa2x":
            vp.msaa_3d = Viewport.MSAA_2X
            vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
        "msaa4x":
            vp.msaa_3d = Viewport.MSAA_4X
            vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
        "smaa":
            vp.msaa_3d = Viewport.MSAA_DISABLED
            vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
        "smaa_msaa":
            vp.msaa_3d = Viewport.MSAA_2X
            vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
        _:
            vp.msaa_3d = Viewport.MSAA_DISABLED
            vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


func _apply_shadow() -> void:
    var quality := String(get_value("shadow_quality"))
    var light := _directional_light()
    if light != null:
        light.shadow_enabled = quality != "off"
        if quality != "off":
            light.directional_shadow_mode = SHADOW_MODE.get(quality, 0)
    RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS.get(quality, 4096), false)


func _apply_cloud_shadows() -> void:
    var visible := bool(get_value("cloud_shadows"))
    for node in get_tree().get_nodes_in_group("cloud_shadow_overlay"):
        if node is Node3D:
            (node as Node3D).visible = visible


func _apply_environment() -> void:
    var env := _world_environment()
    if env == null or env.environment == null:
        return
    var environment := env.environment
    var gi := String(get_value("gi"))
    environment.sdfgi_enabled = gi != "off"
    if gi == "high":
        environment.sdfgi_cascades = 6
        environment.sdfgi_min_cell_size = 0.1
    environment.tonemap_mode = _tonemap_mode(String(get_value("tonemap")))
    environment.tonemap_exposure = float(get_value("exposure"))


## Window mode and size, applied live. Skipped under the headless driver where
## there is no window.
func _apply_display() -> void:
    if _is_headless():
        return
    match String(get_value("window_mode")):
        "borderless":
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
        "fullscreen":
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
        _:
            var size := _parse_resolution(String(get_value("resolution")))
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
            if size != Vector2i.ZERO:
                DisplayServer.window_set_size(size)
            _center_window()


func _center_window() -> void:
    var screen := DisplayServer.window_get_current_screen()
    var usable := DisplayServer.screen_get_usable_rect(screen)
    var window_size := DisplayServer.window_get_size()
    DisplayServer.window_set_position(usable.position + (usable.size - window_size) / 2)


func _tonemap_mode(name: String) -> int:
    match name:
        "linear":
            return Environment.TONE_MAPPER_LINEAR
        "reinhard":
            return Environment.TONE_MAPPER_REINHARDT
        "aces":
            return Environment.TONE_MAPPER_ACES
        _:
            return Environment.TONE_MAPPER_FILMIC


# --- Node resolution (group first, then type) -------------------------------


func _directional_light() -> DirectionalLight3D:
    for node in get_tree().get_nodes_in_group("lighting_controls"):
        var found := node.find_children("*", "DirectionalLight3D", true, false)
        if not found.is_empty():
            return found[0] as DirectionalLight3D
    var any := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
    return any[0] as DirectionalLight3D if not any.is_empty() else null


func _world_environment() -> WorldEnvironment:
    for node in get_tree().get_nodes_in_group("lighting_controls"):
        var found := node.find_children("*", "WorldEnvironment", true, false)
        if not found.is_empty():
            return found[0] as WorldEnvironment
    var any := get_tree().root.find_children("*", "WorldEnvironment", true, false)
    return any[0] as WorldEnvironment if not any.is_empty() else null


# --- Persistence / lifecycle ------------------------------------------------


func _load() -> void:
    var cfg := UserConfig.read(_config_path)
    for field in SCHEMA:
        _values[field] = cfg.get_value(SECTION, field, SCHEMA[field]["default"])
    if not cfg.has_section_key(SECTION, "resolution"):
        _values["resolution"] = _default_resolution()
    _preset = String(cfg.get_value(SECTION, PRESET_KEY, "low"))


func _on_node_added(node: Node) -> void:
    if node is WorldEnvironment:
        _apply_environment()
        _queue_reapply()
    elif node is DirectionalLight3D:
        _apply_shadow()
        _queue_reapply()
    elif node.is_in_group("cloud_shadow_overlay"):
        _apply_cloud_shadows()


## Deferred so it runs after the scene (and LightingControls) finish readied.
func _queue_reapply() -> void:
    if _reapply_queued:
        return
    _reapply_queued = true
    call_deferred("_reapply_now")


func _reapply_now() -> void:
    _reapply_queued = false
    apply_all()
    if not _boot_applied:
        _boot_applied = true
        settings_changed.emit(PackedStringArray(_values.keys()))


# --- Validation / helpers ---------------------------------------------------


func _matches_preset(name: String) -> bool:
    var values: Dictionary = PRESETS[name]
    for field in values:
        if get_value(field) != values[field]:
            return false
    return true


func _domain(domain: String) -> Dictionary:
    var out := {}
    for field in SCHEMA:
        if String(SCHEMA[field].get("domain", DOMAIN_GRAPHICS)) == domain:
            out[field] = SCHEMA[field]
    return out


## Returns the accepted (possibly clamped) value, or null when it is not allowed.
func _validate(field: String, value: Variant) -> Variant:
    var allowed: Variant = SCHEMA[field].get("values")
    if allowed is Array:
        return _validate_enum(field, allowed as Array, value)
    if allowed is String:
        if allowed == "number":
            return _validate_number(field, value)
        if allowed == "resolutions":
            return _validate_resolution(value)
    return value


func _validate_enum(field: String, options: Array, value: Variant) -> Variant:
    if options.has(value):
        return value
    for option in options:
        if str(option) == str(value):
            return option
    push_error("[GraphicsSettings] Invalid value for %s: %s" % [field, str(value)])
    return null


func _validate_number(field: String, value: Variant) -> Variant:
    var info: Dictionary = SCHEMA[field]
    var number := float(value)
    if info.has("min"):
        number = maxf(number, float(info["min"]))
    if info.has("max"):
        number = minf(number, float(info["max"]))
    return number


func _validate_resolution(value: Variant) -> Variant:
    var text := str(value)
    if _parse_resolution(text) != Vector2i.ZERO:
        return text
    push_error("[GraphicsSettings] Invalid resolution: %s" % text)
    return null


func _default_resolution() -> String:
    if not _is_headless():
        var screen := DisplayServer.screen_get_size()
        if screen.x > 0 and screen.y > 0 and (screen.x < 1920 or screen.y < 1080):
            return "%dx%d" % [screen.x, screen.y]
    return "1920x1080"


func _is_headless() -> bool:
    return DisplayServer.get_name() == "headless"


static func _parse_resolution(text: String) -> Vector2i:
    var parts := text.split("x")
    if parts.size() != 2:
        return Vector2i.ZERO
    if not parts[0].is_valid_int() or not parts[1].is_valid_int():
        return Vector2i.ZERO
    return Vector2i(int(parts[0]), int(parts[1]))
