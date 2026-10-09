class_name Minimap extends Control

## Gameplay minimap: a 2D top-down bake of the diamond terrain grid, composed
## with the local player's fog state, resource/overlay objects, entities, and the
## gameplay camera footprint. Terrain is baked once per grid; overlays and fog
## refresh at a low fixed rate.

const STATE_SHROUD: int = 0
const STATE_FOG: int = 1
const STATE_VISIBLE: int = 2

## Single source of truth for the land-type sentinels — read from the
## TerrainSystem script so pure static helpers stay headless-testable.
const _TERRAIN_SYSTEM: GDScript = preload("res://scripts/core/TerrainSystem.gd")
const LAND_TYPE_DEFAULT: String = _TERRAIN_SYSTEM.DEFAULT_LAND_TYPE
const LAND_TYPE_RESOURCE: String = _TERRAIN_SYSTEM.RESOURCE_LAND_TYPE

## Brightness multiplier for explored-but-not-visible cells.
const FOG_DIM: float = 0.35
const DEFAULT_REFRESH_INTERVAL: float = 0.5
const MAP_EDITOR_META: String = "is_map_editor"
const OVERLAY_GROUPS: Array[String] = ["entities", "resources", "ice"]

## Offline placeholder styling — placeholder until sidebar art lands.
const OFFLINE_TEXT: String = "OFFLINE"
const OFFLINE_FONT_SIZE: int = 16
const OFFLINE_TEXT_COLOR := Color(0.75, 0.75, 0.75)

## Radar online/offline transition static.
const STATIC_SHADER: Shader = preload("res://shaders/ui/RadarStatic.gdshader")
const STATIC_EASE: float = 8.0
const STATIC_SNAP: float = 0.001

## Minimap display sizing/placement in the right-hand HUD column.
const MAX_MINIMAP_SIZE: float = 200.0
const HUD_COLUMN_CENTER: float = 200.0
const MINIMAP_TOP: float = 36.0

@export var refresh_interval: float = DEFAULT_REFRESH_INTERVAL

var _grid_size: Vector2i = Vector2i.ZERO
## Playable grid dimensions (W, H); the display aspect follows the inset play diamond.
var _map_cells: Vector2i = Vector2i.ZERO
## Visible-bounds insets (left, right, top, bottom) captured at bake time so the
## transform, clicks, and the baked crop all agree.
var _play_insets: Vector4i = Vector4i.ZERO
var _terrain: PackedByteArray = PackedByteArray()
var _working: PackedByteArray = PackedByteArray()
var _image: Image = null
var _texture: ImageTexture = null
var _refresh_accum: float = 0.0
var _terrain_pending: bool = false
var _cell_targets: Dictionary = {}
## Live only while the local player has radar (or the debug override is on).
var _radar_online: bool = true
## Panel held under the rising static: the state being left. `_draw()` keeps
## rendering it until the burst fully covers the panel, then swaps to the new
## steady content — so the destination panel never flashes before the static.
var _transition_from_online: bool = true
var _radar_system: Node = null
## Transition static overlay (built at runtime).
var _static_overlay: ColorRect = null
var _static_material: ShaderMaterial = null
var _static_amount: float = 0.0
var _static_rising: bool = false


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    # Linear sampling so the 45-degree orientation transform does not alias.
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    if custom_minimum_size == Vector2.ZERO:
        custom_minimum_size = Vector2(200, 200)
    _setup_static_overlay()
    _radar_system = RadarSystem
    _radar_online = _compute_radar_online()
    _transition_from_online = _radar_online
    _radar_system.radar_availability_changed.connect(_on_radar_availability_changed)
    TerrainSystem.grid_initialized.connect(_on_grid_initialized)
    if TerrainSystem.grid_cells != Vector2i.ZERO:
        _schedule_terrain_bake()


func _exit_tree() -> void:
    if TerrainSystem.grid_initialized.is_connected(_on_grid_initialized):
        TerrainSystem.grid_initialized.disconnect(_on_grid_initialized)
    if (
        _radar_system
        and is_instance_valid(_radar_system)
        and _radar_system.radar_availability_changed.is_connected(_on_radar_availability_changed)
    ):
        _radar_system.radar_availability_changed.disconnect(_on_radar_availability_changed)


