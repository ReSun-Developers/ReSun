extends Node

## Renders the ShroudSystem fog grid as a world-aligned overlay plane and applies
## fog-driven visual culling to enemy buildings. Unit culling lives in
## UnitMeshRenderer. Inert when fog_of_war is false.

const FOG_SHADER: Shader = preload("res://shaders/maps/FogOfWarPlane.gdshader")
const FOG_SHADER_OPAQUE: Shader = preload("res://shaders/maps/FogShroudPlane.gdshader")

## Height above the terrain surface the fog plane drapes, to avoid z-fighting
## while keeping the reveal edge at ground height (no camera parallax).
const PLANE_EPSILON: float = 0.02

## World-units the overlay planes are lifted above the terrain so the OPAQUE
## shroud sheet sits closer to the tilted camera than any ground entity — the
## depth pass then occludes units/buildings/Tiberium in shrouded cells without
## relying on per-instance culling. The XZ components shift the sheet laterally
## to compensate the parallax the lift introduces (a tuning knob, not exact for
## every camera pitch).
const SHROUD_LIFT_XZ: float = 40.0
const SHROUD_LIFT_Y: float = 40.0 * TerrainSystem.HEIGHT_STEP

## Cells of flat shroud added past each edge of the map square, so the plane
## still covers the viewport when the camera is panned to a map edge (ortho
## camera shows ~40 world units past the visible diamond). The fog texture only
## covers the map square; the rim renders shroud via the shader's out-of-range
## UV check.
const RIM_MARGIN: int = 32

## Soft-edge band widths (in cells) for the shroud and fog boundaries, mirrored
## into the fog shader as `shroud_grow` / `shroud_falloff` / `fog_grow` /
## `fog_falloff`. `*_grow` extends the fully-opaque zone past the region
## boundary so the opaque sheet's crisp edge hides under it; `*_falloff` is the
## smoothstep width beyond that. Tunable at runtime through those uniforms
## without a rebake.
const SHROUD_GROW: float = 0.5
const SHROUD_FALLOFF: float = 1.5
const FOG_GROW: float = 0.25
const FOG_FALLOFF: float = 1.0

## Max ring distance baked into the edge mask; must exceed the largest falloff
## width so the smoothstep saturates before the sentinel is reached.
const MASK_MAX_RING: int = 4

var _plane: MeshInstance3D
var _plane_opaque: MeshInstance3D
var _material: ShaderMaterial
var _material_opaque: ShaderMaterial
var _last_states := PackedByteArray()
var _buildings: Dictionary = {}
var _overlays: Dictionary = {}

## Standalone dev scenes (asset browser, map editor) carry no gameplay fog; set
## false to keep the world-space fog/shroud plane hidden regardless of rules.
var overlay_enabled := true

## One deferred _sync_overlays() per frame while any overlay is unstaged, so K
## unstaged crystals schedule linear work, not K deferred sweeps per node.
const MAX_OVERLAY_RESYNC_TICKS: int = 3

var _overlay_resync_pending: bool = false
var _overlay_resync_ticks: int = 0

## Persistent textures/images: created once per grid init, updated in place on
## state changes (ImageTexture.update) instead of re-allocating per resolve.
var _grid_image: Image = null
var _mask_image: Image = null
var _grid_tex: ImageTexture = null
var _mask_tex: ImageTexture = null
var _shroud_dist := PackedByteArray()
var _fog_dist := PackedByteArray()


func _ready() -> void:
    _material = ShaderMaterial.new()
    _material.shader = FOG_SHADER
    _plane = MeshInstance3D.new()
    _plane.name = "FogOfWarPlane"
    _plane.material_override = _material
    _plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _plane.extra_cull_margin = 100.0
    add_child(_plane)
    _material_opaque = ShaderMaterial.new()
    _material_opaque.shader = FOG_SHADER_OPAQUE
    _plane_opaque = MeshInstance3D.new()
    _plane_opaque.name = "FogShroudPlane"
    _plane_opaque.material_override = _material_opaque
    _plane_opaque.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _plane_opaque.extra_cull_margin = 100.0
    add_child(_plane_opaque)
    _plane.visible = false
    _plane_opaque.visible = false
    ShroudSystem.state_changed.connect(_on_shroud_changed)
    TerrainSystem.grid_initialized.connect(_on_grid_initialized)
    get_tree().node_added.connect(_on_node_added)
    get_tree().node_removed.connect(_on_node_removed)
    if TerrainSystem.grid_cells != Vector2i.ZERO:
        _on_grid_initialized()


