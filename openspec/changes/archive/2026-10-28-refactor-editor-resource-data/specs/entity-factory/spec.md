# Spec Delta

## ADDED Requirements

### Requirement: Primary resource catalog queries

`EntityFactory` SHALL expose two read-only catalog queries so editor tools can resolve resource entities from registered data instead of fixed ids:

- the primary resource-tree spawner: the first id-ordered cached entity with `resource_spawner == true` whose `spawned_entity_id` resolves to a non-spawner entity whose `resource_category` equals the active rules' `primary_resource_category` and whose `resource_type_id` is non-empty;
- the primary harvestable resource entity: the primary spawner's `spawned_entity_id` entity when that spawner exists, otherwise the first id-ordered non-spawner entity in the primary category with a non-empty `resource_type_id`.

Both SHALL return null when the active rules are absent or no candidate exists. The queries SHALL NOT select a spawner as the harvestable entity and SHALL NOT select an entity with an empty `resource_type_id`.

#### Scenario: Tree-linked primary crystal
- **WHEN** the active game registers a spawner whose `spawned_entity_id` is a crystal in its primary resource category
- **THEN** the primary resource entity is that crystal, even when other crystals in the category sort earlier by id

#### Scenario: Deterministic spawner choice
- **WHEN** several spawners seed a crystal in the primary category
- **THEN** the primary spawner is the one whose id sorts first

#### Scenario: Fallback without a spawner
- **WHEN** no spawner seeds a crystal in the primary category
- **THEN** the primary resource entity is the first id-ordered non-spawner crystal in that category with a non-empty `resource_type_id`

#### Scenario: No candidate
- **WHEN** the active rules are absent or the catalog has no candidate for the primary category
- **THEN** both queries return null

#### Scenario: Tiberian Sun resolves its canonical pair
- **WHEN** the TS game's entity catalog is registered
- **THEN** the primary tree is `TIBERIUM_TREE` and the primary resource entity is `TIBERIUM_RIPARIUS`, not an overlay variant such as `TIBERIUM_BLUE_01`
