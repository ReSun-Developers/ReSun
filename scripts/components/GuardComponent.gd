class_name GuardComponent extends Node

## Mode A stand-and-shoot acquisition (#261): while the owning unit is idle,
## periodically scan SpatialHash for the nearest hostile already inside weapon
## range and hand it to CombatComponent with hold_ground so the unit fires
## without chasing. Mode B (sight + leash) is #444/#445.

## Seconds between hood scans.
const SCAN_INTERVAL: float = 0.3

## Extra hood cells beyond the weapon-range radius. SpatialHash indexes each
## entity at its centre cell, so a building whose centre sits outside weapon
## range but whose nearest footprint edge is inside it would be missed. The
## largest foundation in content is 6x6 (half-extent 3 cells); the margin is 4,
## not 3, to absorb cell rounding (an axis-aligned centre at range + 6 can land
## in a cell one index further out), after which the nearest footprint point is
## measured. Bump if content grows wider than 6 cells.
const BUILDING_HOOD_MARGIN_CELLS: int = 4

var _parent: Node3D = null
var _combat: CombatComponent = null
var _mc: MovementController = null
var _power: PowerComponent = null
var _stats: StatsComponent = null
var _resolved: bool = false
var _scan_timer: float = 0.0
## Incremented each hood walk; tests assert throttle without peeking SpatialHash.
var scan_count: int = 0


func _ready() -> void:
    if Engine.is_editor_hint():
        set_physics_process(false)
        return
    _parent = get_parent() as Node3D
    var ancestor: Node = _parent
    while ancestor:
        if ancestor.has_meta("is_map_editor"):
            set_physics_process(false)
            return
        ancestor = ancestor.get_parent()
    # Phase-offset so same-frame spawns do not scan on the same tick.
    _scan_timer = float(absi(hash(get_instance_id())) % 1000) / 1000.0 * SCAN_INTERVAL


func _physics_process(delta: float) -> void:
    if Engine.is_editor_hint():
        return
    # Detached entities (previews) never scan; checked per tick so a preview
    # finalized into a real entity resumes without re-initialization.
    if _parent and _parent.get_meta("detached", false):
        return
    if not _resolve_siblings():
        return
    if _is_blocked():
        return
    _scan_timer -= delta
    if _scan_timer > 0.0:
        return
    _scan_timer = SCAN_INTERVAL
    scan_count += 1
    var target := _find_nearest_enemy()
    if target:
        _combat.set_target(target, true)


## Resolves sibling components once, lazily (components attach before tree entry).
func _resolve_siblings() -> bool:
    if _resolved:
        return _combat != null
    if _parent == null:
        _parent = get_parent() as Node3D
        if _parent == null:
            return false
    _combat = _parent.get_node_or_null("CombatComponent") as CombatComponent
    _mc = _parent.get_node_or_null("MovementController") as MovementController
    _power = _parent.get_node_or_null("PowerComponent") as PowerComponent
    _stats = _parent.get_node_or_null("StatsComponent") as StatsComponent
    _resolved = true
    return _combat != null


func _is_blocked() -> bool:
    if not is_instance_valid(_parent):
        return true
    # Engagement, not entity target: a force-fire ground engagement keeps
    # get_target() null but must still stop the scan from stealing it.
    if _combat and _combat.is_engaged():
        return true
    if _mc and _mc.is_moving():
        return true
    if _power and not _power.is_online:
        return true
    return false


## Visibility of `cell` to the owning player, mirroring
## ShroudSystem.is_cell_visible_to_local but for an arbitrary house — a
## computer-owned unit must be judged by its own shroud, never the local
## player's. Cells outside the playable diamond are not tracked by the shroud
## grid at all (ShroudSystem._revealable), so there is nothing to be blind
## about and they count as visible. Ungated while no grid exists so scenes
## without one still engage.
func _is_visible_to_owner(cell: Vector2i, own_id: int) -> bool:
    if not ShroudSystem.is_grid_ready():
        return true
    if not BoundsSystem.is_in_play_area(cell):
        return true
    if ShroudSystem.is_visible(own_id, cell):
        return true
    if not ShroudSystem.is_explored(own_id, cell):
        return not ShroudSystem.is_shroud_enabled()
    return not ShroudSystem.is_fog_enabled()


## Longest weapon range in world units; 0 when no weapons (never acquires).
func _acquisition_range_world() -> float:
    if _combat == null:
        return 0.0
    var best: float = 0.0
    for weapon in _combat.weapons:
        if weapon and weapon.attack_range > best:
            best = weapon.attack_range
    return best * CellUtil.CELL_SIZE


## Nearest hostile within weapon range (horizontal), or null.
func _find_nearest_enemy() -> Node3D:
    if SpatialHash.instance == null or _stats == null:
        return null
    var range_world := _acquisition_range_world()
    if range_world <= 0.0:
        return null
    var own_id := _stats.player_id
    if own_id < 0:
        return null
    var origin := _parent.global_position
    var r_cells := maxi(1, ceili(range_world / CellUtil.CELL_SIZE)) + BUILDING_HOOD_MARGIN_CELLS
    var center := CellUtil.world_to_cell(origin)
    var range_sq := range_world * range_world
    var nearest: Node3D = null
    var nearest_dist := range_sq
    # Square cell hood (matches Exit/Factory/Transport): a cell-index circle
    # misses in-range entities in diagonal corner cells; the world dist_sq
    # check below is the exact filter.
    for dx in range(-r_cells, r_cells + 1):
        for dz in range(-r_cells, r_cells + 1):
            for entry in SpatialHash.instance.get_entries(center + Vector2i(dx, dz)):
                var other := entry.node as Node3D
                if not is_instance_valid(other) or other == _parent:
                    continue
                var other_stats := entry.stats as StatsComponent
                if other_stats == null or other_stats.player_id < 0:
                    continue
                if not PlayerManager.is_enemy(own_id, other_stats.player_id):
                    continue
                if other.get_node_or_null("HealthComponent") == null:
                    continue
                # Buildings are in range when their nearest footprint point is,
                # matching CombatComponent range checking. Visibility is judged
                # at that same point, so a structure whose in-range corner is
                # visible is still acquired when its centre sits in shroud.
                var other_pos := other.global_position
                if other_stats.is_structure():
                    var fc := other.get_node_or_null("FoundationComponent") as FoundationComponent
                    if fc:
                        other_pos = fc.nearest_world_point(origin)
                # Acquisition is the only visibility test: a candidate the
                # owning player cannot see is not a candidate. Once acquired,
                # the engagement is kept even if the target later leaves sight.
                if not _is_visible_to_owner(CellUtil.world_to_cell(other_pos), own_id):
                    continue
                var to_other := other_pos - origin
                var dist_sq := Vector3(to_other.x, 0.0, to_other.z).length_squared()
                if dist_sq <= range_sq and dist_sq < nearest_dist:
                    nearest_dist = dist_sq
                    nearest = other
    return nearest
