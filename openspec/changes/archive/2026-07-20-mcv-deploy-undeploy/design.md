## Context

ReSun is an RTS remake of Command & Conquer: Tiberian Sun built in Redot Engine 26.2 LTS with pure GDScript. The game uses a data-driven entity system where entities are created from EntityData resources via EntityFactory autoload, with components dynamically attached based on data properties.

The MCV (Mobile Construction Vehicle) is a vehicle that transforms into a Construction Yard building. This bidirectional transformation is a core RTS mechanic — players start with an MCV, deploy it to begin base building, and can undeploy to relocate.

**Current state:**
- EntityData has `entity_type` enum (INFANTRY, VEHICLE, BUILDING, AIRCRAFT, TERRAIN, OVERLAY)
- EntityFactory creates entities and dynamically adds components based on data properties
- BuildingManager handles building placement with foundation validation
- SelectionManager dispatches commands (move, harvest, dock) to selected entities
- MovementController handles unit movement via kinematic updates
- #77 (PlayerManager) is implemented — owner tracking works on entities

**Key constraint:** WASD is already used for camera pan. Deploy hotkey must avoid this conflict.

## Goals / Non-Goals

**Goals:**
- Implement bidirectional deploy/undeploy between MCV and Construction Yard
- Preserve health as ratio through transformation
- Preserve owner through transformation
- Validate foundation cells before deploy
- Auto-scatter allied units blocking foundation cells
- Support deploy via Ctrl+D hotkey
- Support undeploy via left-click move command on buildings
- Keep implementation minimal and data-driven

**Non-Goals:**
- Deploy/undeploy animation (future enhancement)
- Deploy timer (future enhancement)
- Sound effects (future enhancement)
- Visual effects (future enhancement)
- Veterancy/status bonus transfer (veterancy system not implemented yet)
- Multiple deploy targets per entity (one deploy, one undeploy)
- Deploy preview/ghost (instant deploy)

## Decisions

### 1. Single Bidirectional Component vs Separate Components

**Decision:** Single `DeployComponent` with both `deploys_into` and `undeploys_into` fields.

**Rationale:**
- Both directions share the same logic (health transfer, rotation, validation)
- Single component = single system to maintain
- Goes on both MCV (with `deploys_into`) and ConYard (with `undeploys_into`)
- System checks `entity_type` to determine direction

**Alternatives considered:**
- Separate `DeployComponent` + `UnDeployComponent`: More files, more complexity, duplicated logic
- Component on vehicle only, building uses BuildingManager: Breaks symmetry, harder to extend

### 2. Deploy Hotkey

**Decision:** Ctrl+D for deploy.

**Rationale:**
- Original Tiberian Sun uses D for deploy (canonical)
- D is used for camera pan right in our WASD scheme
- Ctrl is already used for team creation (Ctrl+1-0), familiar modifier
- Alt+D was considered but Ctrl is more standard in RTS for secondary actions

**Alternatives considered:**
- Alt+D: Less standard in RTS context
- D only: Conflicts with camera pan
- X: Would conflict if scatter is ever added

### 3. Undeploy Trigger

**Decision:** Left-click on ground (move command) triggers undeploy for buildings with DeployComponent.

**Rationale:**
- Buildings cannot move — a move command on a building is semantically "relocate"
- Relocation = undeploy to vehicle → move → deploy again
- Matches original Tiberian Sun flow: select ConYard → right-click to undeploy (we use left-click because our right-click = deselect)
- Single action (left-click) for both move and undeploy reduces cognitive load

**Alternatives considered:**
- Ctrl+D for undeploy too: Requires remembering two different contexts for same key
- Dedicated undeploy button: Adds UI complexity

### 4. Health Transfer Method

**Decision:** Percentage-based health transfer using float division.

**Rationale:**
- Preserves relative damage state (50% damaged MCV → 50% damaged ConYard)
- Formula: `target_health = int(float(target_max_health) * float(source_health) / float(source_max_health))`
- Float cast prevents integer division truncation
- Guard: if `source_max_health <= 0`, target spawns with full health
- Consistent across both directions
- Future-proof for veterancy (bonus health would transfer proportionally)

**Alternatives considered:**
- Integer-only math: Would lose precision (500/1000 = 0 with int division)
- No health transfer: Breaks game balance

### 5. Foundation Validation

**Decision:** Reuse BuildingManager's `_is_cell_free()` logic for deploy validation.

**Rationale:**
- Already checks: building cells, blocked cells, entity cells, bib cells, resource cells, terrain type
- Proven to work for building placement
- No need to duplicate validation logic

**Alternatives considered:**
- New validation function: Would duplicate existing logic
- Skip validation: Would allow invalid deployments

### 6. Auto-Scatter

**Decision:** Single-attempt auto-scatter: scatter allies AND deploy if cells clear after scatter.

**Rationale:**
- More fluid gameplay (one action instead of two)
- Matches user expectation (deploy should "just work")
- Reuses MovementController's `_scatter_blockers()` pattern
- If scatter fails to clear all cells, deploy aborts with warning

**Alternatives considered:**
- Two-step (scatter then deploy): More clicks, less fluid
- Scatter only: Requires manual deploy after scatter

### 7. Origin Cell Calculation

**Decision:** For deploy (MCV→building), origin = MCV cell + offset to center foundation. For undeploy (building→MCV), MCV appears at `deploy_cell` offset (default [0,0] = origin cell).

**Rationale:**
- Centers building on MCV position (natural feel)
- `deploy_cell` allows per-entity customization (e.g., MCV could appear at center of ConYard)
- Default [0,0] = origin cell = top-left for buildings, works for most cases

**Alternatives considered:**
- Always at MCV position: Building would be offset, not centered
- Always at building center: Complex calculation, less intuitive

### 8. Selection Cleanup

**Decision:** Deselect source entity before removal during deploy/undeploy.

**Rationale:**
- Prevents stale selection references in SelectionManager
- Stale references could cause crashes when accessing freed nodes
- Deselect is atomic operation before entity removal

**Alternatives considered:**
- Remove from selection after entity removal: Race condition risk
- Keep selection, let SelectionManager handle invalid refs: More defensive code needed

### 9. PrerequisiteSystem Integration

**Decision:** Call `PrerequisiteSystem.register_building()` on deploy and `PrerequisiteSystem.unregister_building()` on undeploy.

**Rationale:**
- Buildings affect prerequisite chains (e.g., ConYard enables other buildings)
- Deploy adds a building → must register
- Undeploy removes a building → must unregister
- Keeps prerequisite state consistent

**Alternatives considered:**
- Skip prerequisite registration: Would break tech tree
- Only register on initial building placement: Deploy would not count toward prerequisites

## Risks / Trade-offs

- **Risk: SelectionManager becomes aware of deploy logic** → Mitigation: Keep deploy logic in DeployComponent, SelectionManager only calls `_execute_undeploy()` which delegates to the component
- **Risk: Auto-scatter may push units into bad positions** → Mitigation: Scatter only pushes to adjacent free cells, respects blocked cells
- **Risk: Health ratio rounding** → Mitigation: Use integer math, accept small rounding errors
- **Risk: Deploy during combat** → Mitigation: MCV must be idle (not moving) to deploy, but can deploy while under attack (valid strategy in original TS)
- **Trade-off: No deploy animation** → Acceptable for MVP, animation can be added later
- **Trade-off: No deploy preview** → Acceptable for instant deploy, preview adds complexity
