# Proposal

## Why

The map editor's resource tools bake Tiberian Sun content into shared editor code: `ResourcePainter` spawns `TIBERIUM_RIPARIUS` with a hardcoded `resource_type_id = "tiberium_green"`, and `EntityPlacer` spawns `TIBERIUM_TREE`. A game with ore/ore-crystal or a different tree ships different ids, so the editor paints the wrong entity or nothing at all. This is the editor slice of #395 and part of #374.

## What Changes

- `EntityFactory` gains two catalog queries: the primary resource-tree spawner (first id-ordered spawner whose `spawned_entity_id` is a non-spawner entity in `GlobalRules.primary_resource_category` with a resource type) and the primary harvestable resource entity (that spawner's `spawned_entity_id`; falls back to the first id-ordered non-spawner in the category when no spawner exists). Tree-first linkage matters because TS registers pre-authored crystal overlay variants (e.g. `TIBERIUM_BLUE_01`) in the same category.
- `ResourcePainter` paints the resolved primary resource entity instead of the literal `TIBERIUM_RIPARIUS`; its health default comes from that entity's `strength`, and the redundant `resource_type_id` override is dropped (the entity data already carries it).
- `EntityPlacer`'s Place Tree tool plants the resolved primary resource-tree spawner instead of the literal `TIBERIUM_TREE`.
- Editor locals/constants named `tib`/`TIB_*` become neutral `res`/`RES_*` (`TIB_DEFAULT_STRENGTH` disappears with the data-sourced strength).
- The `map-editor-tiberium` spec records that both tools resolve their entity from registered data.

Explicitly out of scope: #374 (the wider editor/data unification) and a full editor rework. No user-facing resource-type dropdown is added in this change — the editor paints the active game's primary resource by default; a picker UI can layer on the same catalog queries later.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `map-editor-tiberium`: Paint Resource and Place Tree resolve their entity id from registered entity data instead of fixed `TIBERIUM_RIPARIUS`/`TIBERIUM_TREE` ids.
- `entity-factory`: adds the two primary-resource catalog queries (tree-first crystal resolution, id-order determinism, null when no candidate).

## Impact

- **Scripts:** `scripts/entities/EntityFactory.gd` (two catalog queries), `scripts/editor/ResourcePainter.gd` (data-resolved paint, neutral names), `scripts/editor/EntityPlacer.gd` (data-resolved tree), `scripts/editor/MapEditor.gd` (`tib` locals → neutral names)
- **Tests:** new `test/unit/test_editor_resource_data.gd`; existing map-editor suites must pass unchanged
- **Docs:** `GLOSSARY.md` gains a `primary resource entity` row
- **Scenes:** none — scripts only, no `.tscn` or packed-resource format change; existing maps keep working because the saved `id` is whatever was painted
- **Backward compatibility:** TS behavior is unchanged (its first tree by id is `TIBERIUM_TREE`, which spawns `TIBERIUM_RIPARIUS`, so the painted crystal and its 300 strength stay the same); other games now paint their own data