func _exit_tree() -> void:
    if ShroudSystem.state_changed.is_connected(_on_shroud_changed):
        ShroudSystem.state_changed.disconnect(_on_shroud_changed)
    if TerrainSystem.grid_initialized.is_connected(_on_grid_initialized):
        TerrainSystem.grid_initialized.disconnect(_on_grid_initialized)
    if get_tree() and get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.disconnect(_on_node_added)
    if get_tree() and get_tree().node_removed.is_connected(_on_node_removed):
        get_tree().node_removed.disconnect(_on_node_removed)


## Building reveal is event-driven: resolved shroud state only changes on the
## state_changed signal (or a building spawn), so the old per-frame poll
## recomputed a constant. The opaque shroud sheet depth-occludes anything a
## stale flag would leave visible in the window between resolves.
func _sync_buildings() -> void:
    if Engine.is_editor_hint():
        return
    var scene := get_tree().current_scene
    if scene != null and scene.has_meta("is_map_editor"):
        return
    for entity in _buildings.keys():
        var node: Node3D = entity
        if not is_instance_valid(node):
            _buildings.erase(entity)
            continue
        _sync_building(node)


func _sync_overlays() -> void:
    if Engine.is_editor_hint():
        return
    var scene := get_tree().current_scene
    if scene != null and scene.has_meta("is_map_editor"):
        return
    var is_retry: bool = _overlay_resync_pending
    if is_retry:
        _overlay_resync_ticks += 1
        if _overlay_resync_ticks > MAX_OVERLAY_RESYNC_TICKS:
            # A never-staged crystal has burned the retry budget; stop re-queuing
            # until the next real event resets it (a busy loop otherwise).
            _overlay_resync_pending = false
            return
    else:
        # Fresh event (shroud change, grid init): reset the retry budget.
        _overlay_resync_ticks = 0
    _overlay_resync_pending = false
    for entity in _overlays.keys():
        var node: Node3D = entity
        if not is_instance_valid(node):
            _overlays.erase(entity)
            continue
        _sync_overlay(node)


func _sync_building(node: Node3D) -> void:
    var stats := node.get_node_or_null("StatsComponent") as StatsComponent
    if stats == null or stats.player_id < 0:
        return
    if not PlayerManager.is_enemy(PlayerManager.get_local_player_id(), stats.player_id):
        return
    if node.has_meta("detached"):
        return
    var depot := GhostDepot.get_instance()
    var art := node.get_node_or_null("ArtComponent") as ArtComponent
    var model: Node3D = art.get_model_root() if art else null
    var state := _entity_fog_state(node)
    if state == ShroudSystem.STATE_VISIBLE:
        node.visible = true
        if depot:
            depot.release_entry(node)
        return
    if state == ShroudSystem.STATE_FOG:
        # Freeze the model in the depot; the building root carries no visual
        # (door/construction appearance is frozen with the ghost).
        if is_instance_valid(model):
            node.visible = false
            if depot:
                (
                    depot
                    . reparent_in(
                        node,
                        model,
                        model.get_parent(),
                        CellUtil.world_to_cell(node.global_position),
                        false,
                    )
                )
            return
        node.visible = true
        return
    node.visible = false
    if depot:
        depot.release_entry(node)


## Fog/visible/shroud classification for an entity, using the building
## foundation gate (visible when ANY foundation cell is visible; ghosted in
## fog when any foundation cell has been explored).
func _entity_fog_state(node: Node3D) -> int:
    var foundation := Vector2i(1, 1)
    var fc := node.get_node_or_null("FoundationComponent") as FoundationComponent
    if fc:
        foundation = fc.foundation
    var origin := CellUtil.world_to_cell_origin(node.global_position, foundation)
    for dx in foundation.x:
        for dz in foundation.y:
            if (
                ShroudSystem.cell_state_to_local(origin + Vector2i(dx, dz))
                == ShroudSystem.STATE_VISIBLE
            ):
                return ShroudSystem.STATE_VISIBLE
    if ShroudSystem.is_entity_revealed_to_local(node):
        return ShroudSystem.STATE_FOG
    return ShroudSystem.STATE_SHROUD