func _process(delta: float) -> void:
    if Engine.is_editor_hint() or _is_map_editor():
        return
    _tick_static(delta)
    _refresh_accum += delta
    if _refresh_accum >= refresh_interval:
        _refresh_accum = 0.0
        _refresh()
    queue_redraw()


# ========================================
# Pure helpers (headless-testable)
# ========================================


static func cell_to_index(cell: Vector2i, width: int) -> int:
    if width <= 0 or cell.x < 0 or cell.y < 0:
        return -1
    return cell.y * width + cell.x


static func index_to_cell(index: int, width: int) -> Vector2i:
    if width <= 0 or index < 0:
        return Vector2i(-1, -1)
    return Vector2i(index % width, index / width)


## Land type used for terrain colour: the painted override unless it is empty or
## the resource-derived type, which is rendered as an overlay instead.
static func resolve_land_type_id(painted: String) -> String:
    if painted.is_empty() or painted == LAND_TYPE_RESOURCE:
        return LAND_TYPE_DEFAULT
    return painted


## Terrain colour for one cell, or null when the cell has no map colour.
static func shade_terrain(
    art: TerrainArtData, land_type: LandType, height_ratio: float, low: float, high: float
) -> Variant:
    var base: Variant = TerrainArtData.minimap_color(art, land_type)
    if base == null:
        return null
    return TerrainArtData.shade_map_color(base, height_ratio, low, high)


## Fog brightness multiplier for a resolved cell state. Shroud is black when the
## shroud toggle is on; explored cells are dimmed only when fog of war is on.
static func fog_factor(state: int, shroud_enabled: bool, fog_enabled: bool) -> float:
    match state:
        STATE_SHROUD:
            return 0.0 if shroud_enabled else 1.0
        STATE_FOG:
            return FOG_DIM if fog_enabled else 1.0
        _:
            return 1.0


## Overlay dot colour: transparent (omitted) in shroud, dimmed in fog, full when
## visible.
static func overlay_color(
    color: Color, state: int, shroud_enabled: bool, fog_enabled: bool
) -> Color:
    var factor := fog_factor(state, shroud_enabled, fog_enabled)
    if factor <= 0.0:
        return Color(0, 0, 0, 0)
    return Color(color.r * factor, color.g * factor, color.b * factor, color.a)


## Radar gate predicate — the minimap is live when the player owns an online
## radar or the debug override is engaged. Pure so the state logic is testable
## headless.
static func radar_gate_online(force_online: bool, online_count: int) -> bool:
    return force_online or online_count > 0


## Which panel `_draw()` renders: the held (from) panel while the static burst
## is still rising — the content swap happens only once it fully covers — and
## the steady state otherwise. Pure so the transition logic is testable
## headless.
static func shows_offline_panel(online: bool, static_rising: bool, from_online: bool) -> bool:
    return not (from_online if static_rising else online)


## Frame-rate independent exponential ease toward `target`, snapping on arrival
## (mirrors PowerBar._advance). Pure so the transition is testable headless.
static func ease_transition(
    current: float, target: float, delta: float, speed: float = STATIC_EASE
) -> float:
    var eased := lerpf(current, target, 1.0 - exp(-speed * delta))
    return target if absf(eased - target) < STATIC_SNAP else eased


# ========================================
# Orientation transform (index space <-> minimap pixels)
# ========================================
#
# The playable area is the map diamond inset by the visible-bounds insets. In
# cell-index space it is a smaller diamond (cells outside it are never
# revealable, so they are permanently shrouded). The gameplay camera is yawed
# ~45 degrees, so on screen the play diamond reads as an axis-aligned
# rectangle. The transform below rotates index space by 45 degrees and maps the
# inset play bounds onto the control rect, cropping the shrouded rim.


## Visible-bounds insets (left, right, top, bottom) from `BoundsSystem`; zeros
## when the system is absent (e.g. isolated tests).
static func play_insets() -> Vector4i:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return Vector4i.ZERO
    var bounds := tree.root.get_node_or_null("BoundsSystem")
    if bounds == null:
        return Vector4i.ZERO
    return Vector4i(
        int(bounds.get("left_inset")),
        int(bounds.get("right_inset")),
        int(bounds.get("top_inset")),
        int(bounds.get("bottom_inset")),
    )


