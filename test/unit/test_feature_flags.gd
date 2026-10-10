extends Node

# Feature-flag behavior — GameDefinition.features gates TS-shaped mechanics:
# breakable ice (factory + pathfinder), tree-seeded resource regrowth, and the
# data-driven harvest/unload/ROF values. Global state is snapshotted/restored.

const FIXTURES: String = "res://test/fixtures/gamectx"

var _gc: Node = null
var _ef: Node = null
var _em: Node = null
var _bm: Node = null


func _ready() -> void:
    if has_node("/root/GameContext"):
        _gc = get_node("/root/GameContext")
    if has_node("/root/EntityFactory"):
        _ef = get_node("/root/EntityFactory")


func _register_def(id: String, features: Dictionary) -> void:
    var def := GameDefinition.new()
    def.id = id
    def.rules = load(FIXTURES + "/rules.tres") as GlobalRules
    def.features = features
    _gc._defs[id] = def


# --- definition lookup -------------------------------------------------------


func test_unknown_feature_reads_false():
    var def := GameDefinition.new()
    TestHelper.assert_true(not def.has_feature("anything"), "undeclared feature is off")


# --- breakable ice gate ------------------------------------------------------


func test_breakable_ice_component_gated():
    var snap := TestHelper.snapshot_game_context(_gc)
    var data := EntityData.new()
    data.entity_type = EntityData.EntityType.TERRAIN
    data.breakable_surface = true

    _register_def("feat_ice_off", {"breakable_ice": false})
    _gc.select_game("feat_ice_off")
    var off := Node3D.new()
    _ef._add_ice_component(off, data)
    TestHelper.assert_true(not off.is_in_group("ice"), "ice off -> no group")
    TestHelper.assert_eq(off.get_node_or_null("IceComponent"), null, "ice off -> no component")
    off.free()

    _register_def("feat_ice_on", {"breakable_ice": true})
    _gc.select_game("feat_ice_on")
    var on := Node3D.new()
    _ef._add_ice_component(on, data)
    TestHelper.assert_true(on.is_in_group("ice"), "ice on -> group")
    TestHelper.assert_true(on.get_node_or_null("IceComponent") != null, "ice on -> component")
    on.free()

    TestHelper.restore_game_context(_gc, snap)


func test_pathfinder_ice_footing_gated():
    var snap := TestHelper.snapshot_game_context(_gc)
    _register_def("feat_pf_off", {"breakable_ice": false})
    _gc.select_game("feat_pf_off")
    TestHelper.assert_true(not Pathfinder._breakable_ice_enabled(), "pathfinder ice off")
    _register_def("feat_pf_on", {"breakable_ice": true})
    _gc.select_game("feat_pf_on")
    TestHelper.assert_true(Pathfinder._breakable_ice_enabled(), "pathfinder ice on")
    TestHelper.restore_game_context(_gc, snap)


# --- tree regrowth gate ------------------------------------------------------


func test_tree_regrowth_gated():
    var growth := _gc.get_node_or_null("/root/ResourceGrowthSystem")
    TestHelper.assert_true(growth != null, "ResourceGrowthSystem autoload present")
    if growth == null:
        return
    var snap := TestHelper.snapshot_game_context(_gc)
    _register_def("feat_tree_off", {"resource_tree_regrowth": false})
    _gc.select_game("feat_tree_off")
    TestHelper.assert_true(not growth._tree_regrowth_enabled(), "tree regrowth off")
    _register_def("feat_tree_on", {"resource_tree_regrowth": true})
    _gc.select_game("feat_tree_on")
    TestHelper.assert_true(growth._tree_regrowth_enabled(), "tree regrowth on")
    TestHelper.restore_game_context(_gc, snap)


# --- data-driven values ------------------------------------------------------


func test_harvest_component_configure_categories():
    var hc := HarvestComponent.new()
    TestHelper.assert_true(hc.harvestable_types.is_empty(), "empty default = all categories")
    var data := EntityData.new()
    data.harvestable_categories = PackedStringArray(["tiberium"])
    hc.configure(data)
    TestHelper.assert_true(hc.harvestable_types.has("tiberium"), "categories from data")
    hc.free()


func test_dock_unload_rate_uses_rules():
    var snap := TestHelper.snapshot_game_context(_gc)
    var rules := GlobalRules.new()
    rules.refinery_unload_rate = 5.0
    _ef.set_global_rules(rules)
    var dock := DockUnloadComponent.new()
    dock._global_rules = rules
    TestHelper.assert_true(
        absf(dock.get_effective_unload_rate() - 5.0) < 0.001, "sentinel reads rules rate"
    )
    dock.unload_rate = 1.0
    TestHelper.assert_true(
        absf(dock.get_effective_unload_rate() - 1.0) < 0.001, "positive override wins"
    )
    dock.unload_rate = 0.0
    TestHelper.assert_true(
        absf(dock.get_effective_unload_rate()) < 0.001, "zero disables unloading"
    )
    dock.free()
    TestHelper.restore_game_context(_gc, snap)


