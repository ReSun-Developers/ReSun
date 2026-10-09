## Purpose

Provide an in-game debug overlay panel for development builds: debug overlays, lighting
controls, cheat toggles, and live entity inspection, all absent from release builds.

## Requirements

### Requirement: Debug panel toggle
The system SHALL provide a debug panel toggled with the backtick key (KEY_QUOTELEFT). The panel SHALL appear as a dropdown from the top-left corner of the viewport.

#### Scenario: Toggle panel open
- **WHEN** user presses the backtick key while the debug panel is closed
- **THEN** the debug panel appears at the top-left corner, overlaying the game

#### Scenario: Toggle panel closed
- **WHEN** user presses the backtick key while the debug panel is open
- **THEN** the debug panel disappears and the game continues running

#### Scenario: Panel does not block game input
- **WHEN** user clicks outside the 400px content area of the debug panel while it is open
- **THEN** the click passes through to the game (entity selection, orders, etc.)

#### Scenario: Panel captures its own input
- **WHEN** user clicks inside the 400px content area of the debug panel while it is open
- **THEN** the click is consumed by the panel (toggling checkboxes, adjusting sliders, etc.)

### Requirement: Debug panel layout
The debug panel SHALL be approximately 400px wide, full viewport height, with a dark panel background. The panel SHALL use an accordion layout with 4 collapsible sections in this order: Overlays, Lighting, Cheats, Inspect. A stats label showing entity counts and FPS SHALL be always visible at the top.

#### Scenario: Accordion section toggle
- **WHEN** user clicks a section header in the debug panel
- **THEN** that section's content toggles between visible and hidden

#### Scenario: Multiple sections expanded
- **WHEN** multiple sections are expanded in the debug panel
- **THEN** all expanded sections are visible simultaneously, stacked vertically

### Requirement: Debug overlays
The system SHALL provide 7 toggleable debug overlays, each controlled by a checkbox in the Overlays section of the debug panel. Overlays SHALL redraw every frame when enabled and clean up their visuals when disabled.

#### Scenario: Pathfinding overlay
- **WHEN** the "Pathfinding lines" checkbox is enabled
- **THEN** green/gray lines are drawn showing movement paths for entities with active movement commands

#### Scenario: Spatial hash grid overlay
- **WHEN** the "Spatial hash grid" checkbox is enabled
- **THEN** grid lines are drawn for each spatial hash cell that has entities

#### Scenario: Entity bounds overlay
- **WHEN** the "Entity bounds" checkbox is enabled
- **THEN** selection box outlines are drawn around every entity using FoundationComponent.cell_size for buildings and a default 1x1 for non-buildings

#### Scenario: Health bars overlay
- **WHEN** the "Health bars" checkbox is enabled
- **THEN** the existing SelectionOverlay health bars become visible, showing segmented health bars above selected/hovered entities

#### Scenario: Entity IDs overlay
- **WHEN** the "Entity IDs + Health" checkbox is enabled
- **THEN** a Label is drawn above every entity showing StatsComponent.display_name, StatsComponent.id, and HealthComponent current/max health

#### Scenario: Occupied cells overlay
- **WHEN** the "Occupied cells" checkbox is enabled
- **THEN** colored outlines are drawn for occupied cells: green for building cells, red for blocked cells (idle units)

#### Scenario: Map bounds overlay
- **WHEN** the "Map Bounds" checkbox is enabled
- **THEN** `BoundsSystem.show_bounds` becomes true and both outer (red) and visible (blue) bounds meshes become visible, rendering in x-ray mode through terrain

#### Scenario: Overlay cleanup on disable
- **WHEN** user disables an overlay
- **THEN** all meshes and canvas items created by that overlay are removed from the scene

#### Scenario: Overlay reset on scene change
- **WHEN** the scene changes (new map loaded)
- **THEN** all overlay checkboxes reset to off and all overlay visuals are cleaned up

### Requirement: Lighting controls
The system SHALL provide sliders in the Lighting section of the debug panel for 8 lighting properties plus a color picker. Changes SHALL apply in real-time to the scene's LightPivot and WorldEnvironment nodes. The system SHALL read the scene's initial light pivot rotation to avoid overwriting baked lighting.

#### Scenario: Sun elevation adjustment
- **WHEN** user adjusts the Sun Elevation slider (range: 0-90 degrees)
- **THEN** the LightPivot node's X rotation updates to match the slider value in degrees

#### Scenario: Sun rotation adjustment
- **WHEN** user adjusts the Sun Rotation slider (range: 0-360 degrees)
- **THEN** the LightPivot node's Y rotation updates to match the slider value in degrees

#### Scenario: Sun intensity adjustment
- **WHEN** user adjusts the Sun Intensity slider (range: 0-5)
- **THEN** the DirectionalLight3D's energy property updates to match the slider value

#### Scenario: Sun color adjustment
- **WHEN** user adjusts the Sun Color picker
- **THEN** the DirectionalLight3D's light_color property updates to match the selected color

