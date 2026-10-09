# Spec Delta

## MODIFIED Requirements

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
