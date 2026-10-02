extends Node

signal cell_changed(cell_key: String, cell_data: Dictionary)
signal grid_initialized

const HEIGHT_STEP: float = 0.815
const MAX_HEIGHT: int = 10
const DEFAULT_GRID_CELLS: Vector2i = Vector2i(50, 50)
## Default land type for cells with no explicit surface assignment.
const DEFAULT_LAND_TYPE: String = "clear"
## Land type reported for cells occupied by a resource crystal.
const RESOURCE_LAND_TYPE: String = "resource"

var grid_cells: Vector2i = DEFAULT_GRID_CELLS:
    set(value):
        grid_cells = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
        _init_vertex_grid()

var _vertex_grid: Array = []
var _cells: Dictionary = {}
## Sparse per-cell land type overlay: cell_key -> land type id. Absent = DEFAULT_LAND_TYPE.
var _land_types: Dictionary = {}
## Cliff-stamp pins: cell_key -> pinned TerrainObject id. Pinned cells render
## their pinned object regardless of height-derived resolution and lock their
## vertices against height edits. Persisted as "cell_pins" in map JSON.
var _cell_pins: Dictionary = {}

## World-lifetime per-cell corner-vertex height snapshot: cell_key -> [h_nw, h_ne, h_sw, h_se]
## (raw ints, HEIGHT_STEP applied by consumers). Populated lazily on first query; heights only —
## land type stays batch-lifetime (set_land_type emits no cell_changed; resource registry mutates
## on harvest/growth). Invalidated per-cell on cell_changed and wholesale on grid re-init.
var _height_snapshot: Dictionary = {}
## Bumped on every grid re-init / full snapshot clear so frame-scoped consumers
## (e.g. MovementController's per-frame height memo) can detect terrain changes.
var height_snapshot_generation: int = 0

## Perf-guard counter: `get_land_type` invocations. The movement hot path must
## resolve land type once per cell per frame via the MovementController frame
## cache, asserted by test/unit/test_movement_frame_cache.gd. ponytail: test-only
## instrumentation; a single int increment per call.
var land_type_query_count: int = 0

var _corner_to_dir: Array[String] = ["west", "north", "south", "east"]

## Catalog slope tile families (TS slope01/05/09/13/17 + hand-authored saddle2).
const SLOPE_FAMILIES: Array[String] = [
    "slope01", "slope05", "slope09", "slope13", "slope17", "slope_saddle2"
]

static var _slope_lookup: Dictionary = {}
static var _slope_lookup_built := false


## Catalog slope object id (e.g. "slope01_n") for a cell's 4 corner heights in
## map-editor order [NW, NE, SW, SE]. Matches the baked TS corner patterns, so
## slope rendering uses the exact same object/rotation as the asset preview.
## Diagonal saddles are 180°-degenerate in the catalog; the natural `_n` match
## is preferred. Returns "" when no catalog tile matches (extreme steeps).
static func slope_object_id(corners: Array) -> String:
    if not _slope_lookup_built:
        _build_slope_lookup()
    if corners.size() != 4:
        return ""
    var catalog := [corners[0], corners[1], corners[3], corners[2]]
    return _slope_lookup.get(_corners_key(catalog), "")


static func _build_slope_lookup() -> void:
    _slope_lookup_built = true
    for id_str in SLOPE_FAMILIES:
        for dir in ["n", "e", "s", "w"]:
            var obj := TerrainCatalog.get_object("%s_%s" % [id_str, dir])
            if obj == null:
                continue
            var corners := obj.corners_at("0,0")
            if corners.size() != 4:
                continue
            var key := _corners_key(corners)
            if not _slope_lookup.has(key):
                _slope_lookup[key] = obj.id
            elif dir == "n" and not String(_slope_lookup[key]).ends_with("_n"):
                # Prefer the natural base orientation for degenerate (saddle) tiles.
                _slope_lookup[key] = obj.id


static func _corners_key(corners: Array) -> String:
    var lo := 1 << 30
    for c in corners:
        lo = mini(lo, int(c))
    var parts: Array[String] = []
    for c in corners:
        parts.append(str(int(c) - lo))
    return ",".join(parts)


func _init() -> void:
    _init_vertex_grid()
    cell_changed.connect(_on_snapshot_cell_changed)
    grid_initialized.connect(_on_snapshot_grid_initialized)


func init_grid(cells_x: int, cells_z: int) -> void:
    grid_cells = Vector2i(cells_x, cells_z)  # setter calls _init_vertex_grid()
    CellUtil.notify_grid_changed()
    grid_initialized.emit()


func _init_vertex_grid() -> void:
    var extent: Vector2i = CellUtil.get_diamond_extent(grid_cells)
    var v_count_x := extent.x + 1
    var v_count_z := extent.y + 1
    _vertex_grid = []
    _vertex_grid.resize(v_count_x)
    for vx in v_count_x:
        var row: Array[int] = []
        row.resize(v_count_z)
        _vertex_grid[vx] = row
    _height_snapshot.clear()
    _cell_pins.clear()
    height_snapshot_generation += 1


func _enter_tree() -> void:
    CellUtil.notify_grid_changed()


func _exit_tree() -> void:
    CellUtil.notify_grid_changed()
    clear()


func _on_snapshot_cell_changed(cell_key: String, _cell_data: Dictionary) -> void:
    var parts: PackedStringArray = cell_key.split(",")
    if parts.size() == 2:
        _height_snapshot.erase(CellUtil.cell_key(Vector2i(int(parts[0]), int(parts[1]))))


func _on_snapshot_grid_initialized() -> void:
    _height_snapshot.clear()
    height_snapshot_generation += 1


## Clears the world-lifetime height snapshot. Test/tool code that mutates
## `_vertex_grid` directly (bypassing set_vertex, which emits cell_changed) must
## call this before reading cached heights.
func invalidate_height_snapshot() -> void:
    _height_snapshot.clear()
    height_snapshot_generation += 1


## World-lifetime per-cell corner-vertex snapshot: [h_nw, h_ne, h_sw, h_se] raw ints.
## Returns [] for out-of-diamond cells (consumers keep their bounds defaults).
func _snapshot_corners(cell: Vector2i) -> Array:
    var cx := cell.x
    var cz := cell.y
    var extent: Vector2i = CellUtil.get_diamond_extent(grid_cells)
    if cx < 0 or cx >= extent.x or cz < 0 or cz >= extent.y:
        return []
    var key: int = CellUtil.cell_key(cell)
    var cached: Array = _height_snapshot.get(key, [])
    if not cached.is_empty():
        return cached
    cached = [
        _vertex_grid[cx][cz],
        _vertex_grid[cx + 1][cz],
        _vertex_grid[cx][cz + 1],
        _vertex_grid[cx + 1][cz + 1],
    ]
    _height_snapshot[key] = cached
    return cached


