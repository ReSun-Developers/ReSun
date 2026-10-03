extends Node

# HoverTooltip tests — label resolution (friendly/enemy/neutral/ownerless),
# enemy type mapping, uppercase rendering, hover-delay show/hide, resource
# entities, and the shrouded-cell label.

const HOVER_TOOLTIP_SCENE: PackedScene = preload("res://scenes/ui/HoverTooltip.tscn")
const HOVER_TOOLTIP_SCRIPT: GDScript = preload("res://scripts/ui/HoverTooltip.gd")
const MAP_BASE_SCENE: PackedScene = preload("res://scenes/maps/MapBase01.tscn")
const HUD_SURFACE_SCENE: PackedScene = preload("res://scenes/ui/HudSurface.tscn")
const SELECT_COMPONENT_SCENE: PackedScene = preload("res://scenes/components/SelectComponent.tscn")
const MOVEMENT_CONTROLLER_SCENE: PackedScene = preload(
    "res://scenes/components/MovementController.tscn"
)

var _pm: Node = null
var _sm: Node = null


func _make_tooltip() -> Node:
    var tooltip := HOVER_TOOLTIP_SCENE.instantiate()
    tooltip.name = "HoverTooltip"
    _pm.get_tree().root.add_child(tooltip)
    return tooltip


func _make_entity(display_name: String, player_id: int, entity_type: int) -> Node3D:
    var entity := Node3D.new()
    entity.name = "TooltipEntity"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.display_name = display_name
    stats.player_id = player_id
    stats.entity_type = entity_type
    entity.add_child(stats)
    _pm.get_tree().root.add_child(entity)
    return entity


func _make_selectable(display_name: String, player_id: int, entity_type: int) -> Dictionary:
    var entity := _make_entity(display_name, player_id, entity_type)
    var select_comp := SELECT_COMPONENT_SCENE.instantiate() as SelectComponent
    select_comp.name = "SelectComponent"
    entity.add_child(select_comp)
    return {"entity": entity, "select_comp": select_comp}


func _add_airborne(entity: Node3D, airborne: bool) -> void:
    var mc := MOVEMENT_CONTROLLER_SCENE.instantiate() as MovementController
    mc.name = "MovementController"
    entity.add_child(mc)
    mc.set_physics_process(false)
    mc._is_jumpjet = true
    mc._vertical_state = (
        MovementController.VerticalState.AIR
        if airborne
        else MovementController.VerticalState.GROUND
    )


func test_friendly_shows_real_name() -> void:
    if _pm == null:
        TestHelper.fail("PlayerManager not injected")
        return
    var entity := _make_entity("Rifleman", 0, EntityData.EntityType.INFANTRY)
    var label := HOVER_TOOLTIP_SCRIPT.resolve_label(entity) as String
    TestHelper.assert_eq(label, "Rifleman", "friendly entity shows its real display name")
    entity.free()


func test_ownerless_shows_real_name() -> void:
    if _pm == null:
        TestHelper.fail("PlayerManager not injected")
        return
    var entity := _make_entity("Tiberium Field", -1, EntityData.EntityType.TERRAIN)
    var label := HOVER_TOOLTIP_SCRIPT.resolve_label(entity) as String
    TestHelper.assert_eq(
        label, "Tiberium Field", "ownerless entity (player_id -1) shows its real display name"
    )
    entity.free()


func test_neutral_shows_real_name() -> void:
    if _pm == null:
        TestHelper.fail("PlayerManager not injected")
        return
    var neutral: PlayerData = _pm.get_player_data(2)
    var saved_team_id: int = neutral.team_id
    neutral.team_id = 1
    var entity := _make_entity("Friendly Faction Unit", 2, EntityData.EntityType.VEHICLE)
    var label := HOVER_TOOLTIP_SCRIPT.resolve_label(entity) as String
    (
        TestHelper
        . assert_eq(
            label,
            "Friendly Faction Unit",
            "same-team other-player (neutral) entity shows its real display name",
        )
    )
    neutral.team_id = saved_team_id
    entity.free()


func test_enemy_infantry_label() -> void:
    var entity := _make_entity("Hidden Name", 1, EntityData.EntityType.INFANTRY)
    (
        TestHelper
        . assert_eq(
            HOVER_TOOLTIP_SCRIPT.resolve_label(entity) as String,
            "ENEMY INFANTRY",
            "enemy infantry shows ENEMY INFANTRY, not its real name",
        )
    )
    entity.free()


func test_enemy_vehicle_label() -> void:
    var entity := _make_entity("Hidden Name", 1, EntityData.EntityType.VEHICLE)
    (
        TestHelper
        . assert_eq(
            HOVER_TOOLTIP_SCRIPT.resolve_label(entity) as String,
            "ENEMY UNIT",
            "enemy vehicle shows ENEMY UNIT, not its real name",
        )
    )
    entity.free()


