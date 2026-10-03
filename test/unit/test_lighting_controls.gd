extends Node

# Lighting controls wiring tests (#298): within a real MapBase01 scene, the
# Debug panel must lazily resolve the LightingControls node (which readies
# after the panel) and wire its sliders so a UI slider change propagates to
# the live scene light / world environment nodes.

const MAP_BASE_SCENE: PackedScene = preload("res://scenes/maps/MapBase01.tscn")
const HUD_SURFACE_SCENE: PackedScene = preload("res://scenes/ui/HudSurface.tscn")


func _tree() -> SceneTree:
    return Engine.get_main_loop() as SceneTree


func _make_map() -> Node:
    var map := MAP_BASE_SCENE.instantiate()
    _tree().root.add_child(map)
    return map


## The in-game HUD is a separate surface (a peer of the World root), not part of
## the map scene, so the Debug panel is instantiated from the HUD surface.
func _make_hud() -> Node:
    var hud := HUD_SURFACE_SCENE.instantiate()
    _tree().root.add_child(hud)
    return hud


func _cleanup(map: Node, hud: Node = null) -> void:
    # Detached nodes are freed immediately (not queue_free): a deferred DebugMenu
    # would keep its `node_added` connection and mutate global state in later
    # suites, and a deferred map would keep a Camera in the root viewport.
    if is_instance_valid(hud):
        _tree().root.remove_child(hud)
        hud.free()
    if is_instance_valid(map):
        var lc := map.get_node_or_null("LightingControls") as Node
        if lc:
            lc.remove_from_group("lighting_controls")
        _tree().root.remove_child(map)
        map.free()


func _open_lighting(dbg: Node) -> Control:
    # Clicking the Lighting header toggles the section and wires the sliders.
    var lighting_content := dbg.get("lighting_content") as Control
    dbg.call("_toggle_section", lighting_content)
    return lighting_content


func test_group_registered_after_full_ready() -> void:
    var map := _make_map()
    var lc := map.get_node_or_null("LightingControls") as Node
    TestHelper.assert_true(is_instance_valid(lc), "MapBase01 contains LightingControls")
    var grouped := _tree().get_first_node_in_group("lighting_controls")
    TestHelper.assert_true(grouped != null, "LightingControls registers in its group after _ready")
    TestHelper.assert_true(grouped == lc, "group holds the scene's LightingControls")
    var dir_light := map.get_node_or_null("LightPivot/DirectionalLight3D")
    (
        TestHelper
        . assert_true(
            is_instance_valid(dir_light),
            "LightingControls resolved its DirectionalLight3D",
        )
    )
    (
        TestHelper
        . assert_true(
            is_instance_valid(map.get_node_or_null("WorldEnvironment")),
            "LightingControls resolved its WorldEnvironment",
        )
    )
    _cleanup(map)


func test_sun_intensity_slider_drives_scene_light() -> void:
    var map := _make_map()
    var hud := _make_hud()
    var dbg := hud.get_node_or_null("DebugMenu") as Node
    if not is_instance_valid(dbg):
        TestHelper.fail("the match HUD surface contains DebugMenu")
        _cleanup(map, hud)
        return
    var lighting_content := _open_lighting(dbg)
    var slider := lighting_content.get_node_or_null("SunIntensitySlider") as Slider
    if slider == null:
        TestHelper.fail("sun-intensity slider present")
        _cleanup(map, hud)
        return
    slider.emit_signal("value_changed", 2.5)
    var dir_light := map.get_node_or_null("LightPivot/DirectionalLight3D") as DirectionalLight3D
    (
        TestHelper
        . assert_true(
            is_instance_valid(dir_light) and absf(dir_light.light_energy - 2.5) < 0.001,
            "Dragging sun-intensity reaches DirectionalLight3D.light_energy",
        )
    )
    _cleanup(map, hud)


func test_fog_density_slider_drives_environment() -> void:
    var map := _make_map()
    var hud := _make_hud()
    var dbg := hud.get_node_or_null("DebugMenu") as Node
    if not is_instance_valid(dbg):
        TestHelper.fail("the match HUD surface contains DebugMenu")
        _cleanup(map, hud)
        return
    var world_env := map.get_node_or_null("WorldEnvironment") as WorldEnvironment
    if not is_instance_valid(world_env):
        TestHelper.fail("MapBase01 has a WorldEnvironment")
        _cleanup(map, hud)
        return
    world_env.environment.fog_density = 0.0
    var lighting_content := _open_lighting(dbg)
    var slider := lighting_content.get_node_or_null("FogDensitySlider") as Slider
    if slider == null:
        TestHelper.fail("fog-density slider present")
        _cleanup(map, hud)
        return
    slider.emit_signal("value_changed", 0.005)
    (
        TestHelper
        . assert_true(
            absf(world_env.environment.fog_density - 0.005) < 0.0000001,
            "Dragging fog-density moves WorldEnvironment fog density",
        )
    )
    _cleanup(map, hud)