func clear() -> void:
    _init_vertex_grid()
    _cells.clear()
    _land_types.clear()
    _cell_pins.clear()


# ========================================
# Vertex API
# ========================================


func get_vertex(vx: int, vz: int) -> int:
    var extent: Vector2i = CellUtil.get_diamond_extent(grid_cells)
    if vx < 0 or vx > extent.x or vz < 0 or vz > extent.y:
        return 0
    return _vertex_grid[vx][vz]


func set_vertex(vx: int, vz: int, height: int) -> void:
    var extent: Vector2i = CellUtil.get_diamond_extent(grid_cells)
    if vx < 0 or vx > extent.x or vz < 0 or vz > extent.y:
        return
    if not _is_vertex_editable(vx, vz):
        return
    _vertex_grid[vx][vz] = clampi(height, 0, MAX_HEIGHT)
    _cascade_from_vertices([Vector2i(vx, vz)])


func _set_vertex_no_cascade(vx: int, vz: int, height: int) -> void:
    _vertex_grid[vx][vz] = height


# ========================================
# Cell Painting API
# ========================================


func raise_cell(cell: Vector2i) -> void:
    var cx := cell.x
    var cz := cell.y
    var extent: Vector2i = CellUtil.get_diamond_extent(grid_cells)
    if cx < 0 or cx >= extent.x or cz < 0 or cz >= extent.y:
        return
    if is_cell_pinned(cell):
        return
    var h_min := MAX_HEIGHT
    for vx in [cx, cx + 1]:
        for vz in [cz, cz + 1]:
            if _is_vertex_editable(vx, vz):
                h_min = mini(h_min, _vertex_grid[vx][vz])
    if h_min >= MAX_HEIGHT:
        return
    var origins: Array[Vector2i] = []
    for vx in [cx, cx + 1]:
        for vz in [cz, cz + 1]:
            if _is_vertex_editable(vx, vz) and _vertex_grid[vx][vz] == h_min:
                _vertex_grid[vx][vz] += 1
                origins.append(Vector2i(vx, vz))
    if not origins.is_empty():
        _cascade_from_vertices(origins)


func lower_cell(cell: Vector2i) -> void:
    var cx := cell.x
    var cz := cell.y
    var extent: Vector2i = CellUtil.get_diamond_extent(grid_cells)
    if cx < 0 or cx >= extent.x or cz < 0 or cz >= extent.y:
        return
    if is_cell_pinned(cell):
        return
    var h_max := 0
    for vx in [cx, cx + 1]:
        for vz in [cz, cz + 1]:
            if _is_vertex_editable(vx, vz):
                h_max = maxi(h_max, _vertex_grid[vx][vz])
    if h_max <= 0:
        return
    var origins: Array[Vector2i] = []
    for vx in [cx, cx + 1]:
        for vz in [cz, cz + 1]:
            if _is_vertex_editable(vx, vz) and _vertex_grid[vx][vz] == h_max:
                _vertex_grid[vx][vz] -= 1
                origins.append(Vector2i(vx, vz))
    if not origins.is_empty():
        _cascade_from_vertices(origins)


## Level a footprint region to its maximum height. `origin_cell` and `size` are
## in centered cell coordinates (same space as get_cell_max_height). Sets every
## vertex bounding the footprint to the region's max level; the existing cascade
## then re-slopes the surrounding ring to keep single-step transitions.
# ponytail: set_vertex cascades per call; placement is a rare user event, so the
# repeated cascade cost is fine. Batch cascade only if profiling flags it.
func flatten_footprint(origin_cell: Vector2i, size: Vector2i) -> void:
    if size.x <= 0 or size.y <= 0:
        return
    var offset_x := grid_cells.x >> 1
    var offset_z := grid_cells.y >> 1
    var vx0 := origin_cell.x + offset_x
    var vz0 := origin_cell.y + offset_z
    var vx1 := vx0 + size.x
    var vz1 := vz0 + size.y
    var target := 0
    var any_editable := false
    for vx in range(vx0, vx1 + 1):
        for vz in range(vz0, vz1 + 1):
            if not _is_vertex_editable(vx, vz):
                continue
            any_editable = true
            target = maxi(target, get_vertex(vx, vz))
    if not any_editable:
        return
    for vx in range(vx0, vx1 + 1):
        for vz in range(vz0, vz1 + 1):
            if not _is_vertex_editable(vx, vz):
                continue
            set_vertex(vx, vz, target)


# ========================================
# Cell Queries (from cache)
# ========================================


func get_cell(cell: Vector2i) -> Dictionary:
    var key := CellUtil.cell_key_str(cell)
    return _cells.get(key, {})


func get_cell_type(cell: Vector2i) -> String:
    var cx := cell.x
    var cz := cell.y
    var extent: Vector2i = CellUtil.get_diamond_extent(grid_cells)
    if cx < 0 or cx >= extent.x or cz < 0 or cz >= extent.y:
        return ""
    var key := CellUtil.cell_key_str(Vector2i(cx, cz))
    var data: Dictionary = _cells.get(key, {})
    return data.get("type", "")


## Land type id for a cell surface. At level 0: resource-occupied cells resolve
## to `resource`; otherwise the painted overlay applies, defaulting to "clear".
## Level 0 ignores any bridge deck above the cell — a deck is a separate surface,
## so the ground beneath keeps its own land (this is what makes under-deck
## pathing possible). Above level 0: a level with a deck resolves to that deck
## lane's land (`road`, or `railroad` for a rail middle lane), otherwise no
## surface (""). Level 0 defaults preserve every existing caller.
func get_land_type(cell: Vector2i, level: int = 0) -> String:
    land_type_query_count += 1
    if level > 0:
        if SpatialHash.instance:
            var deck: Dictionary = SpatialHash.instance.get_bridge_cell(cell, level)
            if not deck.is_empty():
                return String(deck.get("land", "road"))
        return ""
    if SpatialHash.instance and SpatialHash.instance.has_resource_cell(cell):
        return RESOURCE_LAND_TYPE
    return _land_types.get(CellUtil.cell_key(cell), DEFAULT_LAND_TYPE)


## Explicit per-cell land type override id, or "" when the cell has none.
## Unlike get_land_type(), this ignores the "clear" default and the
## resource-derived "resource" type — only a painted override returns a value.
## Map coloring uses this to pick the fallback LandType color without letting a
## resource cell masquerade as a painted surface.
func get_painted_land_type(cell: Vector2i) -> String:
    return _land_types.get(CellUtil.cell_key(cell), "")


