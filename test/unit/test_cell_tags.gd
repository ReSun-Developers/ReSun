extends Node

# TerrainSystem cell tags: registry API (set/clear/get/has, diamond and empty-id
# guards), region query, signal emission, and "cell_tags" map-JSON round-trip
# (absent key, out-of-diamond, and malformed entries).

const TAG_A := "02A74D10"
const TAG_B := "08717E90"

var _ts: Node = null


## Restore the shared TerrainSystem grid after this suite so later suites that
## rely on the 50x50 default are not poisoned by these small fixtures.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE and is_instance_valid(_ts):
        _ts.init_grid(50, 50)


func test_set_and_read_back():
    _ts.init_grid(6, 6)
    var cell := Vector2i(3, 3)
    TestHelper.assert_true(_ts.set_cell_tag(cell, TAG_A), "in-diamond tag succeeds")
    TestHelper.assert_eq(_ts.get_cell_tag(cell), TAG_A, "tag readable")
    TestHelper.assert_true(_ts.has_cell_tag(cell), "cell reports tagged")
    TestHelper.assert_eq(_ts.get_cell_tag(Vector2i(2, 3)), "", "untagged cell reads empty")


func test_reassign_a_cell():
    _ts.init_grid(6, 6)
    var cell := Vector2i(3, 3)
    _ts.set_cell_tag(cell, TAG_A)
    TestHelper.assert_true(_ts.set_cell_tag(cell, TAG_B), "reassign succeeds")
    TestHelper.assert_eq(_ts.get_cell_tag(cell), TAG_B, "cell holds the newer tag")
    TestHelper.assert_eq(_ts.cells_with_tag(TAG_A).size(), 0, "old tag no longer owns the cell")


func test_clear_a_tag():
    _ts.init_grid(6, 6)
    var cell := Vector2i(3, 3)
    _ts.set_cell_tag(cell, TAG_A)
    TestHelper.assert_true(_ts.clear_cell_tag(cell), "clear succeeds when tagged")
    TestHelper.assert_eq(_ts.get_cell_tag(cell), "", "tag cleared")
    TestHelper.assert_true(not _ts.has_cell_tag(cell), "cell reports untagged")
    TestHelper.assert_true(not _ts.clear_cell_tag(cell), "clear without tag fails")


func test_outside_diamond_rejected():
    _ts.init_grid(6, 6)
    TestHelper.assert_true(not _ts.set_cell_tag(Vector2i(0, 0), TAG_A), "corner tag rejected")
    TestHelper.assert_true(not _ts.has_cell_tag(Vector2i(0, 0)), "no tag recorded outside diamond")


func test_empty_tag_id_rejected():
    _ts.init_grid(6, 6)
    var cell := Vector2i(3, 3)
    TestHelper.assert_true(not _ts.set_cell_tag(cell, ""), "empty tag id rejected")
    TestHelper.assert_true(not _ts.has_cell_tag(cell), "no tag recorded for empty id")


func test_clear_resets_overlay():
    _ts.init_grid(6, 6)
    _ts.set_cell_tag(Vector2i(3, 3), TAG_A)
    _ts.clear()
    TestHelper.assert_eq(_ts.get_cell_tag(Vector2i(3, 3)), "", "clear() drops all tags")


func test_grid_reinit_resets_overlay():
    _ts.init_grid(6, 6)
    _ts.set_cell_tag(Vector2i(3, 3), TAG_A)
    _ts.init_grid(6, 6)
    TestHelper.assert_eq(_ts.get_cell_tag(Vector2i(3, 3)), "", "grid re-init drops all tags")


func test_signal_emitted_on_set_and_clear():
    _ts.init_grid(6, 6)
    var events: Array = []
    var cb := func(cell: Vector2i, tag_id: String) -> void: events.append([cell, tag_id])
    _ts.cell_tag_changed.connect(cb)
    _ts.set_cell_tag(Vector2i(3, 3), TAG_A)
    _ts.clear_cell_tag(Vector2i(3, 3))
    _ts.cell_tag_changed.disconnect(cb)
    TestHelper.assert_eq(events.size(), 2, "set and clear each emit once")
    TestHelper.assert_eq(events[0], [Vector2i(3, 3), TAG_A], "set emits the cell and tag")
    TestHelper.assert_eq(events[1], [Vector2i(3, 3), ""], "clear emits an empty tag")


func test_cells_with_tag_region():
    _ts.init_grid(8, 8)
    for cell in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5)]:
        _ts.set_cell_tag(cell, TAG_A)
    _ts.set_cell_tag(Vector2i(5, 5), TAG_B)
    var region: Array[Vector2i] = _ts.cells_with_tag(TAG_A)
    TestHelper.assert_eq(region.size(), 3, "region returns every bound cell")
    for cell in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5)]:
        TestHelper.assert_true(cell in region, "region contains %s" % cell)
    TestHelper.assert_eq(_ts.cells_with_tag("no_such_tag").size(), 0, "unknown tag is empty")


func test_round_trip_through_json():
    _ts.init_grid(6, 6)
    _ts.set_cell_tag(Vector2i(2, 3), TAG_A)
    _ts.set_cell_tag(Vector2i(3, 3), TAG_B)
    var path := "user://test_cell_tags_roundtrip.json"
    _ts.export_to_json(path)
    _ts.clear()
    _ts.import_from_json(path)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    TestHelper.assert_eq(_ts.get_cell_tag(Vector2i(2, 3)), TAG_A, "tag a survives round-trip")
    TestHelper.assert_eq(_ts.get_cell_tag(Vector2i(3, 3)), TAG_B, "tag b survives round-trip")


