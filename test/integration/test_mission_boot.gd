extends Node

# Mission boot integration — MissionMap loads the active mission's map JSON
# into gameplay and applies the mission's camera override on top of the map's
# own start-location framing. The expected start cell is read from the map
# JSON independently (never through the production framing helper).

const MISSION_MAP_SCENE: PackedScene = preload("res://scenes/maps/MissionMap.tscn")
const MISSION_BOOT_SCRIPT: GDScript = preload("res://scripts/maps/MissionBoot.gd")
const GDI01_MISSION_PATH: String = "res://games/ts/missions/gdi01.tres"
const GDI01_MAP_PATH: String = "res://games/ts/maps/gdi01.json"
const MISSING_MAP_PATH: String = "res://games/ts/maps/does_not_exist.json"
const CREDITS_MAP_PATH: String = "res://test/fixtures/maps/mission_map_credits.json"


## Minimal stand-in for the UI session shell: records that mission start asked
## for match mode without instantiating the real GUI surfaces.
class _StubSessionShell:
    extends Node

    var match_requested := false

    func show_match() -> void:
        match_requested = true


var _gc: Node = null
var _pm: Node = null


func _guard() -> bool:
    if _gc == null or _pm == null:
        TestHelper.fail("GameContext/PlayerManager not injected")
        return false
    return true


func _setup() -> Dictionary:
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    var root := Node3D.new()
    root.name = "MissionBootTestRoot"
    tree.root.add_child(root)
    var gameplay := Node3D.new()
    gameplay.name = "Gameplay"
    root.add_child(gameplay)
    var pivot := Node3D.new()
    pivot.name = "MissionBootTestPivot"
    tree.root.add_child(pivot)
    pivot.global_position = Vector3(0.0, 9.0, 0.0)
    var bounds: Node = tree.root.get_node_or_null("BoundsSystem")
    if bounds:
        bounds.camera_pivot = pivot
    _gc.select_game("ts")
    return {"tree": tree, "root": root, "gameplay": gameplay, "pivot": pivot, "bounds": bounds}


func _teardown(ctx: Dictionary) -> void:
    _gc.current_mission = null
    var tree: SceneTree = ctx["tree"]
    if ctx["bounds"]:
        ctx["bounds"].camera_pivot = null
    var root: Node = ctx["root"]
    if is_instance_valid(root):
        tree.root.remove_child(root)
        root.free()
    var pivot: Node = ctx["pivot"]
    if is_instance_valid(pivot):
        tree.root.remove_child(pivot)
        pivot.free()
    TerrainSystem.clear()
    TerrainSystem.init_grid(50, 50)
    _pm._players.clear()
    _pm._local_player_id = 0
    _pm._init_defaults()
    tree.paused = false


func _gdi01() -> Mission:
    var base := load(GDI01_MISSION_PATH) as Mission
    return base.duplicate() as Mission if base else null


func _add_mission_map(ctx: Dictionary, mission: Mission) -> Node3D:
    _gc.current_mission = mission
    var map: Node3D = MISSION_MAP_SCENE.instantiate()
    (ctx["gameplay"] as Node).add_child(map)
    return map


## Cells listed for `player_id` in the map JSON, read directly from the fixture.
func _map_start_cell(player_id: int) -> Vector2i:
    var file := FileAccess.open(GDI01_MAP_PATH, FileAccess.READ)
    if not file:
        return Vector2i(-999, -999)
    var json := JSON.parse_string(file.get_as_text()) as Dictionary
    file.close()
    if json == null:
        return Vector2i(-999, -999)
    for entry in json.get("start_locations", []):
        if int(entry.get("player_id", -1)) != player_id:
            continue
        var parts := (entry.get("cell", "") as String).split(",")
        if parts.size() == 2:
            return Vector2i(parts[0].to_int(), parts[1].to_int())
    return Vector2i(-999, -999)


func _count_map_entities(map: Node) -> int:
    var count := 0
    for child in map.get_children():
        if child.has_meta("house_id"):
            count += 1
    return count


## The gdi01 JSON entity list, read directly from the fixture (never through
## MapLoader) so expectations are independent of the loader.
func _json_entities() -> Array:
    var file := FileAccess.open(GDI01_MAP_PATH, FileAccess.READ)
    if not file:
        return []
    var json := JSON.parse_string(file.get_as_text()) as Dictionary
    file.close()
    if json == null:
        return []
    return json.get("entities", []) as Array


## Number of JSON entities that declare ownership (house_id) — the ones with a
## house_id meta after load.
func _count_json_owned() -> int:
    var count := 0
    for entry in _json_entities():
        if (entry as Dictionary).has("house_id"):
            count += 1
    return count


