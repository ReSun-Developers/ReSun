extends Node

# GraphicsSettings unit tests — schema/presets, persistence, AA/shadow/env apply.

const SCRATCH_CONFIG: String = "user://test_graphics_settings_scratch.cfg"


func _get_gs() -> Node:
    var tree := Engine.get_main_loop() as SceneTree
    if not tree:
        return null
    return tree.root.get_node_or_null("GraphicsSettings")


func _remove_scratch() -> void:
    if FileAccess.file_exists(SCRATCH_CONFIG):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CONFIG))


func _redirect(gs: Node) -> String:
    _remove_scratch()
    var saved: String = gs._config_path
    gs._config_path = SCRATCH_CONFIG
    return saved


func _restore(gs: Node, saved: String) -> void:
    gs._config_path = saved
    _remove_scratch()
    gs._load()


func test_schema_fields_present_in_every_preset():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    for preset: String in gs.PRESETS:
        for field: String in gs.schema():
            TestHelper.assert_true(
                gs.PRESETS[preset].has(field), "%s preset defines %s" % [preset, field]
            )


func test_display_fields_are_separate_from_presets():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    TestHelper.assert_true(gs.display_schema().has("window_mode"), "display has window mode")
    TestHelper.assert_true(gs.display_schema().has("resolution"), "display has resolution")
    for field: String in gs.schema():
        TestHelper.assert_true(
            not gs.display_schema().has(field), "%s is not a display field" % field
        )
    for preset: String in gs.PRESETS:
        TestHelper.assert_true(
            not gs.PRESETS[preset].has("resolution"), "presets never set resolution"
        )


func test_low_preset_excludes_expensive_features():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var low: Dictionary = gs.PRESETS["low"]
    TestHelper.assert_eq(low["gi"], "off", "Low GI off")
    TestHelper.assert_eq(low["aa"], "off", "Low AA off")
    TestHelper.assert_eq(low["shadow_quality"], "off", "Low shadow quality off")
    TestHelper.assert_eq(low["cloud_shadows"], false, "Low cloud shadows off")


func test_fresh_install_defaults_to_low():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var saved := _redirect(gs)
    gs._load()
    TestHelper.assert_eq(gs.current_preset(), "low", "fresh install preset is low")
    TestHelper.assert_eq(gs.get_value("gi"), "off", "fresh install GI off")
    TestHelper.assert_eq(gs.get_value("shadow_quality"), "off", "fresh install shadow off")
    _restore(gs, saved)


func test_field_round_trip_through_config():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var saved := _redirect(gs)
    gs._load()
    gs.set_value("aa", "smaa")
    gs.set_value("exposure", 1.5)
    gs.set_value("window_mode", "borderless")
    gs._load()
    TestHelper.assert_eq(gs.get_value("aa"), "smaa", "aa persisted")
    TestHelper.assert_eq(gs.get_value("exposure"), 1.5, "exposure persisted")
    TestHelper.assert_eq(gs.get_value("window_mode"), "borderless", "window mode persisted")
    _restore(gs, saved)


func test_matching_preset_reports_custom_after_edit():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var saved := _redirect(gs)
    gs.apply_preset("high")
    TestHelper.assert_eq(gs.matching_preset(), "high", "matching preset identified")
    gs.set_value("aa", "off")
    TestHelper.assert_eq(gs.matching_preset(), "custom", "divergent values report custom")
    _restore(gs, saved)


func test_invalid_values_are_rejected_or_clamped():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var saved := _redirect(gs)
    gs._load()
    gs.set_value("aa", "not_a_mode")
    TestHelper.assert_eq(gs.get_value("aa"), "off", "invalid enum ignored")
    gs.set_value("exposure", 99.0)
    TestHelper.assert_eq(gs.get_value("exposure"), 4.0, "exposure clamped to max")
    gs.set_value("window_mode", "nonsense")
    TestHelper.assert_eq(gs.get_value("window_mode"), "windowed", "invalid window mode ignored")
    gs.set_value("resolution", "not-a-size")
    TestHelper.assert_eq(gs.get_value("resolution"), "1920x1080", "invalid resolution ignored")
    _restore(gs, saved)


func test_resolution_options_include_current_value():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var saved := _redirect(gs)
    gs._load()
    var current := String(gs.get_value("resolution"))
    TestHelper.assert_true(gs.resolution_options().has(current), "current resolution is selectable")
    _restore(gs, saved)


func test_boot_application_notifies_once():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var saved := _redirect(gs)
    var count := [0]
    var cb := func(_changed: PackedStringArray) -> void: count[0] += 1
    gs.settings_changed.connect(cb)
    gs._boot_applied = false
    gs._reapply_now()
    gs.settings_changed.disconnect(cb)
    TestHelper.assert_eq(count[0], 1, "boot application fires one notification")
    _restore(gs, saved)


