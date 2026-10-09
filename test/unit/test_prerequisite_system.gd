extends Node

# PrerequisiteSystem unit tests — Nod advanced power plant availability (#167)
# TS reference: rules.ini [NAAPWR] Prerequisite=NAWEAP (Nod war factory).
# The plant must stay locked until the war factory chain is built — owning
# only a construction yard (fresh MCV deploy) is not enough.

var _pm: Node = null
var _ps: Node = null


func _get_ps() -> Node:
    if _ps == null:
        # The runner never adds this suite to the tree, so resolve the
        # autoload through an injected sibling instead of /root.
        _ps = _pm.get_node_or_null("/root/PrerequisiteSystem")
    if _ps == null:
        TestHelper.fail("PrerequisiteSystem not reachable")
    return _ps


func _data(entity_id: String) -> EntityData:
    var data: EntityData = EntityFactory.get_entity_data(entity_id)
    if data == null:
        TestHelper.fail("EntityFactory has no data for %s" % entity_id)
    return data


func test_naapwr_data_requires_war_factory():
    var naapwr := _data("NOD_ADVANCED_POWER_PLANT")
    if naapwr == null:
        return
    TestHelper.assert_true(
        "NOD_WAR_FACTORY" in naapwr.prerequisite,
        "NAAPWR prerequisite must include NOD_WAR_FACTORY per TS rules.ini"
    )


func test_naapwr_locked_with_yard_only():
    var ps := _get_ps()
    var naapwr := _data("NOD_ADVANCED_POWER_PLANT")
    var power_plant := _data("NOD_POWER_PLANT")
    var yard := _data("NOD_CONSTRUCTION_YARD")
    if ps == null or naapwr == null or power_plant == null or yard == null:
        return
    # MCV just deployed: only a construction yard exists.
    ps.register_building(201, yard)
    # Sanity: the setup is a playable state — basic power plant is buildable.
    TestHelper.assert_true(
        ps.can_build(201, power_plant), "yard-only state must allow the basic Nod power plant"
    )
    # Regression #167: advanced plant must NOT be buildable yet.
    TestHelper.assert_true(
        not ps.can_build(201, naapwr), "NAAPWR must stay locked with only a construction yard"
    )


func test_naapwr_available_after_war_factory():
    var ps := _get_ps()
    var naapwr := _data("NOD_ADVANCED_POWER_PLANT")
    var yard := _data("NOD_CONSTRUCTION_YARD")
    var war_factory := _data("NOD_WAR_FACTORY")
    if ps == null or naapwr == null or yard == null or war_factory == null:
        return
    ps.register_building(202, yard)
    ps.register_building(202, war_factory)
    TestHelper.assert_true(
        ps.can_build(202, naapwr), "NAAPWR must become available once the war factory exists"
    )


func test_naapwr_locked_before_any_building():
    var ps := _get_ps()
    var naapwr := _data("NOD_ADVANCED_POWER_PLANT")
    if ps == null or naapwr == null:
        return
    TestHelper.assert_true(
        not ps.can_build(203, naapwr), "NAAPWR must be locked before the MCV is deployed"
    )


func test_registry_cleared_on_game_changed():
    var ps := _get_ps()
    var yard := _data("NOD_CONSTRUCTION_YARD")
    if ps == null or yard == null:
        return
    ps.register_building(204, yard)
    (
        TestHelper
        . assert_true(
            ps.get_build_count(204, "NOD_CONSTRUCTION_YARD") == 1,
            "building is registered before the game switch",
        )
    )
    ps._on_game_changed(null)
    (
        TestHelper
        . assert_true(
            ps.get_build_count(204, "NOD_CONSTRUCTION_YARD") == 0,
            "a game switch clears owned buildings so stale ids cannot zero capacity",
        )
    )


# --- evaluate_build: reason per gate and gate order (openspec build-gate) ---

const SYNTH_FACTORY_ID := "synth_test_barracks"
const SYNTH_QUEUE := "InfantryType"


## Synthetic build-menu type. `queue` empty means the no_factory gate does not apply.
func _synth(entity_id: String, tech: int, buildable: bool = true, queue: String = "") -> EntityData:
    var data := EntityData.new()
    data.id = entity_id
    data.entity_type = EntityData.EntityType.INFANTRY
    data.tech_level = tech
    data.buildable = buildable
    data.buildable_queue = queue
    return data


