class_name MovementController extends Node3D

signal arrived(position: Vector3)
signal movement_started
signal pathfinding_failed

enum State { IDLE, ROTATING, MOVING, WAIT }
enum VerticalState { GROUND, ASCENDING, AIR, DESCENDING }

@export_group("Movement")
@export var move_speed: float = 8.0
@export var cell_radius: float = 1.0
@export var rotation_speed: float = 180.0
@export_range(1.0, 45.0) var rotation_angle_threshold: float = 5.0
@export_node_path("MeshInstance3D") var rotation_target_path: NodePath
@export var debug_show_path: bool = false
@export var locomotor: String = ""
@export var movement_zone: String = ""

const REPULSION_STRENGTH: float = 0.1

## Timing thresholds in seconds, derived from the frame counts they replaced at 60 FPS.
## Delta-accumulated, so they stay frame-rate independent and scale with game speed.
const REPAIR_INTERVAL: float = 10.0 / 60.0
const WAIT_SCATTER_SECONDS: float = 15.0 / 60.0
const WAIT_MIN_SECONDS: float = 10.0 / 60.0
const WAIT_MAX_SECONDS: float = 25.0 / 60.0

static var _scattered_this_frame: Dictionary = {}
static var _last_physics_frame: int = -1

## Frame-scoped smoothed-height memo, shared across all controllers. Terrain is
## static within a physics frame, so the ~3 bilinear reads per unit per tick
## collapse to one read per half-cell bucket. Keyed by half-cell (1m) buckets;
## the cached value is the bucket-center height, so it is deterministic and
## order-independent. Cleared when the process frame advances or when the
## TerrainSystem height snapshot generation changes (grid re-init / direct
## vertex edits).
static var _frame_heights: Dictionary = {}
static var _frame_heights_frame: int = -1

static var _frame_heights_gen: int = -1

## Frame-scoped per-cell cache shared across all controllers: land type and the
## 3×3 avoidance hood for each cell touched by the movement hot path this frame.
## Terrain and occupancy are static within a physics frame, so units sharing a
## cell pay one dict fetch per cell per frame instead of once per unit per tick.
## Keyed by `CellUtil.cell_key(cell)`; cleared when the process frame advances or
## when the TerrainSystem height-snapshot generation changes (grid re-init).
static var _frame_cells: Dictionary = {}
static var _frame_cells_frame: int = -1

static var _frame_cells_gen: int = -1
## Grid-generation at the time `_frame_cells` was built. `SpatialHash.rebuild()`
## replaces the `_grid` arrays the hood references; bumping past this gen
## invalidates the cache so no unit scans a stale array holding freed-node
## entries (crushed infantry).
static var _frame_cells_grid_gen: int = -1
const CELL_KEY_OFFSET: int = 1024
var _state: State = State.IDLE
var _vertical_state: VerticalState = VerticalState.GROUND
var _waypoints: PackedVector3Array = PackedVector3Array()
## Surface level of each waypoint, parallel to `_waypoints` (0 = ground, N = deck
## level). The unit's current surface level is derived from the segment it is on
## so Y is sampled from the deck while on a deck and from the ground beneath one.
var _waypoint_levels: PackedInt32Array = PackedInt32Array()
## Surface level the unit currently stands on / is stepping onto.
var _surface_level: int = 0
var _spline_t: float = 0.0
## Baked per-segment spline data: control points [p0,p1,p2,p3] and 3D length per
## segment, precomputed at path-build time so `_get_spline_pos`/`_get_spline_tangent`
## and the segment-length read index arrays instead of re-evaluating Catmull-Rom
## (and re-deriving control points) ~4x per unit per tick. `_baked_generation`
## guards against stale access when `_waypoints` is rebuilt.
var _baked_controls: Array = []
var _baked_seg_len: PackedFloat32Array = PackedFloat32Array()
var _path_generation: int = 0
var _baked_generation: int = -1
var _rotation_target: Node3D
var _parent: Node3D
var _wait_time: float = 0.0
var _wait_threshold: float = 1.0
var _repair_time: float = 0.0
var _speed_jitter: float = 1.0
var _rotation_yaw: float = 0.0

var _shares_cell: bool = false
var _stand_upright: bool = false
var _instant_turn: bool = false
var _organic_path: bool = false
var _crusher: bool = false
var _player_id: int = -1
var _assigned_slot: int = -1
var _sub_slot_position: Vector3 = Vector3.ZERO
var _has_sub_slot: bool = false
var _last_position: Vector3 = Vector3.ZERO
var _idle_snap_cell: Vector2i = Vector2i.ZERO
var _idle_snapped := false
var _veteran_speed_mult: float = 1.0
var _rules: GlobalRules = null
var _locomotor_data: Locomotor = null
var _hover_height: float = 0.0
var _jumpjet_air_height: float = 0.0
var _is_hover: bool = false
var _is_jumpjet: bool = false
var _is_subterranean: bool = false
var _hybrid_active: bool = false
var _land_on_arrival: bool = false
## Exact-target move: destination stays put even when occupied (boarding a
## transport); the unit walks a straight final leg onto it and arrives instead
## of waiting for the cell to clear.
var _exact_target: bool = false
var _ice_cracking_weight: float = 2.0
var _weight: float = 1.0
## Raw `EntityData.speed` (TS leptons/frame) stashed by `configure()`. -1 means
## the controller was not configured (scene/editor/test), so `move_speed` keeps
## its export default.
var _speed_leptons: float = -1.0

## Ramp state for Accelerate/Decelerate flags
var _ramp_speed: float = 0.0
var _ramp_accel_rate: float = 0.0
var _ramp_decel_rate: float = 0.0


func configure(data: EntityData) -> void:
    locomotor = data.locomotor
    movement_zone = data.movement_zone
    rotation_speed = data.rotation_speed
    _speed_leptons = data.speed
    _apply_speed()


## Resolves the unit's base `move_speed` from `EntityData.speed` (TS leptons
## per frame) through the GlobalRules conversion. Idempotent and called from
## both `configure()` (rules may not resolve yet) and `_ready()` (rules now
## known), so either call order leaves the converted value in force. May resolve
## and cache `_rules` itself when called before `_ready()`. A bare controller
## that was never configured keeps its export default.
func _apply_speed() -> void:
    if _speed_leptons < 0.0:
        return
    if not _rules:
        _rules = GlobalRules.get_current()
    if _rules:
        move_speed = _rules.speed_to_units_per_second(_speed_leptons)


## Slews the entity body toward a world position without touching waypoints or
## emitting movement signals. Returns true when the body faces the target
## within rotation_angle_threshold. Instant-turn locomotors snap and align
## in the same call.
func face_toward(target_pos: Vector3, delta: float) -> bool:
    if not is_instance_valid(_parent):
        return false
    var to_target := target_pos - _parent.global_position
    to_target.y = 0.0
    if to_target.length_squared() < 0.001:
        return true
    var desired_yaw := atan2(-to_target.x, -to_target.z)
    if _instant_turn:
        _rotation_yaw = desired_yaw
        _apply_facing(Vector3(-sin(desired_yaw), 0.0, -cos(desired_yaw)))
        return true
    var step := deg_to_rad(rotation_speed) * delta
    var tolerance := maxf(step, deg_to_rad(rotation_angle_threshold))
    if absf(angle_difference(_rotation_yaw, desired_yaw)) <= tolerance:
        _rotation_yaw = desired_yaw
        _apply_facing(Vector3(-sin(desired_yaw), 0.0, -cos(desired_yaw)))
        return true
    _rotation_yaw += signf(angle_difference(_rotation_yaw, desired_yaw)) * step
    _apply_facing(Vector3(-sin(_rotation_yaw), 0.0, -cos(_rotation_yaw)))
    return false


func _ready() -> void:
    _parent = get_parent() as Node3D
    debug_show_path = OS.is_debug_build() and debug_show_path
    _resolve_rotation_target()
    _speed_jitter = randf_range(0.95, 1.0)
    _wait_threshold = randf_range(WAIT_MIN_SECONDS, WAIT_MAX_SECONDS)
    _rules = GlobalRules.get_current()
    var stats := _parent.get_node_or_null("StatsComponent") as StatsComponent
    if stats:
        _crusher = stats.crusher
        _player_id = stats.player_id
        _weight = stats.weight
        _veteran_speed_mult = _get_veteran_speed_mult(stats.veteran_level)
    _resolve_locomotor()
    _apply_speed()


