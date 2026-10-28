extends Node

# Locomotor/LandType registry validation and EntityData zone consistency checks

var _saved_rules: GlobalRules = null
var _entity_factory: Node = null


func _make_rules() -> GlobalRules:
    var rules := GlobalRules.new()
    for lt_id in ["clear", "water"]:
        var lt := LandType.new()
        lt.id = lt_id
        rules.land_types[lt_id] = lt
    return rules


func _real_rules() -> GlobalRules:
    var root: Node = Engine.get_main_loop().root
    var ef: Node = root.get_node_or_null("EntityFactory")
    if ef and ef.has_method("get_global_rules"):
        return ef.get_global_rules() as GlobalRules
    return null


func _inject_rules(rules: GlobalRules) -> void:
    var root: Node = Engine.get_main_loop().root
    _entity_factory = root.get_node_or_null("EntityFactory")
    if _entity_factory:
        _saved_rules = _entity_factory.get_global_rules()
        _entity_factory.set_global_rules(rules)


func _restore_rules() -> void:
    if _entity_factory and _entity_factory.has_method("set_global_rules"):
        _entity_factory.set_global_rules(_saved_rules)


func _make_entity(locomotor_id: String, zone: String) -> EntityData:
    var data := EntityData.new()
    data.id = "UNIT"
    data.entity_type = EntityData.EntityType.VEHICLE
    data.strength = 100
    data.cost = 100
    data.owner = PackedStringArray(["GDI"])
    data.locomotor = locomotor_id
    data.movement_zone = zone
    return data


func _has_error(errors: PackedStringArray, needle: String) -> bool:
    for error in errors:
        if error.contains(needle):
            return true
    return false


func _make_locomotor(id: String, zones: PackedStringArray) -> Locomotor:
    var lm := Locomotor.new()
    lm.id = id
    lm.set("zones", zones)
    return lm


func _zones_of(lm: Locomotor) -> PackedStringArray:
    var value: Variant = lm.get("zones")
    if value is PackedStringArray:
        return value
    return PackedStringArray()


func test_validate_clean_registry():
    var rules := _make_rules()
    var lm := Locomotor.new()
    lm.id = "Foot"
    lm.terrain_speeds = {"clear": 1.0, "water": 0.0}
    rules.locomotors["Foot"] = lm
    TestHelper.assert_true(rules.validate_locomotor_keys().is_empty(), "valid keys -> no errors")


func test_resource_land_type_registered():
    var rules := _real_rules()
    if rules == null:
        TestHelper.fail("EntityFactory rules unavailable")
        return
    TestHelper.assert_true(rules.land_types.has("resource"), "resource land type registered")
    TestHelper.assert_true(
        rules.validate_locomotor_keys().is_empty(), "resource terrain keys validate cleanly"
    )


func test_registered_resource_speeds():
    var rules := _real_rules()
    if rules == null:
        TestHelper.fail("EntityFactory rules unavailable")
        return
    var expected: Dictionary = {
        "Foot": 0.9,
        "Jumpjet": 0.9,
        "Track": 0.7,
        "Subterranean": 0.7,
        "Wheel": 0.5,
        "Amphibious": 0.5,
        "Hover": 1.0,
    }
    for id in expected:
        var lm := rules.get_locomotor(id) as Locomotor
        TestHelper.assert_true(lm != null, "%s locomotor present" % id)
        if lm == null:
            continue
        (
            TestHelper
            . assert_true(
                is_equal_approx(lm.get_speed_multiplier("resource"), float(expected[id])),
                "%s resource speed is %.1f" % [id, float(expected[id])],
            )
        )
        if id != "Hover":
            (
                TestHelper
                . assert_true(
                    lm.get_speed_multiplier("resource") < lm.get_speed_multiplier("clear"),
                    "%s is slowed on resource" % id,
                )
            )
    var ship := rules.get_locomotor("Ship") as Locomotor
    TestHelper.assert_true(
        ship != null and not ship.is_passable("resource"), "Ship cannot cross resource"
    )


func test_validate_dangling_terrain_key():
    var rules := _make_rules()
    var lm := Locomotor.new()
    lm.id = "Wheel"
    lm.terrain_speeds = {"clear": 1.0, "lava": 0.5}
    rules.locomotors["Wheel"] = lm
    var errors := rules.validate_locomotor_keys()
    TestHelper.assert_eq(errors.size(), 1, "one dangling key error")
    TestHelper.assert_true(errors[0].contains("lava"), "error names missing land type")


