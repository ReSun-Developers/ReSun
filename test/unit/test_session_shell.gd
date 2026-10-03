extends Node

# UI session shell — exactly one GUI surface is mounted at a time, chosen by
# session mode: the process-level menu or the match-scoped HUD. Switching
# detaches and frees the previous surface.

const SESSION_SHELL_SCRIPT: GDScript = preload("res://scripts/ui/SessionShell.gd")


func _shell() -> Node:
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    var shell: Node = SESSION_SHELL_SCRIPT.new()
    shell.name = "SessionShellTestNode"
    tree.root.add_child(shell)
    return shell


func _drop(shell: Node) -> void:
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    if is_instance_valid(shell):
        tree.root.remove_child(shell)
        shell.free()


func test_starts_in_menu_mode_with_the_menu_surface():
    var shell := _shell()

    TestHelper.assert_eq(
        shell.get_mode(), SESSION_SHELL_SCRIPT.Mode.MENU, "shell starts in menu mode"
    )
    var surface: Node = shell.get_surface()
    TestHelper.assert_true(surface != null, "a surface is mounted at start")
    TestHelper.assert_eq(surface.name, "MenuSurface", "the menu surface is mounted")
    TestHelper.assert_eq(shell.get_child_count(), 1, "exactly one surface is mounted")

    _drop(shell)


func test_match_mode_replaces_the_menu_surface():
    var shell := _shell()
    var menu_surface: Node = shell.get_surface()

    shell.show_match()

    TestHelper.assert_eq(
        shell.get_mode(), SESSION_SHELL_SCRIPT.Mode.MATCH, "show_match switches mode"
    )
    var surface: Node = shell.get_surface()
    TestHelper.assert_true(surface != null, "a surface is mounted after the switch")
    TestHelper.assert_eq(surface.name, "HudSurface", "the HUD surface is mounted")
    TestHelper.assert_eq(shell.get_child_count(), 1, "exactly one surface is mounted")
    TestHelper.assert_true(menu_surface.get_parent() == null, "the menu surface is detached")
    TestHelper.assert_true(menu_surface.is_queued_for_deletion(), "the menu surface is freed")

    _drop(shell)


func test_match_hud_contains_sidebar_and_minimap():
    var shell := _shell()

    shell.show_match()

    var surface: Node = shell.get_surface()
    TestHelper.assert_true(surface != null, "the HUD surface is mounted")
    if surface != null:
        TestHelper.assert_true(
            surface.get_node_or_null("Sidebar") != null, "the HUD surface contains the sidebar"
        )
        TestHelper.assert_true(
            surface.get_node_or_null("Minimap") != null, "the HUD surface contains the minimap"
        )

    _drop(shell)


func test_switching_back_to_menu_restores_the_menu_only():
    var shell := _shell()
    shell.show_match()
    var hud_surface: Node = shell.get_surface()

    shell.show_menu()

    TestHelper.assert_eq(
        shell.get_mode(), SESSION_SHELL_SCRIPT.Mode.MENU, "show_menu switches back to menu mode"
    )
    var surface: Node = shell.get_surface()
    TestHelper.assert_eq(surface.name, "MenuSurface", "the menu surface is mounted again")
    TestHelper.assert_eq(shell.get_child_count(), 1, "exactly one surface is mounted")
    TestHelper.assert_true(hud_surface.get_parent() == null, "the HUD surface is detached")

    _drop(shell)