## Loaded entities carrying a component node of `component_name` (e.g.
## ResourceComponent for tiberium), counted among MissionMap's direct children.
func _count_loaded_with_component(map: Node, component_name: String) -> int:
    var count := 0
    for child in map.get_children():
        if child.has_node(component_name):
            count += 1
    return count


func _assert_centered(pivot: Node3D, cell: Vector2i, msg: String) -> void:
    var expected: Vector3 = CellUtil.cell_to_world(cell)
    var centered := (
        is_equal_approx(pivot.global_position.x, expected.x)
        and is_equal_approx(pivot.global_position.z, expected.z)
    )
    (
        TestHelper
        . assert_true(
            centered,
            (
                "%s — pivot=%s expected cell=%s world=%s"
                % [msg, pivot.global_position, cell, expected]
            ),
        )
    )


func test_mission_map_loads_entities_and_centers_camera() -> void:
    if not _guard():
        return
    var ctx := _setup()
    var mission := _gdi01()
    TestHelper.assert_true(mission != null, "gdi01 mission resource loads")
    var map := _add_mission_map(ctx, mission)
    TestHelper.assert_true(_gc.current_mission.id == "gdi01", "active mission remains gdi01")

    var owned_expected := _count_json_owned()
    TestHelper.assert_true(owned_expected > 0, "gdi01 JSON declares owned entities")
    (
        TestHelper
        . assert_eq(
            _count_map_entities(map),
            owned_expected,
            "every owned map entity is instantiated under MissionMap",
        )
    )
    (
        TestHelper
        . assert_true(
            _count_loaded_with_component(map, "ResourceComponent") > 0,
            "tiberium entities are instantiated under MissionMap",
        )
    )

    var start_cell := _map_start_cell(0)
    TestHelper.assert_true(
        start_cell != Vector2i(-999, -999), "gdi01 JSON lists a local-player start location"
    )
    _assert_centered(ctx["pivot"], start_cell, "empty home_cell frames the map start location")
    _teardown(ctx)


func test_home_cell_override_centers_camera() -> void:
    if not _guard():
        return
    var ctx := _setup()
    var mission := _gdi01()
    mission.home_cell = "10,20"
    mission.show_briefing = false
    _add_mission_map(ctx, mission)
    _assert_centered(ctx["pivot"], Vector2i(10, 20), "home_cell override centers the camera")
    _teardown(ctx)


func test_empty_home_cell_defers_to_map_start() -> void:
    if not _guard():
        return
    var ctx := _setup()
    var mission := _gdi01()
    mission.home_cell = ""
    mission.show_briefing = false
    _add_mission_map(ctx, mission)
    var start_cell := _map_start_cell(0)
    _assert_centered(ctx["pivot"], start_cell, "empty home_cell defers to the map start framing")
    _teardown(ctx)


func test_missing_map_leaves_gameplay_empty() -> void:
    if not _guard():
        return
    var ctx := _setup()
    var mission := Mission.new()
    mission.id = "missing_map"
    mission.map_path = MISSING_MAP_PATH
    mission.show_briefing = false
    var map := _add_mission_map(ctx, mission)
    TestHelper.assert_eq(_gc.current_mission.id, "missing_map", "active mission is unchanged")
    TestHelper.assert_eq(_count_map_entities(map), 0, "missing map creates no entities")
    _teardown(ctx)


func test_start_mission_via_boot_seam() -> void:
    if not _guard():
        return
    var ctx := _setup()
    var boot: Node = MISSION_BOOT_SCRIPT.new()
    (ctx["root"] as Node).add_child(boot)
    var emitted := [0]
    var handler := func(_m: Mission) -> void: emitted[0] += 1
    _gc.mission_started.connect(handler)
    _gc.start_mission("gdi01")
    TestHelper.assert_eq(_gc.current_mission.id, "gdi01", "start_mission sets the active mission")
    TestHelper.assert_eq(emitted[0], 1, "start_mission emits mission_started exactly once")
    var gameplay: Node = ctx["gameplay"]
    TestHelper.assert_eq(gameplay.get_child_count(), 1, "boot seam adds one World root to Gameplay")
    if gameplay.get_child_count() == 1:
        var world: Node = gameplay.get_child(0)
        TestHelper.assert_eq(world.name, "World", "the match is hosted in a World root")
        var map: Node = world.get_node_or_null("MissionMap")
        TestHelper.assert_true(map != null, "the map is hosted under the World root")
        if map != null:
            (
                TestHelper
                . assert_eq(
                    _count_map_entities(map),
                    _count_json_owned(),
                    "boot-loaded map has its owned entities",
                )
            )
    _gc.select_game("ts")
    TestHelper.assert_true(
        _gc.current_mission == null, "selecting a game clears the active mission"
    )
    _gc.mission_started.disconnect(handler)
    _teardown(ctx)