func test_preset_survives_reload():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var saved := _redirect(gs)
    gs.apply_preset("ultra")
    gs._load()
    TestHelper.assert_eq(gs.current_preset(), "ultra", "preset name persisted")
    TestHelper.assert_eq(gs.get_value("gi"), "high", "ultra GI persisted")
    TestHelper.assert_eq(gs.get_value("aa"), "smaa_msaa", "ultra AA persisted")
    _restore(gs, saved)


func test_preset_notifies_once():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var saved := _redirect(gs)
    var count := [0]
    var cb := func(_changed: PackedStringArray) -> void: count[0] += 1
    gs.settings_changed.connect(cb)
    gs.apply_preset("high")
    gs.settings_changed.disconnect(cb)
    TestHelper.assert_eq(count[0], 1, "preset application fires one notification")
    TestHelper.assert_eq(gs.get_value("gi"), "sdfgi", "high preset GI sdfgi")
    TestHelper.assert_eq(gs.get_value("cloud_shadows"), true, "high preset cloud shadows on")
    _restore(gs, saved)


func test_antialiasing_maps_to_viewport():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var saved := _redirect(gs)
    var vp := gs.get_viewport()
    gs.set_value("aa", "msaa4x")
    TestHelper.assert_eq(vp.msaa_3d, Viewport.MSAA_4X, "MSAA 4x sets msaa_3d")
    TestHelper.assert_eq(
        vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED, "MSAA 4x disables SMAA"
    )
    gs.set_value("aa", "smaa")
    TestHelper.assert_eq(
        vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_SMAA, "SMAA sets screen-space AA"
    )
    gs.set_value("aa", "off")
    TestHelper.assert_eq(vp.msaa_3d, Viewport.MSAA_DISABLED, "Off disables msaa_3d")
    TestHelper.assert_eq(
        vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED, "Off disables screen-space AA"
    )
    _restore(gs, saved)


func test_restart_only_classification():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    TestHelper.assert_true(gs.is_restart_only("texture_quality"), "texture quality is restart-only")
    TestHelper.assert_true(not gs.is_restart_only("shadow_quality"), "shadow quality is live")
    TestHelper.assert_true(not gs.is_restart_only("aa"), "aa is live")


func test_shadow_quality_applies_live():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var saved := _redirect(gs)
    var tree := Engine.get_main_loop() as SceneTree
    var light := DirectionalLight3D.new()
    tree.root.add_child(light)
    gs.set_value("shadow_quality", "high")
    TestHelper.assert_true(light.shadow_enabled, "high enables shadows")
    TestHelper.assert_eq(light.directional_shadow_mode, 0, "high uses orthogonal mode")
    gs.set_value("shadow_quality", "off")
    TestHelper.assert_true(not light.shadow_enabled, "off disables shadows")
    tree.root.remove_child(light)
    light.free()
    _restore(gs, saved)


func test_environment_applies_gi_and_tonemap():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var saved := _redirect(gs)
    var tree := Engine.get_main_loop() as SceneTree
    var we := WorldEnvironment.new()
    we.environment = Environment.new()
    tree.root.add_child(we)
    gs.set_value("gi", "high")
    gs.set_value("tonemap", "aces")
    TestHelper.assert_true(we.environment.sdfgi_enabled, "high GI enables SDFGI")
    TestHelper.assert_eq(
        we.environment.tonemap_mode, Environment.TONE_MAPPER_ACES, "ACES tonemap applied"
    )
    gs.set_value("gi", "off")
    TestHelper.assert_true(not we.environment.sdfgi_enabled, "off disables SDFGI")
    tree.root.remove_child(we)
    we.free()
    _restore(gs, saved)


func test_preset_reapplies_when_environment_scene_loads():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var saved := _redirect(gs)
    var tree := Engine.get_main_loop() as SceneTree
    gs.apply_preset("low")
    var env_scene: PackedScene = load("res://scenes/environment/DefaultWorldEnvironment01.tscn")
    var env_node: Node = env_scene.instantiate()
    tree.root.add_child(env_node)
    var we := env_node as WorldEnvironment
    TestHelper.assert_true(
        not we.environment.sdfgi_enabled, "low preset overrides SDFGI=true scene default on load"
    )
    var light_scene: PackedScene = load("res://scenes/environment/DefaultSunLight01.tscn")
    var light_node: Node = light_scene.instantiate()
    tree.root.add_child(light_node)
    var lights := light_node.find_children("*", "DirectionalLight3D", true, false)
    TestHelper.assert_true(not lights.is_empty(), "light scene has a DirectionalLight3D")
    if not lights.is_empty():
        (
            TestHelper
            . assert_true(
                not (lights[0] as DirectionalLight3D).shadow_enabled,
                "low preset disables the scene default shadow on load",
            )
        )
    tree.root.remove_child(env_node)
    env_node.free()
    tree.root.remove_child(light_node)
    light_node.free()
    _restore(gs, saved)
