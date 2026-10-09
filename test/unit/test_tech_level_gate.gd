extends Node

# Tech-level gate tests — PrerequisiteSystem.can_build against PlayerData.tech_level.


class FakePlayerConfig:
    extends RefCounted

    var player_id: int = 0
    var faction_id: String = ""
    var color: Color = Color.WHITE
    var team_id: int = 1
    var spawn_index: int = 0
    var display_name: String = "P"
    var is_bot: bool = false
    var starting_credits: int = -1


class FakeMapConfig:
    extends Node

    var players: Array = []


var _pm: Node = null


func _ps() -> Node:
    var ps: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("PrerequisiteSystem")
    if ps == null:
        TestHelper.fail("PrerequisiteSystem autoload not present")
    return ps


func _data(tech: int) -> EntityData:
    var data := EntityData.new()
    data.id = "TECH_TEST"
    data.entity_type = EntityData.EntityType.INFANTRY
    data.tech_level = tech
    return data


func _reset_players(tech: int) -> PlayerData:
    _pm._players.clear()
    _pm._init_defaults()
    var player: PlayerData = _pm.get_player_data(0)
    player.tech_level = tech
    return player


func test_at_level_is_buildable():
    _reset_players(5)
    TestHelper.assert_true(_ps().can_build(0, _data(5)), "type at the house level is buildable")


func test_below_level_is_buildable():
    _reset_players(5)
    TestHelper.assert_true(_ps().can_build(0, _data(3)), "type below the house level is buildable")


func test_above_level_is_rejected():
    _reset_players(3)
    TestHelper.assert_true(
        not _ps().can_build(0, _data(7)), "type above the house level is rejected"
    )


func test_negative_level_is_never_buildable():
    _reset_players(10)
    TestHelper.assert_true(not _ps().can_build(0, _data(-1)), "tech_level -1 is never buildable")


func test_rejection_caused_by_tech_condition():
    # Same setup succeeds without the condition, then fails once it is introduced.
    _reset_players(10)
    TestHelper.assert_true(_ps().can_build(0, _data(5)), "buildable before lowering the level")
    _reset_players(3)
    TestHelper.assert_true(
        not _ps().can_build(0, _data(5)), "rejected after the level drops below the type"
    )


func test_mission_override_resolves():
    TestHelper.assert_eq(PlayerManager.resolve_tech_level(3, 10), 3, "mission override wins")


func test_rules_fallback_resolves():
    TestHelper.assert_eq(PlayerManager.resolve_tech_level(-1, 10), 10, "rules fallback used")


func test_debug_override_bypasses_gate():
    _reset_players(1)
    Cheats.no_prereqs = true
    TestHelper.assert_true(_ps().can_build(0, _data(9)), "debug no_prereqs bypasses the tech gate")


func test_begin_mission_writes_mission_level():
    var mission := Mission.new()
    mission.tech_level = 4
    _pm.begin_mission(mission)
    TestHelper.assert_eq(
        _pm.get_player_data(0).tech_level, 4, "begin_mission applies the mission level"
    )
    TestHelper.assert_eq(
        _pm.get_player_data(1).tech_level, 4, "begin_mission applies it to every player"
    )


func test_begin_mission_inherits_rules_level():
    var rules := GlobalRules.get_current()
    var mission := Mission.new()
    mission.tech_level = -1
    _pm.begin_mission(mission)
    TestHelper.assert_eq(
        _pm.get_player_data(0).tech_level, rules.tech_level, "inherit sentinel uses the rules level"
    )


func test_init_defaults_writes_rules_level():
    var rules := GlobalRules.get_current()
    _pm._players.clear()
    _pm._init_defaults()
    TestHelper.assert_eq(
        _pm.get_player_data(0).tech_level, rules.tech_level, "_init_defaults uses the rules level"
    )


func test_map_config_path_writes_rules_level():
    var rules := GlobalRules.get_current()
    var cfg := FakeMapConfig.new()
    var pc := FakePlayerConfig.new()
    cfg.players = [pc]
    _pm._players.clear()
    _pm._init_from_map_config(cfg)
    (
        TestHelper
        . assert_eq(
            _pm.get_player_data(0).tech_level,
            rules.tech_level,
            "map-config init uses the rules level",
        )
    )
    cfg.free()
