extends Node

# TransportComponent tests — cargo, cursor resolution, and order generation

const SELECT_COMPONENT_SCENE: PackedScene = preload("res://scenes/components/SelectComponent.tscn")

var _sm: Node = null


func _make_transport(capacity: int = 28) -> TransportComponent:
    var transport := TransportComponent.new()
    transport.name = "TransportComponent"
    transport.storage = capacity
    return transport


## Mark the entity as the only selected unit — the precondition for a
## mouse-click unload (mixed selections must not unload via click).
func _select_sole(entity: Node3D) -> SelectComponent:
    var sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    sc.name = "SelectComponent"
    entity.add_child(sc)
    sc.is_selected = true
    if _sm == null:
        _sm = Engine.get_main_loop().root.get_node_or_null("SelectionManager")
    _sm.selected_entities.clear()
    _sm.selected_entities.append(sc)
    return sc


func _clear_selection() -> void:
    if _sm:
        _sm.selected_entities.clear()


func _make_rules() -> GlobalRules:
    var rules := GlobalRules.new()
    rules.resource_types = {}
    var tib_green := ResourceType.new()
    tib_green.id = "tiberium_green"
    tib_green.value = 25.0
    rules.resource_types["tiberium_green"] = tib_green
    var tib_blue := ResourceType.new()
    tib_blue.id = "tiberium_blue"
    tib_blue.value = 40.0
    rules.resource_types["tiberium_blue"] = tib_blue
    return rules


func test_add_cargo():
    var transport := _make_transport(28)
    var actual := transport.add_cargo("tiberium_green", 10.5)
    (
        TestHelper
        . assert_true(
            actual == 10.5 and transport.cargo.get("tiberium_green") == 10.5,
            "add_cargo adds correctly: add_cargo mismatch",
        )
    )


func test_add_cargo_respects_capacity():
    var transport := _make_transport(10)
    var actual := transport.add_cargo("tiberium_green", 15.0)
    (
        TestHelper
        . assert_true(
            actual == 10.0 and transport.get_cargo_total() == 10.0,
            "add_cargo respects capacity: add_cargo did not respect capacity",
        )
    )


func test_remove_cargo():
    var transport := _make_transport(28)
    transport.add_cargo("tiberium_green", 10.0)
    var actual := transport.remove_cargo("tiberium_green", 3.5)
    (
        TestHelper
        . assert_true(
            actual == 3.5 and transport.cargo.get("tiberium_green") == 6.5,
            "remove_cargo removes correctly: remove_cargo mismatch",
        )
    )


func test_remove_cargo_erases_at_zero():
    var transport := _make_transport(28)
    transport.add_cargo("tiberium_green", 10.0)
    transport.remove_cargo("tiberium_green", 10.0)
    (
        TestHelper
        . assert_true(
            transport.cargo.is_empty(),
            "remove_cargo erases at zero: " + "remove_cargo did not erase at zero",
        )
    )


func test_get_cargo_total():
    var transport := _make_transport(28)
    transport.add_cargo("tiberium_green", 14.5)
    transport.add_cargo("tiberium_blue", 7.5)
    (
        TestHelper
        . assert_true(
            transport.get_cargo_total() == 22.0,
            (
                "get_cargo_total sums correctly: get_cargo_total returned %f"
                % transport.get_cargo_total()
            ),
        )
    )


func test_get_cargo_value():
    var transport := _make_transport(28)
    transport.add_cargo("tiberium_green", 14.0)
    transport.add_cargo("tiberium_blue", 7.0)
    var rules := _make_rules()
    var value := transport.get_cargo_value(rules)
    TestHelper.assert_true(
        value == 630, "get_cargo_value calculates correctly: get_cargo_value returned %d" % value
    )


# --- order-cursor tests (derived from get_order_for_target) ---
# The pre-passenger ENTER stub (selected transport -> click loadable unit) was
# replaced by self-hover DEPLOY unload orders — see
# openspec/changes/add-transport-passengers/specs/transport-passengers/spec.md.


func test_cursor_self_hover_unloadable_returns_deploy():
    var transport := _make_transport(28)
    transport.passengers = 4
    transport.current_passengers = 2
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)
    _select_sole(entity)

    var cursor := TestHelper.order_cursor(transport, entity)
    TestHelper.assert_eq(cursor, CursorState.Type.DEPLOY, "hover-self unloadable -> DEPLOY")

    _clear_selection()
    entity.queue_free()


func test_cursor_self_hover_mixed_selection_returns_default():
    var transport := _make_transport(28)
    transport.passengers = 4
    transport.current_passengers = 2
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)
    _select_sole(entity)
    var other := Node3D.new()
    other.name = "OtherUnit"
    var other_sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    other.add_child(other_sc)
    other_sc.is_selected = true
    _sm.selected_entities.append(other_sc)

    var cursor := TestHelper.order_cursor(transport, entity)
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "mixed selection -> DEFAULT")

    _clear_selection()
    entity.queue_free()
    other.queue_free()


func test_cursor_self_hover_not_selected_returns_default():
    var transport := _make_transport(28)
    transport.passengers = 4
    transport.current_passengers = 2
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)
    _select_sole(entity)
    # Deselect the transport itself: nothing left selected.
    _sm.selected_entities.clear()

    var cursor := TestHelper.order_cursor(transport, entity)
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "unselected transport -> DEFAULT")

    _clear_selection()
    entity.queue_free()