## Inset play-diamond bounds in the (b = x - y, a = x + y - (W+H)) frame, as
## (b_lo, b_hi, a_lo, a_hi). The play diamond maps onto the control rect.
static func play_bounds(map_cells: Vector2i, insets: Vector4i) -> Vector4:
    var w := float(map_cells.x)
    var h := float(map_cells.y)
    return Vector4(
        -w + float(insets.x),
        w - float(insets.y),
        -h + float(insets.z),
        h - float(insets.w),
    )


## Whether a cell is inside the revealable play diamond (mirrors
## `BoundsSystem._in_play_diamond` with zero extra inset).
static func in_play_area(cell: Vector2i, map_cells: Vector2i, insets: Vector4i) -> bool:
    var w := float(map_cells.x)
    var h := float(map_cells.y)
    if w <= 0.0 or h <= 0.0:
        return false
    var center := (w + h) * 0.5
    var cx := float(cell.x) + 0.5 - center
    var cz := float(cell.y) + 0.5 - center
    var sum_axis := cx + cz
    var difference := cx - cz
    return (
        sum_axis >= -h + float(insets.z)
        and sum_axis < h - float(insets.w)
        and difference >= -w + float(insets.x)
        and difference < w - float(insets.y)
    )


## Minimap display size for the inset play diamond, preserving its aspect (the
## diff-axis : sum-axis spans from `play_bounds`) within `max_size`.
static func size_for_play_area(map_cells: Vector2i, insets: Vector4i, max_size: float) -> Vector2:
    var bounds := play_bounds(map_cells, insets)
    var span_b := bounds.y - bounds.x
    var span_a := bounds.w - bounds.z
    if span_b <= 0.0 or span_a <= 0.0:
        return Vector2(max_size, max_size)
    if span_b >= span_a:
        return Vector2(max_size, max_size * span_a / span_b)
    return Vector2(max_size * span_b / span_a, max_size)


## Continuous index-space position (cell + 0.5 = cell centre) -> minimap pixel,
## mapping the inset play bounds to the full control rect.
static func index_to_pixel(
    index: Vector2, map_cells: Vector2i, insets: Vector4i, size: Vector2
) -> Vector2:
    var w := float(map_cells.x)
    var h := float(map_cells.y)
    if w <= 0.0 or h <= 0.0:
        return Vector2.ZERO
    var bounds := play_bounds(map_cells, insets)
    var span_b := bounds.y - bounds.x
    var span_a := bounds.w - bounds.z
    if span_b <= 0.0 or span_a <= 0.0:
        return Vector2.ZERO
    var b := index.x - index.y
    var a := index.x + index.y - (w + h)
    return Vector2((b - bounds.x) * size.x / span_b, (a - bounds.z) * size.y / span_a)


## Inverse of `index_to_pixel`.
static func pixel_to_index(
    pixel: Vector2, map_cells: Vector2i, insets: Vector4i, size: Vector2
) -> Vector2:
    var w := float(map_cells.x)
    var h := float(map_cells.y)
    if w <= 0.0 or h <= 0.0:
        return Vector2.ZERO
    var bounds := play_bounds(map_cells, insets)
    var span_b := bounds.y - bounds.x
    var span_a := bounds.w - bounds.z
    if span_b <= 0.0 or span_a <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
        return Vector2.ZERO
    var b := bounds.x + pixel.x * span_b / size.x
    var a := bounds.z + pixel.y * span_a / size.y
    return Vector2((b + a + w + h) * 0.5, (a + w + h - b) * 0.5)


# ========================================
# Terrain bake
# ========================================


func _on_grid_initialized() -> void:
    _schedule_terrain_bake()


func _schedule_terrain_bake() -> void:
    if _terrain_pending:
        return
    _terrain_pending = true
    _bake_terrain.call_deferred()


# ========================================
# Radar gate
# ========================================


## Resolves local radar availability. Defaults live when the system is absent
## (isolated tests / an unwired scene) so rendering still works.
func _compute_radar_online() -> bool:
    if _radar_system == null:
        return true
    var pid := PlayerManager.get_local_player_id()
    return radar_gate_online(_radar_system.force_online, _radar_system.get_online_count(pid))


func _on_radar_availability_changed(player_id: int) -> void:
    if player_id != PlayerManager.get_local_player_id():
        return
    _set_radar_online(_compute_radar_online())


