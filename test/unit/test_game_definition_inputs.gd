extends Node

# GameDefinition.supported_inputs semantics — empty declaration means all.


func test_empty_declaration_allows_all():
    var def := GameDefinition.new()
    TestHelper.assert_true(def.supports_input("camera_up"), "empty allows every action")


func test_non_empty_declaration_is_an_allow_list():
    var def := GameDefinition.new()
    def.supported_inputs = PackedStringArray(["camera_up"])
    TestHelper.assert_true(def.supports_input("camera_up"), "listed action supported")
    TestHelper.assert_true(not def.supports_input("camera_down"), "unlisted action unsupported")
