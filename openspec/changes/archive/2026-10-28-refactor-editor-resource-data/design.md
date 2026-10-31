# Design

## Context

See `proposal.md` — Why. Current state, traced end to end:

- `ResourcePainter._paint_resource_cell` (`scripts/editor/ResourcePainter.gd:43`) spawns the literal `TIBERIUM_RIPARIUS`, overrides `resource_type_id = "tiberium_green"`, and derives initial health from a private `TIB_DEFAULT_STRENGTH = 300`.
- `EntityPlacer._place_tree_on_cell` (`scripts/editor/EntityPlacer.gd:179`) spawns the literal `TIBERIUM_TREE`, freeing any existing entity before the spawn succeeds.
- Both spawn detached through `EntityFactory.spawn`, so the editor tracks `{node, data}` in `MapEditor._painted_entities`; `EditorSaveLoad.build_entity_entry` writes `data.id` and the `MapLoader.OVERRIDE_KEYS`.
- `EntityFactory` already owns the registered catalog (`_entity_cache`), the active rules (`_global_rules`), and `get_all_by_type`. `GameContext.rules.primary_resource_category` already names the active game's primary resource category ("tiberium" for TS, e.g. "ore" for RA2).
- `EntityData` already links a crystal to its `resource_type_id` and a tree to its crystal through `spawned_entity_id`; `ResourceComponent.configure` reads both from data.
- TS registers pre-authored crystal overlays (`games/ts/entities/overlay/tiberium_blue_01.tres`, …) with the same `resource_category = "tiberium"`, `entity_type = TERRAIN`, `procedural_resource_visual = true`, and a non-empty `resource_type_id` as `TIBERIUM_RIPARIUS`. Category + id order alone would pick `TIBERIUM_BLUE_01`, not the canonical crystal.

## Goals / Non-Goals

**Goals:**

- The editor paints/plants whatever the active game registers, with no id literals in editor code.
- One resolution seam for both tools, testable without the editor UI.
- TS behavior is unchanged: paint `TIBERIUM_RIPARIUS` with its `tiberium_green` type and 300 strength, plant `TIBERIUM_TREE`.

**Non-Goals:**

- A resource-type dropdown/picker UI (deferred; see D4).
- Removing `primary_resource_category` or changing the economy/HUD.
- Any change to resource growth, harvesting, art, or the map JSON schema.
- Fixing pre-existing toolbar-spec drift beyond the labels and tool list this delta already touches.
- #374's wider editor/data unification.

## Decisions

### D1: Resolve in `EntityFactory`, tree-first

Add two queries to `EntityFactory`:

- `get_primary_resource_tree_entity() -> EntityData` — among `_entity_cache` values ordered by id, the first `resource_spawner` whose `spawned_entity_id` resolves to a non-spawner entity whose `resource_category` equals `_global_rules.primary_resource_category` and whose `resource_type_id` is non-empty. Null when no rules/candidate.
- `get_primary_resource_entity() -> EntityData` — the primary tree's `spawned_entity_id` entity when a primary tree exists; otherwise the first id-ordered non-spawner in the primary category with a non-empty `resource_type_id`.

Tree-first is the data link that distinguishes the canonical crystal from TS's pre-authored overlay variants: all four TS trees spawn `TIBERIUM_RIPARIUS`, and no spawner references `TIBERIUM_BLUE_01`. The fallback keeps a game without trees paintable (its first crystal by id), and is documented as such.

Why in `EntityFactory`: it already owns the registry and rules binding, both editor tools already depend on it, and it keeps the editor scripts free of catalog scans. Sorting by id makes the choice deterministic across directory scan order.

**Alternatives considered:**

- *Resolve in each editor script* — duplicates the scan and the "primary" rule in two files; rejected.
- *Category + id order only* — picks `TIBERIUM_BLUE_01` in TS (id order) and breaks the unchanged-TS goal; rejected.
- *Link through `GlobalRules.resource_types` only* — `ResourceType` has no entity id field; it would need a new field per type plus every game authoring it. Rejected: `EntityData` already carries the link.
- *New `GlobalRules.primary_resource_entity_id` / `primary_resource_tree_entity_id` fields* — explicit, but duplicates information already on the entity, needs migration for every game, and can disagree with the entity data. Rejected for this change; the tree linkage is the single documented source.

### D2: "Primary" is tree-linked, then deterministic id order

