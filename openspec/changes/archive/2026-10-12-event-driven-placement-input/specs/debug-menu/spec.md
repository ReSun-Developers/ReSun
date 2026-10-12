# Spec Delta

## MODIFIED Requirements

### Requirement: Entity placement via EntityPlacer
The system SHALL provide a centralized EntityPlacer singleton for all entity placement, including debug mode. EntityPlacer manages inert preview entities (frozen, non-interactive, transparent) and restores original materials on finalize. EntityPlacer SHALL own the free-placement session as a single nullable placing-data field: `start_placing(data)` starts the preview, `exit_placing_mode()` cancels it, `is_placing()` reports session state — there SHALL be no separate mode-flag state machine and no session state stored in any UI script. A primary (`select_entity`) press SHALL commit the placement and a secondary (`deselect_entity`) press or `ui_cancel` (Escape) SHALL cancel it. A commit press while the pointer is over the gameplay minimap SHALL be ignored (the minimap owns it); cancel is unaffected by the minimap. The click that arms the session is a cameo button press consumed as GUI input, so it SHALL NOT commit the placement. Preview repositioning SHALL track the cursor every frame, independent of input events. Building ghosts SHALL commit through BuildingManager (`place_building` at the foundation-snapped origin cell); all other entity types finalize the ghost via `finalize_preview`. `EntityPlacer.is_placing()` SHALL be the single source of placement-mode truth for gameplay guards: MouseHandler click routing and the PauseMenu ESC guard SHALL query EntityPlacer, not the Sidebar.

#### Scenario: Preview creation
- **WHEN** user enters placement mode (debug or production)
- **THEN** EntityPlacer creates a preview entity with PROCESS_MODE_DISABLED, zeroed collision, stripped groups, and transparent material_override

#### Scenario: Preview finalization
- **WHEN** user clicks to place a non-building entity
- **THEN** EntityPlacer restores groups, collision layers, process mode, and surface override materials, then emits entity_placed signal

#### Scenario: Material preservation
- **WHEN** a preview entity is finalized
- **THEN** original set_surface_override_material values (set by ArtComponent) are restored, preventing gray/default material loss

#### Scenario: Placing-start click does not commit
- **WHEN** a cameo click arms the placing session (the click is consumed as GUI input)
- **THEN** the same physical click SHALL NOT commit the placement

#### Scenario: Commit is poll-driven
- **WHEN** the session is placing and a `select_entity` input event is received
- **THEN** the placement commits (buildings via `BuildingManager.place_building`, other entities via `finalize_preview`) and `is_placing()` returns false in the same frame

#### Scenario: Cancel is poll-driven
- **WHEN** the session is placing and a `deselect_entity` or `ui_cancel` input event is received
- **THEN** the preview is cancelled and `is_placing()` returns false

#### Scenario: Building commits route through BuildingManager
- **WHEN** a BUILDING ghost commits
- **THEN** the origin cell snaps to the mouse cell minus half the foundation footprint and the building lands via `BuildingManager.place_building` (cell reservation, terrain leveling, building registry) — not via raw ghost finalization

#### Scenario: Repositioning tracks camera pans
- **WHEN** the camera pans or rotates while the session is placing
- **THEN** the preview repositions to the cursor's terrain position on the next frame (buildings snapped to the foundation grid)

#### Scenario: Refused commit keeps the session armed
- **WHEN** `place_building` refuses the placement (e.g. origin out of map bounds)
- **THEN** the session stays armed with the live ghost so the user can retry

#### Scenario: Commit click does not leak into order resolution
- **WHEN** the commit click finalizes a placement
- **THEN** MouseHandler's subsequent processing observes the commit-click latch for the same physical click — it SHALL NOT additionally issue a unit order on the freshly placed entity

#### Scenario: Placement-mode truth is centralized
- **WHEN** the PauseMenu ESC guard or MouseHandler click routing needs placement-mode state
- **THEN** it reads `EntityPlacer.is_placing()`; no gameplay script queries the Sidebar for placement state
