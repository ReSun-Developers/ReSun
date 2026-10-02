extends Node

# Autoload access guard — a registered autoload must be resolved by its global
# identifier, never through an absolute get_node("/root/<Name>") string path.
# The autoload names are parsed from project.godot so the scan stays in sync
# with the registry instead of hardcoding a list here.
#
# Scope: `scripts/**/*.gd`. Deliberately out of scope:
#   - `.tscn` node paths (none currently reference an autoload),
#   - nullable lazy accessors that resolve a child of the root by bare name,
#     e.g. `tree.root.get_node_or_null("<Autoload>")`. That pattern is
#     intentional in static helpers and is tracked as a separate follow-up.
# The scan therefore matches the `/root/` absolute form only.

const PROJECT_GODOT := "res://project.godot"
const SCRIPTS_ROOT := "res://scripts/"
const MIN_SCANNED_FILES := 100
const ROOT_LOOKUP_PATTERN := 'get_node(?:_or_null)?\\s*\\(\\s*"/root/([A-Za-z_][A-Za-z0-9_]*)'

var _scanned_files := 0


func test_autoload_names_are_discovered():
    var names := _autoload_names()
    TestHelper.assert_true(
        names.size() >= 30, "project.godot should declare the autoloads (got %d)" % names.size()
    )
    TestHelper.assert_true(names.has("GameContext"), "parser must find GameContext")
    TestHelper.assert_true(names.has("EconomyManager"), "parser must find EconomyManager")


func test_scan_visits_the_script_tree():
    _scanned_files = 0
    _scan_dir(SCRIPTS_ROOT, _autoload_names(), [])
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


func test_no_autoload_resolved_by_root_string():
    _scanned_files = 0
    var violations: Array[String] = []
    _scan_dir(SCRIPTS_ROOT, _autoload_names(), violations)
    var detail := "none" if violations.is_empty() else "\n".join(violations)
    TestHelper.assert_true(violations.is_empty(), "autoload /root string lookups found:\n" + detail)


func test_scanner_flags_a_planted_lookup():
    var dir := "user://autoload_guard_planted"
    var path := dir.path_join("planted.gd")
    _prepare_fixture(dir, path)
    _write_text(path, 'func f() -> void:\n    var x := get_node_or_null("/root/PlayerManager")\n')
    _scanned_files = 0
    var violations: Array[String] = []
    _scan_dir(dir, PackedStringArray(["PlayerManager"]), violations)
    TestHelper.assert_eq(_scanned_files, 1, "scanner must visit the planted file")
    TestHelper.assert_eq(violations.size(), 1, "planted /root lookup must be flagged")
    (
        TestHelper
        . assert_true(
            violations.size() == 1 and violations[0].contains("planted.gd:2"),
            "violation must name the file and line",
        )
    )
    _cleanup_fixture(dir, path)


func test_scanner_sees_a_multiline_call():
    var dir := "user://autoload_guard_wrapped"
    var path := dir.path_join("wrapped.gd")
    _prepare_fixture(dir, path)
    _write_text(
        path,
        (
            "func f() -> void:\n"
            + "    var x := get_node_or_null(\n"
            + '        "/root/PlayerManager"\n'
            + "    )\n"
        ),
    )
    var violations: Array[String] = []
    _scan_dir(dir, PackedStringArray(["PlayerManager"]), violations)
    TestHelper.assert_eq(violations.size(), 1, "a wrapped /root lookup must still be flagged")
    _cleanup_fixture(dir, path)


func test_scanner_ignores_comments_and_scene_paths():
    var dir := "user://autoload_guard_clean"
    var path := dir.path_join("clean.gd")
    _prepare_fixture(dir, path)
    _write_text(
        path,
        (
            '# get_node("/root/PlayerManager") in a comment\n'
            + "func f() -> void:\n"
            + '    var c := get_node("/root/MainScene/Gameplay/Camera")\n'
        ),
    )
    var violations: Array[String] = []
    _scan_dir(dir, PackedStringArray(["PlayerManager"]), violations)
    TestHelper.assert_true(violations.is_empty(), "comments and scene paths must not be flagged")
    _cleanup_fixture(dir, path)


func _autoload_names() -> PackedStringArray:
    var names := PackedStringArray()
    var f := FileAccess.open(PROJECT_GODOT, FileAccess.READ)
    if f == null:
        return names
    var in_section := false
    while f.get_position() < f.get_length():
        var line := f.get_line().strip_edges()
        if line.begins_with("["):
            in_section = line == "[autoload]"
            continue
        if not in_section or line.is_empty() or line.begins_with(";"):
            continue
        var name := line.get_slice("=", 0).strip_edges()
        if not name.is_empty():
            names.append(name)
    f.close()
    return names


func _scan_dir(path: String, autoloads: PackedStringArray, violations: Array[String]) -> void:
    var dir := DirAccess.open(path)
    if dir == null:
        return
    dir.list_dir_begin()
    var entry := dir.get_next()
    while entry != "":
        var full := path.path_join(entry)
        if dir.current_is_dir():
            if not entry.begins_with("."):
                _scan_dir(full, autoloads, violations)
        elif entry.ends_with(".gd"):
            _scan_file(full, autoloads, violations)
        entry = dir.get_next()
    dir.list_dir_end()


func _scan_file(path: String, autoloads: PackedStringArray, violations: Array[String]) -> void:
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
    var re := RegEx.new()
    if re.compile(ROOT_LOOKUP_PATTERN) != OK:
        violations.append("%s: guard regex failed to compile" % _rel(path))
        return
    for m in re.search_all(text):
        var target := m.get_string(1)
        if autoloads.has(target):
            var line_no := text.substr(0, m.get_start()).count("\n") + 1
            violations.append("%s:%d: /root/%s" % [_rel(path), line_no, target])


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