func _set_radar_online(online: bool) -> void:
    if online == _radar_online:
        return
    # Hold the panel being left while the burst rises; a flip mid-rise keeps
    # the currently held panel so rapid double flips never pop.
    if not _static_rising:
        _transition_from_online = _radar_online
    _radar_online = online
    # Play the static burst on every flip; it fades in then out to the steady
    # state (map when online, black OFFLINE when not).
    _static_amount = 0.0
    _static_rising = true
    if online:
        _refresh()
    queue_redraw()


## Runtime-built full-rect static overlay (no .tscn structural change —
## FogRenderer builds its planes in code the same way).
func _setup_static_overlay() -> void:
    _static_material = ShaderMaterial.new()
    _static_material.shader = STATIC_SHADER
    _static_material.set_shader_parameter("intensity", 0.0)
    _static_overlay = ColorRect.new()
    _static_overlay.name = "StaticOverlay"
    _static_overlay.material = _static_material
    _static_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _static_overlay.visible = false
    add_child(_static_overlay)
    _static_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Advances the transition pulse: full-strength static eases in, then eases out
## to zero. Settled states leave no residual static (overlay hidden).
func _tick_static(delta: float) -> void:
    if _static_overlay == null:
        return
    if _static_amount <= 0.0 and not _static_rising:
        if _static_overlay.visible:
            _static_overlay.visible = false
            _static_material.set_shader_parameter("intensity", 0.0)
        return
    var target := 1.0 if _static_rising else 0.0
    _static_amount = ease_transition(_static_amount, target, delta)
    if _static_rising and _static_amount >= 1.0:
        _static_rising = false
    _static_overlay.visible = true
    _static_material.set_shader_parameter("intensity", _static_amount)
    if not _static_rising and _static_amount <= 0.0:
        _static_amount = 0.0
        _static_overlay.visible = false
        _static_material.set_shader_parameter("intensity", 0.0)


## Deferred one frame so the active theater (set after terrain import) is
## resolved before colours are baked.
func _bake_terrain() -> void:
    _terrain_pending = false
    var grid: Vector2i = TerrainSystem.grid_cells
    if grid == Vector2i.ZERO:
        return
    var dims := CellUtil.get_diamond_extent(grid)
    _grid_size = dims
    _map_cells = grid
    _play_insets = play_insets()
    _apply_size_for_grid()
    _terrain = PackedByteArray()
    _terrain.resize(dims.x * dims.y * 4)
    var theater := TerrainCatalog.get_active_theater()
    var low := theater.low_radar_brightness if theater else 1.0
    var high := theater.high_radar_brightness if theater else 1.6
    for y in dims.y:
        for x in dims.x:
            var cell := Vector2i(x, y)
            if not CellUtil.is_in_diamond(cell, grid):
                continue
            # Crop the permanently-shrouded rim: only the revealable play diamond
            # is painted, so the inset bounds fill the control with no overflow.
            if not in_play_area(cell, grid, _play_insets):
                continue
            var land_id := resolve_land_type_id(TerrainSystem.get_painted_land_type(cell))
            var land_type := _lookup_land_type(land_id)
            var art := TerrainCatalog.get_cell_art(TerrainSystem.get_cell(cell))
            var color: Variant = shade_terrain(
                art,
                land_type,
                TerrainSystem.get_cell_height_ratio(cell),
                low,
                high,
            )
            if color == null:
                continue
            _write_texel(cell_to_index(cell, dims.x), color)
    _working = _terrain.duplicate()
    _image = Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_RGBA8, _working)
    _texture = ImageTexture.create_from_image(_image)


## Resizes and re-centres the minimap in the right-hand HUD column so its
## aspect ratio matches the inset play diamond and that diamond fills it.
func _apply_size_for_grid() -> void:
    var display := size_for_play_area(_map_cells, _play_insets, MAX_MINIMAP_SIZE)
    custom_minimum_size = Vector2.ZERO
    offset_left = -HUD_COLUMN_CENTER - display.x * 0.5
    offset_right = -HUD_COLUMN_CENTER + display.x * 0.5
    offset_top = MINIMAP_TOP
    offset_bottom = MINIMAP_TOP + display.y


func _lookup_land_type(land_id: String) -> LandType:
    var rules := GlobalRules.get_current()
    if rules == null or land_id.is_empty():
        return null
    return rules.get_land_type(land_id)


func _write_texel(index: int, color: Color) -> void:
    _write_rgba(_terrain, index * 4, color)