func test_unknown_mission_refused() -> void:
    if not _guard():
        return
    _gc.select_game("ts")
    var before: Mission = _gc.current_mission
    var emitted := [0]
    var handler := func(_m: Mission) -> void: emitted[0] += 1
    _gc.mission_started.connect(handler)
    _gc.start_mission("nope")
    TestHelper.assert_eq(emitted[0], 0, "unknown mission emits no mission_started")
    TestHelper.assert_true(
        _gc.current_mission == before, "unknown mission leaves current unchanged"
    )
    _gc.mission_started.disconnect(handler)


## Content guard for the placeholder mission map: it must stay a populated map
## (tiberium, terrain objects, a GDI base and Nod opposition), not regress to a
## bare construction yard. Reads the fixture directly.
func test_gdi01_placeholder_has_terrain_and_tiberium() -> void:
    var entities := _json_entities()
    TestHelper.assert_true(entities.size() > 20, "gdi01 has a populated entity set")
    var has_tiberium := false
    var has_tree := false
    var has_gdi := false
    var has_nod := false
    for entry in entities:
        var d := entry as Dictionary
        var id := String(d.get("id", ""))
        if id.begins_with("TIBERIUM_RIPARIUS"):
            has_tiberium = true
        elif id.begins_with("TIBERIUM_TREE"):
            has_tree = true
        var house := String(d.get("house_id", ""))
        if house == "GDI":
            has_gdi = true
        elif house == "Nod":
            has_nod = true
    TestHelper.assert_true(has_tiberium, "gdi01 places tiberium")
    TestHelper.assert_true(has_tree, "gdi01 places tiberium trees")
    TestHelper.assert_true(has_gdi, "gdi01 places GDI-owned content")
    TestHelper.assert_true(has_nod, "gdi01 places Nod-owned content")


## Drives the MissionBoot seam against a `_setup()` context: sets the active
## mission, attaches a boot node, and boots. Returns the MissionMap now hosted
## by Gameplay.
func _boot(ctx: Dictionary, mission: Mission) -> Node:
    _gc.current_mission = mission
    var boot: Node = MISSION_BOOT_SCRIPT.new()
    (ctx["root"] as Node).add_child(boot)
    boot._on_mission_started(mission)
    var gameplay: Node = ctx["gameplay"]
    if gameplay.get_child_count() == 0:
        return null
    var world: Node = gameplay.get_child(0)
    return world.get_node_or_null("MissionMap")


## Starting a mission must hand the UI off to the match surface, so the menu
## overlays are no longer shown (the --mission launch path would otherwise sit
## behind BootScreen). Surface mounting itself is covered by
## test_session_shell.gd; here we assert the boot seam requests match mode and
## hosts the match in a World root.
func test_mission_start_switches_session_to_match() -> void:
    if not _guard():
        return
    _gc.select_game("ts")
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    var root := Node.new()
    root.name = "MissionSessionTestRoot"
    tree.root.add_child(root)
    var gameplay := Node3D.new()
    gameplay.name = "Gameplay"
    root.add_child(gameplay)
    var shell := _StubSessionShell.new()
    shell.name = "SessionShell"
    root.add_child(shell)

    var boot: Node = MISSION_BOOT_SCRIPT.new()
    root.add_child(boot)
    var mission := Mission.new()
    mission.id = "session_test"
    mission.map_path = CREDITS_MAP_PATH
    mission.show_briefing = false
    _gc.current_mission = mission
    boot._on_mission_started(mission)

    TestHelper.assert_true(shell.match_requested, "mission start requests match session mode")
    TestHelper.assert_eq(gameplay.get_child_count(), 1, "the match is hosted in a World root")
    if gameplay.get_child_count() == 1:
        TestHelper.assert_eq(gameplay.get_child(0).name, "World", "the World root is active")

    _gc.current_mission = null
    _pm._players.clear()
    _pm._local_player_id = 0
    _pm._init_defaults()
    TerrainSystem.clear()
    TerrainSystem.init_grid(50, 50)
    if is_instance_valid(root):
        tree.root.remove_child(root)
        root.free()
    tree.paused = false


## Booting a map that defines players materializes a MapConfig node under the
## MissionMap so PlayerManager can read the map's overrides.
func test_map_config_materialized_on_boot() -> void:
    if not _guard():
        return
    var ctx := _setup()
    var mission := Mission.new()
    mission.id = "credits_map"
    mission.map_path = CREDITS_MAP_PATH
    mission.show_briefing = false
    mission.starting_credits = -1
    var map := _boot(ctx, mission)

    var config: Node = map.get_node_or_null("MapConfig")
    TestHelper.assert_true(config != null, "boot materializes a MapConfig node under the map")
    if config != null:
        var players: Array = config.get("players")
        TestHelper.assert_eq(players.size(), 2, "MapConfig carries both fixture players")
    _teardown(ctx)


