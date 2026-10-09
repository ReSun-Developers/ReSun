class_name OrderGenerator

## Base class for order generators. A generator performs one `resolve()` per
## player input, returning both the cursor and the orders so they cannot drift.
## `get_cursor()` and `get_orders()` are projections of `resolve()`; subclasses
## override `resolve()` only.


func resolve(
    _target: Node3D,
    _target_cell: Vector2i,
    _target_pos: Vector3,
    _modifiers: Dictionary,
) -> OrderResolution:
    return OrderResolution.new()


func get_cursor(
    target: Node3D,
    target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary,
) -> CursorState.Type:
    return resolve(target, target_cell, target_pos, modifiers).cursor


func get_orders(
    target: Node3D,
    target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary,
) -> Array[OrderResult]:
    return resolve(target, target_cell, target_pos, modifiers).orders


func cancel() -> void:
    pass