## Tiberium overlay freeze: the harvest-stage container is reparented into the
## depot so the stage visible on fog entry stays frozen. A crystal that spawned
## into fog was never revealed, so it has no last-known visual and stays hidden
## until its cell reveals (`_overlays` tracks the ever-seen flag). Shroud-hide
## is #276.
func _sync_overlay(node: Node3D) -> void:
    if not is_instance_valid(node):
        return
    var depot := GhostDepot.get_instance()
    var rc := node.get_node_or_null("ResourceComponent") as ResourceComponent
    var state := _overlay_fog_state(node)
    var ever_seen: bool = _overlays.get(node, false)
    if state == ShroudSystem.STATE_VISIBLE:
        _overlays[node] = true
        node.visible = true
        if depot:
            depot.release_entry(node)
        return
    if state == ShroudSystem.STATE_FOG:
        if not ever_seen and not (depot and depot.has_ghost(node)):
            node.visible = false
            return
        var stage: Node3D = rc.get_active_stage_node() if rc else null
        if not is_instance_valid(stage):
            # Stage containers build deferred in _ready (global_position must be
            # settled), so a crystal has no stage on the node_added pass. Hide it
            # and re-sync once the build lands so a seen crystal still freezes
            # like any other. The flag dedupes to one deferred sweep regardless
            # of how many crystals are unstaged (linear, not one per node).
            node.visible = false
            if not _overlay_resync_pending:
                _overlay_resync_pending = true
                _sync_overlays.call_deferred()
            return
        node.visible = true
        if depot:
            (
                depot
                . reparent_in(
                    node,
                    stage,
                    stage.get_parent(),
                    CellUtil.world_to_cell(node.global_position),
                    false,
                )
            )
        return
    node.visible = true
    if depot:
        depot.release_entry(node)


func _overlay_fog_state(node: Node3D) -> int:
    return ShroudSystem.cell_state_to_local(CellUtil.world_to_cell(node.global_position))


func _on_shroud_changed(dirty: PackedInt32Array) -> void:
    if Engine.is_editor_hint():
        return
    if _is_map_editor():
        _set_plane_visible(false)
        _clear_textures()
        return
    # Re-sync the toggle uniforms every signal: `_layout_plane` only runs on grid
    # init, so a runtime toggle (DebugMenu -> refresh) would otherwise leave
    # `fog_enabled`/`shroud_enabled` stale and the shader never show fog.
    var shroud: bool = ShroudSystem.is_shroud_enabled()
    var fog: bool = ShroudSystem.is_fog_enabled()
    _material.set_shader_parameter("shroud_enabled", shroud)
    _material.set_shader_parameter("fog_enabled", fog)
    _material.set_shader_parameter("shroud_grow", SHROUD_GROW)
    _material.set_shader_parameter("shroud_falloff", SHROUD_FALLOFF)
    _material.set_shader_parameter("fog_grow", FOG_GROW)
    _material.set_shader_parameter("fog_falloff", FOG_FALLOFF)
    _material_opaque.set_shader_parameter("shroud_enabled", shroud)
    # Building flips ride the same event as the fog texture, so they land
    # atomically; also force-reveals when both toggles are off (shroud off ->
    # is_entity_revealed_to_local returns true).
    _sync_buildings()
    _sync_overlays()
    if not shroud and not fog:
        _set_plane_visible(false)
        _clear_textures()
        return
    _set_plane_visible(true)
    if _grid_tex == null:
        _init_textures(ShroudSystem.get_effective_state(PlayerManager.get_local_player_id()))
        return
    if dirty.is_empty():
        return
    var local := PlayerManager.get_local_player_id()
    var changed: Array[int] = []
    for idx in dirty:
        if idx < 0 or idx >= _last_states.size():
            continue
        var s: int = ShroudSystem.get_cell_effective_state(local, idx)
        if s != _last_states[idx]:
            _last_states[idx] = s
            changed.append(idx)
    if changed.is_empty():
        return
    _update_textures(changed)