## Assigns a land type to a cell. Assigning the default land type clears the override.
func set_land_type(cell: Vector2i, land_type_id: String) -> void:
    var key: int = CellUtil.cell_key(cell)
    if land_type_id == DEFAULT_LAND_TYPE or land_type_id.is_empty():
        _land_types.erase(key)
    else:
        _land_types[key] = land_type_id


func get_cell_max_height(cell: Vector2i) -> float:
    var corners := _snapshot_corners(cell)
    if corners.is_empty():
        return 0.0
    var h_max := maxi(maxi(corners[0], corners[1]), maxi(corners[2], corners[3]))
    return float(h_max) * HEIGHT_STEP


## Normalized cell height in 0..1 (max corner height / MAX_HEIGHT) for map
## color height shading. Flat ground is 0.0, max height is 1.0.
func get_cell_height_ratio(cell: Vector2i) -> float:
    var max_height: float = float(MAX_HEIGHT) * HEIGHT_STEP
    if max_height <= 0.0:
        return 0.0
    return clampf(get_cell_max_height(cell) / max_height, 0.0, 1.0)


## Min-corner height for a cell (raw heights * HEIGHT_STEP). Matches the pre-cache
## Pathfinder._cell_height semantics (4-corner minimum); out-of-diamond reads as 0.0.
func get_cell_min_height(cell: Vector2i) -> float:
    var corners := _snapshot_corners(cell)
    if corners.is_empty():
        return 0.0
    var h_min := mini(mini(corners[0], corners[1]), mini(corners[2], corners[3]))
    return float(h_min) * HEIGHT_STEP


## Walkable surface height for a cell at `level`: the deck height when a bridge
## covers the cell at that level, otherwise the smooth terrain height at the cell
## center. Level 0 is the ground surface and ignores any deck above it (the deck
## is a separate level), so the ground beneath a deck reads its own height.
## Level 0 defaults to the pre-level behavior.
func get_cell_surface_height(cell: Vector2i, level: int = 0) -> float:
    if level > 0:
        if SpatialHash.instance and SpatialHash.instance.has_bridge_on_cell(cell, level):
            var deck: Dictionary = SpatialHash.instance.get_bridge_cell(cell, level)
            if deck.has("surface_height"):
                return float(deck["surface_height"])
        return get_height_at_world_smooth(CellUtil.cell_to_world(cell))
    return get_height_at_world_smooth(CellUtil.cell_to_world(cell))


## Surface levels present on a cell: always ground (0), plus each deck level
## above it, sorted ascending. Delegates to the SpatialHash bridge registry
## (single source of deck surfaces). Returns [0] when no deck covers the cell.
func get_cell_surface_levels(cell: Vector2i) -> Array[int]:
    var levels: Array[int] = [0]
    if SpatialHash.instance:
        for deck_level in SpatialHash.instance.get_bridge_levels(cell):
            if deck_level > 0 and not levels.has(deck_level):
                levels.append(deck_level)
    levels.sort()
    return levels


func get_cell_corner_heights(cell: Vector2i) -> Array[float]:
    var cx := cell.x
    var cz := cell.y
    var extent: Vector2i = CellUtil.get_diamond_extent(grid_cells)
    if cx < 0 or cx >= extent.x or cz < 0 or cz >= extent.y:
        return [0.0, 0.0, 0.0, 0.0]
    var h_nw: float = float(_vertex_grid[cx][cz]) * HEIGHT_STEP
    var h_ne: float = float(_vertex_grid[cx + 1][cz]) * HEIGHT_STEP
    var h_sw: float = float(_vertex_grid[cx][cz + 1]) * HEIGHT_STEP
    var h_se: float = float(_vertex_grid[cx + 1][cz + 1]) * HEIGHT_STEP
    return [h_nw, h_ne, h_sw, h_se]


## Raw corner heights `[h_nw, h_ne, h_sw, h_se]` from the world-lifetime snapshot,
## in unscaled height units (matching `_vertex_grid` semantics). Empty array for
## out-of-diamond cells. Callers that need a smooth bilinear sample at a world
## position can cache these per cell and interpolate at the exact position —
## bit-identical to `_sample_heightfield_at` with `HEIGHT_STEP` applied last.
func get_cell_snapshot_corners_raw(cell: Vector2i) -> Array:
    return _snapshot_corners(cell)


## Steepest adjacent-corner rise of a cell in raw height units (unscaled by
## HEIGHT_STEP): the maximum height difference across the cell's four edges
## [nw-ne, sw-se, nw-sw, ne-se]. A flat cell, out-of-diamond cells, and stair
## patterns (e.g. [0,1,1,2], where each edge rises one step but the span is two)
## read as 1 or less; a true cliff face whose single edge jumps two or more
## levels reads as 2 or more. Used by LOS blocking to exempt walkable graded
## faces (edge rise <= 1, matching Foot/Track climb_tolerance) from the
## height-delta check while keeping sheer cliff faces blocking. At a deck level
## (> 0) the deck is flat, so its grade is the surface height in steps.
func get_cell_grade_steps(cell: Vector2i, level: int = 0) -> int:
    if level > 0:
        return roundi(get_cell_surface_height(cell, level) / HEIGHT_STEP)
    var corners := _snapshot_corners(cell)
    if corners.is_empty():
        return 0
    var h_nw := corners[0] as int
    var h_ne := corners[1] as int
    var h_sw := corners[2] as int
    var h_se := corners[3] as int
    var edge_rise := maxi(
        maxi(absi(h_nw - h_ne), absi(h_sw - h_se)),
        maxi(absi(h_nw - h_sw), absi(h_ne - h_se)),
    )
    return edge_rise


func get_cell_at_world(world_pos: Vector3) -> Dictionary:
    var cell := CellUtil.world_to_cell(world_pos)
    return get_cell(cell)


func get_height_at_world(world_pos: Vector3) -> float:
    var cell := CellUtil.world_to_cell(world_pos)
    var data := get_cell(cell)
    if data.is_empty():
        return 0.0
    return data.get("height", 0) * HEIGHT_STEP


func get_height_at_world_smooth(world_pos: Vector3) -> float:
    var center: float = float(grid_cells.x + grid_cells.y) * 0.5
    var vx: float = world_pos.x / CellUtil.CELL_SIZE + center
    var vz: float = world_pos.z / CellUtil.CELL_SIZE + center
    return _sample_heightfield_at(vx, vz) * HEIGHT_STEP


