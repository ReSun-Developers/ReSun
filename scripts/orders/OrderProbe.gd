class_name OrderProbe
extends RefCounted

## The typed input to order intake: the quadruple fed to `OrderSystem.resolve()`.
## Built through factories so target-level and modifier policy cannot drift
## between call sites (hover cursor, world click, minimap) — the input-side
## counterpart of `OrderResolution`.

var target: Node3D = null
var target_cell: Vector2i = Vector2i.ZERO
var target_pos: Vector3 = Vector3.ZERO
var modifiers: Dictionary = {}


## Entity-targeted intake (hover cursor, world click on a unit/building/interact).
## Cell and position derive from the entity; `MOD_TARGET_LEVEL` is never set —
## entity orders do not target a surface level.
static func from_entity(p_target: Node3D, shift_pressed: bool) -> OrderProbe:
    var probe := OrderProbe.new()
    probe.target = p_target
    if p_target != null:
        probe.target_cell = CellUtil.world_to_cell(p_target.global_position)
        probe.target_pos = p_target.global_position
    probe.modifiers = OrderSystem.build_modifiers(shift_pressed)
    return probe


## Ground-targeted intake (world-click move, hover ground fallback). Always sets
## `MOD_TARGET_LEVEL` — level 0 for ground, N for a bridge deck pick — so the
## key is present exactly when a surface pick exists.
static func from_ground(ground_pos: Vector3, level: int, shift_pressed: bool) -> OrderProbe:
    var probe := OrderProbe.new()
    probe.target = null
    probe.target_cell = Vector2i.ZERO
    probe.target_pos = ground_pos
    probe.modifiers = OrderSystem.build_modifiers(shift_pressed)
    probe.modifiers[OrderResult.MOD_TARGET_LEVEL] = level
    return probe


## Minimap-cell intake: caller supplies the cell's target entity, order world
## point and top surface level; the level is always carried on the modifiers.
static func from_cell(
    cell: Vector2i,
    p_target: Node3D,
    world_pos: Vector3,
    level: int,
    shift_pressed: bool,
) -> OrderProbe:
    var probe := OrderProbe.new()
    probe.target = p_target
    probe.target_cell = cell
    probe.target_pos = world_pos
    probe.modifiers = OrderSystem.build_modifiers(shift_pressed)
    probe.modifiers[OrderResult.MOD_TARGET_LEVEL] = level
    return probe