func test_cursor_no_passengers_returns_default():
    var transport := _make_transport(28)
    transport.passengers = 0
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)

    var target := Node3D.new()
    target.name = "TargetUnit"
    var cursor := TestHelper.order_cursor(transport, entity)
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "no passengers -> DEFAULT")

    entity.queue_free()
    target.queue_free()


func test_cursor_null_target_returns_default():
    var transport := _make_transport(28)
    transport.passengers = 1
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)

    var cursor := TestHelper.order_cursor(transport, null)
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "null target -> DEFAULT")

    entity.queue_free()


func test_cursor_enemy_returns_default():
    var transport := _make_transport(28)
    transport.passengers = 1
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)

    var target := Node3D.new()
    target.name = "EnemyUnit"
    target.add_to_group("enemy")
    var target_sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    target.add_child(target_sc)

    var cursor := TestHelper.order_cursor(transport, target)
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "enemy -> DEFAULT")

    entity.queue_free()
    target.queue_free()


func test_cursor_target_without_transport_returns_default():
    var transport := _make_transport(28)
    transport.passengers = 1
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)

    var target := Node3D.new()
    target.name = "TargetUnit"
    target.add_to_group("selectable")
    var target_sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    target.add_child(target_sc)

    var cursor := TestHelper.order_cursor(transport, target)
    TestHelper.assert_eq(
        cursor, CursorState.Type.DEFAULT, "target without TransportComponent -> DEFAULT"
    )

    entity.queue_free()
    target.queue_free()


func test_cursor_target_zero_passengers_returns_default():
    var transport := _make_transport(28)
    transport.passengers = 1
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)

    var target := Node3D.new()
    target.name = "TargetUnit"
    target.add_to_group("selectable")
    var target_sc := SelectComponent.new()
    target.add_child(target_sc)
    var target_transport := TransportComponent.new()
    target_transport.name = "TransportComponent"
    target_transport.passengers = 0
    target.add_child(target_transport)

    var cursor := TestHelper.order_cursor(transport, target)
    TestHelper.assert_eq(cursor, CursorState.Type.DEFAULT, "target with 0 passengers -> DEFAULT")

    entity.queue_free()
    target.queue_free()


func test_cursor_no_select_component_returns_default():
    var transport := _make_transport(28)
    transport.passengers = 1
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)

    var target := Node3D.new()
    target.name = "TargetUnit"

    var cursor := TestHelper.order_cursor(transport, target)
    TestHelper.assert_eq(
        cursor, CursorState.Type.DEFAULT, "target without SelectComponent -> DEFAULT"
    )

    entity.queue_free()
    target.queue_free()


# --- get_order_for_target tests ---


func test_order_self_hover_unloadable_returns_deploy():
    var transport := _make_transport(28)
    transport.passengers = 4
    transport.current_passengers = 2
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)
    _select_sole(entity)

    var order := transport.get_order_for_target(entity, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order != null, "hover-self unloadable -> order not null")
    TestHelper.assert_eq(order.cursor, CursorState.Type.DEPLOY, "cursor -> DEPLOY")
    TestHelper.assert_eq(order.priority, 15, "priority -> 15")

    _clear_selection()
    entity.queue_free()


func test_order_self_hover_mixed_selection_returns_null():
    var transport := _make_transport(28)
    transport.passengers = 4
    transport.current_passengers = 2
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)
    _select_sole(entity)
    var other := Node3D.new()
    other.name = "OtherUnit"
    var other_sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    other.add_child(other_sc)
    other_sc.is_selected = true
    _sm.selected_entities.append(other_sc)

    var order := transport.get_order_for_target(entity, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order == null, "mixed selection -> no unload order")

    _clear_selection()
    entity.queue_free()
    other.queue_free()


func test_order_null_target_returns_null():
    var transport := _make_transport(28)
    transport.passengers = 1
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)

    var order := transport.get_order_for_target(null, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order == null, "null target -> null order")

    entity.queue_free()


func test_order_no_passengers_returns_null():
    var transport := _make_transport(28)
    transport.passengers = 0
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)

    var target := Node3D.new()
    target.name = "TargetUnit"
    var order := transport.get_order_for_target(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order == null, "no passengers -> null order")

    entity.queue_free()
    target.queue_free()


func test_order_enemy_returns_null():
    var transport := _make_transport(28)
    transport.passengers = 1
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)

    var target := Node3D.new()
    target.name = "EnemyUnit"
    target.add_to_group("enemy")
    var order := transport.get_order_for_target(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order == null, "enemy -> null order")

    entity.queue_free()
    target.queue_free()


func test_order_target_without_transport_returns_null():
    var transport := _make_transport(28)
    transport.passengers = 1
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)

    var target := Node3D.new()
    target.name = "TargetUnit"
    target.add_to_group("selectable")
    var target_sc := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    target.add_child(target_sc)

    var order := transport.get_order_for_target(target, Vector2i.ZERO, Vector3.ZERO, {})
    TestHelper.assert_true(order == null, "target without TransportComponent -> null order")

    entity.queue_free()
    target.queue_free()


func test_order_queued_modifier():
    var transport := _make_transport(28)
    transport.passengers = 4
    transport.current_passengers = 2
    var entity := Node3D.new()
    entity.name = "TransportEntity"
    entity.add_child(transport)
    _select_sole(entity)

    var modifiers := {OrderResult.MOD_QUEUED: true}
    var order := transport.get_order_for_target(entity, Vector2i.ZERO, Vector3.ZERO, modifiers)
    TestHelper.assert_true(order != null, "queued modifier -> order not null")
    TestHelper.assert_true(order.queued, "queued modifier -> order.queued = true")

    _clear_selection()
    entity.queue_free()

    entity.queue_free()