## Bilinear height sample at vertex-space coordinates (vx, vz), in raw height
## units (0..MAX_HEIGHT, not scaled by HEIGHT_STEP). Shared by the smooth height
## query, segment intersection, and the HeightMapShape3D builder so all answer
## surfaces sample the same surface.
func _sample_heightfield_at(vx: float, vz: float) -> float:
    var x0 := floori(vx)
    var z0 := floori(vz)
    var fx: float = vx - float(x0)
    var fz: float = vz - float(z0)
    var corners := _snapshot_corners(Vector2i(x0, z0))
    var h00: float
    var h10: float
    var h01: float
    var h11: float
    if corners.is_empty():
        h00 = float(get_vertex(x0, z0))
        h10 = float(get_vertex(x0 + 1, z0))
        h01 = float(get_vertex(x0, z0 + 1))
        h11 = float(get_vertex(x0 + 1, z0 + 1))
    else:
        h00 = float(corners[0])
        h10 = float(corners[1])
        h01 = float(corners[2])
        h11 = float(corners[3])
    var h0: float = h00 + (h10 - h00) * fx
    var h1: float = h01 + (h11 - h01) * fx
    return h0 + (h1 - h0) * fz


func get_normal_at_world(world_pos: Vector3) -> Vector3:
    var center: float = float(grid_cells.x + grid_cells.y) * 0.5
    var vx: float = world_pos.x / CellUtil.CELL_SIZE + center
    var vz: float = world_pos.z / CellUtil.CELL_SIZE + center
    var x0 := floori(vx)
    var x1 := x0 + 1
    var z0 := floori(vz)
    var z1 := z0 + 1
    var h00: float = float(get_vertex(x0, z0)) * HEIGHT_STEP
    var h10: float = float(get_vertex(x1, z0)) * HEIGHT_STEP
    var h01: float = float(get_vertex(x0, z1)) * HEIGHT_STEP
    var edge_x := Vector3(CellUtil.CELL_SIZE, h10 - h00, 0.0)
    var edge_z := Vector3(0.0, h01 - h00, CellUtil.CELL_SIZE)
    return edge_z.cross(edge_x).normalized()


## Cast a ray from `camera` through `screen_pos` and return the world position
## where it meets the nearest terrain surface, or null when the ray never reaches
## the ground plane (e.g. the camera is pitched above the horizon). Back-compatible
## single-return wrapper around `mouse_ray_to_terrain_candidates`; callers that
## ignore surface levels get the nearest surface (a deck over the ground picks the
## deck). Intersects the Y=0 plane first, then refines the hit against the smoothed
## heightfield for a fixed 4 iterations. Single shared implementation for placement
## previews, order ground targeting, and any future cursor-to-terrain consumer.
func mouse_ray_to_terrain(camera: Camera3D, screen_pos: Vector2) -> Variant:
    var candidates: Array[Dictionary] = mouse_ray_to_terrain_candidates(camera, screen_pos)
    if candidates.is_empty():
        return null
    return candidates[0]["position"] as Vector3


## Every terrain surface the camera ray through `screen_pos` hits, nearest first,
## as `{"position": Vector3, "cell": Vector2i, "level": int}`. The ground (level 0)
## uses the existing heightfield solve; each bridge deck covered by the ray is a
## flat horizontal plane at its walkable surface height. A ray over a high deck
## therefore reports the deck level first and still reports the ground beneath as
## a second candidate, so the ground under a bridge stays selectable. Returns an
## empty array when the ray never reaches the ground plane.
func mouse_ray_to_terrain_candidates(camera: Camera3D, screen_pos: Vector2) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var from := camera.project_ray_origin(screen_pos)
    var dir := camera.project_ray_normal(screen_pos)
    var ground_plane := Plane(Vector3.UP, 0.0)
    var intersection = ground_plane.intersects_ray(from, dir)
    if intersection == null:
        return result
    var hit_pos := intersection as Vector3
    for i in 4:
        var terrain_y := get_height_at_world_smooth(hit_pos)
        var adjusted := Plane(Vector3.UP, terrain_y)
        var new_hit = adjusted.intersects_ray(from, dir)
        if new_hit == null:
            break
        hit_pos = new_hit as Vector3
    var ground_cell := CellUtil.world_to_cell(hit_pos)
    # ponytail: decks are scanned over the ground-hit cell's 3x3 hood only. A deck
    # several cells off the ground hit under an extremely oblique ray is not
    # resolved; widen the scan only if a real map needs it.
    for dx in range(-1, 2):
        for dz in range(-1, 2):
            var cell := ground_cell + Vector2i(dx, dz)
            for level in get_cell_surface_levels(cell):
                if level <= 0:
                    continue
                var deck_y := get_cell_surface_height(cell, level)
                var deck_hit = Plane(Vector3.UP, deck_y).intersects_ray(from, dir)
                if deck_hit == null:
                    continue
                var deck_pos := deck_hit as Vector3
                if dir.dot(deck_pos - from) <= 0.0:
                    continue
                if CellUtil.world_to_cell(deck_pos) != cell:
                    continue
                result.append({"position": deck_pos, "cell": cell, "level": level})
    result.append({"position": hit_pos, "cell": ground_cell, "level": 0})
    result.sort_custom(
        func(a: Dictionary, b: Dictionary) -> bool:
            return from.distance_squared_to(a["position"]) < from.distance_squared_to(b["position"])
    )
    return result


## First point where a segment crosses the terrain surface, descending.
## Contract:
## - Returns the first t in [0,1] where the segment transitions from above the
##   bilinear heightfield surface to below it (a downward crossing).
## - Returns `{"point": Vector3, "cell": Vector2i}` on hit, or `{}` on no hit.
## - Segments fully above terrain return `{}` (never descend into it).
## - Segments starting below terrain return `{}` unless they rise above the
##   surface and descend again; the initial up-crossing is never reported.
## - Cells outside the playable diamond produce no hits.
## Pure math — no physics server involvement. Deterministic and headless-safe.
func intersect_heightfield_segment(from: Vector3, to: Vector3) -> Dictionary:
    var center: float = float(grid_cells.x + grid_cells.y) * 0.5
    var avx: float = from.x / CellUtil.CELL_SIZE + center
    var avz: float = from.z / CellUtil.CELL_SIZE + center
    var bvx: float = to.x / CellUtil.CELL_SIZE + center
    var bvz: float = to.z / CellUtil.CELL_SIZE + center
    var du: float = bvx - avx
    var dw: float = bvz - avz
    var dy: float = to.y - from.y
    var t := 0.0
    var cx := floori(avx)
    var cz := floori(avz)
    var step_x := 1 if du > 0.0 else (-1 if du < 0.0 else 0)
    var step_z := 1 if dw > 0.0 else (-1 if dw < 0.0 else 0)
    var t_delta_x := 1.0 / absf(du) if du != 0.0 else INF
    var t_delta_z := 1.0 / absf(dw) if dw != 0.0 else INF
    var t_max_x := _t_to_boundary(avx, cx, du)
    var t_max_z := _t_to_boundary(avz, cz, dw)
    while true:
        var t_exit := minf(minf(t_max_x, t_max_z), 1.0)
        if CellUtil.is_in_diamond(Vector2i(cx, cz), grid_cells):
            var hit := _intersect_cell_bilinear(from, to, cx, cz, t, t_exit)
            if not hit.is_empty():
                return hit
        if t_exit >= 1.0:
            break
        t = t_exit
        if t_max_x <= t_max_z:
            cx += step_x
            t_max_x += t_delta_x
        else:
            cz += step_z
            t_max_z += t_delta_z
    return {}


