extends Node

# CreditCounter resync + insufficient-funds color tests
# (openspec/specs/credit-ui/spec.md). The counter is CreditCounter on CreditsLabel.

const CREDITS_SCENE: PackedScene = preload("res://scenes/ui/CreditsLabel.tscn")
## Synthetic catalog entries injected into EntityFactory so the player-scoped
## cheapest set is controlled and non-empty in tests.
const SYNTH_ID: String = "test_credit_synth_building"
const LOCKED_ID: String = "test_credit_locked_building"
const SYNTH_COST: int = 7

var _em: Node = null


func _ready() -> void:
    _em = get_node_or_null("/root/EconomyManager")


func _make_counter() -> Control:
    var label: Control = CREDITS_SCENE.instantiate()
    (Engine.get_main_loop() as SceneTree).root.add_child(label)
    return label


func _drop_counter(counter: Control) -> void:
    if counter and is_instance_valid(counter):
        counter.free()


## Force the local player's balance to an exact value, isolated from other suites.
func _set_local_balance(amount: int) -> void:
    var data: PlayerData = PlayerManager.get_player_data(PlayerManager.get_local_player_id())
    data.free_credits = amount
    data.stored_by_category.clear()


## Inject an always-buildable, positive-cost type for the local player so the
## player-scoped cheapest set is non-empty (no map/base fixture is registered).
## tech_level 1 passes the local player's default rules level; no player state is
## mutated here.
func _ensure_synth_buildable() -> void:
    EntityFactory._entity_cache[SYNTH_ID] = _synth(SYNTH_ID, SYNTH_COST, true, [])


## Inject a cheaper type the local player can never build (unmet prerequisite).
func _inject_locked_cheap() -> void:
    EntityFactory._entity_cache[LOCKED_ID] = _synth(LOCKED_ID, 1, true, ["NEVER_OWNED_BUILDING"])


func _synth(id: String, cost: int, buildable: bool, prereq: Array) -> EntityData:
    var data := EntityData.new()
    data.id = id
    data.entity_type = EntityData.EntityType.BUILDING
    data.buildable = buildable
    data.tech_level = 1
    data.cost = cost
    data.prerequisite = PackedStringArray(prereq)
    return data


func _drop_synth() -> void:
    EntityFactory._entity_cache.erase(SYNTH_ID)
    EntityFactory._entity_cache.erase(LOCKED_ID)


func test_ready_shows_local_balance():
    if _em == null:
        TestHelper.fail("EconomyManager not injected")
        return
    var counter := _make_counter()
    var balance: int = _em.get_balance(PlayerManager.get_local_player_id())
    TestHelper.assert_eq((counter as Label).text, "$%d" % balance, "ready shows current balance")
    _drop_counter(counter)


## A roster rebuild (mission start) must replace a stale balance on screen.
func test_players_changed_resyncs_label():
    if _em == null:
        TestHelper.fail("EconomyManager not injected")
        return
    var counter := _make_counter()
    _set_local_balance(4321)
    PlayerManager.players_changed.emit()
    TestHelper.assert_eq(
        (counter as Label).text, "$4321", "players_changed resyncs the label instantly"
    )
    _drop_counter(counter)


func test_insufficient_funds_color_threshold():
    if _em == null:
        TestHelper.fail("EconomyManager not injected")
        return
    _ensure_synth_buildable()
    var counter := _make_counter()
    var cheapest: int = counter.get("_cheapest_cost")
    if cheapest <= 0:
        TestHelper.fail("no buildable entity to derive the cheapest cost")
        _drop_counter(counter)
        _drop_synth()
        return
    _set_local_balance(cheapest - 1)
    counter.call("_update_credits_color")
    var below: Color = counter.get_theme_color("font_color")
    _set_local_balance(cheapest)
    counter.call("_update_credits_color")
    var at: Color = counter.get_theme_color("font_color")
    (
        TestHelper
        . assert_true(
            below == Color(1, 0.3, 0.3, 1) and at == Color(1, 1, 1, 1),
            "counter is red below the cheapest buildable cost and white at/above it",
        )
    )
    _drop_counter(counter)
    _drop_synth()


