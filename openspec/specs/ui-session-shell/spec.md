# ui-session-shell Specification

## Purpose
Defines the persistent UI session shell: a GUI host that outlives individual
matches and mounts exactly one surface at a time — the process-level main menu or
the match-scoped in-game HUD — selected by a session mode, so the two GUI
surfaces have a single explicit owner and clean hand-off.

## Requirements

### Requirement: One persistent UI host owns the GUI surfaces

The system SHALL provide a UI session shell hosted under `MainScene` that
persists across map changes and owns the top-level GUI surfaces. The shell SHALL
outlive any single match's World root.

#### Scenario: UI host survives a match change

- **WHEN** one match is replaced by another
- **THEN** the UI session shell node remains in the scene tree while the match's
  World root is replaced

### Requirement: Session mode selects exactly one GUI surface

The UI session shell SHALL mount exactly one top-level GUI surface at a time,
selected by a session mode with at least `Menu` and `Match`. Switching session
mode SHALL clear the previously mounted surface so two top-level surfaces are
never shown at once.

#### Scenario: Match mode shows the HUD only

- **WHEN** session mode becomes `Match`
- **THEN** the in-game HUD surface is mounted and the main-menu surface is not

#### Scenario: Menu mode shows the menu only

- **WHEN** session mode becomes `Menu`
- **THEN** the main-menu surface is mounted and the in-game HUD surface is not

#### Scenario: Switching clears the previous surface

- **WHEN** session mode changes from `Menu` to `Match`
- **THEN** the main-menu surface is removed before or as the match HUD surface is
  mounted, leaving exactly one top-level surface

### Requirement: The main menu is process-level

In `Menu` session mode the main menu SHALL be shown without requiring a match or
a World root. The main menu SHALL NOT depend on per-match scene content to be
displayed.

#### Scenario: Menu without a match

- **WHEN** the game starts and no match has been started
- **THEN** the main-menu surface is shown and no World root is required

### Requirement: The in-game HUD is match-scoped and map-independent

The in-game HUD SHALL be mounted by the UI session shell while the session is in
`Match` mode and released when the shell switches away from `Match` (for example
when one match is replaced by another, or the session returns to the menu),
independently of the loaded map node's own teardown. The HUD SHALL NOT be hosted
as a descendant of the loaded map scene; replacing the map SHALL NOT be what
mounts or frees the HUD.

#### Scenario: HUD present for an active match

- **WHEN** a match is active
- **THEN** the in-game HUD surface is mounted and contains the match's sidebar and
  minimap

#### Scenario: HUD released when the session leaves match mode

- **WHEN** the session switches from `Match` back to `Menu`, or one match is
  replaced by another
- **THEN** the in-game HUD surface is detached and freed without the loaded map
  scene having to free it as a child