func _resolve_locomotor() -> void:
    if not _rules or locomotor.is_empty():
        return
    _locomotor_data = _rules.get_locomotor(locomotor)
    if _locomotor_data == null:
        push_error("[MovementController] Unknown locomotor: %s" % locomotor)
        return
    _is_hover = _locomotor_data.is_hover
    _is_jumpjet = _locomotor_data.is_jumpjet
    _is_subterranean = _locomotor_data.is_subterranean
    if _locomotor_data.hover_height_override > 0.0:
        _hover_height = _locomotor_data.hover_height_override
    else:
        _hover_height = float(_rules.hover_height) * (CellUtil.CELL_SIZE / 256.0)
    _jumpjet_air_height = _locomotor_data.jumpjet_target_height * TerrainSystem.HEIGHT_STEP
    _ice_cracking_weight = _rules.ice_cracking_weight
    _shares_cell = _locomotor_data.shares_cell
    _stand_upright = _locomotor_data.stand_upright
    _instant_turn = _locomotor_data.instant_turn
    _organic_path = _locomotor_data.organic_path


func shares_cell() -> bool:
    return _shares_cell


func _get_veteran_speed_mult(veteran_level: int) -> float:
    if veteran_level <= 0:
        return 1.0
    if not _rules:
        return 1.0
    return _rules.get_veteran_speed_multiplier(veteran_level)


func _slope_coefficient() -> float:
    if not _locomotor_data or _is_hover:
        return 1.0
    var uphill: float = _locomotor_data.uphill_factor
    var downhill: float = _locomotor_data.downhill_factor
    if is_equal_approx(uphill, 1.0) and is_equal_approx(downhill, 1.0):
        return 1.0
    if _waypoints.size() < 2:
        return 1.0
    var seg := _spline_segment()
    var next_idx := mini(seg + 1, _waypoints.size() - 1)
    var probe := CellUtil.cell_to_world(CellUtil.world_to_cell(_waypoints[next_idx]))
    var height_ahead := _memoized_smooth_height(probe)
    var height_now := _memoized_smooth_height(_parent.global_position)
    var grade := height_ahead - height_now
    if absf(grade) < 0.05:
        return 1.0
    return uphill if grade > 0.0 else downhill


func _terrain_speed_factor() -> float:
    if not _locomotor_data or _locomotor_data.is_fly:
        return 1.0
    if _is_jumpjet and _vertical_state != VerticalState.GROUND:
        return 1.0
    var cell := CellUtil.world_to_cell(_parent.global_position)
    if _surface_level > 0:
        # On a deck the terrain figure is skipped: the deck is passed/costed from
        # the land its cell resolves (Road for a road lane, Railroad for a rail
        # middle lane), falling back to Road when the locomotor lacks that row.
        # Bypasses the frame-scoped land cache, which is level-0 keyed.
        # ponytail: deck traffic is rare; fold level into the frame cache only if
        # profiling flags it.
        var deck_land: String = TerrainSystem.get_land_type(cell, _surface_level)
        return _locomotor_data.get_speed_multiplier(_deck_land_row(deck_land))
    return _locomotor_data.get_speed_multiplier(_frame_cell_land(cell))


## Land row a deck surface resolves to for this locomotor's speed: the deck's own
## resolved land when declared, otherwise Road.
func _deck_land_row(deck_land: String) -> String:
    if _locomotor_data.terrain_speeds.has(deck_land):
        return deck_land
    return "road"


func _is_floating() -> bool:
    if _is_hover:
        return true
    return _is_jumpjet and _vertical_state != VerticalState.GROUND


## Frame-scoped smoothed terrain height. Terrain is static within a physics
## frame, so the ~3 `get_height_at_world_smooth` reads per unit per tick
## collapse to one corner-array fetch per cell. The per-cell corner heights are
## cached, then bilinear-interpolated at the exact query position — bit-identical
## to `get_height_at_world_smooth` (no bucket quantization). Unit-independent
## only — the 3x3 avoidance scan stays live per-unit (it reads dynamic neighbor
## positions).
func _ensure_frame_caches_valid() -> void:
    var frame := Engine.get_process_frames()
    var gen: int = TerrainSystem.height_snapshot_generation
    if frame != _frame_heights_frame or gen != _frame_heights_gen:
        _frame_heights.clear()
        _frame_heights_frame = frame
        _frame_heights_gen = gen
    var grid_gen: int = SpatialHash.instance.grid_generation if SpatialHash.instance else -1
    if frame != _frame_cells_frame or gen != _frame_cells_gen or grid_gen != _frame_cells_grid_gen:
        _frame_cells.clear()
        _frame_cells_frame = frame
        _frame_cells_gen = gen
        _frame_cells_grid_gen = grid_gen


## Frame-scoped land type for a cell. Terrain land type is static within a
## physics frame (resource-registry flips land at most at growth/harvest
## boundaries), so the painted-overlay + resource-registry dict reads collapse to
## one per cell per frame for all units on that cell.
func _frame_cell_land(cell: Vector2i) -> String:
    var entry := _frame_cell_entry(cell)
    if not entry.has("land"):
        entry["land"] = TerrainSystem.get_land_type(cell)
    return entry["land"]


## Frame-scoped 3×3 avoidance hood for a cell: the 9 `SpatialHash.get_entries`
## lists around `cell`, fetched once per cell per frame. Units sharing a cell
## read the same hood, and empty neighbor cells answer from the cached empty
## array — no per-unit `get_entries` burst. The cached lists are only read by
## the avoidance scan (never mutated), so sharing them is safe.
func _frame_hood(cell: Vector2i) -> Array:
    var entry := _frame_cell_entry(cell)
    if not entry.has("hood"):
        var hood := []
        hood.resize(9)
        for dx in range(-1, 2):
            for dz in range(-1, 2):
                var entries: Array = SpatialHash.instance.get_entries(cell + Vector2i(dx, dz))
                hood[(dx + 1) * 3 + (dz + 1)] = entries
        entry["hood"] = hood
    return entry["hood"]


func _frame_cell_entry(cell: Vector2i) -> Dictionary:
    _ensure_frame_caches_valid()
    var key := CellUtil.cell_key(cell)
    var entry: Dictionary = _frame_cells.get(key, {})
    if entry.is_empty():
        entry = {}
        _frame_cells[key] = entry
    return entry


## Bridge deck Y at a world position for the unit's current surface level, or NAN
## when the unit's level has no deck there. Kept allocation-free (Vector2i/int
## only) for the movement hot path; callers test with `is_nan`.
func _bridge_deck_height(pos: Vector3) -> float:
    if SpatialHash.instance == null or _surface_level <= 0:
        return NAN
    var cell := CellUtil.world_to_cell(pos)
    if not SpatialHash.instance.has_bridge_on_cell(cell, _surface_level):
        return NAN
    return TerrainSystem.get_cell_surface_height(cell, _surface_level)


func _memoized_smooth_height(pos: Vector3) -> float:
    var deck := _bridge_deck_height(pos)
    if not is_nan(deck):
        return deck
    _ensure_frame_caches_valid()
    var center: float = float(TerrainSystem.grid_cells.x + TerrainSystem.grid_cells.y) * 0.5
    var vx: float = pos.x / CellUtil.CELL_SIZE + center
    var vz: float = pos.z / CellUtil.CELL_SIZE + center
    var x0 := floori(vx)
    var z0 := floori(vz)
    var key := (x0 + CELL_KEY_OFFSET) << 16 | (z0 + CELL_KEY_OFFSET) & 0xFFFF
    var corners: Array = _frame_heights.get(key, [])
    if corners.is_empty():
        corners = TerrainSystem.get_cell_snapshot_corners_raw(Vector2i(x0, z0))
        _frame_heights[key] = corners
    if corners.is_empty():
        # Out-of-diamond cell: fall back to the live query for the exact height.
        return TerrainSystem.get_height_at_world_smooth(pos)
    var fx: float = vx - float(x0)
    var fz: float = vz - float(z0)
    var h00: float = float(corners[0])
    var h10: float = float(corners[1])
    var h01: float = float(corners[2])
    var h11: float = float(corners[3])
    var h0: float = h00 + (h10 - h00) * fx
    var h1: float = h01 + (h11 - h01) * fx
    return (h0 + (h1 - h0) * fz) * TerrainSystem.HEIGHT_STEP


