# Spec Delta

## Purpose

Provide a single, node-free home for the debug cheat flags so simulation and UI systems can read
cheat state without reaching into the debug panel, and so a release build (no panel) reads safe
defaults.

## ADDED Requirements

### Requirement: Shared cheat flags

The system SHALL provide a single global `Cheats` state (`class_name Cheats`) holding four
boolean debug cheat flags — `no_prereqs`, `no_build_time`, `no_cost`, and `place_anywhere` —
accessible by direct identifier from any script. Every flag SHALL default to false and SHALL be
resettable as a group. `Cheats` SHALL NOT depend on a scene node, an autoload, or the debug
panel: reading or writing any flag SHALL succeed with no debug UI present, so a release build
reads false for every flag.

#### Scenario: Defaults are false
- **WHEN** no writer has set a flag
- **THEN** `no_prereqs`, `no_build_time`, `no_cost`, and `place_anywhere` all read false

#### Scenario: No panel required
- **WHEN** the debug panel node is absent (release build)
- **THEN** reading any cheat flag returns false and no reader errors

#### Scenario: Group reset
- **WHEN** the cheat state is reset
- **THEN** all four flags read false

### Requirement: Single writer and direct readers

The debug panel SHALL be the only writer of the cheat flags outside test fixtures; no other
system SHALL set them. Consumers SHALL read the flags directly from `Cheats` by identifier. No
system SHALL resolve cheat state through the `debug_menu` node group.

#### Scenario: Panel writes the flag
- **WHEN** a cheat checkbox toggles in the debug panel
- **THEN** the corresponding `Cheats` flag takes the checkbox's value

#### Scenario: Readers bypass the group
- **WHEN** a simulation or UI system reads cheat state
- **THEN** it reads `Cheats` directly and does not query the `debug_menu` group
