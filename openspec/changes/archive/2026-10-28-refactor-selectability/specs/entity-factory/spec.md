# Spec Delta

## ADDED Requirements

### Requirement: Selection group membership derives from EntityData flags

`EntityFactory.create_entity` SHALL add an entity to the `selectable` group only when `EntityData.is_selectable` is `true`, and to the `drag_selectable` group only when `EntityData.is_drag_selectable` is `true` and the entity type is a unit type. Buildings SHALL never join `drag_selectable`. `EntityPlacer`'s preview group restoration SHALL apply the same rule when it restores groups on a previously detached preview, reading the restored entity's `SelectComponent` flags so the component and group membership cannot disagree.

#### Scenario: Non-selectable unit

- **WHEN** a unit is spawned from data with `is_selectable = false` and `is_drag_selectable = false`
- **THEN** it is not in `selectable` and is not in `drag_selectable`

#### Scenario: Drag-only opt-out stays click-selectable

- **WHEN** a unit is spawned from data with `is_selectable = true` and `is_drag_selectable = false`
- **THEN** it is in `selectable` but not in `drag_selectable`

#### Scenario: Non-selectable building

- **WHEN** a building is spawned from data with `is_selectable = false`
- **THEN** it is not in `selectable` and not in `drag_selectable`

#### Scenario: Restored preview honors the flags

- **WHEN** a detached placement preview is restored for data with `is_selectable = false` and `is_drag_selectable = false`
- **THEN** the restored entity does not join `selectable` or `drag_selectable`

#### Scenario: Restored preview honors drag opt-out

- **WHEN** a detached placement preview is restored for data with `is_selectable = true` and `is_drag_selectable = false`
- **THEN** the restored entity joins `selectable` but not `drag_selectable`