func _on_grid_initialized() -> void:
    if _is_map_editor():
        _set_plane_visible(false)
        _clear_textures()
        return
    _last_states = PackedByteArray()
    _layout_plane()
    if not ShroudSystem.is_shroud_enabled() and not ShroudSystem.is_fog_enabled():
        _set_plane_visible(false)
        _clear_textures()
        return
    _set_plane_visible(true)
    _init_textures(ShroudSystem.get_effective_state(PlayerManager.get_local_player_id()))
    _sync_buildings()
    _sync_overlays()


## Re-applies the shroud/fog toggles (uniforms + plane visibility + texture)
## after the debug menu changes GlobalRules. Nulls the texture refs so the next
## signal does a full rebuild even when no cell state changed.
func refresh() -> void:
    _grid_tex = null
    _mask_tex = null
    _last_states = PackedByteArray()
    _on_shroud_changed(PackedInt32Array())


func _layout_plane() -> void:
    var grid: Vector2i = TerrainSystem.grid_cells
    var extent := CellUtil.get_diamond_extent(grid)
    var origin := _grid_origin(grid)
    var size := Vector2(extent.x * CellUtil.CELL_SIZE, extent.y * CellUtil.CELL_SIZE)
    var mesh := _build_draped_mesh()
    _plane.mesh = mesh
    _plane_opaque.mesh = mesh
    # The sheets are lifted above entity height (SHROUD_LIFT_Y) so the opaque
    # shroud pass depth-occludes every entity in a shrouded cell — guaranteed
    # coverage without per-instance culling. The XZ offset (SHROUD_LIFT_XZ)
    # compensates the parallax the lift causes under the tilted camera; it is a
    # tuning knob. The shaders sample world-space XZ, so the pattern stays
    # column-pinned as long as grid_origin is offset by the same XZ amount.
    var lift := Vector3(SHROUD_LIFT_XZ, SHROUD_LIFT_Y, SHROUD_LIFT_XZ)
    _plane.position = lift
    _plane_opaque.position = lift
    # Redot's PlaneMesh defaults to FACE_Y (horizontal); no pitch rotation needed.
    origin += Vector2(SHROUD_LIFT_XZ, SHROUD_LIFT_XZ)
    _material.set_shader_parameter("grid_origin", origin)
    _material.set_shader_parameter("grid_size", size)
    _material.set_shader_parameter("shroud_enabled", ShroudSystem.is_shroud_enabled())
    _material.set_shader_parameter("fog_enabled", ShroudSystem.is_fog_enabled())
    _material.set_shader_parameter("shroud_grow", SHROUD_GROW)
    _material.set_shader_parameter("shroud_falloff", SHROUD_FALLOFF)
    _material.set_shader_parameter("fog_grow", FOG_GROW)
    _material.set_shader_parameter("fog_falloff", FOG_FALLOFF)
    # Transparent-pass sorting: above the CloudShadowPlane and unit ghosts, but
    # below the 2D SelectionOverlay CanvasLayer (layer 128). RENDER_PRIORITY_MAX
    # clamps at 127 in this engine.
    _material.render_priority = 127
    _material_opaque.set_shader_parameter("grid_origin", origin)
    _material_opaque.set_shader_parameter("grid_size", size)
    _material_opaque.set_shader_parameter("shroud_enabled", ShroudSystem.is_shroud_enabled())
    # UV size of one cell, for the opaque sheet's erosion neighbor taps.
    var texel := Vector2(1.0 / float(extent.x), 1.0 / float(extent.y))
    _material_opaque.set_shader_parameter("grid_texel", texel)