func _synth_factory() -> EntityData:
    var data := EntityData.new()
    data.id = SYNTH_FACTORY_ID
    data.entity_type = EntityData.EntityType.BUILDING
    data.buildable = true
    data.tech_level = 1
    data.factory = SYNTH_QUEUE
    return data


## Give a specific player a tech level without clearing the shared roster.
func _set_tech(player_id: int, level: int) -> void:
    PlayerManager.get_player_data(player_id).tech_level = level


## Remove a synthetic player created by `_set_tech` so the shared roster is not
## polluted for later suites (the runner has no per-suite teardown).
func _forget_player(player_id: int) -> void:
    PlayerManager._players.erase(player_id)


func _reason(result: Dictionary) -> int:
    return int(result["reason"])


func _assert_rejected(result: Dictionary, expected: int, msg: String) -> void:
    TestHelper.assert_true(not bool(result["enabled"]), msg + " — should be disabled")
    TestHelper.assert_eq(_reason(result), expected, msg)


func test_reason_none_when_all_gates_pass():
    var ps := _get_ps()
    if ps == null:
        return
    _set_tech(301, 10)
    var data := _synth("none_type", 1)
    data.cost = 250
    var result: Dictionary = ps.evaluate_build(301, data)
    _forget_player(301)
    TestHelper.assert_true(bool(result["enabled"]), "all gates passing is enabled")
    TestHelper.assert_eq(
        _reason(result), PrerequisiteSystem.BuildReason.NONE, "no failing gate reports NONE"
    )
    TestHelper.assert_eq(int(result["cost"]), 250, "the query reports the type's cost")


func test_reason_not_buildable():
    var ps := _get_ps()
    if ps == null:
        return
    _set_tech(302, 10)
    var result: Dictionary = ps.evaluate_build(302, _synth("nb_type", 1, false))
    _forget_player(302)
    _assert_rejected(result, PrerequisiteSystem.BuildReason.NOT_BUILDABLE, "non-menu type")


func test_reason_never():
    var ps := _get_ps()
    if ps == null:
        return
    _set_tech(303, 10)
    var result: Dictionary = ps.evaluate_build(303, _synth("never_type", -1))
    _forget_player(303)
    _assert_rejected(result, PrerequisiteSystem.BuildReason.NEVER, "tech_level -1")


func test_reason_tech_level():
    var ps := _get_ps()
    if ps == null:
        return
    _set_tech(304, 3)
    var result: Dictionary = ps.evaluate_build(304, _synth("high_type", 7))
    _forget_player(304)
    _assert_rejected(result, PrerequisiteSystem.BuildReason.TECH_LEVEL, "above house level")


func test_reason_build_limit():
    var ps := _get_ps()
    if ps == null:
        return
    _set_tech(305, 10)
    var data := _synth("limited_type", 1)
    data.build_limit = 1
    ps.register_building(305, data)
    var result: Dictionary = ps.evaluate_build(305, data)
    ps.unregister_building(305, data)
    _forget_player(305)
    _assert_rejected(result, PrerequisiteSystem.BuildReason.BUILD_LIMIT, "at build limit")


func test_reason_prerequisite_or():
    var ps := _get_ps()
    if ps == null:
        return
    _set_tech(306, 10)
    var data := _synth("or_type", 1)
    data.prerequisite = ["NOD_CONSTRUCTION_YARD"]
    var result: Dictionary = ps.evaluate_build(306, data)
    _forget_player(306)
    _assert_rejected(result, PrerequisiteSystem.BuildReason.PREREQUISITE, "missing OR prereq")


func test_reason_prerequisite_necessary():
    var ps := _get_ps()
    if ps == null:
        return
    _set_tech(307, 10)
    var data := _synth("and_type", 1)
    data.prerequisite_necessary = ["NOD_WAR_FACTORY"]
    var result: Dictionary = ps.evaluate_build(307, data)
    _forget_player(307)
    _assert_rejected(
        result, PrerequisiteSystem.BuildReason.PREREQUISITE_NECESSARY, "missing AND prereq"
    )