func test_enemy_structure_label() -> void:
    var entity := _make_entity("Hidden Name", 1, EntityData.EntityType.BUILDING)
    (
        TestHelper
        . assert_eq(
            HOVER_TOOLTIP_SCRIPT.resolve_label(entity) as String,
            "ENEMY STRUCTURE",
            "enemy structure shows ENEMY STRUCTURE, not its real name",
        )
    )
    entity.free()


func test_enemy_aircraft_airborne_label() -> void:
    var entity := _make_entity("Hidden Name", 1, EntityData.EntityType.AIRCRAFT)
    _add_airborne(entity, true)
    (
        TestHelper
        . assert_eq(
            HOVER_TOOLTIP_SCRIPT.resolve_label(entity) as String,
            "ENEMY AIRCRAFT",
            "airborne enemy aircraft shows ENEMY AIRCRAFT",
        )
    )
    entity.free()


func test_enemy_aircraft_grounded_label() -> void:
    var entity := _make_entity("Hidden Name", 1, EntityData.EntityType.AIRCRAFT)
    _add_airborne(entity, false)
    (
        TestHelper
        . assert_eq(
            HOVER_TOOLTIP_SCRIPT.resolve_label(entity) as String,
            "ENEMY UNIT",
            "grounded enemy aircraft shows ENEMY UNIT",
        )
    )
    entity.free()


func test_label_is_uppercased() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var tooltip := _make_tooltip()
    var fixture := _make_selectable("Rifleman", 0, EntityData.EntityType.INFANTRY)
    _sm.set_hover_preview(true, fixture["select_comp"] as SelectComponent)
    tooltip._on_delay_timeout()
    var text_label := tooltip.get_node("Label") as Label
    TestHelper.assert_eq(
        text_label.text, "RIFLEMAN", "tooltip renders the display name in uppercase"
    )
    _sm.clear_hover_preview()
    tooltip.free()
    fixture["entity"].free()


func test_delay_before_show() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var tooltip := _make_tooltip()
    var fixture := _make_selectable("Rifleman", 0, EntityData.EntityType.INFANTRY)
    _sm.set_hover_preview(true, fixture["select_comp"] as SelectComponent)
    TestHelper.assert_true(not tooltip.visible, "tooltip stays hidden during the hover delay")
    tooltip._on_delay_timeout()
    TestHelper.assert_true(tooltip.visible, "tooltip appears after the hover delay lapses")
    _sm.clear_hover_preview()
    tooltip.free()
    fixture["entity"].free()


func test_hover_clear_cancels_delay() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var tooltip := _make_tooltip()
    var fixture := _make_selectable("Rifleman", 0, EntityData.EntityType.INFANTRY)
    _sm.set_hover_preview(true, fixture["select_comp"] as SelectComponent)
    _sm.clear_hover_preview()
    tooltip._on_delay_timeout()
    TestHelper.assert_true(
        not tooltip.visible, "clearing hover before the delay lapses cancels the tooltip"
    )
    tooltip.free()
    fixture["entity"].free()


func test_mouse_movement_resets_delay() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var tooltip := _make_tooltip()
    var fixture := _make_selectable("Rifleman", 0, EntityData.EntityType.INFANTRY)
    _sm.set_hover_preview(true, fixture["select_comp"] as SelectComponent)
    TestHelper.assert_true(
        not tooltip._delay_timer.is_stopped(), "the pending delay timer is running"
    )
    tooltip._last_mouse_pos = Vector2(9999, 9999)
    tooltip._process(0.0)
    var timer: Timer = tooltip._delay_timer
    (
        TestHelper
        . assert_true(
            abs(timer.time_left - timer.wait_time) < 0.01,
            "moving the cursor while pending restarts the hover delay",
        )
    )
    TestHelper.assert_true(not tooltip.visible, "a moved cursor keeps the tooltip hidden")
    tooltip.free()
    fixture["entity"].free()


func test_mouse_movement_hides_visible_tooltip() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var tooltip := _make_tooltip()
    var fixture := _make_selectable("Rifleman", 0, EntityData.EntityType.INFANTRY)
    _sm.set_hover_preview(true, fixture["select_comp"] as SelectComponent)
    tooltip._on_delay_timeout()
    TestHelper.assert_true(tooltip.visible, "tooltip visible after the delay lapses")
    tooltip._last_mouse_pos = Vector2(9999, 9999)
    tooltip._process(0.0)
    (
        TestHelper
        . assert_true(
            not tooltip.visible,
            "moving the cursor hides the visible tooltip until the delay refills",
        )
    )
    var timer: Timer = tooltip._delay_timer
    (
        TestHelper
        . assert_true(
            not timer.is_stopped() and abs(timer.time_left - timer.wait_time) < 0.01,
            "the delay timer restarts after the cursor moves",
        )
    )
    tooltip._on_delay_timeout()
    TestHelper.assert_true(tooltip.visible, "tooltip reappears once the refilled delay lapses")
    tooltip.free()
    fixture["entity"].free()


