class_name PowerBar extends Control

## Twin power bar for the sidebar's left edge: a black column backed by a
## green fill (power output) with a red fill (drain) drawn in front — on
## deficit the red bar rises above the green. Fills follow the active rules'
## power-bar curve and ease toward their targets so grid changes animate
## instead of jumping.

## Fallback full-bar scale when no rules are active.
const DEFAULT_MAX_POWER := 2000.0
## Fallback fill curve exponent when no rules are active.
const DEFAULT_CURVE_EXPONENT := 0.4
## Exponential ease rate (per second) for the fill animation.
const ANIM_SPEED := 8.0
## Distance at which an animating fill snaps to its target — below this the
## lerp asymptote would otherwise stall redraws forever.
const SNAP_DISTANCE_SQ := 0.000001

const COLOR_BACKGROUND := Color(0.0, 0.0, 0.0, 0.75)
const COLOR_OUTPUT := Color(0.0, 0.75, 0.0)
const COLOR_DRAIN := Color(0.75, 0.0, 0.0)

## Fill fractions currently displayed — eased toward the live grid targets.
var _displayed := Vector2.ZERO


func _process(delta: float) -> void:
    var pid := PlayerManager.get_local_player_id()
    var rules := GlobalRules.get_current()
    var max_power: float = rules.power_bar_max_output if rules else DEFAULT_MAX_POWER
    var exponent: float = rules.power_bar_curve_exponent if rules else DEFAULT_CURVE_EXPONENT
    var target := _ratios(PowerGrid.get_output(pid), PowerGrid.get_drain(pid), max_power, exponent)
    if _displayed.is_equal_approx(target):
        return
    _displayed = _advance(_displayed, target, delta)
    queue_redraw()


func _draw() -> void:
    var height := size.y
    var width := size.x
    draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND)
    draw_rect(
        Rect2(Vector2(0, height * (1.0 - _displayed.x)), Vector2(width, height * _displayed.x)),
        COLOR_OUTPUT
    )
    draw_rect(
        Rect2(Vector2(0, height * (1.0 - _displayed.y)), Vector2(width, height * _displayed.y)),
        COLOR_DRAIN
    )


## Bottom-up fill fractions for output and drain, clamped to the bar height.
static func _ratios(
    output: int,
    drain: int,
    max_power: float = DEFAULT_MAX_POWER,
    exponent: float = DEFAULT_CURVE_EXPONENT
) -> Vector2:
    return Vector2(_curve(output, max_power, exponent), _curve(drain, max_power, exponent))


## Milder-than-linear fill curve; clamped before pow so negative/oversized
## values stay well-defined (pow of a negative base is NaN).
static func _curve(
    value: int, max_power: float = DEFAULT_MAX_POWER, exponent: float = DEFAULT_CURVE_EXPONENT
) -> float:
    return pow(clampf(float(value) / maxf(max_power, 0.001), 0.0, 1.0), exponent)


## Frame-rate independent exponential ease toward the target, snapping on
## arrival.
static func _advance(current: Vector2, target: Vector2, delta: float) -> Vector2:
    var eased := current.lerp(target, 1.0 - exp(-ANIM_SPEED * delta))
    return target if eased.distance_squared_to(target) < SNAP_DISTANCE_SQ else eased
