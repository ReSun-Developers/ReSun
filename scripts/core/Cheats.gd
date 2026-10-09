class_name Cheats

## Shared debug cheat flags. Written only by the debug panel (DebugMenu); read
## directly by gameplay and UI systems. Node-free — no scene, no autoload — so a
## release build (where the panel frees itself) reads false for every flag.
## The test runner clears these before each test via TestHelper.reset().

static var no_prereqs: bool = false
static var no_build_time: bool = false
static var no_cost: bool = false
static var place_anywhere: bool = false


## Clears every cheat flag. Called on scene reset and before each test.
static func reset() -> void:
    no_prereqs = false
    no_build_time = false
    no_cost = false
    place_anywhere = false
