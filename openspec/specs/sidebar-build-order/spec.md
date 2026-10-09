# sidebar-build-order Specification

## Purpose

Sidebar build menu ordering and tab assignment.
## Requirements
### Requirement: Sidebar build items sort by type group then tech level
The sidebar build menu SHALL sort buildable items by: entity type group rank (mirroring `Sidebar.TAB_ENTITY_TYPES` order — Buildings, Infantry, Vehicles, Aircraft), then ascending `EntityData.tech_level` (a `-1` key SHALL sort before all finite levels), then `display_name` (natural case-insensitive), then `id`. `tech_level == -1` means never buildable and is filtered out by the build gate before sorting, so the `-1` ordering SHALL be retained only for deterministic handling of any raw list passed to the sort. Sorting SHALL be deterministic: items with equal keys SHALL resolve to the same sequence regardless of load order.

#### Scenario: Ground vehicles precede aircraft in the Vehicles tab
- **WHEN** the Vehicles tab lists buildable entities of type VEHICLE and AIRCRAFT
- **THEN** every VEHICLE entry SHALL appear before every AIRCRAFT entry

#### Scenario: Lower tech level appears earlier within a type group
- **WHEN** two buildable entities share an entity type and differ in tech_level
- **THEN** the entity with the lower tech_level SHALL appear first, with a tech_level of -1 sorting before all finite levels

#### Scenario: Equal keys resolve deterministically
- **WHEN** two buildable entities share entity type, tech_level, and display_name
- **THEN** their relative order SHALL be decided by id, identically on every sidebar rebuild

### Requirement: No manual sidebar position field
`EntityData` SHALL NOT expose a sidebar position/priority field; sidebar order SHALL derive solely from entity type, tech_level, display_name, and id.

#### Scenario: New buildable entity requires no ordering metadata
- **WHEN** a new buildable entity is added with only entity_type and tech_level set
- **THEN** it SHALL slot into the sidebar order automatically without editing any sibling entity

### Requirement: Sidebar tabs are per-game data
The sidebar tab set SHALL be built from per-game configuration declared by the active `GameDefinition` (tab label, accepted entity type groups, and an optional required feature). The sidebar SHALL NOT hardcode the Tiberian Sun four-tab list or its entity-type mapping. Tabs whose required feature is off SHALL be hidden.

#### Scenario: Declared tabs
- **WHEN** the active game declares sidebar tabs (name + entity types)
- **THEN** the sidebar builds exactly those tabs in order

#### Scenario: No declared tabs
- **WHEN** the active game declares no sidebar tabs
- **THEN** the built-in default tab set is used

#### Scenario: Feature-gated tab hidden
- **WHEN** a declared tab requires a feature the game does not enable
- **THEN** that tab is not shown and its hotkey does nothing

#### Scenario: Empty tabs allowed
- **WHEN** a declared tab maps to no entity type groups (e.g. the special/superweapon tab before that mechanic exists)
- **THEN** the tab builds empty without error