## Writes an opaque RGBA8 texel into `buffer` at byte offset `base`.
static func _write_rgba(buffer: PackedByteArray, base: int, color: Color) -> void:
    buffer[base] = int(clampf(color.r, 0.0, 1.0) * 255.0)
    buffer[base + 1] = int(clampf(color.g, 0.0, 1.0) * 255.0)
    buffer[base + 2] = int(clampf(color.b, 0.0, 1.0) * 255.0)
    buffer[base + 3] = 255


# ========================================
# Overlay + fog refresh
# ========================================


func _refresh() -> void:
    if not _radar_online:
        return
    if _terrain.is_empty() or _grid_size == Vector2i.ZERO:
        return
    _working = _terrain.duplicate()
    var shroud_on := ShroudSystem.is_shroud_enabled()
    var fog_on := ShroudSystem.is_fog_enabled()
    var states := PackedByteArray()
    if shroud_on or fog_on:
        states = ShroudSystem.get_effective_state(PlayerManager.get_local_player_id())
    _apply_fog(states, shroud_on, fog_on)
    _stamp_overlays(shroud_on, fog_on)
    _image = Image.create_from_data(_grid_size.x, _grid_size.y, false, Image.FORMAT_RGBA8, _working)
    if _texture == null:
        _texture = ImageTexture.create_from_image(_image)
    else:
        _texture.update(_image)


func _apply_fog(states: PackedByteArray, shroud_on: bool, fog_on: bool) -> void:
    var texels := _grid_size.x * _grid_size.y
    for i in texels:
        var base := i * 4
        var state := STATE_VISIBLE
        if not states.is_empty() and i < states.size():
            state = states[i]
        var factor := fog_factor(state, shroud_on, fog_on)
        _working[base] = int(_working[base] * factor)
        _working[base + 1] = int(_working[base + 1] * factor)
        _working[base + 2] = int(_working[base + 2] * factor)


func _stamp_overlays(shroud_on: bool, fog_on: bool) -> void:
    var targets := {}
    for group in OVERLAY_GROUPS:
        for node in get_tree().get_nodes_in_group(group):
            if not (node is Node3D):
                continue
            var world_node := node as Node3D
            var footprint := _overlay_footprint(world_node)
            var origin := CellUtil.world_to_cell_origin(world_node.global_position, footprint)
            var color: Variant = _resolve_overlay_color(world_node)
            if color == null:
                continue
            var state := STATE_VISIBLE
            if shroud_on or fog_on:
                state = ShroudSystem.cell_state_to_local(origin)
            var final: Color = overlay_color(color, state, shroud_on, fog_on)
            if final.a <= 0.0:
                continue
            for index in overlay_stamp_cells(footprint, origin, _grid_size):
                _write_working(index * 4, final)
                targets[index_to_cell(index, _grid_size.x)] = world_node
    _cell_targets = targets


## Footprint of an overlay entity in cells: buildings carry a
## `FoundationComponent` (created only when the footprint is larger than 1x1);
## units and resource crystals are a single cell.
func _overlay_footprint(node: Node3D) -> Vector2i:
    var foundation := node.get_node_or_null("FoundationComponent") as FoundationComponent
    if foundation:
        return foundation.foundation
    return Vector2i.ONE


## Texel indices covered by an entity's footprint anchored at `origin`, clipped
## to the texture grid. One texel per occupied cell, so a building reads at its
## real relative size and a unit stays a single texel.
static func overlay_stamp_cells(
    footprint: Vector2i, origin: Vector2i, grid_size: Vector2i
) -> PackedInt32Array:
    var cells := PackedInt32Array()
    if footprint.x <= 0 or footprint.y <= 0 or grid_size.x <= 0 or grid_size.y <= 0:
        return cells
    for dy in footprint.y:
        for dx in footprint.x:
            var cell := origin + Vector2i(dx, dy)
            # Guard x explicitly: cell_to_index only rejects negatives, so a
            # footprint crossing the right edge would wrap onto the next row.
            if cell.x < 0 or cell.y < 0 or cell.x >= grid_size.x or cell.y >= grid_size.y:
                continue
            cells.append(cell.y * grid_size.x + cell.x)
    return cells