func test_ts_locomotor_zones():
    var rules := _real_rules()
    if rules == null:
        TestHelper.fail("EntityFactory rules unavailable")
        return
    var expected: Dictionary = {
        "Foot": PackedStringArray(["Infantry", "InfantryDestroyer"]),
        "Track":
        PackedStringArray(
            [
                "Normal",
                "Crusher",
                "Destroyer",
                "AmphibiousCrusher",
                "AmphibiousDestroyer",
                "InfantryDestroyer",
            ]
        ),
        "Wheel": PackedStringArray(["Normal", "Destroyer", "Crusher", "InfantryDestroyer"]),
        "Hover":
        PackedStringArray(
            [
                "Normal",
                "Destroyer",
                "AmphibiousCrusher",
                "AmphibiousDestroyer",
                "InfantryDestroyer",
                "Crusher",
            ]
        ),
        "Amphibious":
        PackedStringArray(
            [
                "AmphibiousCrusher",
                "AmphibiousDestroyer",
                "Destroyer",
                "InfantryDestroyer",
                "Normal",
            ]
        ),
        "Fly": PackedStringArray(["Fly"]),
        "Jumpjet": PackedStringArray(["Fly"]),
        "Subterranean": PackedStringArray(["Subterannean"]),
        "Ship":
        PackedStringArray(
            [
                "Subterannean",
                "Fly",
                "Destroyer",
                "AmphibiousCrusher",
                "AmphibiousDestroyer",
            ]
        ),
    }
    for id in expected:
        var lm := rules.get_locomotor(id) as Locomotor
        TestHelper.assert_true(lm != null, "%s locomotor present" % id)
        if lm == null:
            continue
        var got := _zones_of(lm)
        var want: PackedStringArray = expected[id]
        TestHelper.assert_eq(got.size(), want.size(), "%s zone count" % id)
        for zone in want:
            TestHelper.assert_true(got.has(zone), "%s accepts %s" % [id, zone])
    var track_zones := _zones_of(rules.get_locomotor("Track") as Locomotor)
    TestHelper.assert_true(not track_zones.has("Subterannean"), "Track rejects Subterannean")
    var fly_zones := _zones_of(rules.get_locomotor("Fly") as Locomotor)
    TestHelper.assert_true(
        fly_zones.has("Fly") and not fly_zones.has("Normal"), "Fly accepts only Fly"
    )


func test_entity_unknown_locomotor_validation():
    var rules := _make_rules()
    _inject_rules(rules)
    var data := EntityData.new()
    data.id = "JET"
    data.entity_type = EntityData.EntityType.VEHICLE
    data.strength = 100
    data.cost = 100
    data.owner = PackedStringArray(["GDI"])
    data.locomotor = "Jetpack"
    var errors := data.validate()
    var hit := false
    for e in errors:
        if e.contains("unknown locomotor"):
            hit = true
    _restore_rules()
    TestHelper.assert_true(hit, "unknown entity locomotor reported")


func test_entity_contradictory_zone_validation():
    var rules := _real_rules()
    if rules == null:
        TestHelper.fail("EntityFactory rules unavailable")
        return
    var track := rules.get_locomotor("Track") as Locomotor
    TestHelper.assert_true(
        track != null and _zones_of(track).size() > 0, "Track zone list populated"
    )
    var errors := _make_entity("Track", "Subterannean").validate()
    TestHelper.assert_true(_has_error(errors, "contradicts"), "contradictory zone reported")


func test_entity_valid_zone_validation():
    var rules := _real_rules()
    if rules == null:
        TestHelper.fail("EntityFactory rules unavailable")
        return
    var track := rules.get_locomotor("Track") as Locomotor
    TestHelper.assert_true(track != null and _zones_of(track).has("Normal"), "Track accepts Normal")
    var errors := _make_entity("Track", "Normal").validate()
    TestHelper.assert_true(not _has_error(errors, "contradicts"), "valid zone accepted")


func test_entity_zone_checked_against_resolved_locomotor():
    var rules := _make_rules()
    rules.locomotors["Foot"] = _make_locomotor("Foot", PackedStringArray(["Fly"]))
    _inject_rules(rules)
    var errors := _make_entity("Foot", "Fly").validate()
    _restore_rules()
    TestHelper.assert_true(
        not _has_error(errors, "contradicts"), "zone follows the resolved locomotor"
    )


func test_entity_zone_not_borrowed_from_other_locomotor():
    var rules := _make_rules()
    rules.locomotors["Foot"] = _make_locomotor("Foot", PackedStringArray(["Fly"]))
    rules.locomotors["Subterranean"] = _make_locomotor(
        "Subterranean", PackedStringArray(["Subterannean"])
    )
    _inject_rules(rules)
    var errors := _make_entity("Foot", "Subterannean").validate()
    _restore_rules()
    TestHelper.assert_true(
        _has_error(errors, "contradicts"), "zone is checked against the unit's own locomotor"
    )


func test_entity_zone_without_locomotor():
    _inject_rules(_make_rules())
    var errors := _make_entity("", "Normal").validate()
    _restore_rules()
    TestHelper.assert_true(_has_error(errors, "contradicts"), "zone without locomotor rejected")


func test_locomotor_zones_default_empty():
    var lm := Locomotor.new()
    lm.id = "Custom"
    TestHelper.assert_true(_zones_of(lm).is_empty(), "zones default empty")
    var rules := _make_rules()
    rules.locomotors["Custom"] = lm
    _inject_rules(rules)
    var errors := _make_entity("Custom", "Normal").validate()
    _restore_rules()
    TestHelper.assert_true(_has_error(errors, "contradicts"), "empty zones reject a non-empty zone")


func test_entity_empty_zone_accepted():
    var rules := _make_rules()
    rules.locomotors["Foot"] = _make_locomotor("Foot", PackedStringArray(["Infantry"]))
    _inject_rules(rules)
    var errors := _make_entity("Foot", "").validate()
    _restore_rules()
    TestHelper.assert_true(not _has_error(errors, "contradicts"), "empty zone accepted")


func test_entity_unknown_locomotor_zone_not_checked():
    _inject_rules(_make_rules())
    var errors := _make_entity("Track", "Subterannean").validate()
    _restore_rules()
    TestHelper.assert_true(_has_error(errors, "unknown locomotor"), "unknown locomotor reported")
    TestHelper.assert_true(
        not _has_error(errors, "contradicts"), "unresolved locomotor skips zone check"
    )


func test_entity_zone_validation_without_rules():
    _inject_rules(null)
    var errors := _make_entity("Foot", "Fly").validate()
    _restore_rules()
    TestHelper.assert_true(
        not _has_error(errors, "contradicts"), "zone compatibility skipped without rules"
    )
