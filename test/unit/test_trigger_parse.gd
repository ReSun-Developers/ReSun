extends Node

# TriggerParser — definition parsing and all-or-nothing validation.

const PARSER: GDScript = preload("res://scripts/triggers/TriggerParser.gd")

const GLOBALS: Array = ["FlagA", "FlagB"]
const LOCALS: Array = ["LocalA"]
const WAYPOINTS: Array = ["WP"]


func _base(overrides: Dictionary = {}) -> Dictionary:
    var entry := {
        "id": "t1",
        "owner": "GDI",
        "enabled": true,
        "tags": [{"id": "tag1", "persistence": 2, "attach": "general"}],
        "events": [{"id": 7, "params": []}],
        "actions": [{"id": 11, "params": ["hello"]}],
    }
    for key in overrides:
        entry[key] = overrides[key]
    return entry


func _parse(entries: Array) -> Dictionary:
    return PARSER.parse(entries, GLOBALS, LOCALS, WAYPOINTS)


func test_valid_definition_parses() -> void:
    var result := _parse([_base()])
    TestHelper.assert_eq((result["errors"] as Array).size(), 0, "no errors")
    var defs: Dictionary = result["definitions"]
    TestHelper.assert_true(defs.has("t1"), "definition present")
    TestHelper.assert_eq((defs["t1"]["events"] as Array).size(), 1, "one event")
    TestHelper.assert_eq((defs["t1"]["tags"] as Array).size(), 1, "one tag")


func test_unknown_event_id_rejected() -> void:
    var result := _parse([_base({"events": [{"id": 999, "params": []}]})])
    TestHelper.assert_true((result["errors"] as Array).size() > 0, "unknown event rejected")


func test_wrong_arity_rejected() -> void:
    var result := _parse([_base({"events": [{"id": 27, "params": []}]})])
    TestHelper.assert_true((result["errors"] as Array).size() > 0, "wrong arity rejected")


func test_undeclared_global_rejected() -> void:
    var result := _parse([_base({"events": [{"id": 27, "params": ["Missing"]}]})])
    TestHelper.assert_true((result["errors"] as Array).size() > 0, "undeclared global rejected")


func test_unknown_waypoint_rejected() -> void:
    var result := _parse([_base({"actions": [{"id": 48, "params": ["Nope"]}]})])
    TestHelper.assert_true((result["errors"] as Array).size() > 0, "unknown waypoint rejected")


func test_duplicate_id_rejected() -> void:
    var result := _parse([_base(), _base()])
    TestHelper.assert_true((result["errors"] as Array).size() > 0, "duplicate id rejected")


func test_no_tags_rejected() -> void:
    var result := _parse([_base({"tags": []})])
    TestHelper.assert_true((result["errors"] as Array).size() > 0, "tagless trigger rejected")


func test_cell_tag_parses_holders() -> void:
    var result := _parse(
        [_base({"tags": [{"id": "tag1", "persistence": 0, "attach": "cell", "cells": ["37,46"]}]})]
    )
    TestHelper.assert_eq((result["errors"] as Array).size(), 0, "cell tag accepted")
    var tag: Dictionary = (result["definitions"]["t1"]["tags"] as Array)[0]
    TestHelper.assert_eq(tag["attach"], "cell", "attach kind")
    TestHelper.assert_eq((tag["holders"] as Array).size(), 1, "one holder")


func test_overlay_patches_actions_by_id() -> void:
    var merged: Array = (
        PARSER
        . merge_overlay(
            [_base(), _base({"id": "t2", "actions": [{"id": 11, "params": ["keep"]}]})],
            [{"id": "t1", "actions": [{"id": 16, "params": ["GDI"]}]}],
        )
    )
    TestHelper.assert_eq((merged as Array).size(), 2, "overlay does not duplicate")
    var t1: Dictionary = merged[0]
    TestHelper.assert_eq(int((t1["actions"] as Array)[0]["id"]), 16, "t1 actions replaced")
    var t2: Dictionary = merged[1]
    TestHelper.assert_eq(int((t2["actions"] as Array)[0]["id"]), 11, "t2 untouched")