## Frame-scoped terrain normal at a world position. Reuses the same per-cell
## corner-array fetch as `_memoized_smooth_height` (same cell key, same
## `_frame_heights` store), so a unit's snap and facing read the corners once per
## frame per cell. Computes the same cross-product normal as
## `TerrainSystem.get_normal_at_world` (same raw corners, same `edge_z.cross(
## edge_x)` ordering, same `HEIGHT_STEP` scaling) — bit-identical output.
func _memoized_normal(pos: Vector3) -> Vector3:
    _ensure_frame_caches_valid()
    var center: float = float(TerrainSystem.grid_cells.x + TerrainSystem.grid_cells.y) * 0.5
    var vx: float = pos.x / CellUtil.CELL_SIZE + center
    var vz: float = pos.z / CellUtil.CELL_SIZE + center
    var x0 := floori(vx)
    var z0 := floori(vz)
    var key := (x0 + CELL_KEY_OFFSET) << 16 | (z0 + CELL_KEY_OFFSET) & 0xFFFF
    var corners: Array = _frame_heights.get(key, [])
    if corners.is_empty():
        corners = TerrainSystem.get_cell_snapshot_corners_raw(Vector2i(x0, z0))
        _frame_heights[key] = corners
    if corners.is_empty():
        # Out-of-diamond cell: fall back to the live query for the exact normal.
        return TerrainSystem.get_normal_at_world(pos).normalized()
    var h00: float = float(corners[0]) * TerrainSystem.HEIGHT_STEP
    var h10: float = float(corners[1]) * TerrainSystem.HEIGHT_STEP
    var h01: float = float(corners[2]) * TerrainSystem.HEIGHT_STEP
    var edge_x := Vector3(CellUtil.CELL_SIZE, h10 - h00, 0.0)
    var edge_z := Vector3(0.0, h01 - h00, CellUtil.CELL_SIZE)
    return edge_z.cross(edge_x).normalized()


## Split factor while a jumpjet vertically transitions (ascend/descend) at the
## same time as moving forward: each axis gets 50% of move_speed. Pure vertical
## transitions (idle landing) keep full speed.
func _vertical_split_factor() -> float:
    if not _is_jumpjet:
        return 1.0
    if _vertical_state != VerticalState.ASCENDING and _vertical_state != VerticalState.DESCENDING:
        return 1.0
    if _state == State.IDLE:
        return 1.0
    return 0.5


func is_airborne_jumpjet() -> bool:
    return _is_jumpjet and _vertical_state != VerticalState.GROUND


func _num_segments() -> int:
    return maxi(0, _waypoints.size() - 1)


func is_moving() -> bool:
    return _state != State.IDLE


func is_waiting() -> bool:
    return _state == State.WAIT


func get_assigned_slot() -> int:
    return _assigned_slot


func stop() -> void:
    if _state == State.IDLE:
        return
    if _state == State.ROTATING:
        _finish_stop()
        return
    if _state == State.WAIT:
        var final_pos := _waypoints[_waypoints.size() - 1]
        var dist := _parent.global_position.distance_to(final_pos)
        if dist < 0.1:
            var final_cell := CellUtil.world_to_cell(final_pos)
            if _exact_target or not _is_cell_occupied_by_idle(final_cell):
                _finish_stop()
                return
    if _state == State.MOVING:
        var seg := _spline_segment()
        var next_idx := mini(seg + 1, _waypoints.size() - 1)
        var next_waypoint := _waypoints[next_idx]
        if _shares_cell and not (_is_jumpjet and _vertical_state != VerticalState.GROUND):
            var current_cell := CellUtil.world_to_cell(_parent.global_position)
            _assign_sub_slot_at_cell(current_cell)
            if _has_sub_slot:
                next_waypoint = _sub_slot_position
            else:
                var free_cell := CellUtil.spiral_first_free(
                    current_cell, 3, _is_cell_occupied_by_idle
                )
                _assign_sub_slot_at_cell(free_cell)
                if _has_sub_slot:
                    next_waypoint = _sub_slot_position
                else:
                    next_waypoint = CellUtil.cell_to_world(free_cell)
        else:
            var dist_to_next := (next_waypoint - _parent.global_position).length()
            if dist_to_next > CellUtil.CELL_SIZE:
                var dir := (next_waypoint - _parent.global_position).normalized()
                var candidate := _parent.global_position + dir * CellUtil.CELL_SIZE
                var candidate_cell := CellUtil.world_to_cell(candidate)
                var current_cell := CellUtil.world_to_cell(_parent.global_position)
                if candidate_cell != current_cell:
                    next_waypoint = CellUtil.cell_to_world(candidate_cell)
        _waypoints = PackedVector3Array([_parent.global_position, next_waypoint])
        _waypoint_levels = PackedInt32Array([_surface_level, _surface_level])
        _spline_t = 0.0
        _bake_spline()


func _finish_stop() -> void:
    _waypoints = PackedVector3Array()
    _waypoint_levels = PackedInt32Array()
    _spline_t = 0.0
    _bake_spline()
    _has_sub_slot = false
    _hybrid_active = false
    _land_on_arrival = false
    _ramp_speed = 0.0
    _state = State.IDLE
    _idle_snapped = false
    SpatialHash.instance.release_cell(
        CellUtil.world_to_cell(_parent.global_position), _surface_level
    )
    CellReservation.instance.release_all(_parent)
    if debug_show_path:
        DebugVisualizer.clear_path(get_path())


## Cancels an airborne jumpjet's current move without losing its air zone, so a
## new order (e.g. an attack) resumes from the air instead of landing first.
func cancel_move_retain_vertical() -> void:
    if not is_airborne_jumpjet():
        return
    if _state != State.IDLE:
        _finish_stop()