func test_map_without_tags_loads_clean():
    _ts.init_grid(6, 6)
    var path := "user://test_cell_tags_absent.json"
    _ts.export_to_json(path)
    _ts.set_cell_tag(Vector2i(3, 3), TAG_A)
    _ts.import_from_json(path)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    TestHelper.assert_eq(_ts.get_cell_tag(Vector2i(3, 3)), "", "no cell_tags key -> no tags")


func test_empty_overlay_omitted():
    _ts.init_grid(6, 6)
    var path := "user://test_cell_tags_omitted.json"
    _ts.export_to_json(path)
    var file := FileAccess.open(path, FileAccess.READ)
    var json := JSON.parse_string(file.get_as_text()) as Dictionary
    file.close()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    TestHelper.assert_true(not json.has("cell_tags"), "empty overlay writes no cell_tags key")


func test_out_of_diamond_entries_ignored():
    _ts.init_grid(6, 6)
    var path := "user://test_cell_tags_oob.json"
    _write_map_json(path, {"3,3": TAG_A, "0,0": TAG_B})
    _ts.import_from_json(path)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    TestHelper.assert_eq(_ts.get_cell_tag(Vector2i(3, 3)), TAG_A, "in-diamond tag restored")
    TestHelper.assert_true(not _ts.has_cell_tag(Vector2i(0, 0)), "out-of-diamond tag discarded")


func test_malformed_entries_ignored():
    _ts.init_grid(6, 6)
    var path := "user://test_cell_tags_malformed.json"
    _write_map_json(path, {"a,b": TAG_A, "3,3": "", "4,4": TAG_B})
    _ts.import_from_json(path)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    TestHelper.assert_eq(_ts.get_cell_tag(Vector2i(4, 4)), TAG_B, "valid entry restored")
    TestHelper.assert_true(not _ts.has_cell_tag(Vector2i(3, 3)), "empty value discarded")
    TestHelper.assert_eq(_ts.cells_with_tag(TAG_A).size(), 0, "non-numeric key discarded")


func test_non_string_value_ignored():
    _ts.init_grid(6, 6)
    var path := "user://test_cell_tags_nonstring.json"
    _write_map_json(path, {"4,4": 123, "5,5": true, "4,5": null, "5,4": TAG_A})
    _ts.import_from_json(path)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    TestHelper.assert_eq(_ts.get_cell_tag(Vector2i(5, 4)), TAG_A, "string entry restored")
    TestHelper.assert_true(not _ts.has_cell_tag(Vector2i(4, 4)), "int value discarded")
    TestHelper.assert_true(not _ts.has_cell_tag(Vector2i(5, 5)), "bool value discarded")
    TestHelper.assert_true(not _ts.has_cell_tag(Vector2i(4, 5)), "null value discarded")
    TestHelper.assert_true(_ts.get_all_cells().size() > 0, "terrain still loads after a bad value")


func test_import_normalizes_cell_key():
    _ts.init_grid(6, 6)
    var path := "user://test_cell_tags_normalize.json"
    _write_map_json(path, {"04,04": TAG_A})
    _ts.import_from_json(path)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    TestHelper.assert_eq(_ts.get_cell_tag(Vector2i(4, 4)), TAG_A, "non-canonical key normalized")


func test_diamond_boundary():
    _ts.init_grid(6, 6)
    TestHelper.assert_true(_ts.set_cell_tag(Vector2i(0, 5), TAG_A), "even-grid edge cell accepted")
    TestHelper.assert_true(_ts.set_cell_tag(Vector2i(5, 0), TAG_A), "opposite edge accepted")
    TestHelper.assert_true(not _ts.set_cell_tag(Vector2i(2, 2), TAG_A), "inner corner rejected")
    _ts.init_grid(7, 7)
    TestHelper.assert_true(_ts.set_cell_tag(Vector2i(3, 3), TAG_A), "odd-grid center accepted")
    TestHelper.assert_true(
        not _ts.set_cell_tag(Vector2i(2, 2), TAG_A), "odd-grid near-corner rejected"
    )


func test_rejected_and_failed_mutations_emit_nothing():
    _ts.init_grid(6, 6)
    var events: Array = []
    var cb := func(cell: Vector2i, tag_id: String) -> void: events.append([cell, tag_id])
    _ts.cell_tag_changed.connect(cb)
    _ts.set_cell_tag(Vector2i(0, 0), TAG_A)
    _ts.set_cell_tag(Vector2i(3, 3), "")
    _ts.clear_cell_tag(Vector2i(4, 4))
    _ts.cell_tag_changed.disconnect(cb)
    TestHelper.assert_eq(events.size(), 0, "rejected set and failed clear emit nothing")


func test_existing_map_without_tags_loads_clean():
    _ts.import_from_json("res://games/ts/maps/gdi01.json")
    TestHelper.assert_eq(_ts.get_all_cell_tags().size(), 0, "gdi01 has no cell tags")
    TestHelper.assert_eq(_ts.get_cell_tag(Vector2i(25, 25)), "", "no stray tags on gdi01")
    _ts.clear()
    _ts.init_grid(50, 50)


func _write_map_json(path: String, cell_tags: Dictionary) -> void:
    var data: Dictionary = {
        "version": 4,
        "grid_cells": [6, 6],
        "cells": {},
        "cell_tags": cell_tags,
    }
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(JSON.stringify(data, "\t"))
    file.close()