## Parameter t at which the segment crosses the next grid boundary on one axis,
## starting from vertex-space coordinate `v` inside cell index `c`. INF when the
## segment does not move along that axis.
static func _t_to_boundary(v: float, c: int, d: float) -> float:
    if d > 0.0:
        return (float(c) + 1.0 - v) / d
    if d < 0.0:
        return (float(c) - v) / d
    return INF


## Tests a single grid cell (cx, cz) over segment parameter range [t0, t1] for a
## downward crossing of the cell's bilinear surface. The surface height within
## the cell is a quadratic in t (bilinear composed with the linear XZ motion),
## solved exactly. Returns {"point", "cell", "t"} or {}.
func _intersect_cell_bilinear(
    from: Vector3, to: Vector3, cx: int, cz: int, t0: float, t1: float
) -> Dictionary:
    var center: float = float(grid_cells.x + grid_cells.y) * 0.5
    var avx: float = from.x / CellUtil.CELL_SIZE + center
    var avz: float = from.z / CellUtil.CELL_SIZE + center
    var du: float = (to.x - from.x) / CellUtil.CELL_SIZE
    var dw: float = (to.z - from.z) / CellUtil.CELL_SIZE
    var dy: float = to.y - from.y
    var h00: float = float(get_vertex(cx, cz)) * HEIGHT_STEP
    var h10: float = float(get_vertex(cx + 1, cz)) * HEIGHT_STEP
    var h01: float = float(get_vertex(cx, cz + 1)) * HEIGHT_STEP
    var h11: float = float(get_vertex(cx + 1, cz + 1)) * HEIGHT_STEP
    var c10 := h10 - h00
    var c01 := h01 - h00
    var c11 := h00 - h10 - h01 + h11
    var u0 := avx - float(cx)
    var w0 := avz - float(cz)
    var h0 := h00 + c10 * u0 + c01 * w0 + c11 * u0 * w0
    var h1 := c10 * du + c01 * dw + c11 * (u0 * dw + du * w0)
    var h2 := c11 * du * dw
    var f0 := from.y - h0
    var f1 := dy - h1
    var f2 := -h2
    for r in _quadratic_roots(f2, f1, f0):
        var rt := float(r)
        if rt < t0 - 1e-6 or rt > t1 + 1e-6:
            continue
        var f_prime := 2.0 * f2 * rt + f1
        if f_prime < 0.0:
            return {
                "point": from.lerp(to, rt),
                "cell": Vector2i(cx, cz),
                "t": rt,
            }
    return {}


## Real roots of a*t^2 + b*t + c = 0, ascending order, or empty when none.
static func _quadratic_roots(a: float, b: float, c: float) -> Array[float]:
    if absf(a) < 1e-9:
        if absf(b) < 1e-9:
            return []
        return [(-c) / b]
    var disc := b * b - 4.0 * a * c
    if disc < 0.0:
        return []
    var sq := sqrt(disc)
    return [((-b) - sq) / (2.0 * a), ((-b) + sq) / (2.0 * a)]


## Native heightfield collision shape mirroring the vertex heightfield, for
## consumers that need the physics server (e.g. knockback collision response).
## `map_data` holds `height * HEIGHT_STEP` per in-diamond vertex and `NAN` for
## vertices outside the playable diamond (holes), so map corners never collide.
## Returns a shape resource only — no nodes are mounted. Purely opt-in; query
## consumers should prefer `intersect_heightfield_segment` instead.
func build_heightfield_shape() -> HeightMapShape3D:
    var extent: Vector2i = CellUtil.get_diamond_extent(grid_cells)
    var v_count := extent.x + 1
    var shape := HeightMapShape3D.new()
    shape.map_width = v_count
    shape.map_depth = v_count
    var data := PackedFloat32Array()
    data.resize(v_count * v_count)
    for vx in v_count:
        for vz in v_count:
            var idx := vz * v_count + vx
            if _is_vertex_in_diamond(vx, vz):
                data[idx] = float(_vertex_grid[vx][vz]) * HEIGHT_STEP
            else:
                data[idx] = NAN
    shape.map_data = data
    return shape


## A vertex is in the playable diamond when it is a corner of at least one
## in-diamond cell.
func _is_vertex_in_diamond(vx: int, vz: int) -> bool:
    var extent: Vector2i = CellUtil.get_diamond_extent(grid_cells)
    if vx < 0 or vx > extent.x or vz < 0 or vz > extent.y:
        return false
    for cx in [vx - 1, vx]:
        for cz in [vz - 1, vz]:
            if CellUtil.is_in_diamond(Vector2i(cx, cz), grid_cells):
                return true
    return false


func get_all_cells() -> Dictionary:
    return _cells.duplicate(true)


func compute_and_emit_cell(cell: Vector2i) -> void:
    var key := CellUtil.cell_key_str(cell)
    _cells[key] = _compute_cell_from_vertices(cell)
    cell_changed.emit(key, _cells[key])


func calculate_cell_mesh(cell: Vector2i) -> Dictionary:
    return _compute_cell_from_vertices(cell)


# ========================================
# Cell Pins (cliff stamps)
# ========================================


## Pins a cell to a TerrainObject id. Returns false when the cell is outside
## the playable diamond. Re-pinning overwrites. Emits cell_changed so the
## renderer re-resolves the cell.
func pin_cell(cell: Vector2i, object_id: String) -> bool:
    if not CellUtil.is_in_diamond(cell, grid_cells):
        push_warning("TerrainSystem: pin_cell outside diamond ignored: %s" % cell)
        return false
    var key := CellUtil.cell_key_str(cell)
    _cell_pins[key] = object_id
    if _cells.has(key):
        cell_changed.emit(key, _cells[key])
    return true


