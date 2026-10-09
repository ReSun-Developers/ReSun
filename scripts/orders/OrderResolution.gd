class_name OrderResolution

## The single result of player order intake: the cursor to display and the
## per-entity orders to execute, decided together so they cannot drift.
## `OrderSystem.get_cursor()` and `get_orders()` are projections of this.

var cursor: CursorState.Type = CursorState.Type.DEFAULT
var orders: Array[OrderResult] = []


func _init(
    p_cursor: CursorState.Type = CursorState.Type.DEFAULT,
    p_orders: Array[OrderResult] = [],
) -> void:
    cursor = p_cursor
    orders = p_orders
