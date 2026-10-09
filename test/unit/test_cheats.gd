extends Node

# Cheats seam tests — the shared, node-free debug cheat-flag state and the
# DebugMenu panel that writes it.

const DEBUG_MENU_SCENE: PackedScene = preload("res://scenes/ui/DebugMenu.tscn")


func test_flags_default_false_after_reset() -> void:
    Cheats.reset()
    TestHelper.assert_true(not Cheats.no_prereqs, "no_prereqs defaults false")
    TestHelper.assert_true(not Cheats.no_build_time, "no_build_time defaults false")
    TestHelper.assert_true(not Cheats.no_cost, "no_cost defaults false")
    TestHelper.assert_true(not Cheats.place_anywhere, "place_anywhere defaults false")


func test_reset_clears_set_flags() -> void:
    Cheats.no_prereqs = true
    Cheats.no_build_time = true
    Cheats.no_cost = true
    Cheats.place_anywhere = true
    Cheats.reset()
    TestHelper.assert_true(not Cheats.no_prereqs, "reset clears no_prereqs")
    TestHelper.assert_true(not Cheats.no_build_time, "reset clears no_build_time")
    TestHelper.assert_true(not Cheats.no_cost, "reset clears no_cost")
    TestHelper.assert_true(not Cheats.place_anywhere, "reset clears place_anywhere")


func test_flag_is_node_free() -> void:
    # No panel is needed to set or read the state: it lives on the class, so a
    # release build (no panel) reads false for every flag.
    Cheats.reset()
    Cheats.no_prereqs = true
    TestHelper.assert_true(Cheats.no_prereqs, "a flag set reads back with no panel present")
    Cheats.reset()
    TestHelper.assert_true(not Cheats.no_prereqs, "reset clears the flag with no panel present")


func test_panel_writes_flags_and_reset_state_clears() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var menu := DEBUG_MENU_SCENE.instantiate() as DebugMenu
    tree.root.add_child(menu)
    menu.cb_no_cost.button_pressed = true
    TestHelper.assert_true(Cheats.no_cost, "toggling the no-cost checkbox writes Cheats.no_cost")
    Cheats.no_prereqs = true
    menu.reset_state()
    TestHelper.assert_true(not Cheats.no_prereqs, "reset_state clears no_prereqs")
    TestHelper.assert_true(not Cheats.no_cost, "reset_state clears no_cost")
    menu.free()
