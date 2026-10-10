extends Node

var editor: Node3D = null

var _entity_browser: PanelContainer
var _selected_entity_id: String = ""
var _selected_player_id: int = 0
var _selected_house_id: String = ""
var _preview_entity: Node3D = null
var _preview_entity_id: String = ""


func setup(ui: CanvasLayer) -> void:
    var entity_browser_script = load("res://scripts/editor/EntityBrowser.gd")
    if entity_browser_script:
        _entity_browser = entity_browser_script.new()
        _entity_browser.name = "EntityBrowser"
        _entity_browser.position = Vector2(10, 50)
        _entity_browser.visible = true
        _entity_browser.entity_selected.connect(_on_entity_selected)
        _entity_browser.player_changed.connect(_on_player_changed)
        ui.add_child(_entity_browser)


func cleanup() -> void:
    _remove_preview()
    _selected_entity_id = ""


func on_tool_toggled() -> void:
    _selected_entity_id = ""
    _remove_preview()


func on_cell_changed() -> void:
    _update_preview_position()


func handle_input(event: InputEvent) -> void:
    if editor._active_tool != editor.Tool.PLACE_ENTITY:
        return
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT:
            _place_entity_on_cell(editor._hovered_cell)
        elif event.button_index == MOUSE_BUTTON_RIGHT:
            _selected_entity_id = ""
            _remove_preview()
            editor._active_tool = editor.Tool.NONE


func handle_tree_input(event: InputEvent) -> void:
    if editor._active_tool != editor.Tool.PLACE_TREE:
        return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        _place_tree_on_cell(editor._hovered_cell)


func _on_entity_selected(entity_id: String) -> void:
    if _selected_entity_id == entity_id:
        _selected_entity_id = ""
        editor._active_tool = editor.Tool.NONE
        _remove_preview()
    else:
        _selected_entity_id = entity_id
        editor._active_tool = editor.Tool.PLACE_ENTITY
        _update_preview()


func _on_player_changed(player_id: int) -> void:
    _selected_player_id = player_id


## Sets the house (faction) id assigned to newly placed entities.
func set_house(house_id: String) -> void:
    _selected_house_id = house_id


func _update_preview() -> void:
    if editor._active_tool != editor.Tool.PLACE_ENTITY or _selected_entity_id.is_empty():
        _remove_preview()
        return
    if _selected_entity_id == _preview_entity_id and is_instance_valid(_preview_entity):
        return
    _remove_preview()
    # Editor ghosts are detached: rendered but never registered in the live world.
    var entity := (
        EntityFactory.spawn(_selected_entity_id, {"detached": true, "parent": editor}) as Node3D
    )
    if not entity:
        return
    _preview_entity = entity
    _preview_entity_id = _selected_entity_id
    _set_preview_transparency(entity, 0.75)
    _update_preview_position()


func _update_preview_position() -> void:
    if not is_instance_valid(_preview_entity):
        return
    var entity_data := EntityFactory.get_entity_data(_preview_entity_id)
    if not entity_data:
        return
    var foundation: Vector2i = entity_data.foundation
    _preview_entity.position = editor._cell_origin_world_pos(editor._hovered_cell, foundation)


func _remove_preview() -> void:
    if is_instance_valid(_preview_entity):
        _preview_entity.queue_free()
    _preview_entity = null
    _preview_entity_id = ""


func _set_preview_transparency(node: Node, alpha: float) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        var tex: Texture2D = null
        for surface_idx in mesh_instance.get_surface_override_material_count():
            var existing_mat := mesh_instance.get_surface_override_material(surface_idx)
            if existing_mat is StandardMaterial3D:
                tex = existing_mat.albedo_texture
                break
        if tex == null and mesh_instance.mesh:
            for surface_idx in mesh_instance.mesh.get_surface_count():
                var surf_mat := mesh_instance.mesh.surface_get_material(surface_idx)
                if surf_mat is StandardMaterial3D:
                    tex = surf_mat.albedo_texture
                    break
        for surface_idx in mesh_instance.get_surface_override_material_count():
            var mat := StandardMaterial3D.new()
            mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            mat.albedo_color = Color(1, 1, 1, alpha)
            if tex:
                mat.albedo_texture = tex
            mesh_instance.set_surface_override_material(surface_idx, mat)
    for child in node.get_children():
        _set_preview_transparency(child, alpha)


func _place_entity_on_cell(cell: Vector2i) -> void:
    if _selected_entity_id.is_empty():
        return
    var key := str(cell.x) + "," + str(cell.y)
    if editor._painted_entities.has(key):
        return
    var entity_data := EntityFactory.get_entity_data(_selected_entity_id)
    if not entity_data:
        return
    var overrides: Dictionary = {}
    var foundation: Vector2i = entity_data.foundation
    var world_pos: Vector3 = editor._cell_origin_world_pos(cell, foundation)
    # Editor stamps are detached: they must not register live occupancy.
    var entity := (
        EntityFactory.spawn(
            _selected_entity_id,
            {"overrides": overrides, "world_pos": world_pos, "detached": true, "parent": editor}
        )
        as Node3D
    )
    if not entity:
        return
    var data: Dictionary = {
        "id": _selected_entity_id,
        "player_id": _selected_player_id,
    }
    if not _selected_house_id.is_empty():
        data["house_id"] = _selected_house_id
    var entry: Dictionary = {"node": entity, "data": data}
    editor._painted_entities[key] = entry
    var select_comp := EditorSelectComponent.new()
    select_comp.name = "EditorSelectComponent"
    entity.add_child(select_comp)
    select_comp.configure(entity_data, key, entry)
    _remove_preview()
    _update_preview()


func _place_tree_on_cell(cell: Vector2i) -> void:
    var key := str(cell.x) + "," + str(cell.y)
    if editor._painted_entities.has(key):
        var existing := editor._painted_entities[key].get("node") as Node3D
        if is_instance_valid(existing):
            existing.queue_free()
        editor._painted_entities.erase(key)
    var entity := (
        EntityFactory.spawn(
            "TIBERIUM_TREE",
            {"world_pos": editor._cell_world_pos(cell), "detached": true, "parent": editor}
        )
        as Node3D
    )
    if not entity:
        return
    var data: Dictionary = {"id": "TIBERIUM_TREE"}
    editor._painted_entities[key] = {"node": entity, "data": data}
