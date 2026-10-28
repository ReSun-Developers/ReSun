# Spec Delta

## ADDED Requirements

### Requirement: Marquee drag ends on release regardless of UI hover
A marquee (selection box) drag SHALL end whenever the left mouse button is released, regardless of where the cursor is at that moment. This includes releases over the sidebar, the gameplay minimap, and the debug menu. On release the drag state SHALL clear and the selection box SHALL hide, so moving back into the gameplay view does not leave a latched drag.

A release over UI SHALL NOT resolve as a world single-click: it MUST NOT select a world entity behind the UI and MUST NOT issue an order. A release with no preceding press that reached gameplay input (for example, a press over UI followed by a release over the map) SHALL likewise select nothing and issue no order. When the drag exceeded the movement threshold before the cursor entered UI, the release SHALL still resolve the box selection from the rectangle formed in the gameplay view.

#### Scenario: Release over the sidebar ends the drag
- **WHEN** the player starts a marquee drag in the gameplay view and releases the left button with the cursor over the sidebar
- **THEN** the drag state clears and the selection box hides
- **AND** moving the cursor back into the gameplay view shows no lingering drag

#### Scenario: Release over the minimap ends the drag
- **WHEN** the player starts a marquee drag in the gameplay view and releases the left button with the cursor over the gameplay minimap
- **THEN** the drag state clears and the selection box hides

#### Scenario: Box selection resolves when released over UI
- **WHEN** the player drags a marquee past the movement threshold and releases over UI
- **THEN** the entities inside the rectangle formed in the gameplay view are selected

#### Scenario: Sub-threshold release over UI does not click through
- **WHEN** the player presses in the gameplay view and releases over UI without exceeding the drag threshold
- **THEN** no world entity is selected and no order is issued

#### Scenario: Release without a preceding press does not click through
- **WHEN** the player presses over UI and releases over the gameplay view
- **THEN** no world entity is selected and no order is issued

#### Scenario: Normal release over the gameplay view is unchanged
- **WHEN** the player drags a marquee and releases over the gameplay view
- **THEN** the box selection resolves and the selection box hides, as before
