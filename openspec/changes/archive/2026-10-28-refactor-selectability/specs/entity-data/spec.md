# Spec Delta

## MODIFIED Requirements

### Requirement: EntityData resource class

The system SHALL provide a single `EntityData.gd` resource class containing ALL properties for ALL entity types (infantry, vehicle, building, aircraft, terrain). Properties SHALL have sensible defaults (0, false, "") so unused fields can be ignored, except the two selectability flags (`is_selectable`, `is_drag_selectable`), which default to `true` because selectable is the behavior of nearly every entity. The class SHALL include a `buildable: bool` field (default `false`) to indicate whether an entity can be placed by the player via the build menu. The class SHALL include a `deploys_into: String` field (default `""`) to specify the entity id this entity can deploy into. The class SHALL include an `undeploys_into: String` field (default `""`) to specify the entity id this entity can undeploy into. The class SHALL include `is_selectable: bool` (default `true`) as the data source for click, hover, and box selection, and `is_drag_selectable: bool` (default `true`) as the data source for box-select group eligibility.

#### Scenario: Create infantry entity data

- **WHEN** an EntityData resource is created with `entity_type = INFANTRY`, `strength = 125`, `speed = 5.0`, `weapons = [WeaponData("minigun")]`
- **THEN** the resource contains all fields with defaults for unused properties (e.g., `foundation = Vector2i(1,1)`, `power = 0`, `radar = false`, `buildable = false`, `deploys_into = ""`, `undeploys_into = ""`)

#### Scenario: Create building entity data

- **WHEN** an EntityData resource is created with `entity_type = BUILDING`, `foundation = Vector2i(2,2)`, `power = 100`, `capturable = true`, `buildable = true`
- **THEN** the resource contains all fields with defaults for unused properties (e.g., `speed = 0.0`, `weapons = []`, `deploys_into = ""`, `undeploys_into = ""`)

#### Scenario: Create terrain entity data

- **WHEN** an EntityData resource is created with `entity_type = TERRAIN`, `strength = 200`, `foundation = Vector2i(1,1)`
- **THEN** the resource contains all fields with defaults for unused properties (e.g., `speed = 0.0`, `weapons = []`, `capturable = false`, `buildable = false`, `deploys_into = ""`, `undeploys_into = ""`)

#### Scenario: Buildable field defaults to false

- **WHEN** an EntityData resource is created without explicitly setting `buildable`
- **THEN** `buildable` is `false`

#### Scenario: DeploysInto field defaults to empty

- **WHEN** an EntityData resource is created without explicitly setting `deploys_into`
- **THEN** `deploys_into` is `""`

#### Scenario: UndeploysInto field defaults to empty

- **WHEN** an EntityData resource is created without explicitly setting `undeploys_into`
- **THEN** `undeploys_into` is `""`

#### Scenario: Selectability defaults to true

- **WHEN** an EntityData resource is created without setting `is_selectable` or `is_drag_selectable`
- **THEN** both fields are `true`

#### Scenario: Explicit opt-out persists

- **WHEN** an EntityData resource is saved with `is_selectable = false`
- **THEN** loading that resource returns `is_selectable = false`
