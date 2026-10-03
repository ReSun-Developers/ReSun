extends Node

const MASK_WIDTH := 1280
const MASK_HEIGHT := 720

var _sub_viewport: SubViewport
var _mask_camera: Camera3D
var _main_camera: Camera3D


func _ready() -> void:
    _create_mask_viewport()


func _process(_delta: float) -> void:
    _find_main_camera()
    if not is_instance_valid(_main_camera):
        return

    _setup_shared_world()
    _sync_mask_camera()


func _create_mask_viewport() -> void:
    _sub_viewport = SubViewport.new()
    _sub_viewport.name = "EntityMaskViewport"
    _sub_viewport.size = Vector2i(MASK_WIDTH, MASK_HEIGHT)
    _sub_viewport.transparent_bg = true
    _sub_viewport.disable_3d = false
    _sub_viewport.audio_listener_enable_3d = false
    _sub_viewport.handle_input_locally = false
    add_child(_sub_viewport)

    _mask_camera = Camera3D.new()
    _mask_camera.name = "MaskCamera3D"
    _mask_camera.cull_mask = 0b10
    _mask_camera.current = true
    _sub_viewport.add_child(_mask_camera)


func get_mask_texture() -> ViewportTexture:
    return _sub_viewport.get_texture()


func _setup_shared_world() -> void:
    if is_instance_valid(_sub_viewport.world_3d):
        return
    var main_viewport := get_viewport()
    if not is_instance_valid(main_viewport):
        return
    var world := main_viewport.world_3d as World3D
    if not is_instance_valid(world):
        return
    _sub_viewport.world_3d = world


func _find_main_camera() -> void:
    if is_instance_valid(_main_camera):
        return
    var vp := get_viewport()
    if is_instance_valid(vp):
        _main_camera = vp.get_camera_3d()


func _sync_mask_camera() -> void:
    if not is_instance_valid(_main_camera):
        return
    _mask_camera.global_transform = _main_camera.global_transform
    _mask_camera.projection = _main_camera.projection
    _mask_camera.size = _main_camera.size
    _mask_camera.far = _main_camera.far
    _mask_camera.near = _main_camera.near