## With the mission inheriting (starting_credits < 0), the local player's
## credits come from the map's per-player override (200).
func test_map_credits_used_when_mission_inherits() -> void:
    if not _guard():
        return
    var ctx := _setup()
    var mission := Mission.new()
    mission.id = "credits_inherit"
    mission.map_path = CREDITS_MAP_PATH
    mission.show_briefing = false
    mission.starting_credits = -1
    _boot(ctx, mission)

    var player: PlayerData = _pm.get_player_data(0)
    TestHelper.assert_eq(
        player.free_credits, 200, "inheriting mission takes the map's starting credits"
    )
    _teardown(ctx)


## A mission-level starting_credits override beats the map's per-player value.
func test_mission_credits_beat_map() -> void:
    if not _guard():
        return
    var ctx := _setup()
    var mission := Mission.new()
    mission.id = "credits_override"
    mission.map_path = CREDITS_MAP_PATH
    mission.show_briefing = false
    mission.starting_credits = 50
    _boot(ctx, mission)

    var player: PlayerData = _pm.get_player_data(0)
    TestHelper.assert_eq(player.free_credits, 50, "mission starting_credits beats the map value")
    _teardown(ctx)


## The placeholder gdi01 map is split by side: GDI (local, player 0) holds the
## west, Nod (enemy, player 1) the east. Reads the fixture directly so the
## expectation is independent of the loader.
func test_gdi01_sides_assign_local_west_enemy_east() -> void:
    var west_is_gdi := true
    var has_gdi_mcv := false
    var has_nod_conyard := false
    for entry in _json_entities():
        var d := entry as Dictionary
        var house := String(d.get("house_id", ""))
        if house.is_empty():
            continue
        var parts := (d.get("cell", "") as String).split(",")
        var x := parts[0].to_int()
        var player_id := int(d.get("player_id", -1))
        if house == "GDI":
            has_gdi_mcv = has_gdi_mcv or String(d.get("id", "")) == "GDI_MCV"
            west_is_gdi = west_is_gdi and x < 50 and player_id == 0
        elif house == "Nod":
            has_nod_conyard = has_nod_conyard or String(d.get("id", "")) == "NOD_CONSTRUCTION_YARD"
            west_is_gdi = west_is_gdi and x > 50 and player_id == 1
    TestHelper.assert_true(west_is_gdi, "GDI is local on the west, Nod is enemy on the east")
    TestHelper.assert_true(has_gdi_mcv, "the west GDI force includes an MCV")
    TestHelper.assert_true(has_nod_conyard, "the east Nod base includes a construction yard")

    var local_start := _map_start_cell(0)
    var enemy_start := _map_start_cell(1)
    TestHelper.assert_true(local_start.x < 50, "local player starts on the west side")
    TestHelper.assert_true(enemy_start.x > 50, "enemy player starts on the east side")


## Regression: the mission map must render terrain. MapBase01 carries no
## TerrainRenderer, so MissionMap supplies one and hides the flat ground plane.
func test_mission_map_scene_renders_terrain() -> void:
    var scene := MISSION_MAP_SCENE.instantiate()
    var renderer := scene.get_node_or_null("TerrainRenderer")
    TestHelper.assert_true(renderer != null, "MissionMap hosts a TerrainRenderer")
    var ground := scene.get_node_or_null("GroundPlane") as Node3D
    TestHelper.assert_true(ground != null, "MissionMap still has a GroundPlane node")
    if ground != null:
        TestHelper.assert_true(not ground.visible, "the flat ground plane is hidden")
    var file := FileAccess.open(GDI01_MAP_PATH, FileAccess.READ)
    var theater := ""
    if file:
        var json := JSON.parse_string(file.get_as_text()) as Dictionary
        file.close()
        if json != null:
            theater = String(json.get("theater_id", ""))
    TestHelper.assert_true(not theater.is_empty(), "gdi01 declares a theater for art resolution")
    scene.free()


## Regression: the mission map must actually build terrain tile instances, not
## just host the renderer node.
func test_mission_map_terrain_tiles_rendered() -> void:
    if not _guard():
        return
    var ctx := _setup()
    var mission := _gdi01()
    mission.show_briefing = false
    var map := _add_mission_map(ctx, mission)
    var renderer := map.get_node_or_null("TerrainRenderer")
    TestHelper.assert_true(renderer != null, "MissionMap has a TerrainRenderer")
    var tiles := 0
    if renderer != null:
        var terrain_parent := renderer.get_node_or_null("Terrain")
        if terrain_parent != null:
            for child in terrain_parent.get_children():
                var mesh_instance := child as MultiMeshInstance3D
                if mesh_instance and mesh_instance.multimesh:
                    tiles += mesh_instance.multimesh.visible_instance_count
    TestHelper.assert_true(tiles > 0, "the mission map renders terrain tiles")
    _teardown(ctx)
