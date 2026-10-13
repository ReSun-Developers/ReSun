extends Node

# OrderProbe factory policy: the drift class this module exists to kill.
# Asserts the *differences* between factories — entity omits MOD_TARGET_LEVEL,
# ground/cell always set it — plus shift propagation and tuple derivation.

var _sm: Node = null


func _make_entity(pos: Vector3) -> Node3D:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return null
    # Attach under an in-tree autoload so global_position is real: an
    # out-of-tree Node3D reports identity, making pos/cell asserts vacuous.
    var entity := Node3D.new()
    _sm.add_child(entity)
    entity.position = pos
    return entity


func test_from_entity_omits_target_level() -> void:
    var entity := _make_entity(Vector3(10, 0, 20))
    var probe := OrderProbe.from_entity(entity, false)
    (
        TestHelper
        . assert_true(
            not probe.modifiers.has(OrderResult.MOD_TARGET_LEVEL),
            "from_entity must not set MOD_TARGET_LEVEL",
        )
    )
    TestHelper.assert_eq(probe.target, entity, "from_entity keeps the target")
    TestHelper.assert_eq(probe.target_pos, entity.global_position, "from_entity pos")
    (
        TestHelper
        . assert_eq(
            probe.target_cell,
            CellUtil.world_to_cell(entity.global_position),
            "from_entity cell derives from entity position",
        )
    )
    entity.free()


func test_from_ground_sets_level_zero() -> void:
    var probe := OrderProbe.from_ground(Vector3(4, 0, 8), 0, false)
    (
        TestHelper
        . assert_true(
            probe.modifiers.has(OrderResult.MOD_TARGET_LEVEL),
            "from_ground must set MOD_TARGET_LEVEL even at level 0",
        )
    )
    (
        TestHelper
        . assert_eq(
            probe.modifiers[OrderResult.MOD_TARGET_LEVEL],
            0,
            "ground pick carries level 0",
        )
    )
    TestHelper.assert_eq(probe.target, null, "from_ground has no entity target")
    TestHelper.assert_eq(probe.target_cell, Vector2i.ZERO, "from_ground cell is ZERO")
    TestHelper.assert_eq(probe.target_pos, Vector3(4, 0, 8), "from_ground pos")


func test_from_ground_sets_deck_level() -> void:
    var probe := OrderProbe.from_ground(Vector3(1, 3, 2), 3, false)
    (
        TestHelper
        . assert_eq(
            probe.modifiers[OrderResult.MOD_TARGET_LEVEL],
            3,
            "deck pick carries its level",
        )
    )


func test_from_cell_sets_level_and_tuple() -> void:
    var entity := _make_entity(Vector3.ZERO)
    var probe := OrderProbe.from_cell(Vector2i(7, 9), entity, Vector3(5, 2, 5), 2, false)
    (
        TestHelper
        . assert_true(
            probe.modifiers.has(OrderResult.MOD_TARGET_LEVEL),
            "from_cell must set MOD_TARGET_LEVEL",
        )
    )
    TestHelper.assert_eq(probe.modifiers[OrderResult.MOD_TARGET_LEVEL], 2, "cell level")
    TestHelper.assert_eq(probe.target, entity, "from_cell keeps the target")
    TestHelper.assert_eq(probe.target_cell, Vector2i(7, 9), "from_cell cell")
    TestHelper.assert_eq(probe.target_pos, Vector3(5, 2, 5), "from_cell world pos")
    entity.free()


func test_shift_propagates_through_all_factories() -> void:
    var entity := _make_entity(Vector3.ZERO)
    var probes: Array[OrderProbe] = [
        OrderProbe.from_entity(entity, true),
        OrderProbe.from_ground(Vector3.ZERO, 0, true),
        OrderProbe.from_cell(Vector2i.ZERO, entity, Vector3.ZERO, 0, true),
    ]
    for i in probes.size():
        (
            TestHelper
            . assert_eq(
                probes[i].modifiers[OrderResult.MOD_QUEUED],
                true,
                "shift queued flag %d" % i,
            )
        )
    entity.free()


func test_from_entity_null_yields_empty_tuple() -> void:
    var probe := OrderProbe.from_entity(null, false)
    TestHelper.assert_eq(probe.target, null, "null target stays null")
    TestHelper.assert_eq(probe.target_cell, Vector2i.ZERO, "null target cell is ZERO")
    TestHelper.assert_eq(probe.target_pos, Vector3.ZERO, "null target pos is ZERO")
    (
        TestHelper
        . assert_true(
            not probe.modifiers.has(OrderResult.MOD_TARGET_LEVEL),
            "null from_entity must not set MOD_TARGET_LEVEL",
        )
    )


func test_resolve_probe_matches_tuple_resolve() -> void:
    var probe := OrderProbe.from_ground(Vector3(4, 0, 8), 2, false)
    var via_probe := OrderSystem.resolve_probe(probe)
    var via_tuple := OrderSystem.resolve(
        probe.target, probe.target_cell, probe.target_pos, probe.modifiers
    )
    (
        TestHelper
        . assert_eq(
            via_probe.cursor,
            via_tuple.cursor,
            "resolve_probe cursor parity with resolve()",
        )
    )
    (
        TestHelper
        . assert_eq(
            via_probe.orders.size(),
            via_tuple.orders.size(),
            "resolve_probe orders parity",
        )
    )