func test_reason_no_factory():
    var ps := _get_ps()
    if ps == null:
        return
    _set_tech(308, 10)
    var result: Dictionary = ps.evaluate_build(308, _synth("unit_type", 1, true, SYNTH_QUEUE))
    _forget_player(308)
    _assert_rejected(result, PrerequisiteSystem.BuildReason.NO_FACTORY, "no owned producer")
    TestHelper.assert_true(not bool(result["owned_factory"]), "owned_factory is false with none")


func test_gate_order_tech_before_prerequisite():
    var ps := _get_ps()
    if ps == null:
        return
    _set_tech(309, 3)
    var data := _synth("order_type", 7)
    data.prerequisite = ["NOD_CONSTRUCTION_YARD"]
    var result: Dictionary = ps.evaluate_build(309, data)
    _forget_player(309)
    TestHelper.assert_true(not bool(result["enabled"]), "gate-order case is disabled")
    (
        TestHelper
        . assert_eq(
            _reason(result),
            PrerequisiteSystem.BuildReason.TECH_LEVEL,
            "the earlier gate (tech) is the reportable reason, not the later prereq",
        )
    )


func test_cheat_leaves_owned_factory_truthful():
    var ps := _get_ps()
    if ps == null:
        return
    _set_tech(310, 1)
    Cheats.no_prereqs = true
    var result: Dictionary = ps.evaluate_build(310, _synth("cheat_type", 9, true, SYNTH_QUEUE))
    _forget_player(310)
    TestHelper.assert_true(bool(result["enabled"]), "cheat enables every type")
    TestHelper.assert_eq(
        _reason(result), PrerequisiteSystem.BuildReason.NONE, "cheat reports reason NONE"
    )
    TestHelper.assert_true(
        not bool(result["owned_factory"]), "cheat does not falsify the raw owned_factory fact"
    )


func test_cheat_with_ownership_present():
    var ps := _get_ps()
    if ps == null:
        return
    _set_tech(314, 1)
    var factory := _synth_factory()
    EntityFactory._entity_cache[SYNTH_FACTORY_ID] = factory
    ps.register_building(314, factory)
    Cheats.no_prereqs = true
    var result: Dictionary = ps.evaluate_build(314, _synth("cheat_owned", 9, true, SYNTH_QUEUE))
    ps.unregister_building(314, factory)
    EntityFactory._entity_cache.erase(SYNTH_FACTORY_ID)
    _forget_player(314)
    TestHelper.assert_true(bool(result["enabled"]), "cheat enables with ownership present")
    TestHelper.assert_true(bool(result["owned_factory"]), "ownership fact is truthful under cheat")


func test_owned_factory_is_player_scoped():
    var ps := _get_ps()
    if ps == null:
        return
    _set_tech(311, 10)
    _set_tech(312, 10)
    var factory := _synth_factory()
    EntityFactory._entity_cache[SYNTH_FACTORY_ID] = factory
    ps.register_building(311, factory)
    var unit := _synth("scoped_unit", 1, true, SYNTH_QUEUE)
    var owner_result: Dictionary = ps.evaluate_build(311, unit)
    var other_result: Dictionary = ps.evaluate_build(312, unit)
    ps.unregister_building(311, factory)
    EntityFactory._entity_cache.erase(SYNTH_FACTORY_ID)
    _forget_player(311)
    _forget_player(312)
    (
        TestHelper
        . assert_true(
            bool(owner_result["enabled"]) and bool(owner_result["owned_factory"]),
            "the owner sees the producer",
        )
    )
    _assert_rejected(
        other_result, PrerequisiteSystem.BuildReason.NO_FACTORY, "another player's producer"
    )
    TestHelper.assert_true(
        not bool(other_result["owned_factory"]), "another player has no owned_factory fact"
    )


func test_owned_factory_false_for_building():
    var ps := _get_ps()
    if ps == null:
        return
    _set_tech(313, 10)
    var building := _synth("plain_building", 1, true, "")
    var result: Dictionary = ps.evaluate_build(313, building)
    _forget_player(313)
    TestHelper.assert_true(bool(result["enabled"]), "a no-queue type needs no producer")
    TestHelper.assert_true(
        not bool(result["owned_factory"]), "no-queue type reports owned_factory false"
    )
    TestHelper.assert_eq(
        _reason(result), PrerequisiteSystem.BuildReason.NONE, "no_factory gate does not apply"
    )