#### Scenario: Shadow strength adjustment
- **WHEN** user adjusts the Shadow Strength slider (range: 0-1)
- **THEN** the DirectionalLight3D's shadow_opacity and shadow_blur both update to match the slider value directly (no multiplier)

#### Scenario: Ambient light adjustment
- **WHEN** user adjusts the Ambient Light slider (range: 0-2)
- **THEN** the WorldEnvironment's ambient_light_energy property updates to match the slider value

#### Scenario: Fog density adjustment
- **WHEN** user adjusts the Fog Density slider (range: 0-0.01)
- **THEN** the WorldEnvironment's fog_density property updates to match the slider value

#### Scenario: Sky rotation adjustment
- **WHEN** user adjusts the Sky Rotation slider (range: -1 to 1)
- **THEN** the WorldEnvironment's sky_rotation Y component updates to match the slider value, X and Z components remain at 0

#### Scenario: Glow intensity adjustment
- **WHEN** user adjusts the Glow Intensity slider (range: 0-2)
- **THEN** the WorldEnvironment's glow_intensity property updates to match the slider value

#### Scenario: Lighting default values
- **WHEN** the debug panel opens and no lighting adjustments have been made
- **THEN** sliders show values derived from the scene's actual light pivot rotation and environment settings

### Requirement: Cheat toggles

The system SHALL provide 5 independent cheat toggles in the Cheats section: No prerequisites, No build time, No cost, Place anywhere, Force radar online. Each toggle SHALL persist its state across panel open/close cycles. Cheat flags are stored on the shared `Cheats` value, which the debug panel writes and other systems read directly by identifier — the panel holds no cheat state and consumers do not read it via group reference. The Force radar online toggle SHALL set `RadarSystem.force_online` (the single source of truth for the override), and resetting it SHALL restore normal radar availability.

#### Scenario: No prerequisites toggle
- **WHEN** the "No prerequisites" toggle is enabled
- **THEN** PrerequisiteSystem.can_build() returns true for all entities, bypassing both prerequisite checks and build_limit checks
- **AND** the Sidebar build menu refreshes to show all entities

#### Scenario: No build time toggle
- **WHEN** the "No build time" toggle is enabled
- **THEN** entity build_time is treated as 0, causing ProductionManager to complete production immediately

#### Scenario: No cost toggle
- **WHEN** the "No cost" toggle is enabled
- **THEN** EconomyManager.deduct() is a no-op (returns true without deducting credits)

#### Scenario: Place anywhere toggle
- **WHEN** the "Place anywhere" toggle is enabled
- **THEN** BuildingManager.can_place() returns true for any cell (skips foundation, terrain, and bib checks)
- **AND** EntityPlacer arms the free-placement session for any entity type clicked in the build menu

#### Scenario: Non-building entity placement
- **WHEN** "Place anywhere" is enabled and user clicks a unit/infantry cameo in the build menu
- **THEN** the unit enters placement mode with a preview ghost via EntityPlacer, and clicking a non-blocked ground cell spawns the unit

#### Scenario: Force radar online toggle
- **WHEN** the "Force radar online" toggle is enabled while the local player owns no radar structure
- **THEN** `RadarSystem.force_online` becomes true and the gameplay minimap renders live instead of the offline placeholder

#### Scenario: Force radar toggle reset
- **WHEN** the scene changes (new map loaded)
- **THEN** the "Force radar online" toggle is unchecked and `RadarSystem.force_online` is false

#### Scenario: Cheat reset on scene change
- **WHEN** the scene changes (new map loaded)
- **THEN** all cheat toggles reset to off and debug place mode is exited

### Requirement: Action buttons
The system SHALL provide 2 action buttons in the Cheats section: "Clear All Paths" and "Add 100k Credits".

#### Scenario: Clear all paths
- **WHEN** user clicks the "Clear All Paths" button
- **THEN** DebugVisualizer.clear_all() is called and all debug overlays are cleaned up

#### Scenario: Add credits
- **WHEN** user clicks the "Add 100k Credits" button
- **THEN** 100,000 credits are added to the local player's balance via EconomyManager.add()

### Requirement: Entity inspection
The system SHALL display component data for the currently selected entity in the Inspect section. Inspection is driven by SelectionManager.selection_changed — no separate click handler needed.

#### Scenario: Entity selected with panel open
- **WHEN** user selects an entity while the debug panel is open
- **THEN** the Inspect section expands and displays a health summary (current/max) followed by all exported properties from all attached components, grouped by component name

#### Scenario: Entity deselected
- **WHEN** user deselects all entities (clicks empty space)
- **THEN** the Inspect section clears and collapses

#### Scenario: Different entity selected
- **WHEN** user selects a different entity while one is already being inspected
- **THEN** the Inspect section updates to show the newly selected entity's data

#### Scenario: Panel opens with entity already selected
- **WHEN** user opens the debug panel while an entity is already selected
- **THEN** the Inspect section immediately shows the selected entity's data

### Requirement: Game state display
The system SHALL display a compact debug stats label at the top of the panel (always visible when panel is open) showing entity count by EntityType enum and FPS.