## Removes a cell's pin. Returns false when the cell had none. Emits
## cell_changed for tracked cells so the renderer falls back to derived art.
func unpin_cell(cell: Vector2i) -> bool:
    var key := CellUtil.cell_key_str(cell)
    if not _cell_pins.has(key):
        return false
    _cell_pins.erase(key)
    if _cells.has(key):
        cell_changed.emit(key, _cells[key])
    return true


## Pinned object id for a cell, or "" when unpinned.
func get_pin(cell: Vector2i) -> String:
    return String(_cell_pins.get(CellUtil.cell_key_str(cell), ""))


## True when the cell carries a pin (locked against height edits).
func is_cell_pinned(cell: Vector2i) -> bool:
    return _cell_pins.has(CellUtil.cell_key_str(cell))


## A vertex is editable when no cell sharing it is pinned: raising or lowering
## it would deform a pinned cell's stamped geometry.
func _is_vertex_editable(vx: int, vz: int) -> bool:
    for cell in [
        Vector2i(vx - 1, vz - 1), Vector2i(vx, vz - 1), Vector2i(vx - 1, vz), Vector2i(vx, vz)
    ]:
        if _cell_pins.has(CellUtil.cell_key_str(cell)):
            return false
    return true


# ========================================
# TerrainObject stamping
# ========================================

## Sentinel "no cell"/"no origin" for the stamp helpers (outside any playable diamond).
const _NO_STAMP_CELL: Vector2i = Vector2i(1 << 30, 1 << 30)


## Stamps a `TerrainObject` onto the grid at `origin`: every object-local cell
## `"x,z"` maps to `origin + (x, z)`; its four absolute corner heights
## (`[nw, ne, se, sw]`) are written to that cell's vertices with the
## non-cascading setter (so the authored cliff face is exact and never smoothed
## into the neighbours), its `land` is painted when non-default, and the cell is
## pinned to `obj.id` so later height edits cannot deform the stamp. Absolute
## writes make stamping idempotent; shared vertices are written in authored order,
## so a well-formed object (adjacent cells agree on the shared corner) stamps
## deterministically. Recomputes and emits the footprint plus its in-diamond ring.
func stamp_terrain_object(obj: TerrainObject, origin: Vector2i) -> void:
    if obj == null:
        return
    var touched: Dictionary = {}
    for local_key in obj.cells:
        var cell := _stamp_cell_for(obj, origin, String(local_key))
        if cell == _NO_STAMP_CELL:
            continue
        _apply_object_cell(obj, String(local_key), cell)
        pin_cell(cell, obj.id)
        touched[cell] = true
    if touched.is_empty():
        return
    invalidate_height_snapshot()
    var affected: Dictionary = {}
    for cell: Vector2i in touched:
        _add_cells_for_vertex(cell.x, cell.y, affected)
        _add_cells_for_vertex(cell.x + 1, cell.y, affected)
        _add_cells_for_vertex(cell.x, cell.y + 1, affected)
        _add_cells_for_vertex(cell.x + 1, cell.y + 1, affected)
    for key in affected:
        var parts: PackedStringArray = String(key).split(",")
        if parts.size() != 2:
            continue
        var cell := Vector2i(int(parts[0]), int(parts[1]))
        if CellUtil.is_in_diamond(cell, grid_cells):
            compute_and_emit_cell(cell)


## Convenience: resolves `id` via TerrainCatalog and stamps it. Returns false when
## the id is not a registered terrain object (nothing is written).
func stamp_terrain_object_by_id(id: String, origin: Vector2i) -> bool:
    var obj := TerrainCatalog.get_object(id)
    if obj == null:
        push_warning("TerrainSystem: unknown terrain object '%s'" % id)
        return false
    stamp_terrain_object(obj, origin)
    return true


## Applies one object cell's authored `corners` and `land` to a world cell.
func _apply_object_cell(obj: TerrainObject, local_key: String, cell: Vector2i) -> void:
    var corners := obj.corners_at(local_key)
    if corners.size() == 4:
        _apply_cell_corners(cell, corners)
    var land := obj.land_type_at(local_key)
    if not land.is_empty() and land != DEFAULT_LAND_TYPE:
        set_land_type(cell, land)


## Writes a cell's authored corner heights (`[nw, ne, se, sw]`) to the vertex
## grid without cascading, so the stamped cliff face is not smoothed away.
func _apply_cell_corners(cell: Vector2i, corners: Array) -> void:
    _set_vertex_no_cascade(cell.x, cell.y, clampi(int(corners[0]), 0, MAX_HEIGHT))
    _set_vertex_no_cascade(cell.x + 1, cell.y, clampi(int(corners[1]), 0, MAX_HEIGHT))
    _set_vertex_no_cascade(cell.x + 1, cell.y + 1, clampi(int(corners[2]), 0, MAX_HEIGHT))
    _set_vertex_no_cascade(cell.x, cell.y + 1, clampi(int(corners[3]), 0, MAX_HEIGHT))


## Applies an object's cells at `origin` without pinning or emitting — used to
## rebuild a stamped object after import (pins and `cell_changed` are handled by
## the import loop).
func _apply_object_land_and_corners(obj: TerrainObject, origin: Vector2i) -> void:
    for local_key in obj.cells:
        var cell := _stamp_cell_for(obj, origin, String(local_key))
        if cell == _NO_STAMP_CELL:
            continue
        _apply_object_cell(obj, String(local_key), cell)


## Object-local `"x,z"` key -> absolute world cell at `origin`, or `_NO_STAMP_CELL`
## when malformed or outside the playable diamond.
func _stamp_cell_for(_obj: TerrainObject, origin: Vector2i, local_key: String) -> Vector2i:
    var parts: PackedStringArray = local_key.split(",")
    if parts.size() != 2:
        return _NO_STAMP_CELL
    var cell := origin + Vector2i(int(parts[0]), int(parts[1]))
    if not CellUtil.is_in_diamond(cell, grid_cells):
        return _NO_STAMP_CELL
    return cell


## Rebuilds stamped objects after import from their pins. `cell_pins` stores only
## `cell -> object_id`, so each object's origin is recovered by finding the
## object-local cell whose translation maps the whole footprint onto cells pinned
## to the same id; then the authored land/corners are re-applied. A pin set that
## does not cover a full footprint (e.g. a hand-pinned single cliff cell) is left
## untouched.
func _restore_pinned_objects() -> void:
    if _cell_pins.is_empty():
        return
    var resolved: Dictionary = {}
    for pin_key in _cell_pins:
        var parts: PackedStringArray = String(pin_key).split(",")
        if parts.size() != 2:
            continue
        var pinned_cell := Vector2i(int(parts[0]), int(parts[1]))
        var object_id := String(_cell_pins[pin_key])
        if object_id.is_empty():
            continue
        if not resolved.has(object_id):
            resolved[object_id] = TerrainCatalog.get_object(object_id)
        var obj: TerrainObject = resolved[object_id]
        if obj == null:
            continue
        var origin := _resolve_stamp_origin(obj, pinned_cell, object_id)
        if origin != _NO_STAMP_CELL:
            _apply_object_land_and_corners(obj, origin)