## `internal` marks re-targets issued by this controller itself (repair,
## blocked-arrival settle, wait scatter, nudges) rather than new player orders;
## those do not emit `movement_started`.
func set_target_position(
    target: Vector3,
    unblock_buildings: bool = false,
    keep_zone: bool = false,
    internal: bool = false,
    cost_cache: Pathfinder.PathCostCache = null,
    terrain: Node = null,
    bounded: bool = false,
    exact_target: bool = false,
    end_level: int = 0,
) -> void:
    _exact_target = exact_target
    if (
        is_nan(target.x)
        or is_nan(target.y)
        or is_nan(target.z)
        or not is_finite(target.x)
        or not is_finite(target.y)
        or not is_finite(target.z)
    ):
        printerr("[MovementController] Ignoring invalid target position: ", target)
        return

    var target_cell := CellUtil.world_to_cell(target)

    # Jumpjet flight decision before any ground booking: fly when airborne,
    # when attacking from the air, or when the target is far; otherwise walk
    # on the ground like infantry (default zone GROUND).
    var fly_move := false
    if _is_jumpjet and _locomotor_data:
        if keep_zone:
            fly_move = _vertical_state != VerticalState.GROUND
            # A grounded jumpjet ordered far still takes off even when the
            # caller asked to keep the zone (e.g. combat approach to a distant
            # target), matching the normal-move fly-when-far rule.
            if not fly_move and _locomotor_data.jumpjet_fly_distance > 0.0:
                var fly_dist := _parent.global_position.distance_to(target)
                fly_move = fly_dist > _locomotor_data.jumpjet_fly_distance
        elif _vertical_state != VerticalState.GROUND:
            fly_move = true
        else:
            var fly_dist := _parent.global_position.distance_to(target)
            var fly_threshold: float = _locomotor_data.jumpjet_fly_distance
            fly_move = fly_threshold > 0.0 and fly_dist > fly_threshold

    var path: PackedVector3Array
    var path_levels: PackedInt32Array = PackedInt32Array()
    var blocked: Dictionary = {}
    var hybrid_fallback := false

    if fly_move:
        # Air move: straight line to the target, no path-cell booking. When the
        # move will land (not keep_zone), reserve a sub-slot at the landing cell
        # so the jumpjet descends onto a sub-slot instead of the cell center.
        _has_sub_slot = false
        hybrid_fallback = true
        if _shares_cell and not keep_zone:
            # Never fly into an occupied landing cell: relocate up front, like
            # the ground branch, before booking so arrival is clean.
            if _is_cell_occupied_by_idle(target_cell):
                var free := _find_nearest_free_idle_cell(target_cell, bounded)
                target = CellUtil.cell_to_world(free)
                target_cell = free
            _assign_sub_slot_at_cell(target_cell, end_level)
            if not _has_sub_slot:
                var free_cell := _find_nearest_free_sub_slot_cell(target_cell, bounded)
                _assign_sub_slot_at_cell(free_cell, end_level)
                if _has_sub_slot:
                    target = _sub_slot_position
            else:
                target = _sub_slot_position
        # `target` is the exact stop position (clamped attack approach) or the
        # booked landing sub-slot; both are single straight-line fly segments.
        path = PackedVector3Array([target])
        path_levels = PackedInt32Array([end_level])
    else:
        # Ground move: normal infantry booking, then walk pathfinding.
        # Exact-target moves (boarding) keep the occupied destination and walk
        # a straight final leg onto it instead of relocating.
        if not exact_target and _is_cell_occupied_by_idle(target_cell):
            var free := _find_nearest_free_idle_cell(target_cell, bounded)
            target = CellUtil.cell_to_world(free)
            target_cell = free
        if _shares_cell:
            _assign_sub_slot_at_cell(target_cell, end_level)
            if not _has_sub_slot:
                var free_cell := _find_nearest_free_sub_slot_cell(target_cell, bounded)
                _assign_sub_slot_at_cell(free_cell, end_level)
                target_cell = free_cell
                if _has_sub_slot:
                    target = _sub_slot_position
            else:
                target = _sub_slot_position

        blocked = _build_blocked_cells(unblock_buildings)
        var routed: Dictionary = _greedy_or_search_path(
            target, target_cell, blocked, unblock_buildings, cost_cache, terrain, end_level
        )
        path = routed["path"]
        path_levels = routed["levels"]
        if exact_target and not path.is_empty():
            var last_cell := CellUtil.world_to_cell(path[path.size() - 1])
            # Straight final leg onto the occupied destination (the APC) —
            # skipped when that cell is water: the walker stops at the shore
            # cell and still boards via the arrival range check.
            if last_cell != target_cell and TerrainSystem.get_land_type(target_cell) != "water":
                path.append(target)
                path_levels.append(end_level)

        if _is_jumpjet and _locomotor_data:
            if path.is_empty():
                var same_cell := (
                    CellUtil.world_to_cell(_parent.global_position)
                    == CellUtil.world_to_cell(target)
                )
                if same_cell:
                    # Already at the target cell: settle into the sub-slot on
                    # the ground instead of taking off.
                    path = PackedVector3Array([target])
                    path_levels = PackedInt32Array([end_level])
                else:
                    # Unreachable on foot: fly straight to the target, then land.
                    hybrid_fallback = true
                    path = PackedVector3Array([target])
                    path_levels = PackedInt32Array([end_level])
        elif _is_subterranean and _locomotor_data:
            var dig_dist := _parent.global_position.distance_to(target)
            var dig_threshold: float = _locomotor_data.subterranean_dig_distance
            if path.is_empty() or (dig_threshold > 0.0 and dig_dist > dig_threshold):
                hybrid_fallback = true
                path = PackedVector3Array([target])
                path_levels = PackedInt32Array([end_level])

    if _is_jumpjet:
        if _vertical_state == VerticalState.DESCENDING:
            hybrid_fallback = true
        var desired_zone: VerticalState = (
            VerticalState.AIR if hybrid_fallback else VerticalState.GROUND
        )
        _apply_zone_desire(desired_zone)

    _land_on_arrival = _is_jumpjet and hybrid_fallback and not keep_zone
    _hybrid_active = hybrid_fallback

    if path.is_empty():
        _scatter_blockers()
        pathfinding_failed.emit()
        return

    if _organic_path and path.size() > 2 and not hybrid_fallback:
        # Smoothed organic paths drop collinear waypoints; re-map each surviving
        # waypoint's level from the pre-smoothing path by cell so deck segments
        # keep their surface.
        var level_by_cell: Dictionary = {}
        for j in path.size():
            var lvl_j: int = path_levels[j] if j < path_levels.size() else 0
            level_by_cell[CellUtil.world_to_cell(path[j])] = lvl_j
        path = Pathfinder.smooth_path(path, blocked)
        var smoothed_levels := PackedInt32Array()
        for j in path.size():
            smoothed_levels.append(int(level_by_cell.get(CellUtil.world_to_cell(path[j]), 0)))
        path_levels = smoothed_levels

    if _shares_cell and _has_sub_slot and path.size() > 0 and not hybrid_fallback:
        path[path.size() - 1] = _sub_slot_position

    # Share the unit's own lane offset across all intermediate waypoints so the
    # whole path runs parallel to the cell-center path (a squad of sharers fans
    # out into parallel lanes). The offset is the booked destination sub-slot's
    # displacement from its cell center — radius < half-cell, so each shifted
    # waypoint stays inside its own cell and path integrity is preserved.
    if _shares_cell and _has_sub_slot and path.size() > 2 and not hybrid_fallback:
        var lane_offset := (
            _sub_slot_position - CellUtil.cell_to_world(CellUtil.world_to_cell(_sub_slot_position))
        )
        for i in range(0, path.size() - 1):
            path[i] += lane_offset

    var full_path: PackedVector3Array = [_parent.global_position]
    full_path.append_array(path)
    var full_levels := PackedInt32Array([_surface_level])
    full_levels.append_array(path_levels)

    # The unit's start is a sub-slot offset, not a cell center, so the first
    # waypoint (cell center or its sub-slot) can point sideways off the line to
    # the destination. When the start has a clear line of sight to the final
    # waypoint, collapse the path to a straight segment — no hump through
    # intermediate cell centers, and no cut corners (LOS is obstacle-aware).
    if _shares_cell and full_path.size() > 2 and not hybrid_fallback:
        if (
            Pathfinder
            . has_line_of_sight(
                CellUtil.world_to_cell(full_path[0]),
                CellUtil.world_to_cell(full_path[full_path.size() - 1]),
                blocked,
            )
        ):
            full_path = PackedVector3Array([full_path[0], full_path[full_path.size() - 1]])
            full_levels = PackedInt32Array([full_levels[0], full_levels[full_levels.size() - 1]])

    if full_levels.size() != full_path.size():
        # Defensive: never let the level sequence drift out of step with the
        # waypoints; fill missing entries with the destination level.
        var repaired := PackedInt32Array()
        for i in full_path.size():
            repaired.append(full_levels[i] if i < full_levels.size() else end_level)
        full_levels = repaired

    for i in range(1, full_path.size()):
        var wp_level: int = full_levels[i]
        if wp_level > 0:
            full_path[i].y = TerrainSystem.get_cell_surface_height(
                CellUtil.world_to_cell(full_path[i]), wp_level
            )
        else:
            full_path[i].y = TerrainSystem.get_height_at_world_smooth(full_path[i])

    _waypoints = full_path
    _waypoint_levels = full_levels
    _bake_spline()
    _spline_t = 0.0
    _wait_time = 0.0
    _repair_time = 0.0
    _last_position = _parent.global_position
    if is_instance_valid(_rotation_target):
        _rotation_yaw = _rotation_target.global_rotation.y
    if _instant_turn:
        _state = State.MOVING
        if is_instance_valid(_rotation_target) and _waypoints.size() > 1:
            var tangent := (_waypoints[1] - _waypoints[0]).normalized()
            var target_yaw := atan2(-tangent.x, -tangent.z)
            _rotation_yaw = target_yaw
            _apply_facing(Vector3(-sin(target_yaw), 0.0, -cos(target_yaw)))
    else:
        _state = State.ROTATING

    # Decel-only locomotors start at full speed (TS semantics: no Accelerate = immediate cruise)
    if _locomotor_data and _locomotor_data.decelerate and not _locomotor_data.accelerate:
        _ramp_speed = move_speed
    elif _state == State.IDLE:
        _ramp_speed = 0.0

    if debug_show_path:
        DebugVisualizer.draw_path(get_path(), _parent.global_position, _waypoints, 0)

    # Emit only after _waypoints is set so consumers reading the destination
    # (e.g. SelectComponent's move-target line) never see the stale/empty path.
    if not internal:
        movement_started.emit()


func get_target_position() -> Vector3:
    if _waypoints.is_empty():
        return _parent.global_position
    return _waypoints[_waypoints.size() - 1]


## Move onto an occupied destination (e.g. infantry boarding a transport): the
## target is not relocated, the unit walks a straight final leg onto it, and
## arrival fires even though the destination cell is occupied.
func set_exact_target(target: Vector3) -> void:
    # Positional tail: unblock=false, keep_zone=false, internal=false,
    # caches=null, bounded=false, exact_target=true.
    set_target_position(target, false, false, false, null, null, false, true)


## Greedy-first path resolution: walks bounded greedy descent (`try_greedy_step`)
## from the unit's current cell toward the destination cell. On open terrain the
## walk completes in O(distance) cheap steps, skipping the full A* search. When
## the walk stalls (concave pocket, blocked cells, cliff) or exhausts the budget,
## the walked prefix is kept and the remaining leg is finished with a full
## `find_path` from the stalled cell — so the path is always completed and the
## result degrades gracefully to the pre-greedy behavior.
func _greedy_or_search_path(
    target: Vector3,
    target_cell: Vector2i,
    blocked: Dictionary,
    unblock_buildings: bool,
    cost_cache: Pathfinder.PathCostCache,
    terrain: Node = null,
    end_level: int = 0,
) -> Dictionary:
    const GREEDY_BUDGET: int = 64
    if terrain == null:
        terrain = Pathfinder._get_terrain_system()
    var start_cell := CellUtil.world_to_cell(_parent.global_position)
    var current := start_cell
    var current_level := _surface_level
    var prefix := PackedVector3Array()
    var prefix_levels := PackedInt32Array()
    var prev: Vector2i = current
    var steps := 0
    while (current != target_cell or current_level != end_level) and steps < GREEDY_BUDGET:
        var step: Dictionary = (
            Pathfinder
            . try_greedy_step_detailed(
                current,
                target_cell,
                blocked,
                _locomotor_data,
                prev,
                cost_cache,
                terrain,
                current_level,
                end_level,
            )
        )
        if step["cell"] == Pathfinder.GREEDY_STALL:
            break
        prefix.append(CellUtil.cell_to_world(step["cell"]))
        prefix_levels.append(int(step["level"]))
        prev = current
        current = step["cell"]
        current_level = int(step["level"])
        steps += 1

    if current == target_cell and current_level == end_level and prefix.size() > 0:
        # Greedy completed the whole walk: cell-center waypoints mirror the
        # find_path output shape (start cell excluded).
        return {"path": prefix, "levels": prefix_levels}

    # Greedy stalled or exhausted the budget: finish the remaining leg with A*
    # from the stalled cell (or the original start when greedy never moved).
    var search_start: Vector3 = (
        _parent.global_position if prefix.is_empty() else CellUtil.cell_to_world(current)
    )
    var rest: Dictionary = (
        Pathfinder
        . find_path_detailed(
            search_start,
            target,
            blocked,
            _locomotor_data,
            unblock_buildings,
            cost_cache,
            terrain,
            current_level,
            end_level,
        )
    )
    var rest_path: PackedVector3Array = rest["path"]
    var rest_levels: PackedInt32Array = rest["levels"]
    if prefix.is_empty():
        return {"path": rest_path, "levels": rest_levels}
    var combined := prefix
    combined.append_array(rest_path)
    var combined_levels := prefix_levels
    combined_levels.append_array(rest_levels)
    return {"path": combined, "levels": combined_levels}