The primary tree is the first id-ordered spawner seeding a crystal in `primary_resource_category`. The primary crystal is that spawner's `spawned_entity_id`. For TS this yields `TIBERIUM_TREE` (unsuffixed sorts before `TIBERIUM_TREE_01..03`) and `TIBERIUM_RIPARIUS`, matching today's output. If a future game ships several primary spawners/crystals, id order is the documented tie-break; a real selection UI would replace the tie-break, not the queries.

### D3: Data supplies strength; drop the redundant override

`ResourcePainter` uses the resolved entity's `strength` as the 100% health default instead of `TIB_DEFAULT_STRENGTH` (300). The `resource_type_id` override is deleted: `EntityData.resource_type_id` already configures `ResourceComponent`, so the override only duplicated data. Saved maps keep their `id`; existing maps that carry a `resource_type_id` override still load through `MapLoader.OVERRIDE_KEYS`.

### D4: No picker UI in this change

The issue's preferred shape allows a picker or data-resolved defaults. A picker needs new editor UI plus scene wiring and cannot be exercised headlessly; #374 owns the editor rework. This change ships the resolution seam the picker would sit on. Add a dropdown when a second selectable resource per game exists and #374 is underway.

### D5: Neutral editor names

`TIB_DEFAULT_STRENGTH` is deleted (D3); `tib` locals in `ResourcePainter` and `MapEditor` become `res_comp`; no `TIB_*`/`tib_*` identifiers remain under `scripts/editor/`. The toolbar already labels the tool "Paint Resource"; the delta corrects the spec's stale "Paint Tiberium" label and keeps "Place Tree".

### D6: Tests fail on base, then pass

New `test/unit/test_editor_resource_data.gd` injects synthetic `EntityData` into `EntityFactory._entity_cache` (the established test seam), points `set_global_rules` at rules whose `primary_resource_category` matches, and drives `ResourcePainter._paint_resource_cell` / `EntityPlacer._place_tree_on_cell` with a minimal editor stub. Assertions:

1. Painted entity id equals the injected crystal id (base paints `TIBERIUM_RIPARIUS` → fails).
2. Replacing the registered tree's spawned crystal changes the id painted on the next cell (base never changes → fails).
3. Initial health scales from the injected entity's `strength` (base uses 300 → fails with a non-300 fixture).
4. The painted entity's `ResourceComponent.resource_type_id` equals the injected type (base forces `tiberium_green` → fails with a different type fixture).
5. Planted tree id equals the injected spawner id (base plants `TIBERIUM_TREE` → fails).
6. Resolver returns null when no candidate exists, and the tools leave `_painted_entities` unchanged with a warning. Guarded by `has_method` so the missing resolver fails the test on base rather than aborting with zero assertions.
7. The real TS catalog resolves `TIBERIUM_TREE` / `TIBERIUM_RIPARIUS`, ignoring `TIBERIUM_BLUE_01`.

`test/integration/test_map_editor_e2e.gd` must pass unchanged: it instantiates the real scene, which still resolves TS data.

## Risks / Trade-offs

- [Multiple primary-category crystals in one game] → tree linkage picks the canonical one; id-order tie-break for multiple spawners is deterministic and documented. A picker (D4) supersedes it later.
- [A game registers a crystal but no spawner] → the fallback paints its first id-ordered crystal; this is a documented fallback, not an error.
- [A game registers no crystal at all] → both queries return null; both tools warn and leave `_painted_entities` untouched. Place Tree resolves before freeing the existing entity so a failed resolve cannot delete map content.
- [Editor test fixture leaks into other suites] → the test saves/restores `EntityFactory._global_rules` and erases only its synthetic ids in teardown, matching `test_building_manager_input`.
- [Dropping the `resource_type_id` override changes saved output] → the saved `id` still resolves the same `EntityData` and therefore the same type on load; only a redundant JSON key disappears. The map JSON schema is unchanged; existing maps with the key remain valid.
- [A future game names its crystal with a suffix sorting before the intended one] → same tie-break risk as D2; the order is explicit, not scan order.

## Migration Plan

Single PR, no data migration. Order: tests (fail on base) → resolver queries → painter → placer → neutral renames → full suite. Rollback = revert the PR; no scene change and no schema change.

## Open Questions

None. The picker UI is deliberately deferred to #374 (D4).
