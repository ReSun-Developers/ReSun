extends Node

## MapEditor tool for cell tags. A view over TerrainSystem (single store):
## assign/clear delegate to TerrainSystem and the label overlay rebuilds from it
## on cell_tag_changed / grid_initialized. Because TerrainSystem owns the overlay
## and serializes it, saving/loading needs no editor-side store.

var _labels: Node3D
var _tag_id: String = ""


func setup(parent: Node3D) -> void:
    _labels = Node3D.new()
    _labels.name = "CellTagLabels"
    _labels.top_level = true
    parent.add_child(_labels)
    TerrainSystem.cell_tag_changed.connect(_on_cell_tag_changed)
    TerrainSystem.grid_initialized.connect(rebuild)
    rebuild()


func cleanup() -> void:
    if TerrainSystem.cell_tag_changed.is_connected(_on_cell_tag_changed):
        TerrainSystem.cell_tag_changed.disconnect(_on_cell_tag_changed)
    if TerrainSystem.grid_initialized.is_connected(rebuild):
        TerrainSystem.grid_initialized.disconnect(rebuild)
    if _labels and is_instance_valid(_labels):
        _labels.queue_free()
        _labels = null


func set_tag_id(tag_id: String) -> void:
    _tag_id = tag_id


func active_tag_id() -> String:
    return _tag_id


## Binds the cell to the active tag id; false when the id is empty or the cell
## is outside the diamond.
func assign(cell: Vector2i) -> bool:
    return TerrainSystem.set_cell_tag(cell, _tag_id)


## Clears the cell's tag; false when it had none.
func clear_at(cell: Vector2i) -> bool:
    return TerrainSystem.clear_cell_tag(cell)


func _on_cell_tag_changed(_cell: Vector2i, _tag_id: String) -> void:
    rebuild()


func rebuild() -> void:
    if not _labels or not is_instance_valid(_labels):
        return
    for child in _labels.get_children():
        child.queue_free()
    var tags: Dictionary = TerrainSystem.get_all_cell_tags()
    for key in tags:
        var parts := String(key).split(",")
        if parts.size() != 2:
            continue
        var cell := Vector2i(parts[0].to_int(), parts[1].to_int())
        var world_pos := CellUtil.cell_to_world(cell)
        world_pos.y = TerrainSystem.get_height_at_world_smooth(world_pos) + 1.0
        var label := Label3D.new()
        label.name = "Tag_%d_%d" % [cell.x, cell.y]
        label.text = String(tags[key])
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.pixel_size = 0.01
        label.no_depth_test = true
        label.position = world_pos
        _labels.add_child(label)