func validate(data: EntityData) -> PackedStringArray:
    var errors: PackedStringArray = []
    if data.speed <= 0.0:
        errors.append("MovementController: '%s' has speed <= 0" % data.id)
    return errors


func _resolve_rotation_target() -> void:
    if not rotation_target_path.is_empty():
        var resolved := get_node(rotation_target_path) as Node3D
        if is_instance_valid(resolved):
            _rotation_target = resolved

    if not is_instance_valid(_rotation_target):
        _rotation_target = _parent


func _physics_process(delta: float) -> void:
    if Engine.is_editor_hint():
        return

    var frame := Engine.get_process_frames()
    if frame != _last_physics_frame:
        _last_physics_frame = frame
        _scattered_this_frame.clear()

    match _state:
        State.ROTATING:
            _handle_rotating(delta)
        State.MOVING:
            _handle_moving_movement(delta)
        State.WAIT:
            _handle_wait(delta)
        State.IDLE:
            if _is_jumpjet:
                _update_vertical(delta)
            else:
                _snap_if_idle_cell_changed()


func _handle_rotating(delta: float) -> void:
    if not is_instance_valid(_rotation_target):
        _state = State.MOVING
        return

    var tangent := _get_spline_tangent(_spline_t)
    if tangent.length() < 0.01:
        _state = State.MOVING
        return

    var target_yaw := atan2(-tangent.x, -tangent.z)
    var step := deg_to_rad(rotation_speed) * delta

    if (
        abs(angle_difference(_rotation_yaw, target_yaw))
        < max(step, deg_to_rad(rotation_angle_threshold))
    ):
        _spline_t = 0.001
        _state = State.MOVING
    else:
        _rotation_yaw += sign(angle_difference(_rotation_yaw, target_yaw)) * step
        _apply_facing(Vector3(-sin(_rotation_yaw), 0.0, -cos(_rotation_yaw)))


func _handle_moving_movement(delta: float) -> void:
    _update_surface_level()
    var seg := _spline_segment()
    var seg_begin := _get_spline_pos(float(seg))
    var seg_end := _get_spline_pos(float(seg + 1))
    var seg_length := _segment_length(seg)
    # Floating units move horizontally while their Y is owned by the vertical
    # state machine (`_update_vertical` / hover float). Using the 3D segment
    # length here would let `_spline_t` reach the path end after travelling more
    # horizontal distance than the destination needs — overshooting past the
    # stop and then gliding back (the "bounce"). Measure on the XZ plane instead.
    if _is_floating():
        seg_length = Vector2(seg_begin.x - seg_end.x, seg_begin.z - seg_end.z).length()
    if seg_length < 0.01:
        seg_length = 0.01

    if seg + 1 < _waypoints.size() - 1:
        _repair_time += delta
        if _repair_time >= REPAIR_INTERVAL:
            _repair_time = 0.0
            var next_cell := CellUtil.world_to_cell(_waypoints[seg + 1])
            if (
                not (_is_jumpjet and _vertical_state != VerticalState.GROUND)
                and _is_cell_occupied_by_idle(next_cell)
            ):
                set_target_position(
                    _waypoints[_waypoints.size() - 1], false, not _land_on_arrival, true
                )
                return

    var parent_pos := _parent.global_position
    var spline_dir := _get_spline_tangent(_spline_t)
    spline_dir.y = 0.0
    spline_dir = spline_dir.normalized()
    # Organic paths (infantry) walk straight legs between waypoints — no spline
    # arc, which Catmull-Rom sweeps into a wide curve at sharp corners.
    var steering_dir := spline_dir
    if _organic_path and _waypoints.size() > 1:
        var next_wp := _waypoints[mini(_spline_segment() + 1, _waypoints.size() - 1)]
        var to_next := next_wp - parent_pos
        to_next.y = 0.0
        if to_next.length() > 0.001:
            steering_dir = to_next.normalized()
    var direction := steering_dir

    var final_pos := _waypoints[_waypoints.size() - 1]
    var dist_to_final := parent_pos.distance_to(final_pos)
    var repulsion_weight := clampf(dist_to_final / (cell_radius * 4.0), 0.0, 1.0)

    var parent_cell := CellUtil.world_to_cell(parent_pos)
    var min_neighbor_dist_ahead: float = INF
    var hood: Array = _frame_hood(parent_cell)

    var hi: int = 0
    for dx in range(-1, 2):
        for dz in range(-1, 2):
            for entry in hood[hi]:
                var node_ref: Object = entry.node
                if not is_instance_valid(node_ref) or node_ref == _parent:
                    continue
                # Level-scoped avoidance: a unit on another surface of the same
                # cell (deck vs ground) is not a neighbour to steer around.
                if int(entry.get("level", 0)) != _surface_level:
                    continue
                var entity_parent := node_ref as Node3D

                var mc := entry.mc as MovementController
                if not mc or mc._state == State.IDLE:
                    continue

                if _shares_cell and mc.shares_cell():
                    continue

                var neighbor_dist: float = parent_pos.distance_to(entity_parent.global_position)
                var to_neighbor := (entity_parent.global_position - parent_pos).normalized()
                if to_neighbor.dot(steering_dir) > 0.0 and neighbor_dist < min_neighbor_dist_ahead:
                    min_neighbor_dist_ahead = neighbor_dist

                if neighbor_dist < cell_radius * 2.0 and neighbor_dist > 0.01:
                    var push_away: Vector3 = (
                        (parent_pos - entity_parent.global_position).normalized()
                        / squaref(neighbor_dist)
                    )
                    direction += push_away * REPULSION_STRENGTH * repulsion_weight
            hi += 1

    var speed_factor: float = 1.0
    if min_neighbor_dist_ahead < INF:
        var t := clampf(min_neighbor_dist_ahead / (cell_radius * 1.5), 0.0, 1.0)
        speed_factor = 0.3 + 0.7 * smoothstep(0.0, 1.0, t)

    # Update ramp speed when moving (freeze during ROTATING/WAIT)
    if (
        _state == State.MOVING
        and _locomotor_data
        and (_locomotor_data.accelerate or _locomotor_data.decelerate)
    ):
        _update_ramp_speed(delta)

    var deviation := (direction - steering_dir).limit_length(0.3 * repulsion_weight)
    var final_direction := (steering_dir + deviation).normalized()

    if is_instance_valid(_rotation_target):
        var face := Vector3(final_direction.x, 0.0, final_direction.z).normalized()
        if face.length_squared() >= 0.001:
            # Keep the yaw mirror in sync with the body: face_toward and
            # _handle_rotating slew from _rotation_yaw, and a stale value (path
            # start heading) makes the next face_toward snap the vehicle.
            _rotation_yaw = atan2(-face.x, -face.z)
            _apply_facing(face)

    var step := (
        final_direction
        * move_speed
        * _vertical_split_factor()
        * _speed_jitter
        * speed_factor
        * _veteran_speed_mult
        * _slope_coefficient()
        * _terrain_speed_factor()
        * _get_ramp_factor()
        * delta
    )
    _spline_t += step.length() / seg_length

    if _spline_t >= float(_num_segments()):
        _spline_t = float(_num_segments())
        var final_cell := CellUtil.world_to_cell(final_pos)
        # An airborne attack hold hovers at its in-range stop position regardless
        # of what occupies the ground cell below — re-targeting would push it off
        # the range circle and make it bounce back. Only landing moves (and ground
        # movers) re-target off a blocked cell.
        var airborne_hold := is_airborne_jumpjet() and not _land_on_arrival
        if not airborne_hold and not _exact_target and _is_cell_occupied_by_idle(final_cell):
            if _is_jumpjet:
                # A jumpjet can fly: don't freeze waiting for the cell to clear,
                # glide to the nearest free cell instead (keeping its zone intent).
                var free_cell := _find_nearest_free_idle_cell(final_cell)
                set_target_position(
                    CellUtil.cell_to_world(free_cell), false, not _land_on_arrival, true
                )
            else:
                _state = State.WAIT
            return

        var approach_step := (final_pos - _parent.global_position).limit_length(
            (
                move_speed
                * _vertical_split_factor()
                * _veteran_speed_mult
                * _slope_coefficient()
                * _terrain_speed_factor()
                * _get_ramp_factor()
                * delta
            )
        )
        # Jumpjets hover above terrain, so arrival is measured on the XZ plane.
        var arrival_dist: float = (
            Vector2(approach_step.x, approach_step.z).length()
            if _is_jumpjet
            else approach_step.length()
        )
        if arrival_dist < 0.001:
            if not _is_jumpjet:
                _parent.global_position.y = _memoized_smooth_height(_parent.global_position)
            if _is_jumpjet and _land_on_arrival and _vertical_state != VerticalState.GROUND:
                _vertical_state = VerticalState.DESCENDING
            _has_sub_slot = false
            _hybrid_active = false
            _ramp_speed = 0.0
            _state = State.IDLE
            _idle_snapped = false
            # ponytail: no _claim_sub_slot() here — sub-slot is determined at
            # movement start in set_target_position(). Snapping on arrival is
            # visually broken.
            SpatialHash.instance.release_cell(
                CellUtil.world_to_cell(_parent.global_position), _surface_level
            )
            CellReservation.instance.release_all(_parent)
            if debug_show_path:
                DebugVisualizer.clear_path(get_path())
            arrived.emit(_parent.global_position)
            # A subscriber may have detached or freed the mover (boarding a
            # transport detaches the passenger mid-callback); the cell-tracking
            # tail below must not read the parent once it left the tree.
            if not _parent.is_inside_tree():
                return
        else:
            _parent.global_position += Vector3(approach_step.x, 0.0, approach_step.z)
            _snap_to_terrain(delta)
    else:
        # A parameter/position mismatch (repulsion, tangent-vs-curve, lerp lag)
        # can leave the unit closer to the final waypoint than _spline_t implies;
        # a full step here would overshoot it — visible as a 1-frame offshoot
        # followed by the approach branch snapping back on the next tick.
        if seg + 1 >= _num_segments():
            var to_final := final_pos - _parent.global_position
            to_final.y = 0.0
            var remaining := to_final.length()
            if remaining > 0.001 and remaining <= step.length():
                step = to_final.normalized() * remaining
                _spline_t = float(_num_segments())
        _parent.global_position += step
        # Organic paths (infantry) steer straight toward each waypoint; the
        # Catmull-Rom spline-position lerp is what dragged them into arcs at
        # corners. Only spline-steered (non-organic) movers lerp toward the curve.
        if not _organic_path:
            var spline_pos := _get_spline_pos(_spline_t)
            var lerped := _parent.global_position.lerp(spline_pos, 0.2)
            _parent.global_position = Vector3(lerped.x, _parent.global_position.y, lerped.z)
        _snap_to_terrain(delta)

    var new_cell := CellUtil.world_to_cell(_parent.global_position)
    var old_cell := CellUtil.world_to_cell(_last_position)
    if new_cell != old_cell:
        _damage_ice(new_cell)
        if _crusher:
            _try_crush(new_cell)
    _last_position = _parent.global_position


