# Spec Delta

## MODIFIED Requirements

### Requirement: Marquee drag ends on release regardless of UI hover
A marquee (selection box) drag SHALL end whenever the left mouse button is released, regardless of where the cursor is at that moment. This includes releases over the sidebar, the gameplay minimap, and the debug menu. On release the drag state SHALL clear and the selection box SHALL hide, so moving back into the gameplay view does not leave a latched drag.

While the button is held, the selection box SHALL keep tracking the cursor even when the cursor moves over UI. The rectangle MAY cover UI regions, and a release over UI SHALL resolve the box selection over the full rectangle as drawn, selecting the entities whose screen projection lies inside it, including entities visually behind the UI. A drag SHALL NOT start while the cursor is over UI.

A release over UI SHALL NOT resolve as a world single-click: it MUST NOT select a world entity by point-picking behind the UI and MUST NOT issue an order. A release with no preceding press that reached gameplay input (for example, a press over UI followed by a release over the map) SHALL likewise select nothing and issue no order.

For the duration of a drag that exceeded the movement threshold, the game SHALL show the default pointer cursor, including while the cursor is over UI, rather than the `SELECT` affordance.

#### Scenario: Release over the sidebar ends the drag
- **WHEN** the player starts a marquee drag in the gameplay view and releases the left button with the cursor over the sidebar
- **THEN** the drag state clears and the selection box hides
- **AND** moving the cursor back into the gameplay view shows no lingering drag

#### Scenario: Release over the minimap ends the drag
- **WHEN** the player starts a marquee drag in the gameplay view and releases the left button with the cursor over the gameplay minimap
- **THEN** the drag state clears and the selection box hides

#### Scenario: Marquee keeps tracking over UI
- **WHEN** the player drags a marquee from the gameplay view into the sidebar or minimap without releasing
- **THEN** the selection box keeps resizing to follow the cursor

#### Scenario: Box selection resolves when released over UI
- **WHEN** the player drags a marquee past the movement threshold and releases over UI
- **THEN** the entities whose screen projection lies inside the full rectangle as drawn are selected
- **AND** entities projected behind the UI are included

#### Scenario: Drag shows the default pointer cursor
- **WHEN** the player drags a marquee past the movement threshold
- **THEN** the cursor is the default pointer, over the gameplay view and over UI

#### Scenario: Sub-threshold release over UI does not click through
- **WHEN** the player presses in the gameplay view and releases over UI without exceeding the drag threshold
- **THEN** no world entity is selected and no order is issued

#### Scenario: Press over UI does not start a drag
- **WHEN** the player presses the left button with the cursor over UI
- **THEN** no marquee drag starts and no selection box is shown

#### Scenario: Release without a preceding press does not click through
- **WHEN** the player presses over UI and releases over the gameplay view
- **THEN** no world entity is selected and no order is issued

#### Scenario: Normal release over the gameplay view is unchanged
- **WHEN** the player drags a marquee and releases over the gameplay view
- **THEN** the box selection resolves and the selection box hides, as before
