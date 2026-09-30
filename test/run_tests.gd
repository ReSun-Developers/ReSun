extends SceneTree

# Test runner — no framework, no class_name dependencies
# Usage: redot --headless -s test/run_tests.gd [-- --tap]
# Tests report through TestHelper only; the runner owns all output.

var _is_tap := false
var _suites: Array[Dictionary] = []
var _records: Array[Dictionary] = []
var _total_passed := 0
var _total_failed := 0
var _total_asserts := 0
var _total_duration_usec := 0


func _init() -> void:
    _parse_args()
    if _is_tap:
        print("TAP version 14")
    else:
        print("=== ReSun Test Suite ===\n")

    # Wait for autoloads to be available
    var max_wait := 60
    var waited := 0
    while waited < max_wait:
        var tree_root: Node = get_root()
        if tree_root and tree_root.has_node("TerrainSystem"):
            break
        await create_timer(0.1).timeout
        waited += 1

    _discover_and_run_tests()
    _render_results()
    quit(1 if _total_failed > 0 else 0)


func _parse_args() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg == "--tap":
            _is_tap = true


func _discover_and_run_tests() -> void:
    var dirs := ["res://test/unit/", "res://test/integration/"]
    for dir_path in dirs:
        var files: Array[String] = []
        var dir := DirAccess.open(dir_path)
        if not dir:
            continue
        dir.list_dir_begin()
        var file_name: String = dir.get_next()
        while file_name != "":
            if file_name.begins_with("test_") and file_name.ends_with(".gd"):
                files.append(file_name)
            file_name = dir.get_next()
        dir.list_dir_end()
        # Suites leak process-wide singleton state, so results depend on which
        # suites ran before them — run in sorted order on every machine.
        files.sort()
        for sorted_name in files:
            _run_test_file(dir_path + sorted_name)


func _run_test_file(path: String) -> void:
    var script: GDScript = load(path)
    if not script:
        print("ERROR: Cannot load " + path)
        _total_failed += 1
        return

    var obj: Object = script.new()
    var suite_name: String = path.get_file().get_basename()
    var suite_passed := 0
    var suite_failed := 0
    var suite_asserts := 0
    var suite_start := Time.get_ticks_usec()
    var started_any := false

    _inject_autoloads(obj)

    for m in script.get_script_method_list():
        var method_name: String = m["name"]
        if not method_name.begins_with("test_"):
            continue
        var test_start := Time.get_ticks_usec()
        TestHelper.reset()
        obj.call(method_name)
        var passed := TestHelper._passed
        var failed := TestHelper._failed
        var asserts := passed + failed
        var duration_usec := Time.get_ticks_usec() - test_start
        (
            _records
            . append(
                {
                    "suite": suite_name,
                    "path": path,
                    "name": method_name,
                    "passed": passed,
                    "failed": failed,
                    "asserts": asserts,
                    "duration_usec": duration_usec,
                    "errors": TestHelper._errors.duplicate(),
                }
            )
        )
        _total_passed += passed
        _total_failed += failed
        _total_asserts += asserts
        _total_duration_usec += duration_usec
        suite_passed += passed
        suite_failed += failed
        suite_asserts += asserts
        started_any = true

    obj.free()

    if started_any:
        (
            _suites
            . append(
                {
                    "name": suite_name,
                    "path": path,
                    "passed": suite_passed,
                    "failed": suite_failed,
                    "asserts": suite_asserts,
                    "duration_usec": Time.get_ticks_usec() - suite_start,
                }
            )
        )


func _inject_autoloads(obj: Object) -> void:
    var tree_root: Node = get_root()
    if tree_root == null:
        return
    for child in tree_root.get_children():
        var child_name: String = child.name
        if child_name == "GameContext":
            obj.set("_gc", child)
        elif child_name == "TerrainSystem":
            obj.set("_ts", child)
        elif child_name == "EntityFactory":
            obj.set("_ef", child)
        elif child_name == "TerrainCatalog":
            obj.set("_tc", child)
        elif child_name == "SpatialHashSingleton":
            obj.set("_sh", child)
        elif child_name == "SelectionManager":
            obj.set("_sm", child)
        elif child_name == "BuildingManager":
            obj.set("_bm", child)
        elif child_name == "EconomyManager":
            obj.set("_em", child)
        elif child_name == "PlayerManager":
            obj.set("_pm", child)
        elif child_name == "FactionCatalog":
            obj.set("_fc", child)
        elif child_name == "CampaignCatalog":
            obj.set("_cc", child)
        elif child_name == "AudioManager":
            obj.set("_am", child)
        elif child_name == "ShroudSystem":
            obj.set("_ss", child)


