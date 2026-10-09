extends Node

# Sidebar build menu ordering tests.
#
# Requirement: build menu items SHALL sort by entity type group (in
# Sidebar.TYPE_RANK order, mirroring TAB_ENTITY_TYPES — so aircraft in the
# Vehicles tab appear after all ground vehicles), then by ascending
# tech_level (-1 = never buildable, sorted first for determinism), then
# display_name, then
# id. Deterministic tie-breaking prevents load-order flicker between
# rebuilds. Sidebar order derives solely from data the entity already
# carries; adding a new buildable entity requires no ordering metadata on
# any sibling entity.

const SidebarScript := preload("res://scripts/ui/Sidebar.gd")


func _make_item(
    id: String, display_name: String, entity_type: EntityData.EntityType, tech_level: int
) -> EntityData:
    var data := EntityData.new()
    data.id = id
    data.display_name = display_name
    data.entity_type = entity_type
    data.tech_level = tech_level
    return data


func _ids_of(items: Array[EntityData]) -> Array:
    var ids: Array = []
    for item in items:
        ids.append(item.id)
    return ids


# --- Sort helper behavior (pure, no resource files) ---


func test_sort_groups_by_entity_type_before_tech_level():
    var items: Array[EntityData] = [
        _make_item("heli", "Helicopter", EntityData.EntityType.AIRCRAFT, 0),
        _make_item("tank", "Tank", EntityData.EntityType.VEHICLE, 9),
    ]
    var sorted := SidebarScript.sort_buildables(items)
    TestHelper.assert_eq(_ids_of(sorted), ["tank", "heli"], "type group beats tech level")


func test_sort_orders_by_tech_level_ascending_within_type():
    var items: Array[EntityData] = [
        _make_item("late", "Late", EntityData.EntityType.VEHICLE, 7),
        _make_item("basic", "Basic", EntityData.EntityType.VEHICLE, 1),
        _make_item("free", "Free", EntityData.EntityType.VEHICLE, -1),
        _make_item("mid", "Mid", EntityData.EntityType.VEHICLE, 3),
    ]
    var sorted := SidebarScript.sort_buildables(items)
    TestHelper.assert_eq(
        _ids_of(sorted), ["free", "basic", "mid", "late"], "ascending tech level, -1 first"
    )


func test_sort_tie_breaks_by_display_name():
    var items: Array[EntityData] = [
        _make_item("beta_unit", "Beta", EntityData.EntityType.VEHICLE, 7),
        _make_item("alpha_unit", "Alpha", EntityData.EntityType.VEHICLE, 7),
    ]
    var sorted := SidebarScript.sort_buildables(items)
    TestHelper.assert_eq(_ids_of(sorted), ["alpha_unit", "beta_unit"], "name tie-break")


func test_sort_tie_breaks_by_id_when_names_equal():
    var items: Array[EntityData] = [
        _make_item("NOD_UNIT", "Gate", EntityData.EntityType.BUILDING, 4),
        _make_item("GDI_UNIT", "Gate", EntityData.EntityType.BUILDING, 4),
    ]
    var sorted := SidebarScript.sort_buildables(items)
    TestHelper.assert_eq(_ids_of(sorted), ["GDI_UNIT", "NOD_UNIT"], "id tie-break on equal names")


func test_sort_empty_input_returns_empty():
    var items: Array[EntityData] = []
    var sorted := SidebarScript.sort_buildables(items)
    TestHelper.assert_eq(sorted.size(), 0, "empty input stays empty")


func test_sort_single_item_unchanged():
    var items: Array[EntityData] = [_make_item("only", "Only", EntityData.EntityType.INFANTRY, 2)]
    var sorted := SidebarScript.sort_buildables(items)
    TestHelper.assert_eq(_ids_of(sorted), ["only"], "single item passes through")


func test_sort_does_not_mutate_input():
    var items: Array[EntityData] = [
        _make_item("c", "C", EntityData.EntityType.VEHICLE, 3),
        _make_item("a", "A", EntityData.EntityType.VEHICLE, 1),
        _make_item("b", "B", EntityData.EntityType.VEHICLE, 2),
    ]
    var _sorted := SidebarScript.sort_buildables(items)
    TestHelper.assert_eq(_ids_of(items), ["c", "a", "b"], "input array order untouched")