func _resolve_overlay_color(node: Node3D) -> Variant:
    var owner_color: Variant = null
    var stats := node.get_node_or_null("StatsComponent") as StatsComponent
    if stats and stats.player_id >= 0:
        var player := PlayerManager.get_player_data(stats.player_id)
        if player:
            owner_color = player.color
    var art_comp := node.get_node_or_null("ArtComponent") as ArtComponent
    if art_comp and art_comp.art_data:
        var art_color: Variant = ArtData.minimap_color(art_comp.art_data, owner_color)
        if art_color != null:
            return art_color
    var resource := node.get_node_or_null("ResourceComponent") as ResourceComponent
    if resource:
        var rules := GlobalRules.get_current()
        if rules:
            var res_type := rules.get_resource_type(resource.resource_type_id)
            if res_type:
                return res_type.color
    return null


func _write_working(base: int, color: Color) -> void:
    _write_rgba(_working, base, color)


# ========================================
# Drawing
# ========================================


func _draw() -> void:
    if shows_offline_panel(_radar_online, _static_rising, _transition_from_online):
        _draw_offline()
        return
    if _texture == null or _grid_size == Vector2i.ZERO:
        return
    # Draw the index-space texture through the 45-degree orientation transform,
    # then draw the view rectangle in unrotated pixels (crisp 1px stroke).
    draw_set_transform_matrix(_draw_transform())
    var extent := float(_grid_size.x)
    draw_texture_rect(_texture, Rect2(0.0, 0.0, extent, extent), false)
    draw_set_transform_matrix(Transform2D.IDENTITY)
    _draw_view_rect()


## Offline placeholder: black panel with a centered OFFLINE label. Placeholder
## art until the sidebar-art workstream provides a radar-down visual.
func _draw_offline() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
    var font := get_theme_default_font()
    if font == null:
        return
    var text_size := font.get_string_size(
        OFFLINE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, OFFLINE_FONT_SIZE
    )
    var pos := Vector2(
        (size.x - text_size.x) * 0.5,
        (size.y + text_size.y) * 0.5 - font.get_descent(OFFLINE_FONT_SIZE)
    )
    draw_string(
        font,
        pos,
        OFFLINE_TEXT,
        HORIZONTAL_ALIGNMENT_LEFT,
        -1.0,
        OFFLINE_FONT_SIZE,
        OFFLINE_TEXT_COLOR
    )


## Affine transform mapping index-space points to minimap pixels, matching
## `index_to_pixel` and the inset play-area control size.
func _draw_transform() -> Transform2D:
    var w := float(_map_cells.x)
    var h := float(_map_cells.y)
    if w <= 0.0 or h <= 0.0:
        return Transform2D.IDENTITY
    var bounds := play_bounds(_map_cells, _play_insets)
    var span_b := bounds.y - bounds.x
    var span_a := bounds.w - bounds.z
    if span_b <= 0.0 or span_a <= 0.0:
        return Transform2D.IDENTITY
    var sx := size.x / span_b
    var sy := size.y / span_a
    return Transform2D(
        Vector2(sx, sy), Vector2(-sx, sy), Vector2(-bounds.x * sx, (-(w + h) - bounds.z) * sy)
    )


## Liang-Barsky clip of a line segment to an axis-aligned rect. Returns the
## inside portion as [start, end], or an empty array when fully outside. Used
## per rectangle edge so a large view footprint is cropped to its visible chunk
## instead of tracing the minimap border.
static func clip_segment_to_rect(a: Vector2, b: Vector2, rect: Rect2) -> PackedVector2Array:
    var dx := b.x - a.x
    var dy := b.y - a.y
    var t0 := 0.0
    var t1 := 1.0
    for edge in 4:
        var p := 0.0
        var q := 0.0
        match edge:
            0:
                p = -dx
                q = a.x - rect.position.x
            1:
                p = dx
                q = rect.end.x - a.x
            2:
                p = -dy
                q = a.y - rect.position.y
            _:
                p = dy
                q = rect.end.y - a.y
        if is_zero_approx(p):
            if q < 0.0:
                return PackedVector2Array()
            continue
        var r := q / p
        if p < 0.0:
            if r > t1:
                return PackedVector2Array()
            if r > t0:
                t0 = r
        else:
            if r < t0:
                return PackedVector2Array()
            if r < t1:
                t1 = r
    return PackedVector2Array([a + Vector2(dx, dy) * t0, a + Vector2(dx, dy) * t1])