## A cheaper type the player cannot build must not drive the warning: the
## cheapest stays the buildable synth and the Label is white at that balance.
func test_locked_cheap_item_excluded():
    if _em == null:
        TestHelper.fail("EconomyManager not injected")
        return
    _ensure_synth_buildable()
    _inject_locked_cheap()
    var counter := _make_counter()
    var cheapest: int = counter.get("_cheapest_cost")
    _set_local_balance(SYNTH_COST)
    counter.call("_update_credits_color")
    var color: Color = counter.get_theme_color("font_color")
    _drop_counter(counter)
    _drop_synth()
    TestHelper.assert_eq(
        cheapest, SYNTH_COST, "the locked cost-1 item is excluded from the cheapest set"
    )
    TestHelper.assert_eq(color, Color(1, 1, 1, 1), "the counter is white at the buildable cost")


## Player builds nothing → nothing to afford → no warning, computed (not poked).
func test_no_buildable_means_no_warning():
    # Simulate a base-less local player: no injected synth, no registered buildings.
    _drop_synth()
    PrerequisiteSystem._player_buildings.erase(PlayerManager.get_local_player_id())
    var counter := _make_counter()
    var computed: int = counter.get("_cheapest_cost")
    _set_local_balance(0)
    counter.call("_update_credits_color")
    var color: Color = counter.get_theme_color("font_color")
    _drop_counter(counter)
    TestHelper.assert_eq(computed, -1, "no buildable item computes no cheapest")
    TestHelper.assert_eq(color, Color(1, 1, 1, 1), "no buildable item leaves the counter white")


## `no_cost` cheat makes every type affordable → no warning.
func test_no_cost_cheat_disables_warning():
    var counter := _make_counter()
    counter.set("_cheapest_cost", 1000)
    _set_local_balance(0)
    Cheats.no_cost = true
    counter.call("_update_credits_color")
    (
        TestHelper
        . assert_eq(
            counter.get_theme_color("font_color"),
            Color(1, 1, 1, 1),
            "no_cost cheat keeps the counter white regardless of balance",
        )
    )
    _drop_counter(counter)


## The cached cheapest refreshes on each signal the design hooks.
func test_cache_refreshes_on_set_changing_signals():
    _ensure_synth_buildable()
    var counter := _make_counter()
    counter.set("_cheapest_cost", -1)
    PrerequisiteSystem.prerequisites_changed.emit(PlayerManager.get_local_player_id())
    var after_prereq: int = counter.get("_cheapest_cost")
    counter.set("_cheapest_cost", -1)
    PlayerManager.players_changed.emit()
    var after_roster: int = counter.get("_cheapest_cost")
    counter.set("_cheapest_cost", -1)
    counter.call("_on_game_changed", null)
    var after_game: int = counter.get("_cheapest_cost")
    _drop_counter(counter)
    _drop_synth()
    TestHelper.assert_true(after_prereq > 0, "prerequisites_changed recomputes the cheapest")
    TestHelper.assert_true(after_roster > 0, "players_changed recomputes the cheapest")
    TestHelper.assert_true(after_game > 0, "game_changed recomputes the cheapest")


## Affordability is feedback, never a gate: an unaffordable type is still enabled.
func test_unaffordable_type_is_still_enabled():
    _ensure_synth_buildable()
    _set_local_balance(0)
    var data: EntityData = EntityFactory.get_entity_data(SYNTH_ID)
    var result: Dictionary = PrerequisiteSystem.evaluate_build(
        PlayerManager.get_local_player_id(), data
    )
    _drop_synth()
    TestHelper.assert_true(
        bool(result["enabled"]), "a type the player cannot afford is still buildable"
    )