## Builds a grid mesh draping the terrain surface (+PLANE_EPSILON) so the shroud
## follows slopes and reveal edges sit at ground height (no parallax offset).
## Covers the whole map square plus a RIM_MARGIN of flat shroud on every side;
## `TerrainSystem.get_vertex` returns 0 for out-of-diamond keys, so off-map cells
## drape flat. The full sheet renders as shroud beyond the map square because the
## shader forces out-of-range UVs to the shroud state.
func _build_draped_mesh() -> ArrayMesh:
    var extent := CellUtil.get_diamond_extent(TerrainSystem.grid_cells)
    var center: float = float(TerrainSystem.grid_cells.x + TerrainSystem.grid_cells.y) * 0.5
    var cs := CellUtil.CELL_SIZE
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    var vertex_indices: Dictionary = {}
    for cz in range(-RIM_MARGIN, extent.y + RIM_MARGIN):
        for cx in range(-RIM_MARGIN, extent.x + RIM_MARGIN):
            var quad := PackedInt32Array()
            quad.resize(4)
            var corners := [
                Vector2i(cx, cz),
                Vector2i(cx + 1, cz),
                Vector2i(cx, cz + 1),
                Vector2i(cx + 1, cz + 1),
            ]
            for i in 4:
                var key: Vector2i = corners[i]
                var idx: int = vertex_indices.get(key, -1)
                if idx < 0:
                    idx = vertices.size()
                    var height: float = (
                        float(TerrainSystem.get_vertex(key.x, key.y)) * TerrainSystem.HEIGHT_STEP
                    )
                    var vertex := Vector3(
                        (float(key.x) - center) * cs,
                        height + PLANE_EPSILON,
                        (float(key.y) - center) * cs,
                    )
                    vertices.append(vertex)
                    vertex_indices[key] = idx
                quad[i] = idx
            indices.append(quad[0])
            indices.append(quad[1])
            indices.append(quad[3])
            indices.append(quad[0])
            indices.append(quad[3])
            indices.append(quad[2])
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


func _grid_origin(grid: Vector2i) -> Vector2:
    var center: float = float(grid.x + grid.y) * 0.5
    var min_x := (0.5 - center) * CellUtil.CELL_SIZE - CellUtil.CELL_SIZE * 0.5
    var min_z := (0.5 - center) * CellUtil.CELL_SIZE - CellUtil.CELL_SIZE * 0.5
    return Vector2(min_x, min_z)


## Full (re)build of the persistent grid + edge-mask images/textures from a
## freshly computed effective-state buffer. Runs on grid init and on the first
## signal after a refresh — never per state change.
func _init_textures(states: PackedByteArray) -> void:
    var extent := CellUtil.get_diamond_extent(TerrainSystem.grid_cells)
    if extent.x <= 0 or extent.y <= 0 or states.is_empty():
        return
    _last_states = states
    _grid_image = Image.create_from_data(extent.x, extent.y, false, Image.FORMAT_L8, states)
    _shroud_dist = _ring_distance(states, 0, extent.x, extent.y)
    _fog_dist = _ring_distance(states, 1, extent.x, extent.y)
    _mask_image = _mask_from_dists(extent.x, extent.y)
    _grid_tex = ImageTexture.create_from_image(_grid_image)
    _mask_tex = ImageTexture.create_from_image(_mask_image)
    _material.set_shader_parameter("fog_grid", _grid_tex)
    _material_opaque.set_shader_parameter("fog_grid", _grid_tex)
    _material.set_shader_parameter("edge_mask", _mask_tex)


## Packs the two persistent distance buffers into the RG8 edge-mask image
## (R = shroud ring distance, G = fog ring distance).
func _mask_from_dists(width: int, height: int) -> Image:
    var data := PackedByteArray()
    data.resize(width * height * 2)
    for i in width * height:
        data[i * 2] = _shroud_dist[i]
        data[i * 2 + 1] = _fog_dist[i]
    return Image.create_from_data(width, height, false, Image.FORMAT_RG8, data)


## Applies an incremental effective-state change: writes the changed cells into
## the persistent L8 grid image and re-bakes only the affected edge-mask band,
## then re-uploads both textures in place.
func _update_textures(changed: Array[int]) -> void:
    var extent := CellUtil.get_diamond_extent(TerrainSystem.grid_cells)
    var width := extent.x
    var height := extent.y
    for idx in changed:
        var v := float(_last_states[idx]) / 255.0
        (
            _grid_image
            . set_pixel(
                idx % width,
                idx / width,
                Color(v, v, v, 1.0),
            )
        )
    _update_edge_mask(changed, width, height)
    if _grid_tex:
        _grid_tex.update(_grid_image)
    if _mask_tex:
        _mask_tex.update(_mask_image)