#### Scenario: Debug stats display
- **WHEN** user views the debug panel
- **THEN** a label shows entity counts per EntityType (INF, VEH, BLD, ARC, TER, OVR) and current FPS

#### Scenario: Stats update frequency
- **WHEN** the debug panel is open
- **THEN** the debug stats label updates every frame

### Requirement: Entity placement via EntityPlacer
The system SHALL provide a centralized EntityPlacer singleton for all entity placement, including debug mode. EntityPlacer manages inert preview entities (frozen, non-interactive, transparent) and restores original materials on finalize. EntityPlacer SHALL own the free-placement session as a single nullable placing-data field: `start_placing(data)` starts the preview, `stop_placing()` cancels it, `is_placing()` reports session state — there SHALL be no separate mode-flag state machine and no session state stored in any UI script. Session input SHALL be poll-based in `EntityPlacer._process` (mouse events do not reach `_unhandled_input` at runtime in this codebase; the same reason MouseHandler and BuildingManager poll), with `_unhandled_input` keeping keyboard/test fallback handling. A one-frame input skip (`_skip_input_frames`) after arming SHALL prevent the arming cameo click — which the Input singleton records even when GUI consumes it — from committing the placement. Building ghosts SHALL commit through BuildingManager (`place_building` at the foundation-snapped origin cell); all other entity types finalize the ghost via `finalize_preview`. `EntityPlacer.is_placing()` SHALL be the single source of placement-mode truth for gameplay guards: MouseHandler click routing and the PauseMenu ESC guard SHALL query EntityPlacer, not the Sidebar.

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
- **WHEN** a cameo click starts the placing session (the click is consumed as GUI input but still registered by the Input singleton)
- **THEN** the session's first input-poll frame is skipped, so the same physical click SHALL NOT commit the placement

#### Scenario: Commit is poll-driven
- **WHEN** the session is placing and `select_entity` registers as just-pressed in `_process`
- **THEN** the placement commits (buildings via `BuildingManager.place_building`, other entities via `finalize_preview`) and `is_placing()` returns false in the same frame

#### Scenario: Cancel is poll-driven
- **WHEN** the session is placing and `deselect_entity` or `ui_cancel` registers as just-pressed in `_process`
- **THEN** the preview is cancelled and `is_placing()` returns false; keyboard events reaching `_unhandled_input` also cancel as fallback

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

### Requirement: Scene change reset
The system SHALL reset all debug state when a new map is loaded, detected via the node_added signal watching for nodes starting with "Map".

#### Scenario: New map loaded
- **WHEN** a node with name starting with "Map" is added to the scene tree
- **THEN** all cheat toggles reset, debug place mode exits, EntityPlacer cancels preview, overlay checkboxes reset, and inspection clears

### Requirement: Debug facilities gated to debug builds
All debug facilities — the DebugMenu panel, DebugVisualizer overlays, and per-entity path visualization (`MovementController.debug_show_path`) — SHALL be inert in non-debug builds. Behavior in debug builds SHALL be unchanged.

#### Scenario: Debug menu absent in release
- **WHEN** the game runs from a non-debug build
- **THEN** the DebugMenu node removes itself from the scene and does not respond to the backtick key, lighting sliders, cheat toggles, or inspection

#### Scenario: Overlays inert in release
- **WHEN** the game runs from a non-debug build
- **THEN** DebugVisualizer performs no per-frame work and never creates overlay meshes or canvas items

#### Scenario: Path visualization inert in release
- **WHEN** the game runs from a non-debug build and a unit starts or finishes a move
- **THEN** no path line is drawn or cleared, regardless of any `debug_show_path` value in a scene file

#### Scenario: Debug builds unchanged
- **WHEN** the game runs from a debug build
- **THEN** the debug panel, overlays, and path visualization behave exactly as before this change

### Requirement: Direct deploy fallback

When the "No prerequisites" cheat is enabled and the requesting player owns no building that produces the entity's queue type, clicking that entity's cameo SHALL start placing via EntityPlacer's placement session for it (direct deploy): the entity places at a non-blocked ground cell without factory involvement. Ownership SHALL be evaluated for the clicking player only; a producing building owned by another player SHALL NOT suppress the fallback. This fallback SHALL be a named path (`EntityPlacer.start_direct_deploy`, distinct from the place-anywhere start path) routed from ProductionManager so both entry points stay individually observable; the fallback logic SHALL NOT live in UI code.

#### Scenario: No factory for queue type
- **WHEN** "No prerequisites" is enabled, the queue's factory type is registered, the clicking player owns no matching producing building, and the user clicks the entity's cameo
- **THEN** EntityPlacer's session starts a preview for that entity, and clicking a non-blocked ground cell spawns it at full stats

#### Scenario: Another player's producer does not count
- **WHEN** "No prerequisites" is enabled, another player owns a matching producing building but the clicking player owns none, and the user clicks the entity's cameo
- **THEN** the direct deploy fallback fires for the clicking player

#### Scenario: Factory exists — normal production
- **WHEN** "No prerequisites" is enabled, the clicking player owns a matching producing building, and the user clicks the entity's cameo
- **THEN** production starts normally (the direct deploy fallback does not fire)