func test_show_hide_on_hover_changed() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var tooltip := _make_tooltip()
    var fixture := _make_selectable("Rifleman", 0, EntityData.EntityType.INFANTRY)
    _sm.set_hover_preview(true, fixture["select_comp"] as SelectComponent)
    tooltip._on_delay_timeout()
    TestHelper.assert_true(tooltip.visible, "hovering a friendly entity shows the tooltip")
    _sm.clear_hover_preview()
    TestHelper.assert_true(not tooltip.visible, "clearing hover hides the tooltip")
    tooltip.free()
    fixture["entity"].free()


func test_reappears_on_same_entity_after_sidebar_detour() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var tooltip := _make_tooltip()
    var fixture := _make_selectable("Rifleman", 0, EntityData.EntityType.INFANTRY)
    var select_comp := fixture["select_comp"] as SelectComponent
    _sm.set_hover_preview(true, select_comp)
    tooltip._on_delay_timeout()
    TestHelper.assert_true(tooltip.visible, "tooltip shown on the first hover")
    _sm.clear_hover_preview()
    tooltip._cancel_pending()
    TestHelper.assert_true(not tooltip.visible, "tooltip hidden after hover clears")
    _sm.set_hover_preview(true, select_comp)
    (
        TestHelper
        . assert_true(
            not tooltip._delay_timer.is_stopped(),
            "re-hovering the same entity after a clear re-arms the delay",
        )
    )
    tooltip._on_delay_timeout()
    (
        TestHelper
        . assert_true(
            tooltip.visible,
            "tooltip reappears on the same entity once the re-armed delay lapses",
        )
    )
    tooltip.free()
    fixture["entity"].free()


func test_tooltip_has_visible_size() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var tooltip := _make_tooltip()
    var fixture := _make_selectable("Rifleman", 0, EntityData.EntityType.INFANTRY)
    _sm.set_hover_preview(true, fixture["select_comp"] as SelectComponent)
    tooltip._on_delay_timeout()
    (
        TestHelper
        . assert_true(
            tooltip.size.x > 0.0 and tooltip.size.y > 0.0,
            "shown tooltip sizes to its label instead of rendering at 0x0",
        )
    )
    _sm.clear_hover_preview()
    tooltip.free()
    fixture["entity"].free()


func test_resource_entity_shows_tooltip() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var tooltip := _make_tooltip()
    var tree := _make_entity("Tiberium Tree", -1, EntityData.EntityType.TERRAIN)
    _sm.set_hover_node(tree)
    tooltip._on_delay_timeout()
    TestHelper.assert_true(tooltip.visible, "hovering a resource entity shows the tooltip")
    var text_label := tooltip.get_node("Label") as Label
    TestHelper.assert_eq(text_label.text, "TIBERIUM TREE", "resource shows its display name")
    _sm.clear_hover_preview()
    tooltip.free()
    tree.free()


func test_shroud_label() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var tooltip := _make_tooltip()
    _sm.set_hover_shroud()
    tooltip._on_delay_timeout()
    TestHelper.assert_true(tooltip.visible, "hovering a shrouded cell shows the tooltip")
    var text_label := tooltip.get_node("Label") as Label
    TestHelper.assert_eq(
        text_label.text, "UNREVEALED TERRAIN", "shrouded cells show the UNREVEALED TERRAIN label"
    )
    _sm.clear_hover_preview()
    tooltip.free()


func test_empty_display_name_hides_tooltip() -> void:
    if _sm == null:
        TestHelper.fail("SelectionManager not injected")
        return
    var tooltip := _make_tooltip()
    var fixture := _make_selectable("", 0, EntityData.EntityType.INFANTRY)
    _sm.set_hover_preview(true, fixture["select_comp"] as SelectComponent)
    (
        TestHelper
        . assert_eq(
            HOVER_TOOLTIP_SCRIPT.resolve_label(fixture["entity"] as Node3D) as String,
            "",
            "empty display name resolves to an empty label",
        )
    )
    tooltip._on_delay_timeout()
    TestHelper.assert_true(not tooltip.visible, "empty label keeps the tooltip hidden")
    _sm.clear_hover_preview()
    tooltip.free()
    fixture["entity"].free()


func test_tooltip_instanced_in_gameplay_hud() -> void:
    var hud := HUD_SURFACE_SCENE.instantiate()
    _pm.get_tree().root.add_child(hud)
    var tooltip: Node = hud.get_node_or_null("HoverTooltip")
    (
        TestHelper
        . assert_true(
            is_instance_valid(tooltip),
            "the match HUD surface contains the HoverTooltip so hover renders in every map",
        )
    )
    hud.free()
    # The map scene no longer hosts the HUD: it is a peer of the World root.
    var map := MAP_BASE_SCENE.instantiate()
    (
        TestHelper
        . assert_true(
            map.get_node_or_null("HUD") == null,
            "MapBase01 does not host the in-game HUD",
        )
    )
    map.free()