func _handle_wait(delta: float) -> void:
    _wait_time += delta
    if _is_jumpjet:
        _update_vertical(delta)

    # Fire the mid-wait scatter once, on the tick that crosses the threshold.
    if _wait_time >= WAIT_SCATTER_SECONDS and _wait_time - delta < WAIT_SCATTER_SECONDS:
        _scatter_blockers()

    if _wait_time > _wait_threshold:
        _wait_time = 0.0
        _scatter_blockers()
        var target_cell := CellUtil.world_to_cell(_waypoints[_waypoints.size() - 1])
        var free_cell := _find_nearest_free_idle_cell(target_cell)
        # Keep the move's zone intent: an attack hold stays airborne, a landing
        # move still lands.
        set_target_position(
            CellUtil.cell_to_world(free_cell), false, _is_jumpjet and not _land_on_arrival, true
        )
        return

    var final_cell := CellUtil.world_to_cell(_waypoints[_waypoints.size() - 1])
    if _exact_target or not _is_cell_occupied_by_idle(final_cell):
        var cell_center := CellUtil.cell_to_world(final_cell)
        var wait_target := _sub_slot_position if _has_sub_slot else cell_center
        if _is_jumpjet:
            _parent.global_position.x = lerpf(_parent.global_position.x, wait_target.x, 0.3)
            _parent.global_position.z = lerpf(_parent.global_position.z, wait_target.z, 0.3)
        else:
            _parent.global_position = _parent.global_position.lerp(wait_target, 0.3)
        var wait_arrival_dist: float = (
            (
                Vector2(
                    _parent.global_position.x - wait_target.x,
                    _parent.global_position.z - wait_target.z,
                )
                . length()
            )
            if _is_jumpjet
            else _parent.global_position.distance_to(wait_target)
        )
        if wait_arrival_dist < 0.05:
            if not _is_jumpjet:
                _parent.global_position = wait_target
            if _is_jumpjet and _land_on_arrival and _vertical_state != VerticalState.GROUND:
                _vertical_state = VerticalState.DESCENDING
            _has_sub_slot = false
            _hybrid_active = false
            _ramp_speed = 0.0
            _state = State.IDLE
            _idle_snapped = false
            # ponytail: no _claim_sub_slot() here — sub-slot is determined at
            # movement start in set_target_position(). Snapping on arrival is
            # visually broken.
            SpatialHash.instance.release_cell(final_cell, _surface_level)
            CellReservation.instance.release_all(_parent)
            if debug_show_path:
                DebugVisualizer.clear_path(get_path())
            arrived.emit(_parent.global_position)
        return


func squaref(v: float) -> float:
    return v * v


func _try_crush(cell: Vector2i) -> void:
    var enemies: Array = SpatialHash.instance.get_crushable_enemies_on_cell(cell, _player_id)
    for enemy in enemies:
        if not is_instance_valid(enemy):
            continue
        var hc := (enemy as Node3D).get_node_or_null("HealthComponent") as HealthComponent
        if hc:
            hc.kill(get_parent() as Node3D)


## One-time weight-based damage to breakable surfaces (ice) on cell entry.
## Units below the cracking threshold deal none, and floating units (hover,
## jumpjet flight) do not touch the surface. Damage is per entry, not per tick.
## Only active when the game enables the breakable-ice mechanic.
func _damage_ice(cell: Vector2i) -> void:
    if (
        not _breakable_ice_enabled()
        or _is_floating()
        or _weight < _ice_cracking_weight
        or SpatialHash.instance == null
    ):
        return
    for ice in SpatialHash.instance.get_ice_entities_on_cell(cell):
        if not is_instance_valid(ice):
            continue
        var hc := (ice as Node3D).get_node_or_null("HealthComponent") as HealthComponent
        if hc:
            hc.take_damage(roundi(_weight))


## True when the active game enables breakable-ice.
func _breakable_ice_enabled() -> bool:
    return GameContext.has_feature("breakable_ice")


func _apply_facing(direction: Vector3) -> void:
    if not is_instance_valid(_rotation_target):
        return
    var forward := Vector3(direction.x, 0.0, direction.z).normalized()
    if forward.length_squared() < 0.001:
        return
    var normal := (
        Vector3.UP if _stand_upright else _memoized_normal(_parent.global_position).normalized()
    )
    var projected := (forward - forward.dot(normal) * normal).normalized()
    if projected.length_squared() < 0.001:
        return
    var right := projected.cross(normal).normalized()
    var rot_basis := Basis()
    rot_basis.x = right
    rot_basis.y = normal
    rot_basis.z = -projected
    _rotation_target.global_transform.basis = rot_basis


## Books a sub-slot for the destination cell. `level` defaults to the mover's
## current surface; callers booking a deck destination pass the resolved
## `end_level` so the claim and the booked world Y land on the target surface.
func _assign_sub_slot_at_cell(cell: Vector2i, level: int = -1) -> void:
    var assign_level: int = _surface_level if level < 0 else level
    _has_sub_slot = false
    var slot: int = CellReservation.instance.reserve_sub_slot(
        cell, _parent, _assigned_slot, assign_level
    )
    if slot < 0:
        return
    _assigned_slot = slot
    _sub_slot_position = CellSubPositions.get_sub_position(cell, slot, -1, assign_level)
    _has_sub_slot = true


