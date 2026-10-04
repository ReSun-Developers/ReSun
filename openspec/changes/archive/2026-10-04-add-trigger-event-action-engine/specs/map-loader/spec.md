# Spec Delta

## ADDED Requirements

### Requirement: Map JSON carries optional scripting keys

The map JSON SHALL carry the optional top-level keys `"triggers"` (trigger definitions), `"waypoints"`
(named waypoint id to `"x,y"` cell), and `"variables"` (declared global and per-house local variable
names). All three SHALL be optional: a map lacking any of them SHALL load without error. Exporting a
map that defines a non-empty value for any of them SHALL write it back, so an import-then-save
round-trip preserves scripting data. The loaded values SHALL be surfaced to the trigger engine when a
mission starts.

#### Scenario: Round-trip scripting keys
- **WHEN** a map with `"triggers"`, `"waypoints"`, and `"variables"` is loaded and exported
- **THEN** all three keys are present in the exported JSON with the same content

#### Scenario: Absent keys load clean
- **WHEN** a map without any of the three keys is loaded
- **THEN** it loads with no scripting data and no error

#### Scenario: Waypoints are surfaced to the engine
- **WHEN** a mission map declares `"waypoints"`
- **THEN** the named waypoints are available to the trigger engine for the running mission