## The stamp origin for `obj` that places `pinned_cell` on one of its cells and
## pins the whole footprint to `object_id`, or `_NO_STAMP_CELL`.
func _resolve_stamp_origin(
    obj: TerrainObject, pinned_cell: Vector2i, object_id: String
) -> Vector2i:
    for local_key in obj.cells:
        var parts: PackedStringArray = String(local_key).split(",")
        if parts.size() != 2:
            continue
        var origin := pinned_cell - Vector2i(int(parts[0]), int(parts[1]))
        if _is_stamp_at(obj, origin, object_id):
            return origin
    return _NO_STAMP_CELL


## True when every cell of `obj` translated by `origin` is in the diamond and
## pinned to `object_id`.
func _is_stamp_at(obj: TerrainObject, origin: Vector2i, object_id: String) -> bool:
    if obj.cells.is_empty():
        return false
    for local_key in obj.cells:
        var cell := _stamp_cell_for(obj, origin, String(local_key))
        if cell == _NO_STAMP_CELL or get_pin(cell) != object_id:
            return false
    return true


# ========================================
# Cascade (4-directional vertex-to-vertex)
# ========================================


func _cascade_from_vertices(origins: Array[Vector2i]) -> void:
    var queue: Array[Vector2i] = origins.duplicate()
    var visited: Dictionary = {}
    var affected_cells: Dictionary = {}
    var extent: Vector2i = CellUtil.get_diamond_extent(grid_cells)

    for v in origins:
        visited[CellUtil.cell_key_str(v)] = true
        _add_cells_for_vertex(v.x, v.y, affected_cells)

    while not queue.is_empty():
        var cur: Vector2i = queue.pop_front()
        var cur_h: int = _vertex_grid[cur.x][cur.y]

        var neighbors: Array[Vector2i] = [
            Vector2i(cur.x, cur.y - 1),
            Vector2i(cur.x, cur.y + 1),
            Vector2i(cur.x - 1, cur.y),
            Vector2i(cur.x + 1, cur.y),
        ]
        for nbr in neighbors:
            var nkey := CellUtil.cell_key_str(nbr)
            if visited.has(nkey):
                continue
            visited[nkey] = true
            if nbr.x < 0 or nbr.x > extent.x or nbr.y < 0 or nbr.y > extent.y:
                continue
            if not _is_vertex_editable(nbr.x, nbr.y):
                # Locked vertex: a pinned cell owns it; leave the cliff step.
                continue

            var nbr_h: int = _vertex_grid[nbr.x][nbr.y]
            var diff: int = cur_h - nbr_h

            if diff > 1:
                _vertex_grid[nbr.x][nbr.y] = nbr_h + 1
                _add_cells_for_vertex(nbr.x, nbr.y, affected_cells)
                queue.append(nbr)
            elif diff < -1:
                _vertex_grid[nbr.x][nbr.y] = nbr_h - 1
                _add_cells_for_vertex(nbr.x, nbr.y, affected_cells)
                queue.append(nbr)

    var existed_before: Dictionary = {}
    for key in affected_cells:
        existed_before[key] = _cells.has(key)
        # A touched vertex makes this cell's snapshot stale whether or not the
        # cell is tracked in `_cells` (cell_changed is only emitted for tracked
        # cells) — erase the height snapshot entry directly.
        var parts: PackedStringArray = key.split(",")
        if parts.size() == 2:
            _height_snapshot.erase(CellUtil.cell_key(Vector2i(int(parts[0]), int(parts[1]))))

    for key in affected_cells:
        if not existed_before[key]:
            continue
        _recompute_cell(key)

    for key in affected_cells:
        if not existed_before[key]:
            continue
        var data: Dictionary = _cells.get(key, {}) as Dictionary
        if not data.is_empty():
            cell_changed.emit(key, data)


func _add_cells_for_vertex(vx: int, vz: int, cells: Dictionary) -> void:
    var extent: Vector2i = CellUtil.get_diamond_extent(grid_cells)
    for cx in [vx - 1, vx]:
        if cx < 0 or cx >= extent.x:
            continue
        for cz in [vz - 1, vz]:
            if cz < 0 or cz >= extent.y:
                continue
            cells[CellUtil.cell_key_str(Vector2i(cx, cz))] = true


func _recompute_cell(key: String) -> void:
    var parts: PackedStringArray = key.split(",")
    if parts.size() != 2:
        return
    var cell := Vector2i(int(parts[0]), int(parts[1]))
    _cells[key] = _compute_cell_from_vertices(cell)


# ========================================
# Cell Type From Vertices
# ========================================


func _compute_cell_from_vertices(cell: Vector2i) -> Dictionary:
    var cx := cell.x
    var cz := cell.y

    var h: Array[int] = [
        _vertex_grid[cx][cz],
        _vertex_grid[cx + 1][cz],
        _vertex_grid[cx][cz + 1],
        _vertex_grid[cx + 1][cz + 1],
    ]

    var h_min := mini(mini(h[0], h[1]), mini(h[2], h[3]))
    var h_max := maxi(maxi(h[0], h[1]), maxi(h[2], h[3]))
    var rel: Array[int] = []
    for i in 4:
        rel.append(h[i] - h_min)

    var max_rel := 0
    var raised_count := 0
    var raised_indices: Array[int] = []
    var low_index := -1
    var max_idx := 0
    for i in 4:
        if rel[i] > max_rel:
            max_rel = rel[i]
            max_idx = i
        if rel[i] > 0:
            raised_count += 1
            raised_indices.append(i)
        else:
            low_index = i

    var result: Dictionary
    if raised_count == 0:
        result = _make_clear(h_min)
    elif raised_count == 4:
        result = _make_clear(h_min + 1)
    elif max_rel >= 2:
        result = _make_slope(4, _rotate_dir_cw(_corner_to_dir[max_idx]), h_min, h)
    elif raised_count == 1:
        result = _make_slope(2, _corner_to_dir[raised_indices[0]], h_min, h)
    elif raised_count == 3:
        result = _make_slope(3, _corner_to_dir[low_index], h_min, h)
    else:
        var a := raised_indices[0]
        var b := raised_indices[1]
        if _is_adjacent_corners(a, b):
            result = _make_slope(1, _edge_to_dir(a, b), h_min, h)
        elif (a == 0 and b == 3) or (a == 3 and b == 0):
            result = _make_slope(5, "west", h_min, h)
        else:
            result = _make_slope(6, "east", h_min, h)

    result["max_height"] = h_max
    return result