func _spline_segment() -> int:
    return clampi(floori(_spline_t), 0, maxi(0, _num_segments() - 1))


## Resolves the surface level the unit currently stands on from its cell and the
## path's per-waypoint levels. The level of either end of the current segment is
## used only while the unit's cell actually carries a deck at that level, so a
## unit on a deck stays at deck height until it physically leaves the deck cell
## and a unit under a deck never samples the deck above it.
func _update_surface_level() -> void:
    if _waypoint_levels.is_empty():
        _surface_level = _resolve_idle_surface_level()
        return
    var cell := CellUtil.world_to_cell(_parent.global_position)
    var seg := _spline_segment()
    var start_level: int = _waypoint_levels[clampi(seg, 0, _waypoint_levels.size() - 1)]
    var end_level: int = _waypoint_levels[clampi(seg + 1, 0, _waypoint_levels.size() - 1)]
    if start_level > 0 and _cell_has_surface(cell, start_level):
        _surface_level = start_level
    elif end_level > 0 and _cell_has_surface(cell, end_level):
        _surface_level = end_level
    else:
        _surface_level = 0


func _cell_has_surface(cell: Vector2i, level: int) -> bool:
    if SpatialHash.instance == null:
        return true
    return SpatialHash.instance.has_bridge_on_cell(cell, level)


## Precomputes per-segment Catmull-Rom control points and 3D lengths from
## `_waypoints` at path-build time. Called from `set_target_position`; guarded by
## `_path_generation` so any `_waypoints` rebuild invalidates stale baked data.
func _bake_spline() -> void:
    _path_generation += 1
    _baked_generation = _path_generation
    _baked_controls = []
    _baked_seg_len = PackedFloat32Array()
    var n := _waypoints.size()
    if n < 2:
        return
    _baked_seg_len.resize(n - 1)
    for i in range(n - 1):
        var p0 := _waypoints[maxi(0, i - 1)]
        var p1 := _waypoints[i]
        var p2 := _waypoints[mini(n - 1, i + 1)]
        var p3 := _waypoints[mini(n - 1, i + 2)]
        _baked_controls.append([p0, p1, p2, p3])
        _baked_seg_len[i] = p1.distance_to(p2)


## Segment length read, precomputed at bake time. Falls back to a live distance
## when the baked data is stale (path rebuilt without baking).
func _segment_length(seg: int) -> float:
    if _baked_generation == _path_generation and seg >= 0 and seg < _baked_seg_len.size():
        return _baked_seg_len[seg]
    return _waypoints[seg].distance_to(_waypoints[seg + 1])


func _get_spline_pos(t: float) -> Vector3:
    var n := _waypoints.size()
    var seg := clampi(floori(t), 0, maxi(0, n - 2))
    var local_t := clampf(t - float(seg), 0.0, 1.0)
    if _baked_generation == _path_generation and seg < _baked_controls.size():
        var c: Array = _baked_controls[seg]
        return SplineUtil._catmull_rom(c[0], c[1], c[2], c[3], local_t)
    return SplineUtil.evaluate(_waypoints, t)


func _get_spline_tangent(t: float) -> Vector3:
    var n := _waypoints.size()
    var seg := clampi(floori(t), 0, maxi(0, n - 2))
    var local_t := clampf(t - float(seg), 0.0, 1.0)
    if _baked_generation == _path_generation and seg < _baked_controls.size():
        var c: Array = _baked_controls[seg]
        return SplineUtil._catmull_rom_tangent(c[0], c[1], c[2], c[3], local_t)
    return SplineUtil.tangent(_waypoints, t)


func _build_blocked_cells(unblock_buildings: bool = false) -> Dictionary:
    var result: Dictionary = SpatialHash.instance.get_blocked_cells(_surface_level).duplicate()
    var cell := CellUtil.world_to_cell(_parent.global_position)
    result.erase(CellUtil.cell_level_key(cell, _surface_level))
    if not _shares_cell and _crusher:
        result.merge(SpatialHash.instance.get_crusher_blocking_cells(_player_id))
    elif not _shares_cell:
        result.merge(SpatialHash.instance.get_shared_cells(_surface_level))
    if unblock_buildings:
        for key in SpatialHash.instance.get_building_cells():
            result.erase(key)
    else:
        var building_cells := SpatialHash.instance.get_building_cells()
        for key in SpatialHash.instance.get_reserved():
            if not building_cells.has(key):
                result.erase(key)
    return result


func _is_cell_occupied_by_idle(cell: Vector2i) -> bool:
    if SpatialHash.instance.is_cell_blocked(cell, _surface_level):
        return true
    var key: int = CellUtil.cell_key(cell)
    if SpatialHash.instance.get_building_cells().has(key):
        return true
    if SpatialHash.instance._grid.has(key):
        for entry in SpatialHash.instance._grid[key]:
            if entry.node != _parent:
                if int(entry.get("level", 0)) != _surface_level:
                    continue
                var entry_mc := entry.mc as MovementController
                if not entry_mc:
                    continue
                if _shares_cell and entry_mc.shares_cell():
                    continue
                return true
    return false


## Nearest passable cell to `cell`: the cell itself when passable, otherwise a
## spiral search for the closest free cell. Considers blocked cells, building
## footprints, and present units. Public for chasing destinations
## (CombatComponent) that must never aim into a blocked or building cell. Falls
## back to the unit's own cell (always passable) when the radius is exhausted,
## so it never returns a blocked destination.
func find_nearest_free_cell(cell: Vector2i) -> Vector2i:
    if _is_destination_clear(cell):
        return cell
    var free := CellUtil.spiral_first_free(
        cell, 4, func(c: Vector2i) -> bool: return not _is_destination_clear(c)
    )
    if _is_destination_clear(free):
        return free
    return CellUtil.world_to_cell(_parent.global_position)


func _is_destination_clear(cell: Vector2i) -> bool:
    var key: int = CellUtil.cell_key(cell)
    if SpatialHash.instance.get_blocked_cells(_surface_level).has(
        CellUtil.cell_level_key(cell, _surface_level)
    ):
        return false
    if SpatialHash.instance._grid.has(key):
        for entry in SpatialHash.instance._grid[key]:
            if entry.node != _parent:
                if int(entry.get("level", 0)) != _surface_level:
                    continue
                var entry_mc := entry.mc as MovementController
                if _shares_cell and entry_mc and entry_mc.shares_cell():
                    continue
                return false
    return true


func _find_nearest_free_idle_cell(cell: Vector2i, bounded: bool = false) -> Vector2i:
    return _spiral_bounded(cell, bounded, _is_cell_occupied_by_idle)


func _find_nearest_free_sub_slot_cell(cell: Vector2i, bounded: bool = false) -> Vector2i:
    return _spiral_bounded(cell, bounded, _is_cell_unavailable_for_sub_slot)


## Spiral relocation that respects the player-order area when `bounded` is set:
## cells outside the order diamond (the visible outline inset by
## `BoundsSystem.ORDER_EDGE_INSET`, see `BoundsSystem.is_in_order_area`) count
## as occupied so an occupied-cell sidestep can't push the destination past the
## margin. AI/auto controllers leave `bounded` false and keep unbounded
## behavior.
func _spiral_bounded(cell: Vector2i, bounded: bool, is_occupied: Callable) -> Vector2i:
    if not bounded:
        return CellUtil.spiral_first_free(cell, 4, is_occupied)
    return CellUtil.spiral_first_free(
        cell,
        4,
        func(c: Vector2i) -> bool:
            if not BoundsSystem.is_in_order_area(c):
                return true
            return is_occupied.call(c)
    )


func _is_cell_unavailable_for_sub_slot(cell: Vector2i) -> bool:
    if SpatialHash.instance.is_cell_blocked(cell, _surface_level):
        return true
    var key := CellUtil.cell_key(cell)
    if SpatialHash.instance.get_building_cells().has(key):
        return true
    if SpatialHash.instance.is_bib_cell(cell):
        return true
    return CellReservation.instance.is_cell_full(cell, _surface_level)