func test_sort_all_equal_keys_is_deterministic():
    # Regression for load-order flicker: fully equal items must resolve to the
    # same sequence on every call, regardless of input order.
    var first: Array[EntityData] = [
        _make_item("nod_x", "Same", EntityData.EntityType.VEHICLE, 0),
        _make_item("gdi_x", "Same", EntityData.EntityType.VEHICLE, 0),
        _make_item("nod_y", "Same", EntityData.EntityType.VEHICLE, 0),
        _make_item("gdi_y", "Same", EntityData.EntityType.VEHICLE, 0),
    ]
    var shuffled: Array[EntityData] = [first[2], first[0], first[3], first[1]]
    TestHelper.assert_eq(
        _ids_of(SidebarScript.sort_buildables(first)),
        _ids_of(SidebarScript.sort_buildables(shuffled)),
        "equal keys sort identically regardless of input order"
    )
    TestHelper.assert_eq(
        _ids_of(SidebarScript.sort_buildables(first)),
        ["gdi_x", "gdi_y", "nod_x", "nod_y"],
        "equal keys resolve by id"
    )


func test_sort_unknown_entity_type_sorts_last():
    var items: Array[EntityData] = [
        _make_item("odd", "Odd", EntityData.EntityType.TERRAIN, 0),
        _make_item("known", "Known", EntityData.EntityType.AIRCRAFT, 0),
    ]
    var sorted := SidebarScript.sort_buildables(items)
    TestHelper.assert_eq(_ids_of(sorted), ["known", "odd"], "unranked type sorts last")


# --- Data coverage: buildable resources satisfy the ordering contract ---


func _collect_buildable_data() -> Array[EntityData]:
    var result: Array[EntityData] = []
    _walk_dir("res://games/ts/entities", result)
    return result


func _walk_dir(dir_path: String, result: Array[EntityData]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        TestHelper.fail("cannot open directory " + dir_path)
        return
    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        var full := dir_path + "/" + file_name
        if dir.current_is_dir():
            _walk_dir(full, result)
        elif file_name.ends_with(".tres"):
            var data: Resource = load(full)
            if data is EntityData and (data as EntityData).buildable:
                var ed := data as EntityData
                ed.set_meta("source_path", full)
                result.append(ed)
        file_name = dir.get_next()
    dir.list_dir_end()


func _tab_entities(tab_index: int, all_data: Array[EntityData]) -> Array[EntityData]:
    var tab_types: Array = SidebarScript.TAB_ENTITY_TYPES.get(tab_index, [])
    var result: Array[EntityData] = []
    for data in all_data:
        if data.entity_type in tab_types:
            result.append(data)
    return result


func _assert_type_groups_before(
    all_before: EntityData.EntityType,
    all_after: EntityData.EntityType,
    sorted: Array[EntityData],
    label: String,
) -> void:
    var last_before := -1
    var first_after := sorted.size()
    for i in range(sorted.size()):
        if sorted[i].entity_type == all_before:
            last_before = i
        elif sorted[i].entity_type == all_after and i < first_after:
            first_after = i
    TestHelper.assert_true(last_before >= 0, label + " — found " + str(all_before) + " entries")
    TestHelper.assert_true(
        first_after < sorted.size(), label + " — found " + str(all_after) + " entries"
    )
    TestHelper.assert_true(
        last_before < first_after,
        "%s — every %s precedes every %s" % [label, str(all_before), str(all_after)]
    )


func test_vehicles_tab_groups_vehicles_before_aircraft():
    _assert_type_groups_before(
        EntityData.EntityType.VEHICLE,
        EntityData.EntityType.AIRCRAFT,
        SidebarScript.sort_buildables(_tab_entities(2, _collect_buildable_data())),
        "Vehicles tab"
    )


func test_tech_level_nondecreasing_within_each_type_group():
    for tab_index in range(4):
        var sorted := SidebarScript.sort_buildables(
            _tab_entities(tab_index, _collect_buildable_data())
        )
        var last_tech_by_type: Dictionary = {}
        for data in sorted:
            if last_tech_by_type.has(data.entity_type):
                (
                    TestHelper
                    . assert_true(
                        data.tech_level >= last_tech_by_type[data.entity_type],
                        (
                            "%s: tech_level %d after %d in tab %d (%s)"
                            % [
                                data.id,
                                data.tech_level,
                                last_tech_by_type[data.entity_type],
                                tab_index,
                                str(data.entity_type),
                            ]
                        )
                    )
                )
            last_tech_by_type[data.entity_type] = data.tech_level


func test_every_buildable_entity_has_valid_tech_level():
    for data in _collect_buildable_data():
        TestHelper.assert_true(data.tech_level >= -1, "%s has tech_level >= -1" % data.id)


func test_every_buildable_entity_type_maps_to_a_tab():
    var tabbed: Dictionary = {}
    for tab_index in range(4):
        for etype in SidebarScript.TAB_ENTITY_TYPES.get(tab_index, []):
            tabbed[etype] = true
    TestHelper.assert_true(tabbed.size() > 0, "at least one tab declares entity types")
    for data in _collect_buildable_data():
        TestHelper.assert_true(
            tabbed.has(data.entity_type),
            "%s type %s appears in a sidebar tab" % [data.id, str(data.entity_type)]
        )
