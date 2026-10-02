extends Node

# Autoload startup-order contract.
#
# Requirement: ProductionManager resolves PowerGrid in its _ready (connecting
# grid_state_changed for speed-cache invalidation), so PowerGrid MUST be
# registered before it — autoload _ready fires in registration order. Regression
# guard for the stale-cache bug where the connection silently skipped in-game.


func test_power_grid_registers_before_its_ready_time_consumers():
    # Autoloads are flat settings ("autoload/<Name>"); get_order() returns the
    # definition order index — lower means the autoload readies earlier.
    TestHelper.assert_true(
        ProjectSettings.has_setting("autoload/PowerGrid"), "PowerGrid is a registered autoload"
    )
    for consumer in ["ProductionManager"]:
        TestHelper.assert_true(
            ProjectSettings.has_setting("autoload/%s" % consumer),
            "%s is a registered autoload" % consumer
        )
        TestHelper.assert_true(
            (
                ProjectSettings.get_order("autoload/PowerGrid")
                < ProjectSettings.get_order("autoload/%s" % consumer)
            ),
            "PowerGrid registers before %s so its _ready can resolve the grid" % consumer
        )