func _is_adjacent_corners(a: int, b: int) -> bool:
    var pairs: Array[Array] = [
        [0, 1],
        [0, 2],
        [1, 3],
        [2, 3],
    ]
    for pair in pairs:
        if (a == pair[0] and b == pair[1]) or (a == pair[1] and b == pair[0]):
            return true
    return false


func _edge_to_dir(a: int, b: int) -> String:
    if (a == 0 and b == 1) or (a == 1 and b == 0):
        return "north"
    if (a == 0 and b == 2) or (a == 2 and b == 0):
        return "west"
    if (a == 1 and b == 3) or (a == 3 and b == 1):
        return "east"
    if (a == 2 and b == 3) or (a == 3 and b == 2):
        return "south"
    return "north"


# ========================================
# JSON Import / Export
# ========================================


func export_to_json(path: String, extra_data: Dictionary = {}) -> void:
    var vertices: Dictionary = {}
    var extent: Vector2i = CellUtil.get_diamond_extent(grid_cells)
    var v_count_x := extent.x + 1
    var v_count_z := extent.y + 1
    for vx in v_count_x:
        for vz in v_count_z:
            var h: int = _vertex_grid[vx][vz]
            if h != 0:
                vertices[CellUtil.cell_key_str(Vector2i(vx, vz))] = h

    var data: Dictionary = {
        "version": 4,
        "grid_cells": [grid_cells.x, grid_cells.y],
        # map_size is write-only, self-describing metadata; on load the dimensions are
        # restored from the authoritative grid_cells, so this key is never read back.
        "map_size": [grid_cells.x, grid_cells.y],
        "vertices": vertices,
        "cells": _cells.duplicate(),
    }
    if not _cell_pins.is_empty():
        data["cell_pins"] = _cell_pins.duplicate()
    var land_out: Dictionary = {}
    for cx in extent.x:
        for cz in extent.y:
            var land_cell := Vector2i(cx, cz)
            var land_id := get_painted_land_type(land_cell)
            if not land_id.is_empty():
                land_out[CellUtil.cell_key_str(land_cell)] = land_id
    if not land_out.is_empty():
        data["land_types"] = land_out
    data["visible_bounds"] = [
        int(BoundsSystem.left_inset),
        int(BoundsSystem.right_inset),
        int(BoundsSystem.top_inset),
        int(BoundsSystem.bottom_inset),
    ]
    for key in extra_data:
        data[key] = extra_data[key]
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(data, "\t"))
        file.close()


func import_from_json(path: String) -> void:
    var old_keys: Array = _cells.keys().duplicate() as Array
    for key in old_keys:
        cell_changed.emit(key, {})
    _cells.clear()
    _cell_pins.clear()
    _land_types.clear()
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if not file:
        return
    var json: JSON = JSON.new()
    var error: Error = json.parse(file.get_as_text())
    file.close()
    if error != OK:
        return
    var data: Variant = json.data
    if data == null or not data is Dictionary:
        return

    var json_grid_cells: Variant = data.get("grid_cells", [grid_cells.x, grid_cells.y])
    if json_grid_cells is Array:
        var arr: Array = json_grid_cells
        init_grid(int(arr[0]), int(arr[1]))
    else:
        var single: int = int(json_grid_cells)
        init_grid(single, single)

    var vertices: Dictionary = data.get("vertices", {})
    var extent: Vector2i = CellUtil.get_diamond_extent(grid_cells)
    for vkey in vertices:
        var parts: PackedStringArray = vkey.split(",")
        if parts.size() == 2:
            var vx := int(parts[0])
            var vz := int(parts[1])
            if vx >= 0 and vx <= extent.x and vz >= 0 and vz <= extent.y:
                _vertex_grid[vx][vz] = clampi(vertices[vkey], 0, MAX_HEIGHT)

    var json_pins: Variant = data.get("cell_pins", {})
    if json_pins is Dictionary:
        for pin_key in json_pins:
            var pin_parts: PackedStringArray = String(pin_key).split(",")
            if pin_parts.size() != 2:
                continue
            var pin_cell := Vector2i(int(pin_parts[0]), int(pin_parts[1]))
            if CellUtil.is_in_diamond(pin_cell, grid_cells):
                _cell_pins[String(pin_key)] = String(json_pins[pin_key])

    var json_land: Variant = data.get("land_types", {})
    if json_land is Dictionary:
        for land_key in json_land:
            var land_parts: PackedStringArray = String(land_key).split(",")
            if land_parts.size() != 2:
                continue
            var land_cell := Vector2i(int(land_parts[0]), int(land_parts[1]))
            if not CellUtil.is_in_diamond(land_cell, grid_cells):
                continue
            var land_id := String(json_land[land_key])
            if not land_id.is_empty() and land_id != DEFAULT_LAND_TYPE:
                _land_types[CellUtil.cell_key(land_cell)] = land_id

    # Pins carry no geometry, so rebuild stamped objects from their pinned ids.
    _restore_pinned_objects()

    for cx in extent.x:
        for cz in extent.y:
            var cell := Vector2i(cx, cz)
            if not CellUtil.is_in_diamond(cell, grid_cells):
                continue
            var key := CellUtil.cell_key_str(cell)
            _cells[key] = _compute_cell_from_vertices(cell)

    for key in _cells:
        cell_changed.emit(key, _cells[key])

    grid_initialized.emit()


# ========================================
# Helpers
# ========================================


func _make_clear(height: int) -> Dictionary:
    return {"height": height, "type": "clear", "variant": 1, "direction": "", "rotation": 0.0}


func _make_slope(variant: int, direction: String, height: int, corners: Array) -> Dictionary:
    var object_id := slope_object_id(corners)
    var rotation := _direction_to_rotation(direction)
    if not object_id.is_empty():
        rotation = TerrainArtData.direction_rotation(object_id)
    return {
        "height": height,
        "type": "slope",
        "variant": variant,
        "direction": direction,
        "rotation": rotation,
        "object_id": object_id,
    }


func _direction_to_rotation(dir: String) -> float:
    match dir:
        "north":
            return 0.0
        "south":
            return 180.0
        "east":
            return 270.0
        "west":
            return 90.0
    return 0.0


func _rotate_dir_cw(dir: String) -> String:
    match dir:
        "north":
            return "east"
        "east":
            return "south"
        "south":
            return "west"
        "west":
            return "north"
    return "north"
