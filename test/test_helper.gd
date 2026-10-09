class_name TestHelper
# Minimal test assertions — no framework, no crashes on failure.
# Tests report through TestHelper only; the runner owns all output.
# Assertions are silent on success; failures accumulate in _errors.

static var _passed := 0
static var _failed := 0
static var _errors: Array[String] = []


static func assert_eq(got, expected, msg: String = "") -> void:
    if got == expected:
        _passed += 1
    else:
        _failed += 1
        var err := "expected %s, got %s" % [expected, got]
        if msg != "":
            err = msg + " — " + err
        _errors.append(err)


static func assert_true(value: bool, msg: String = "") -> void:
    if value:
        _passed += 1
    else:
        _failed += 1
        var err := "expected true" if msg == "" else msg
        _errors.append(err)


static func fail(msg: String) -> void:
    _failed += 1
    _errors.append(msg)


## The cursor an order targeter would show for `target`: the targeter's order
## cursor, or DEFAULT when it produces no order. Replaces the removed
## component-level `get_cursor_for_target()`.
static func order_cursor(component: Node, target: Node3D) -> CursorState.Type:
    var order: OrderResult = component.get_order_for_target(target, Vector2i.ZERO, Vector3.ZERO, {})
    return order.cursor if order else CursorState.Type.DEFAULT


static func reset() -> void:
    _passed = 0
    _failed = 0
    _errors.clear()


## Snapshots GameContext selection state for tests that switch games.
static func snapshot_game_context(gc: Object) -> Dictionary:
    return {"defs": gc._defs.duplicate(), "current": gc._current}


## Restores the snapshot and re-selects the default game so consumers
## re-register real content.
static func restore_game_context(gc: Object, snap: Dictionary) -> void:
    gc._defs = snap["defs"]
    gc._current = snap["current"]
    gc.select_game("ts")


## Snapshots FactionCatalog registration state for tests that load fixture
## faction roots directly.
static func snapshot_faction_catalog(fc: Object) -> Dictionary:
    return {"data_sets": fc._data_sets.duplicate(), "factions": fc._factions.duplicate()}


## Restores the snapshot and re-projects the house roster from it.
static func restore_faction_catalog(fc: Object, snap: Dictionary) -> void:
    fc._data_sets = snap["data_sets"]
    fc._factions = snap["factions"]
    Houses.apply_roster(fc.get_ordered())