func _scatter_blockers() -> void:
    var cell := CellUtil.world_to_cell(_parent.global_position)
    # ponytail: scatter only when truly boxed in — a free adjacent cell means
    # the mover can sidestep on its own; firing on any wait/path-fail shoved
    # idle vehicles around whenever infantry merely moved nearby.
    var boxed_in := true
    for dx in range(-1, 2):
        for dz in range(-1, 2):
            if dx == 0 and dz == 0:
                continue
            if not SpatialHash.instance.is_cell_blocked(cell + Vector2i(dx, dz), _surface_level):
                boxed_in = false
                break
        if not boxed_in:
            break
    if not boxed_in:
        return
    var blocked := SpatialHash.instance.get_blocked_cells(_surface_level)
    for radius in range(1, 4):
        for dx in range(-radius, radius + 1):
            for dz in range(-radius, radius + 1):
                if abs(dx) != radius and abs(dz) != radius:
                    continue
                var ncell := cell + Vector2i(dx, dz)
                var nkey := CellUtil.cell_level_key(ncell, _surface_level)
                if not blocked.has(nkey):
                    continue
                if _scattered_this_frame.has(nkey):
                    continue
                var push_dir := Vector2i(sign(dx), sign(dz))
                var push_cell := ncell + push_dir
                if SpatialHash.instance.is_cell_blocked(push_cell, _surface_level):
                    continue
                var scatter_targets: Array[MovementController] = []
                for entry in SpatialHash.instance.get_entries(ncell, _surface_level):
                    var mc := entry.mc as MovementController
                    if mc and mc != self and mc._state == State.IDLE and not _is_enemy_unit(mc):
                        scatter_targets.append(mc)
                if scatter_targets.is_empty():
                    continue
                if not SpatialHash.instance.reserve_cell(push_cell, _surface_level):
                    continue
                _scattered_this_frame[nkey] = true
                SpatialHash.instance.force_reserve(ncell, _surface_level)
                for target in scatter_targets:
                    (
                        target
                        . set_target_position(
                            CellUtil.cell_to_world(push_cell),
                            false,
                            target.is_airborne_jumpjet(),
                            true,
                            null,
                            null,
                            false,
                            false,
                            _surface_level,
                        )
                    )


func nudge_from_cell(blocking_cell: Vector2i) -> bool:
    var entries := SpatialHash.instance.get_entries(blocking_cell)
    for entry in entries:
        var mc := entry.mc as MovementController
        if mc and mc._state == State.IDLE:
            if _is_enemy_unit(mc):
                continue
            var free := _find_nearest_free_idle_cell(blocking_cell)
            mc.set_target_position(
                CellUtil.cell_to_world(free), false, mc.is_airborne_jumpjet(), true
            )
            return true
    return false


## True when `other` is owned by an enemy player. Units without a resolvable
## owner on either side (missing StatsComponent or unset player_id) cannot be
## classified and are treated as non-hostile, matching the deploy scatter
## precedent (#164: opponents must never move each other's units).
func _is_enemy_unit(other: MovementController) -> bool:
    if other == null or other._parent == null:
        return false
    var own_stats := _parent.get_node_or_null("StatsComponent") as StatsComponent
    var other_stats := other._parent.get_node_or_null("StatsComponent") as StatsComponent
    if own_stats == null or other_stats == null:
        return false
    if own_stats.player_id < 0 or other_stats.player_id < 0:
        return false
    return PlayerManager.is_enemy(own_stats.player_id, other_stats.player_id)


## Resolves the surface level the unit stands on while idle from its own Y: the
## level whose walkable height is nearest the unit's current Y within a small
## tolerance (well under half a height step), tie-breaking to the lower level.
## Returns 0 when no surface matches. Floating/air units own their Y, so they are
## left on their current level.
func _resolve_idle_surface_level() -> int:
    if _is_floating():
        return _surface_level
    var pos_y: float = _parent.global_position.y
    var cell := CellUtil.world_to_cell(_parent.global_position)
    var tolerance: float = 0.25 * TerrainSystem.HEIGHT_STEP
    var best_level: int = 0
    var best_delta: float = INF
    for level in TerrainSystem.get_cell_surface_levels(cell):
        var delta: float = absf(TerrainSystem.get_cell_surface_height(cell, level) - pos_y)
        if delta > tolerance:
            continue
        # Levels iterate ascending, so a strictly-smaller test keeps the lower
        # level on a tie.
        if delta < best_delta:
            best_delta = delta
            best_level = level
    return best_level


func _snap_if_idle_cell_changed() -> void:
    var cell := CellUtil.world_to_cell(_parent.global_position)
    if _idle_snapped and cell == _idle_snap_cell:
        return
    _surface_level = _resolve_idle_surface_level()
    var idle_y := _memoized_smooth_height(_parent.global_position)
    _parent.global_position.y = idle_y + (_hover_height if _is_floating() else 0.0)
    _idle_snap_cell = cell
    _idle_snapped = true


func _snap_to_terrain(delta: float = 0.0) -> void:
    if _is_jumpjet:
        _update_vertical(delta)
        return
    var terrain_y := _memoized_smooth_height(_parent.global_position)
    var target_y := terrain_y + (_hover_height if _is_floating() else 0.0)
    _parent.global_position.y = lerpf(_parent.global_position.y, target_y, 0.95)


func _update_vertical(delta: float) -> void:
    if not _is_jumpjet:
        return
    var deck := _bridge_deck_height(_parent.global_position)
    var terrain_y := (
        deck
        if not is_nan(deck)
        else TerrainSystem.get_height_at_world_smooth(_parent.global_position)
    )
    match _vertical_state:
        VerticalState.GROUND:
            _parent.global_position.y = terrain_y
        VerticalState.AIR:
            _parent.global_position.y = terrain_y + _jumpjet_air_height
        VerticalState.ASCENDING:
            var target_air_y := terrain_y + _jumpjet_air_height
            _parent.global_position.y += move_speed * _vertical_split_factor() * delta
            if _parent.global_position.y >= target_air_y:
                _parent.global_position.y = target_air_y
                _vertical_state = VerticalState.AIR
        VerticalState.DESCENDING:
            _parent.global_position.y -= move_speed * _vertical_split_factor() * delta
            if _parent.global_position.y <= terrain_y:
                _parent.global_position.y = terrain_y
                _vertical_state = VerticalState.GROUND
                _land_on_arrival = false


func _apply_zone_desire(desired: VerticalState) -> void:
    if not _is_jumpjet:
        return
    if desired == _vertical_state:
        return
    match _vertical_state:
        VerticalState.GROUND:
            if desired == VerticalState.AIR:
                _vertical_state = VerticalState.ASCENDING
        VerticalState.AIR:
            if desired == VerticalState.GROUND:
                _vertical_state = VerticalState.DESCENDING
        VerticalState.ASCENDING:
            _vertical_state = (
                VerticalState.DESCENDING
                if desired == VerticalState.GROUND
                else VerticalState.ASCENDING
            )
        VerticalState.DESCENDING:
            _vertical_state = (
                VerticalState.ASCENDING
                if desired == VerticalState.AIR
                else VerticalState.DESCENDING
            )


func get_cursor_for_target(_target: Node3D, _target_cell: Vector2i) -> CursorState.Type:
    return CursorState.Type.MOVE


func get_order_for_target(
    target: Node3D,
    _target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary,
) -> OrderResult:
    if target:
        return null
    var queued: bool = modifiers.get(OrderResult.MOD_QUEUED, false)
    return OrderResult.new(
        CursorState.Type.MOVE,
        5,
        null,
        target_pos,
        queued,
        func(): set_target_position(target_pos),
    )


## Returns the ramp factor (0.0 to 1.0) to apply to the step speed.
## When locomotor has neither accelerate nor decelerate, returns 1.0 (no ramping).
func _get_ramp_factor() -> float:
    if not _locomotor_data:
        return 1.0
    if not _locomotor_data.accelerate and not _locomotor_data.decelerate:
        return 1.0
    return clampf(_ramp_speed / move_speed, 0.0, 1.0)


## Update the ramp speed for the current frame based on accelerate/decelerate flags.
## This is called during MOVING state only (rotating and wait freeze the ramp).
func _update_ramp_speed(delta: float) -> void:
    # Initialize ramp rates lazily (needed because configure is called after _ready).
    # ponytail: no _ramp_speed reset here — it would clobber the decel-only cruise
    # start from set_target_position; field default and IDLE branch already zero it.
    if _ramp_accel_rate == 0.0 and _rules:
        _ramp_accel_rate = move_speed / _rules.ramp_accel_time
        _ramp_decel_rate = move_speed / _rules.ramp_decel_time

    if _locomotor_data.accelerate:
        # Accelerate toward cruise (move_speed). Factors like split/veteran/slope/terrain
        # multiply on top via the step chain, not inside the ramp target.
        _ramp_speed = move_toward(_ramp_speed, move_speed, _ramp_accel_rate * delta)

    if _locomotor_data.decelerate and not _waypoints.is_empty():
        # Decelerate: compute braking envelope from remaining distance
        var dist_remaining := _waypoints[_waypoints.size() - 1].distance_to(_parent.global_position)
        var decel_limit := sqrt(2.0 * _ramp_decel_rate * dist_remaining)
        # Only apply crawl floor while braking envelope is the limiting term.
        # This lets fresh moves start from 0, while still preventing Zeno creep near arrival.
        if decel_limit < move_speed:
            _ramp_speed = minf(_ramp_speed, decel_limit)
            if _rules:
                var crawl_floor: float = move_speed * _rules.ramp_crawl_fraction
                _ramp_speed = maxf(_ramp_speed, crawl_floor)