## Incremental re-bake of the edge-mask band around the changed cells. The band
## (changed cells dilated by MASK_MAX_RING) is the only region whose ring
## distances can change; a 2-sweep Chebyshev distance transform restricted to a
## region dilated one ring further recomputes it exactly — all sources that can
## affect a band cell lie inside that region, and cells outside it keep their
## correct previous values. Cost scales with the changed area, not grid size.
func _update_edge_mask(changed: Array[int], width: int, height: int) -> void:
    if changed.is_empty() or _mask_image == null:
        return
    var min_x := 0x7FFFFFFF
    var min_y := 0x7FFFFFFF
    var max_x := -1
    var max_y := -1
    for idx in changed:
        var x := idx % width
        var y := idx / width
        min_x = mini(min_x, x)
        min_y = mini(min_y, y)
        max_x = maxi(max_x, x)
        max_y = maxi(max_y, y)
    min_x = maxi(min_x - MASK_MAX_RING * 2, 0)
    min_y = maxi(min_y - MASK_MAX_RING * 2, 0)
    max_x = mini(max_x + MASK_MAX_RING * 2, width - 1)
    max_y = mini(max_y + MASK_MAX_RING * 2, height - 1)
    # Reset the band (changed dilated by ring) to valid upper bounds; targets
    # keep distance 0, everything else restarts at the ring sentinel.
    for idx in changed:
        var cx := idx % width
        var cy := idx / width
        for y in range(maxi(cy - MASK_MAX_RING, min_y), mini(cy + MASK_MAX_RING, max_y) + 1):
            for x in range(maxi(cx - MASK_MAX_RING, min_x), mini(cx + MASK_MAX_RING, max_x) + 1):
                var i := y * width + x
                var is_shroud: bool = _last_states[i] == ShroudSystem.STATE_SHROUD
                var is_fog: bool = _last_states[i] == ShroudSystem.STATE_FOG
                _shroud_dist[i] = 0 if is_shroud else MASK_MAX_RING
                _fog_dist[i] = 0 if is_fog else MASK_MAX_RING
    _sweep_dist(_shroud_dist, width, height, min_x, min_y, max_x, max_y)
    _sweep_dist(_fog_dist, width, height, min_x, min_y, max_x, max_y)
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            var i := y * width + x
            (
                _mask_image
                . set_pixel(
                    x,
                    y,
                    Color(
                        float(_shroud_dist[i]) / 255.0,
                        float(_fog_dist[i]) / 255.0,
                        0.0,
                        1.0,
                    ),
                )
            )


## Two-pass Chebyshev distance transform to the nearest texel whose effective
## state equals `target`, clamped to MASK_MAX_RING. Counts diagonal neighbors at
## the same cost as cardinal ones (8-neighbor, L-infinity), so the falloff band
## aligns equally to axes and diagonals — the 45-degree rotation of a Manhattan
## diamond. Exact (no edge artifact): every cell is relaxed from all 8
## directions; neighbors outside the grid are guarded.
func _ring_distance(
    states: PackedByteArray,
    target: int,
    width: int,
    height: int,
) -> PackedByteArray:
    var dist := PackedByteArray()
    dist.resize(states.size())
    for i in states.size():
        dist[i] = 0 if states[i] == target else MASK_MAX_RING
    _sweep_dist(dist, width, height, 0, 0, width - 1, height - 1)
    return dist


## Two-pass Chebyshev distance relaxation over a sub-rectangle of a distance
## buffer. Cells outside the rectangle hold valid upper bounds (their exact
## value), so restricting the sweep to the band region recomputes it exactly.
## Forward pass relaxes N/W/NW/NE, backward the other four — with out-of-grid
## neighbors guarded so the east column and south row are relaxed too.
func _sweep_dist(
    dist: PackedByteArray,
    width: int,
    height: int,
    min_x: int,
    min_y: int,
    max_x: int,
    max_y: int,
) -> void:
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            var idx := y * width + x
            var best := dist[idx]
            if y > 0 and dist[idx - width] + 1 < best:
                best = dist[idx - width] + 1
            if x > 0 and dist[idx - 1] + 1 < best:
                best = dist[idx - 1] + 1
            if x > 0 and y > 0 and dist[idx - width - 1] + 1 < best:
                best = dist[idx - width - 1] + 1
            if x < width - 1 and y > 0 and dist[idx - width + 1] + 1 < best:
                best = dist[idx - width + 1] + 1
            dist[idx] = best
    for y in range(max_y, min_y - 1, -1):
        for x in range(max_x, min_x - 1, -1):
            var idx := y * width + x
            var best := dist[idx]
            if x < width - 1 and dist[idx + 1] + 1 < best:
                best = dist[idx + 1] + 1
            if y < height - 1 and dist[idx + width] + 1 < best:
                best = dist[idx + width] + 1
            if x < width - 1 and y < height - 1 and dist[idx + width + 1] + 1 < best:
                best = dist[idx + width + 1] + 1
            if x > 0 and y < height - 1 and dist[idx + width - 1] + 1 < best:
                best = dist[idx + width - 1] + 1
            dist[idx] = best