func test_combat_rof_uses_rules_logic_fps():
    var snap := TestHelper.snapshot_game_context(_gc)
    var rules := GlobalRules.new()
    rules.logic_fps = 60.0
    _ef.set_global_rules(rules)
    var combat := CombatComponent.new()
    var weapon := WeaponData.new()
    weapon.rate_of_fire = 60.0
    TestHelper.assert_true(
        absf(combat._rof_seconds(weapon) - 1.0) < 0.001, "60 ROF at 60 logic fps = 1.0s"
    )
    combat.free()
    TestHelper.restore_game_context(_gc, snap)


func test_economy_default_category_from_rules():
    var snap := TestHelper.snapshot_game_context(_gc)
    var rules := GlobalRules.new()
    rules.primary_resource_category = "ore"
    _ef.set_global_rules(rules)
    TestHelper.assert_eq(EconomyManager.get_default_category(), "ore", "category from rules")
    TestHelper.restore_game_context(_gc, snap)


func test_sell_refund_uses_active_category():
    var snap := TestHelper.snapshot_game_context(_gc)
    var rules := GlobalRules.new()
    rules.primary_resource_category = "ore"
    rules.refund_percent = 0.25
    _ef.set_global_rules(rules)
    var pid := PlayerManager.get_local_player_id()
    var before_total: int = _em.get_balance(pid)
    var categories: Array = []
    _em.credits_changed.connect(
        func(_pid: int, _bal: int, _reason: String, category: String) -> void:
            categories.append(category)
    )

    var node := Node3D.new()
    var data := EntityData.new()
    data.id = "TEST_SELL_CATEGORY"
    data.cost = 100
    var saved: Array = _bm._buildings.duplicate()
    _bm._buildings.clear()
    _bm._buildings.append(
        {"node": node, "type": data, "origin": Vector2i(5, 5), "cells": [] as Array}
    )
    var sold: bool = _bm.sell_building(node)
    TestHelper.assert_true(sold, "sell_building succeeds")
    TestHelper.assert_eq(_em.get_balance(pid), before_total + 25, "refund honors refund_percent")
    TestHelper.assert_true(categories.has("ore"), "sell event tagged with the active category")
    TestHelper.assert_true(not categories.has("tiberium"), "no phantom tiberium category")
    _bm._buildings.assign(saved)
    TestHelper.restore_game_context(_gc, snap)


func test_sell_refund_defaults_to_half():
    var snap := TestHelper.snapshot_game_context(_gc)
    var rules := GlobalRules.new()
    _ef.set_global_rules(rules)
    var pid := PlayerManager.get_local_player_id()
    var before_total: int = _em.get_balance(pid)

    var node := Node3D.new()
    var data := EntityData.new()
    data.id = "TEST_SELL_DEFAULT"
    data.cost = 100
    var saved: Array = _bm._buildings.duplicate()
    _bm._buildings.clear()
    _bm._buildings.append(
        {"node": node, "type": data, "origin": Vector2i(5, 5), "cells": [] as Array}
    )
    var sold: bool = _bm.sell_building(node)
    TestHelper.assert_true(sold, "sell_building succeeds")
    TestHelper.assert_eq(_em.get_balance(pid), before_total + 50, "default refund_percent pays 50%")
    _bm._buildings.assign(saved)
    TestHelper.restore_game_context(_gc, snap)


func test_sell_building_refuses_foreign_owner():
    var pid := PlayerManager.get_local_player_id()
    var node := Node3D.new()
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.entity_type = EntityData.EntityType.BUILDING
    stats.player_id = pid + 1
    node.add_child(stats)
    var data := EntityData.new()
    data.id = "TEST_SELL_ENEMY"
    data.cost = 100
    var saved: Array = _bm._buildings.duplicate()
    _bm._buildings.clear()
    (
        _bm
        . _buildings
        . append(
            {
                "node": node,
                "type": data,
                "origin": Vector2i(0, 0),
                "cells": [] as Array,
                "player_id": pid + 1,
            }
        )
    )
    var before: int = _em.get_balance(pid)
    var sold: bool = _bm.sell_building(node)
    TestHelper.assert_true(not sold, "foreign-owned building is refused")
    TestHelper.assert_eq(_em.get_balance(pid), before, "no refund to the local player")
    _bm._buildings.clear()
    _bm._buildings.assign(saved)
    node.free()


func test_resource_component_neutral_defaults():
    var rc := ResourceComponent.new()
    var rt := ResourceTreeComponent.new()
    TestHelper.assert_eq(rc.resource_type_id, "", "ResourceComponent default is empty")
    TestHelper.assert_eq(rt.resource_type_id, "", "ResourceTreeComponent default is empty")
    rc.free()
    rt.free()
