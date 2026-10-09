extends Node

# Cheats seam guard — the four cheat flags live on `Cheats`. The `debug_menu`
# node group may only be read for panel-presentation state (`_is_open`) by
# `UIUtil` and the FPS counter. Any other read must go through `Cheats`, so a
# simulation or UI system never depends on the panel node.
#
# Scope: `scripts/**/*.gd`. The scan matches a group lookup by name
# (`get_first_node_in_group` / `get_nodes_in_group`, quoted or StringName) and
# allows it only in the two presentation files listed below.

const SCRIPTS_ROOT := "res://scripts/"
const MIN_SCANNED_FILES := 100
const GROUP_LOOKUP_PATTERN := "get_(?:first_)?nodes?_in_group\\s*\\(\\s*&?[\"']debug_menu[\"']"
const ALLOWED_FILES := ["scripts/core/UIUtil.gd", "scripts/ui/FPSCounterLabel01.gd"]

var _scanned_files := 0


func test_scan_visits_the_script_tree() -> void:
    _scanned_files = 0
    _scan_dir(SCRIPTS_ROOT, [])
    (
        TestHelper
        . assert_true(
            _scanned_files >= MIN_SCANNED_FILES,
            (
                "scan visited only %d .gd files — the guard is not exercising scripts/"
                % _scanned_files
            ),
        )
    )


func test_no_group_lookup_outside_presentation_files() -> void:
    _scanned_files = 0
    var violations: Array[String] = []
    _scan_dir(SCRIPTS_ROOT, violations)
    var detail := "none" if violations.is_empty() else "\n".join(violations)
    TestHelper.assert_true(
        violations.is_empty(), "debug_menu group lookups outside allowed files:\n" + detail
    )


func test_scanner_flags_a_planted_lookup() -> void:
    var dir := "user://cheats_seam_guard_planted"
    var path := dir.path_join("planted.gd")
    _prepare_fixture(dir, path)
    _write_text(
        path,
        "func f() -> void:\n" + '    var x := get_tree().get_first_node_in_group("debug_menu")\n',
    )
    _scanned_files = 0
    var violations: Array[String] = []
    _scan_dir(dir, violations)
    TestHelper.assert_eq(_scanned_files, 1, "scanner must visit the planted file")
    TestHelper.assert_eq(violations.size(), 1, "planted group lookup must be flagged")
    (
        TestHelper
        . assert_true(
            violations.size() == 1 and violations[0].contains("planted.gd:2"),
            "violation must name the file and line",
        )
    )
    _cleanup_fixture(dir, path)


func test_scanner_sees_a_wrapped_lookup() -> void:
    var dir := "user://cheats_seam_guard_wrapped"
    var path := dir.path_join("wrapped.gd")
    _prepare_fixture(dir, path)
    _write_text(
        path,
        (
            "func f() -> void:\n"
            + "    var x := get_nodes_in_group(\n"
            + '        &"debug_menu"\n'
            + "    )\n"
        ),
    )
    _scanned_files = 0
    var violations: Array[String] = []
    _scan_dir(dir, violations)
    TestHelper.assert_eq(violations.size(), 1, "a wrapped StringName lookup must be flagged")
    _cleanup_fixture(dir, path)


func _scan_dir(path: String, violations: Array[String]) -> void:
    var dir := DirAccess.open(path)
    if dir == null:
        return
    dir.list_dir_begin()
    var entry := dir.get_next()
    while entry != "":
        var full := path.path_join(entry)
        if dir.current_is_dir():
            if not entry.begins_with("."):
                _scan_dir(full, violations)
        elif entry.ends_with(".gd"):
            _scan_file(full, violations)
        entry = dir.get_next()
    dir.list_dir_end()


func _scan_file(path: String, violations: Array[String]) -> void:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        violations.append("%s: unreadable — scan incomplete" % _rel(path))
        return
    _scanned_files += 1
    var text := ""
    while f.get_position() < f.get_length():
        var line := f.get_line()
        # Blank comment lines to keep line numbers while ignoring prose matches.
        text += ("" if line.strip_edges().begins_with("#") else line) + "\n"
    f.close()
    if _rel(path) in ALLOWED_FILES:
        return
    var re := RegEx.new()
    if re.compile(GROUP_LOOKUP_PATTERN) != OK:
        violations.append("%s: guard regex failed to compile" % _rel(path))
        return
    for m in re.search_all(text):
        var line_no := text.substr(0, m.get_start()).count("\n") + 1
        violations.append("%s:%d: debug_menu group lookup" % [_rel(path), line_no])


func _rel(path: String) -> String:
    return path.trim_prefix("res://")


func _prepare_fixture(dir: String, path: String) -> void:
    _cleanup_fixture(dir, path)
    DirAccess.make_dir_recursive_absolute(dir)


func _write_text(path: String, content: String) -> void:
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f:
        f.store_string(content)
        f.close()


func _cleanup_fixture(dir: String, path: String) -> void:
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
