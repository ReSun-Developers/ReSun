extends Node

# Cell tag editor integration: CellTagTool as a view over TerrainSystem (assign/
# clear delegate + label overlay), MapEditor input wiring, and save/load label
# restoration through the existing EditorSaveLoad path.

const MAP_EDITOR_SCENE: PackedScene = preload("res://scenes/editor/MapEditor.tscn")
const CELL_TAG_TOOL := preload("res://scripts/editor/CellTagTool.gd")
const TAG := "02A74D10"

var _ts: Node = null


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE and is_instance_valid(_ts):
        _ts.clear()
        _ts.init_grid(50, 50)


func _make_mouse(button: int) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = button
    event.pressed = true
    return event


func _live_label_count(labels: Node) -> int:
    var count := 0
    for child in labels.get_children():
        if not child.is_queued_for_deletion():
            count += 1
    return count


func test_tool_assign_renders_label():
    if _ts == null:
        TestHelper.fail("TerrainSystem is injected")
        return
    _ts.clear()
    _ts.init_grid(6, 6)
    var parent := Node3D.new()
    add_child(parent)
    var tool: Node = CELL_TAG_TOOL.new()
    add_child(tool)
    tool.setup(parent)
    tool.set_tag_id(TAG)
    TestHelper.assert_true(tool.assign(Vector2i(3, 3)), "assign delegates to TerrainSystem")
    TestHelper.assert_eq(_ts.get_cell_tag(Vector2i(3, 3)), TAG, "store updated by the tool")
    var labels: Node = parent.get_node_or_null("CellTagLabels")
    TestHelper.assert_true(labels != null, "label container created")
    TestHelper.assert_eq(_live_label_count(labels), 1, "one label rendered per tagged cell")
    var label := labels.get_child(0) as Label3D
    TestHelper.assert_eq(label.text, TAG, "label shows the tag id")
    tool.cleanup()
    tool.queue_free()
    parent.queue_free()


func test_tool_clear_removes_label():
    if _ts == null:
        TestHelper.fail("TerrainSystem is injected")
        return
    _ts.clear()
    _ts.init_grid(6, 6)
    var parent := Node3D.new()
    add_child(parent)
    var tool: Node = CELL_TAG_TOOL.new()
    add_child(tool)
    tool.setup(parent)
    tool.set_tag_id(TAG)
    tool.assign(Vector2i(3, 3))
    var labels: Node = parent.get_node_or_null("CellTagLabels")
    TestHelper.assert_true(tool.clear_at(Vector2i(3, 3)), "clear delegates to TerrainSystem")
    TestHelper.assert_eq(_ts.get_cell_tag(Vector2i(3, 3)), "", "store cleared by the tool")
    TestHelper.assert_eq(_live_label_count(labels), 0, "label removed on clear")
    tool.cleanup()
    tool.queue_free()
    parent.queue_free()


func test_map_editor_cell_tag_input_path():
    if _ts == null:
        TestHelper.fail("TerrainSystem is injected")
        return
    _ts.clear()
    var editor: Node3D = MAP_EDITOR_SCENE.instantiate()
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    tree.root.add_child(editor)
    var tool: Node = editor.get_node_or_null("CellTagTool")
    var cell := Vector2i(25, 25)
    TestHelper.assert_true(tool != null, "MapEditor wires a CellTagTool")
    TestHelper.assert_true(editor.get_node_or_null("EditorUI") != null, "MapEditor UI is built")
    tool.set_tag_id(TAG)
    editor._hovered_cell = cell
    editor._handle_cell_tag_input(_make_mouse(MOUSE_BUTTON_LEFT))
    TestHelper.assert_eq(_ts.get_cell_tag(cell), TAG, "left click assigns the active tag")
    editor._handle_cell_tag_input(_make_mouse(MOUSE_BUTTON_RIGHT))
    TestHelper.assert_eq(_ts.get_cell_tag(cell), "", "right click clears the cell tag")
    if editor.is_inside_tree():
        editor.get_parent().remove_child(editor)
    editor.queue_free()
    _ts.clear()
    _ts.init_grid(50, 50)


func test_editor_save_load_restores_labels():
    if _ts == null:
        TestHelper.fail("TerrainSystem is injected")
        return
    _ts.clear()
    var editor: Node3D = MAP_EDITOR_SCENE.instantiate()
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    tree.root.add_child(editor)
    var tool: Node = editor.get_node_or_null("CellTagTool")
    var cell := Vector2i(25, 25)
    tool.set_tag_id(TAG)
    editor._hovered_cell = cell
    editor._handle_cell_tag_input(_make_mouse(MOUSE_BUTTON_LEFT))

    var path := "user://test_cell_tag_editor.json"
    var saveload: Node = editor.get_node_or_null("EditorSaveLoad")
    saveload.call("_on_save_file_selected", path)
    _ts.clear()
    _ts.init_grid(50, 50)
    var labels: Node = editor.get_node_or_null("CellTagLabels")
    TestHelper.assert_eq(_ts.get_cell_tag(cell), "", "tags cleared before reload")

    saveload.call("_on_load_file_selected", path)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    TestHelper.assert_eq(_ts.get_cell_tag(cell), TAG, "tag restored from saved map")
    TestHelper.assert_eq(_live_label_count(labels), 1, "label restored after reload")

    if editor.is_inside_tree():
        editor.get_parent().remove_child(editor)
    editor.queue_free()
    _ts.clear()
    _ts.init_grid(50, 50)


func test_map_json_fixture_region_end_to_end():
    if _ts == null:
        TestHelper.fail("TerrainSystem is injected")
        return
    var path := "user://test_cell_tag_fixture.json"
    var data: Dictionary = {
        "version": 4,
        "grid_cells": [8, 8],
        "cells": {},
        "cell_tags": {"4,4": TAG, "5,4": TAG, "4,5": TAG},
    }
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(JSON.stringify(data, "\t"))
    file.close()
    _ts.import_from_json(path)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    var region: Array[Vector2i] = _ts.cells_with_tag(TAG)
    TestHelper.assert_eq(region.size(), 3, "region query returns the tagged cells")
    TestHelper.assert_eq(_ts.get_cell_tag(Vector2i(4, 4)), TAG, "cell lookup returns the id")
    _ts.clear()
    _ts.init_grid(50, 50)