func _render_results() -> void:
    if _is_tap:
        _render_tap()
    else:
        _render_console()
    _render_ci()


func _suite_records(suite_name: String) -> Array:
    var out: Array = []
    for rec in _records:
        if rec["suite"] == suite_name:
            out.append(rec)
    return out


func _render_console() -> void:
    for suite in _suites:
        print("--- %s (%s) ---" % [suite["name"], _format_secs(suite["duration_usec"])])
        for rec in _suite_records(suite["name"]):
            var status := "PASS" if rec["failed"] == 0 else "FAIL"
            print(
                (
                    "  %s %s (%d asserts, %s)"
                    % [rec["name"], status, rec["asserts"], _format_ms(rec["duration_usec"])]
                )
            )
        print(
            (
                "  suite: %d passed, %d failed · %d asserts (%s)\n"
                % [
                    suite["passed"],
                    suite["failed"],
                    suite["asserts"],
                    _format_secs(suite["duration_usec"]),
                ]
            )
        )
    print(
        (
            "=== Results: %d passed, %d failed · %d asserts · %s ==="
            % [
                _total_passed,
                _total_failed,
                _total_asserts,
                _format_secs(_total_duration_usec),
            ]
        )
    )
    if _total_failed > 0:
        print("\nFAILURES:")
        for rec in _records:
            if rec["failed"] > 0:
                print("  %s::%s" % [rec["suite"], rec["name"]])
                for err in rec["errors"]:
                    print("    " + err)


func _render_tap() -> void:
    var suite_count: int = _suites.size()
    var index := 1
    for suite in _suites:
        var recs := _suite_records(suite["name"])
        print("# Subtest: %s" % suite["name"])
        print("    1..%d" % recs.size())
        for j in recs.size():
            var rec: Dictionary = recs[j]
            var status := "ok" if rec["failed"] == 0 else "not ok"
            print("    %s %d - %s" % [status, j + 1, _tap_escape(rec["name"])])
            if rec["failed"] > 0:
                for err in rec["errors"]:
                    print("      ---")
                    print("      message: '%s'" % _yaml_escape(err))
                    print("      severity: fail")
                    print("      ...")
        var suite_status := "ok" if suite["failed"] == 0 else "not ok"
        print("%s %d - %s" % [suite_status, index, suite["name"]])
        index += 1
    print("1..%d" % suite_count)


func _render_ci() -> void:
    if OS.get_environment("GITHUB_ACTIONS") != "true":
        return
    if not _is_tap:
        for rec in _records:
            if rec["failed"] > 0:
                var rel: String = String(rec["path"]).trim_prefix("res://")
                print("::error file=%s::%s failed" % [rel, rec["name"]])
    var summary_path := OS.get_environment("GITHUB_STEP_SUMMARY")
    if summary_path == "":
        return
    var f := FileAccess.open(summary_path, FileAccess.WRITE)
    if not f:
        return
    f.store_line("## Test Results")
    f.store_line("")
    f.store_line("| Suite | Test | Status | Asserts | Duration |")
    f.store_line("|---|---|---|---|---|")
    for rec in _records:
        var status := "PASS" if rec["failed"] == 0 else "FAIL"
        (
            f
            . store_line(
                (
                    "| %s | %s | %s | %d | %s |"
                    % [
                        rec["suite"],
                        rec["name"],
                        status,
                        rec["asserts"],
                        _format_ms(rec["duration_usec"]),
                    ]
                )
            )
        )
    f.close()


func _format_secs(usec: int) -> String:
    return "%.3fs" % (usec / 1000000.0)


func _format_ms(usec: int) -> String:
    return "%dms" % (usec / 1000)


func _tap_escape(s: String) -> String:
    s = s.replace("\\", "\\\\")
    s = s.replace("#", "\\#")
    return s


func _yaml_escape(s: String) -> String:
    return s.replace("\\", "\\\\").replace("'", "''")
