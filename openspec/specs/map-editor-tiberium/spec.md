# map-editor-tiberium Specification

## Purpose

The map editor's terrain-resource authoring tools: paint harvestable resource entities and place resource-tree spawners from the active game's registered data, with strength/radius brush controls, erase, and tracked placement for save/load.

## Requirements

### Requirement: Toolbar with toggleable tools

The map editor SHALL display a toolbar row at the top with a File MenuButton, Settings MenuButton, horizontally arranged tool buttons (Paint Height, Paint Resource, Place Tree, Set Player Start, Cell Tags, Erase), a Strength HSlider, a Radius SpinBox, and a Height label. Save, Load, Grid, and offset controls are NOT displayed as standalone toolbar items.

#### Scenario: Tool layout
- **WHEN** the map editor opens
- **THEN** the toolbar shows `[File] [Settings] | [Paint Height] [Paint Resource] [Place Tree] [Set Player Start] [Cell Tags] [Erase] | [Strength slider] [Radius spinbox] | [Height label]`

#### Scenario: Radio-button tool selection
- **WHEN** the player clicks a toggleable tool (Paint Height, Paint Resource, Place Tree, Set Player Start, Cell Tags, Erase)
- **THEN** the previously active tool is deactivated, and the clicked tool is activated

### Requirement: Paint Tiberium tool

The editor SHALL paint the active game's primary harvestable resource entity on cells via click+drag, using the Strength and Radius parameters. The entity id SHALL be resolved from registered entity data — the crystal seeded by the game's primary resource-tree spawner, or the first id-ordered non-spawner resource entity in the game's primary resource category when no spawner exists — never a fixed Tiberian Sun id. Only non-spawner entities with a non-empty `resource_type_id` are candidates. Entities are placed at the center of their cells.

#### Scenario: Paint brush on single cell
- **WHEN** Paint Resource is active and the player clicks a cell
- **THEN** the game's primary resource entity is created at the cell center with health equal to `strength%` of that entity's `strength` and its own `resource_type_id`

#### Scenario: Paint brush radius
- **WHEN** Paint Resource is active and Radius = 3
- **THEN** every cell in the 5×5 block centered on the clicked cell is painted in the same pass

#### Scenario: Paint adds to existing pod
- **WHEN** a cell already has a painted resource entity and the player paints over it
- **THEN** the entity's bale amount increases by `strength%` of its bale capacity, capped at capacity

#### Scenario: Paint follows the active game's data
- **WHEN** the registered primary resource entity changes (different id, resource type, or strength)
- **THEN** cells painted afterwards use the new entity id, resource type, and strength, with no editor code change

#### Scenario: No primary resource registered
- **WHEN** the active game registers no candidate resource entity
- **THEN** the tool logs a warning and leaves the tracked painted entities unchanged

### Requirement: Erase tool
The editor SHALL reduce Tiberium amount on cells via click+drag, using Strength and Radius.

#### Scenario: Erase reduces amount
- **WHEN** Erase is active and the player clicks a cell with a pod
- **THEN** the pod's amount is reduced by `strength% * max_amount`

#### Scenario: Erase despawns at zero
- **WHEN** Erase reduces a pod's amount to ≤ 0
- **THEN** the pod entity is removed from the scene

### Requirement: Place Tree tool

The editor SHALL place the active game's primary resource-tree spawner entity on a single-clicked cell. The entity id SHALL be resolved from registered entity data — the first id-ordered spawner whose spawned entity is a non-spawner in the game's primary resource category with a resource type — never a fixed Tiberian Sun id. If the cell is occupied, the existing entity is replaced by the tree only after the spawner resolves. If no primary spawner exists, the tool SHALL log a warning and leave the cell unchanged.

#### Scenario: Place tree on empty cell
- **WHEN** Place Tree is active and the player clicks an empty cell
- **THEN** the game's primary resource-tree spawner entity is created at that cell's center

#### Scenario: Place tree follows the active game's data
- **WHEN** the registered primary resource-tree spawner changes (a different spawner id sorts first, or the existing spawner changes its spawned entity)
- **THEN** trees placed afterwards use the resolved spawner id, and painted resources follow the newly spawned entity, with no editor code change

#### Scenario: Place tree replaces existing entity
- **WHEN** Place Tree is active and the player clicks an occupied cell
- **THEN** the existing entity is removed and the game's primary resource-tree spawner is placed in its cell

#### Scenario: No primary tree registered
- **WHEN** the active game registers no candidate resource-tree spawner
- **THEN** the tool logs a warning and leaves any existing entity on the cell in place

#### Scenario: Place tree is single-click only
- **WHEN** the player drags while Place Tree is active
- **THEN** no entities are placed (only single-click triggers)

### Requirement: Entity tracking
The editor SHALL track painted/placed entities in a local `_painted_entities` dictionary keyed by cell position string.

#### Scenario: Track after paint
- **WHEN** a pod is painted on cell "5,3"
- **THEN** `_painted_entities["5,3"]` contains `{ node, data }` for that pod

#### Scenario: Track after erase
- **WHEN** a pod is erased and its entity removed
- **THEN** the entry is removed from `_painted_entities`

#### Scenario: Track after tree replacement
- **WHEN** a tree replaces an entity on a cell
- **THEN** the old entry is removed and the new tree entry is added

### Requirement: Editor visual feedback
Painted/placed entities SHALL be visible in the editor immediately (real entities with placeholder art).

#### Scenario: Pod visible after paint
- **WHEN** a pod is painted
- **THEN** a pod entity with placeholder cube art appears at the cell center

#### Scenario: Tree visible after place
- **WHEN** a tree is placed
- **THEN** a thin pole placeholder appears at the cell center