func _clear_textures() -> void:
    _grid_tex = null
    _mask_tex = null
    _material.set_shader_parameter("fog_grid", null)
    _material.set_shader_parameter("edge_mask", null)
    _material_opaque.set_shader_parameter("fog_grid", null)


## True when running the runtime MapEditor tool. The map editor owns terrain
## authoring, so the fog-of-war overlay (and its shroud darkening) must stay off.
func _is_map_editor() -> bool:
    var scene := get_tree().current_scene
    return scene != null and scene.has_meta("is_map_editor")


## True when `node` hangs under the runtime MapEditor (any ancestor carries the
## editor meta). `_is_map_editor()` only catches the whole-scene case, but
## entities/building nodes added to the editor are subtree children.
static func _is_under_map_editor(node: Node) -> bool:
    var ancestor := node
    while ancestor:
        if ancestor.has_meta("is_map_editor"):
            return true
        ancestor = ancestor.get_parent()
    return false


func _set_plane_visible(visible: bool) -> void:
    # The fog plane carries the soft shroud band as well as the fog dim, so it
    # renders when either toggle is on (default state is shroud on / fog off).
    var overlay_visible: bool = (
        overlay_enabled
        and visible
        and (ShroudSystem.is_shroud_enabled() or ShroudSystem.is_fog_enabled())
    )
    if is_instance_valid(_plane) and _plane.visible != overlay_visible:
        _plane.visible = overlay_visible
    var opaque_visible: bool = overlay_enabled and visible and ShroudSystem.is_shroud_enabled()
    if is_instance_valid(_plane_opaque) and _plane_opaque.visible != opaque_visible:
        _plane_opaque.visible = opaque_visible


## Hide or restore the world-space fog/shroud overlay. Standalone preview scenes
## call this with `false` so gameplay fog never drapes over the inspected asset;
## `true` rebuilds it from the current shroud state. Returns the previous flag
## so callers can restore the exact prior state on exit.
func set_overlay_enabled(enabled: bool) -> bool:
    var previous := overlay_enabled
    overlay_enabled = enabled
    if not enabled:
        _set_plane_visible(false)
        return previous
    _on_shroud_changed(PackedInt32Array())
    return previous


func _on_node_added(node: Node) -> void:
    if not (node is Node3D):
        return
    if Engine.is_editor_hint():
        return
    if _is_under_map_editor(node):
        return
    var n3d := node as Node3D
    if not n3d.is_in_group("entities"):
        # Tiberium overlays (OVERLAY, ResourceComponent) are not in the entities
        # group; they still freeze their harvest-stage visual in fog. The dict
        # value is the "ever seen by local player" flag used to keep crystals
        # that spawn into fog hidden until revealed.
        if n3d.get_node_or_null("ResourceComponent") != null:
            var rstats := n3d.get_node_or_null("StatsComponent") as StatsComponent
            if rstats != null:
                _overlays[n3d] = false
                _sync_overlay(n3d)
        return
    var stats := n3d.get_node_or_null("StatsComponent") as StatsComponent
    if stats == null:
        return
    if stats.entity_type != EntityData.EntityType.BUILDING:
        return
    _buildings[n3d] = true
    # Buildings spawned between resolves default visible=true; sync immediately
    # so the flag is correct (or the opaque shroud sheet hides it until then).
    _sync_building(n3d)


func _on_node_removed(node: Node) -> void:
    _buildings.erase(node)
    _overlays.erase(node)
    var depot := GhostDepot.get_instance()
    if depot:
        depot.mark_dead(node as Node3D)