func _draw_view_rect() -> void:
    var cam := get_viewport().get_camera_3d()
    var pivot: Node3D = BoundsSystem.camera_pivot
    if cam == null or pivot == null or _grid_size == Vector2i.ZERO:
        return
    var plane := Plane(Vector3.UP, pivot.global_position.y)
    var viewport_size := get_viewport().get_visible_rect().size
    var corners := [
        Vector2.ZERO,
        Vector2(viewport_size.x, 0.0),
        viewport_size,
        Vector2(0.0, viewport_size.y),
    ]
    var points := PackedVector2Array()
    for corner in corners:
        var origin := cam.project_ray_origin(corner)
        var direction := cam.project_ray_normal(corner)
        var hit: Variant = plane.intersects_ray(origin, direction)
        if hit == null:
            return
        points.append(index_to_pixel(_world_to_index(hit), _map_cells, _play_insets, size))
    var clip_rect := Rect2(Vector2.ZERO, size)
    var color := Color(1.0, 1.0, 1.0, 0.9)
    for i in points.size():
        var segment := clip_segment_to_rect(points[i], points[(i + 1) % points.size()], clip_rect)
        if segment.size() == 2:
            draw_line(segment[0], segment[1], color, 1.0)


## World ground position -> continuous index-space coordinate.
func _world_to_index(world: Vector3) -> Vector2:
    var grid: Vector2i = TerrainSystem.grid_cells
    var center := float(grid.x + grid.y) * 0.5
    return Vector2(
        world.x / CellUtil.CELL_SIZE + center,
        world.z / CellUtil.CELL_SIZE + center,
    )


# ========================================
# Input
# ========================================


func _gui_input(event: InputEvent) -> void:
    if not _radar_online:
        return
    if _is_map_editor() or not (event is InputEventMouseButton):
        return
    var mb := event as InputEventMouseButton
    if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
        return
    var cell := _pixel_to_cell(mb.position)
    if cell.x < 0:
        return
    _handle_click(cell)
    accept_event()


func _pixel_to_cell(click: Vector2) -> Vector2i:
    if _grid_size == Vector2i.ZERO or _map_cells == Vector2i.ZERO:
        return Vector2i(-1, -1)
    var index := pixel_to_index(click, _map_cells, _play_insets, size)
    var cell := Vector2i(int(floor(index.x)), int(floor(index.y)))
    if not in_play_area(cell, _map_cells, _play_insets):
        return Vector2i(-1, -1)
    return cell


func _handle_click(cell: Vector2i) -> void:
    # Build and placement modes own the left-click: on the minimap they only
    # relocate the view and never issue orders.
    if _is_placement_mode():
        BoundsSystem.center_camera_on_cell(cell)
        return
    var target: Node3D = _cell_targets.get(cell) as Node3D
    var target_level := _top_surface_level(cell)
    var world := _ground_order_pos(cell, target_level)
    var modifiers := OrderSystem.build_modifiers(Input.is_key_pressed(KEY_SHIFT))
    modifiers[OrderResult.MOD_TARGET_LEVEL] = target_level
    var resolution := OrderSystem.resolve(target, cell, world, modifiers)
    if resolution.orders.is_empty():
        BoundsSystem.center_camera_on_cell(cell)
        return
    OrderSystem.issue(resolution.orders)


## Top walkable surface level on a cell (0 when no deck covers it).
func _top_surface_level(cell: Vector2i) -> int:
    var levels := TerrainSystem.get_cell_surface_levels(cell)
    return levels[levels.size() - 1] if not levels.is_empty() else 0


## World point a minimap order aims at: the cell centre at its top walkable
## surface, so a click on a bridge cell targets the deck (matching the main
## viewport's raycast pick) instead of the ground beneath it.
func _ground_order_pos(cell: Vector2i, level: int) -> Vector3:
    var world := CellUtil.cell_to_world(cell)
    world.y = TerrainSystem.get_cell_surface_height(cell, level)
    return world


## True while a building or free-placement mode is active; both suppress minimap
## commands in favor of panning only.
func _is_placement_mode() -> bool:
    return BuildingManager.is_build_mode or EntityPlacer.is_placing()


func _is_map_editor() -> bool:
    var scene := get_tree().current_scene
    return scene != null and scene.has_meta(MAP_EDITOR_META)
