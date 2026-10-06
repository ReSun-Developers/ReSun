# Glossary

Canonical term directory for ReSun. Fast lookup — meaning readable here,
expanded semantics live in the anchored spec (authoritative) or code. Grouped by
domain cluster.

**Rule:** read this before writing specs/design docs or naming things. When a
term surfaces during planning or clarifying — even a prompt-only term — propose
adding it here. See **Undecided** below for terms that must not be guessed.

Entry form: term → one-line meaning → anchor.

## Game Selection & Content

| Term | Meaning | Where |
|------|---------|-------|
| game definition | One standalone game's content manifest: `GameDefinition` resource at `res://games/<id>/game.tres` (id, display_name, rules, data_sets, maps_dir, features). The `id` must match its directory name. | [game-context](openspec/changes/add-game-definition-context/specs/game-context/spec.md) · scripts/data/GameDefinition.gd |
| feature flag | Per-game on/off mechanic toggle in `GameDefinition.features` (id → bool). An absent id reads as false. Numeric/behavioral values belong on the game's GlobalRules, not here. | [feature-flags](openspec/changes/audit-core-ts-hardcodes/specs/feature-flags/spec.md) · scripts/data/GameDefinition.gd |
| GameContext | First autoload: resolves the active game (`--game` flag → persisted `[game] id` → `ts`), owns `select_game`/`game_changed` lifecycle and per-game rules access. | [game-context](openspec/changes/add-game-definition-context/specs/game-context/spec.md) · scripts/core/GameContext.gd |
| data set | One `res://` layer root a consumer registers for scanning; the consumer appends its known subdir (`entities/`, `audio/`, `terrain_objects/`, `art/terrain/`, `theaters/`). | [game-content](openspec/changes/add-game-definition-context/specs/game-content/spec.md) |
| layering (last-wins) | Same resource id in a later data-set root overrides the earlier registration within one game. Borrowing another game's content = listing its root; same-id claims by two non-borrowing games are a validator error, not layering. | [game-content](openspec/changes/add-game-definition-context/specs/game-content/spec.md) |
| campaign | Ordered collection of missions won one by one; `Campaign` resource (`id`, `display_name`, `faction_id`, `missions` in win order). One `.tres` per `<game>/campaigns/`. | [campaign-catalog](openspec/changes/mission-boot/specs/campaign-catalog/spec.md) · scripts/data/Campaign.gd |
| mission | One single-player map plus campaign metadata and per-mission overrides; `Mission` resource under `<game>/missions/`. Override sentinels inherit from the map, then GlobalRules. | [campaign-catalog](openspec/changes/mission-boot/specs/campaign-catalog/spec.md) · scripts/data/Mission.gd |
| mission boot | Starting a mission: resolve the campaign's first mission, set it active, apply overrides (`mission > map > global rules`), load its map into the match's World root under `MainScene/Gameplay`, and center the camera. | [mission-boot](openspec/specs/mission-boot/spec.md) · [design](openspec/changes/archive/2026-09-15-mission-boot/design.md) |
| briefing | Pre-mission narrative dialog, auto-shown when `Mission.show_briefing` is true; the game stays paused until it closes, and the pause menu can re-open it. | [briefing-screen](openspec/changes/mission-boot/specs/briefing-screen/spec.md) · [design](openspec/changes/mission-boot/design.md) |
| home cell | Start-camera cell override on a `Mission` (`"x,y"` string); empty defers to the map's own start location. Bridge until named waypoints land. | [mission-boot](openspec/changes/mission-boot/specs/mission-boot/spec.md) · scripts/data/Mission.gd |
| next mission | Chained following mission id on a `Mission` (`next_mission_id`); empty = none. Consumed by campaign progression. | [campaign-catalog](openspec/changes/mission-boot/specs/campaign-catalog/spec.md) · scripts/data/Mission.gd |

## Session & Scenes

| Term | Meaning | Where |
|------|---------|-------|
| match root | The per-match container node under `MainScene/Gameplay` (`scenes/core/World.tscn`, node named `World`): owns the loaded map and all content produced for the match — including runtime-spawned units, structures, projectiles, effects, and grown resources — and is the single teardown point when a match is replaced. Not the 3D game world/terrain and not the **World frame** coordinate frame. | [match-root](openspec/specs/match-root/spec.md) · scripts/core/World.gd |
| world root | Alias for **match root** — the `World` node under `MainScene/Gameplay` that hosts all per-match scene content. | [match-root](openspec/specs/match-root/spec.md) · scripts/core/World.gd |
| spawn seam | The single access point runtime spawners use to parent content. `World.spawn_container(bucket, fallback)` resolves the active match root, or falls back to an explicit parent, the current scene, then the scene tree root. Buckets are `Entities` (units, structures, resources) and `Effects` (projectiles, one-shot effects). | [match-root](openspec/specs/match-root/spec.md) · scripts/core/World.gd |
| session mode | The `SessionShell` selector (`Menu` or `Match`) that decides which GUI surface is mounted; exactly one at a time. | [ui-session-shell](openspec/specs/ui-session-shell/spec.md) · scripts/ui/SessionShell.gd |
| UI session shell | The persistent `SessionShell` node under `MainScene` that mounts the menu surface (`MenuSurface`) or the match HUD surface (`HudSurface`) and outlives a match. | [ui-session-shell](openspec/specs/ui-session-shell/spec.md) · scripts/ui/SessionShell.gd |

## Settings & Options

| Term | Meaning | Where |
|------|---------|-------|
| options view | The single reusable options screen with Graphics, Display, Input, and Game sections, opened as a centered modal overlay from the boot selector, pre-match main menu, or in-match pause menu. Themed per opening surface. | [options-framework](openspec/changes/options-settings-framework/specs/options-framework/spec.md) |
| settings authority | The one `user://settings.cfg` writer path: section-namespaced (per concern and per game id) with load-modify-save, so no concern clobbers another's keys. | [options-framework](openspec/changes/options-settings-framework/specs/options-framework/spec.md) · scripts/core/UserConfig.gd |
| graphics settings | The global (all-games) rendering schema (AA, shadow quality, cloud shadows, GI mode, tone mapping, exposure, texture quality). Selectable as Low/Medium/High/Ultra presets. | [graphics-settings](openspec/changes/options-settings-framework/specs/graphics-settings/spec.md) |
| display settings | The global window settings (`window_mode`, `resolution`); a distinct domain that quality presets never change and that applies live. | [graphics-settings](openspec/changes/options-settings-framework/specs/graphics-settings/spec.md) |
| quality preset | A named atomic bundle (Low/Medium/High/Ultra) that sets every graphics setting at once; Low is the minimum-spec-safe preset. | [graphics-settings](openspec/changes/options-settings-framework/specs/graphics-settings/spec.md) |
| custom preset | The preset-picker state shown when the graphics field values match no named preset, i.e. the player has overridden at least one field. | [graphics-settings](openspec/changes/options-settings-framework/specs/graphics-settings/spec.md) |
| game settings | Per-game gameplay/interface toggles stored per game id (e.g. `move_target_line`), independent of the shared graphics settings. | [game-settings](openspec/changes/options-settings-framework/specs/game-settings/spec.md) |
| input support matrix | A game's declaration of which input actions it supports (`GameDefinition.supported_inputs`); unsupported actions are unbound and their table cells disabled. | [input-settings](openspec/changes/options-settings-framework/specs/input-settings/spec.md) · scripts/data/GameDefinition.gd |

## Placement & Building

| Term | Meaning | Where |
|------|---------|-------|
| `foundation` | Data property: building size in cells as `EntityData.foundation` (Vector2i width × depth). Not derived, not runtime state. | [entity-data](openspec/specs/entity-data/spec.md) · scripts/data/EntityData.gd |
| `adjacent` | Max empty-cell gap (Chebyshev) allowed between a new footprint and friendly footprints at placement; `<= 0` = no requirement — diverges from TS (0 = must-touch, negative = disabled). | [building-manager](openspec/specs/building-manager/spec.md) · scripts/data/EntityData.gd |
| `footprint` | Runtime derived set of occupied cells computed from `foundation`: `FoundationComponent.footprint_cells()`. Never a data field. | [foundation-component](openspec/specs/foundation-component/spec.md) · scripts/components/FoundationComponent.gd |
| `bib` | Part of the building foundation: blocks everything the building foundation does, but pathfinding may still pass through bib cells at a cost (`bib_cost_penalty`). | [bib-pathfinding-penalty](openspec/specs/bib-pathfinding-penalty/spec.md) |
| build mode | BuildingManager lifecycle: pick entity → preview ghost → validate → place. | [building-manager](openspec/specs/building-manager/spec.md) |
| placing (EntityPlacer session) | Free-placement lifecycle: pick entity → ghost preview → place or cancel; no validity checks (unlike build mode). `EntityPlacer.is_placing()` is the placement-mode truth. Not "arming" — that word belongs to projectiles. | sidebar-ui-thinning change |
| placement blocking | Placement refused while moving units stand on the footprint. | [building-placement-blocking](openspec/specs/building-placement-blocking/spec.md) |
| free unit | Unit spawned automatically when a building is placed (`EntityData.free_unit`; refinery → harvester). | [free-unit](openspec/specs/free-unit/spec.md) |
| primary building | `FactoryComponent.is_primary` flag; ProductionManager routes production to it over same-type factories. | [primary-building](openspec/specs/primary-building/spec.md) |
| terrain-matched highlight | Build-mode highlight for non-flat cells: a patch with the flat octagon's exact XZ silhouette, split along the `derive_crease` diagonal and draped on the cell's two terrain-triangle planes + offset — no terrain-art dependency. Flat cells keep the octagon. | [placement-grid-overlay](openspec/specs/placement-grid-overlay/spec.md) · scripts/core/PlacementGridOverlay.gd |

⚠ Drift note: some `FoundationComponent` static methods name their Vector2i
parameter `footprint` while it actually receives the `foundation` size. Treat
those params as legacy — `foundation` = the data property, `footprint` = the
cell set.

## Grid & Cells

| Term | Meaning | Where |
|------|---------|-------|
| cell | Grid unit on the 2 m raster, addressed as `Vector2i`. Conversions: CellUtil. | [cell-util](openspec/specs/cell-util/spec.md) |
| sub-slot | Reserved position within a cell for units whose locomotor has `shares_cell = true`; mainly used by infantry. | [cell-occupancy](openspec/specs/cell-occupancy/spec.md) |
| shared slots | Max sharers per cell: `GlobalRules.shared_slots_per_cell`. | [global-rules](openspec/specs/global-rules/spec.md) |
| cell reservation | Present/coming occupancy registry so batching units don't collide mid-move. | [cell-reservation](openspec/specs/cell-reservation/spec.md) |
| blocked cells | Cells removed from pathing: idle-unit bodies, buildings (non-bib), resources. | [spatial-hash](openspec/specs/spatial-hash/spec.md) |
| SpatialHash | Entity-per-cell spatial index rebuilt every physics frame. | [spatial-hash](openspec/specs/spatial-hash/spec.md) |

## Map & Bounds

Two frames of reference — most "diamond vs rectangle" confusion is which frame
you're standing in.

**World frame** (top-down XY plane): cells are axis-aligned squares; map extents
are 45°-rotated rectangles, i.e. diamonds.

| Term | Meaning | Where |
|------|---------|-------|
| playable bounds (red diamond) | World-frame full map extent — a 45°-rotated rectangle; hard validity limit for entities/orders. | [rectangular-grid](openspec/specs/rectangular-grid/spec.md) |
| visible bounds (blue diamond) | Inset shrink of the red diamond via top/right/bottom/left insets; limiter for reveals/clamps/UI. | [rectangular-grid](openspec/specs/rectangular-grid/spec.md) |
| terrain diamond | Visual-only: the EditorGrid draw of the owned-cell raster. Same shape, different sense from the two above. | [rectangular-grid](openspec/specs/rectangular-grid/spec.md) |
| `isometric view` | The gameplay camera: Y=45°-yawed orthographic (`projection = 1`). Inverts the world picture: the whole map reads as an axis-aligned rectangle on screen while each cell reads as a screen diamond — the Tiberian Sun look. Consequence: picking and alignment math must rotate by ±45° (e.g. MouseHandler), and anything drawn world-axis-aligned (minimap footprint, EditorGrid) renders rotated on screen. | scenes/hud/Camera01.tscn · scripts/hud/CameraController.gd · scripts/editor/Minimap.gd:151 |
| `MapConfig` | Scene-level map configuration resource holding players and dimensions. | [map-config](openspec/specs/map-config/spec.md) |
| theater | Light look-tag (temperate/snow/…) affecting art only — never passability or movement. | [terrain-catalog](openspec/specs/terrain-catalog/spec.md) |
| grade | Per-cell integer height level (steps). | [terrain-grade](openspec/specs/terrain-grade/spec.md) |
| heightfield | Terrain collision authority; cells split by a crease diagonal into corner triangles. | [terrain-heightfield-collision](openspec/specs/terrain-heightfield-collision/spec.md) |

## Terrain & Land

| Term | Meaning | Where |
|------|---------|-------|
| `LandType` | Per-cell surface class ("clear", "water", …); drives locomotor passability/speed. | [land-types](openspec/specs/land-types/spec.md) |
| terrain speeds | `Locomotor.terrain_speeds`: land-type id → multiplier (0/absent = impassable for that locomotor). | [locomotor](openspec/specs/locomotor/spec.md) |
| `TerrainObject` | Authored directional terrain tile: per-cell land types, baked corner heights, crease, edge connection roles. | [terrain-object-catalog](openspec/specs/terrain-object-catalog/spec.md) |
| connection roles | Per-edge vocabulary describing how cliffs/ramps mate with neighbors. | [terrain-object-catalog](openspec/specs/terrain-object-catalog/spec.md) |
| resource land type | Cells under resource crystals resolve to the resource land type (drives movement and routing both). | [terrain-movement-costs](openspec/specs/terrain-movement-costs/spec.md) |
| surface stack | Ordered per-cell surfaces: the ground at level 0 plus zero or more deck levels above, bounded by `MAX_HEIGHT` (10). A deck is added at its level without overwriting the ground surface. | [cell-surfaces](openspec/changes/bridges-walkable-surface/specs/cell-surfaces/spec.md) · scripts/core/TerrainSystem.gd |
| deck level | Integer level above the ground (> 0) at which a deck surface sits; the second half of movement/occupancy identity `(cell, level)`. Level 0 is the ground. | [cell-surfaces](openspec/changes/bridges-walkable-surface/specs/cell-surfaces/spec.md) · scripts/core/CellUtil.gd |
| place-set | Per-level occupancy places on a cell (`CellSubPositions` sub-slots). A deck's places are independent of the ground places beneath it, so a deck occupant consumes no ground place. | [cell-surfaces](openspec/changes/bridges-walkable-surface/specs/cell-surfaces/spec.md) · scripts/core/CellSubPositions.gd |
| height transition | Step between adjacent `(cell, level)` surfaces: same level allowed; a level change only within the mover's climb tolerance to a passable matching-grade surface (ramp, low-bridge slope end, high-bridge end); otherwise refused. A step of two or more levels costs from the Road row. | [cell-surfaces](openspec/changes/bridges-walkable-surface/specs/cell-surfaces/spec.md) · scripts/core/Pathfinder.gd |
| deck lane land | The ordinary land type a bridge deck lane resolves at its level: `road` for a road/low/high lane and rail outer lanes, `railroad` for a rail bridge's middle lane — never a synthetic `bridge` type. Costed from that row with the terrain figure skipped; the ground land at level 0 is preserved and reverts when the piece leaves. | [bridge-ts-fidelity](openspec/changes/bridge-ts-fidelity/specs/land-types/spec.md) · scripts/core/TerrainSystem.gd |
| low bridge | Deck about half a height step above the ground, thickness upward, entirely overlay; slope end pieces ramp ground traffic on and off, normal span pieces are destructible and end pieces are not. | [bridges](openspec/changes/bridges-walkable-surface/specs/bridges/spec.md) · games/ts/entities/overlay/bridge.tres |
| high bridge | Deck about four height steps above the ground on one authored flat span grade, thickness downward; entered and left only across a matching-grade end (cliff + road cut), never climbed from the surrounding ground; all cells indestructible. | [bridges](openspec/changes/bridges-walkable-surface/specs/bridges/spec.md) · games/ts/entities/overlay/bridge_high.tres |
| rail bridge | A high-bridge variant only, never low; three lanes whose middle lane resolves `railroad` and outer lanes `road`, with a rail cut through its end. Rail-specific movement restrictions belong to the movement system. | [bridge-ts-fidelity](openspec/changes/bridge-ts-fidelity/specs/bridges/spec.md) · games/ts/entities/overlay/rail_bridge.tres |
| extra-high bridge | Two or more deck levels stacked over the same XZ at different world heights, bounded by `MAX_HEIGHT`; each level is an independent surface and place-set. | [bridges](openspec/changes/bridges-walkable-surface/specs/bridges/spec.md) · [cell-surfaces](openspec/changes/bridges-walkable-surface/specs/cell-surfaces/spec.md) |
| road cut | Three-wide road/rail-grade cut through a high-bridge end `TerrainObject`, generated from the original engine's `ovrps`/`tovrps` end tiles: three cut cells at the deck grade flanked by rock banks over a rock base, the rail end's middle cut cell `railroad`. Applied by the stamp-to-grid consumer and persisted as a `cell pin`. | [bridge-ts-fidelity](openspec/changes/bridge-ts-fidelity/specs/bridges/spec.md) · games/ts/terrain_objects/cliff_bridge_end_n.tres |
| bridge piece / span | Authoring unit of a bridge: three lanes (cells) across by one cell along, each covered cell its own overlay entity at the piece's deck level, all sharing one piece id; placed one cell at a time. | [bridge-ts-fidelity](openspec/changes/bridge-ts-fidelity/specs/bridges/spec.md) |
| bridge end | End cell of a bridge piece: an indestructible low-bridge slope piece, or a high-bridge cliff/road-cut `TerrainObject` end (destruction is #250). | [bridges](openspec/changes/bridges-walkable-surface/specs/bridges/spec.md) |
| walkable surface height | World Y a unit stands on at a level: the deck surface height when a deck covers `(cell, level)`, else the ground smooth-terrain height (`TerrainSystem.get_cell_surface_height(cell, level)`, default level 0). | [bridges](openspec/changes/bridges-walkable-surface/specs/bridges/spec.md) · scripts/core/TerrainSystem.gd |

## Map Editor & Authoring

| Term | Meaning | Where |
|------|---------|-------|
| `house` | Map-object ownership faction (GDI/Nod/Neutral/Special). Houses are factions; player slots are a separate axis (starts/waypoints 0–7). Placed entities store `house_id`; the legacy `player_id` is a serialization alias only, not gameplay ownership. | [map-houses](openspec/specs/map-houses/spec.md) · scripts/data/Houses.gd |
| `waypoint` | Numbered map location. Player starts use indexes 0–7; general waypoints use ≥ 8 and persist in the map JSON `waypoints` dict. | [editor-foundations proposal](openspec/changes/editor-foundations/proposal.md) · #371 |
| `LAT` | Land/terrain attribute surface — the per-cell `LandType` painted by the editor's LAT brush and tools. | [land-types](openspec/changes/editor-foundations/specs/land-types/spec.md) |
| `tileset` | Grouping label on `LandType.group` used by the editor's bottom bar; presentation only, no gameplay effect. | scripts/data/LandType.gd |
| `framework mode` | Editor view mode that renders flat placeholder colors per land type instead of resolved art (marble-madness style). Render-only, no data mutation. | #372 |
| `overlay` | Editor-placed non-blocking map decoration (fences, bridges) sourced from `entities/overlay/`. Distinct from the fog *overlay* (revealed-shroud rendering). | games/ts/entities/overlay/ |
| `smudge` | Editor-placed cosmetic ground stain (burns/scorch) sourced from `entities/smudge/`. | games/ts/entities/smudge/ |
| cell pin | Cliff-stamp overlay: cell → `TerrainObject` id. A pinned cell renders its pinned object, locks its vertices against height edits, and persists as `cell_pins`. Stamp + lock + delete via one mechanism. | [terrain-cell-pins](openspec/changes/editor-foundations/specs/terrain-cell-pins/spec.md) · scripts/core/TerrainSystem.gd |
| cell tag | Sparse overlay binding a map cell to an opaque mission tag id; a tag id may cover many cells (a region). Queried by the trigger engine and persisted as `cell_tags`. Storage only — trigger evaluation is separate. | [terrain-cell-tags](openspec/changes/add-celltags-subsystem/specs/terrain-cell-tags/spec.md) · scripts/core/TerrainSystem.gd |
| asset browser | Standalone dev tool (`scenes/AssetBrowser.tscn`, Run Scene / F6) browsing a game's visual + audio assets by category, with a preview-owned camera (zoom + free/auto/90° rotation). Non-visual data categories are out of scope (#410). | [asset-browser](openspec/specs/asset-browser/spec.md) · #409 |

## Resources & Economy

| Term | Meaning | Where |
|------|---------|-------|
| crystal | Harvestable resource entity (e.g. TIBERIUM_RIPARIUS); self-grows and spreads. | [resource-growth-system](openspec/specs/resource-growth-system/spec.md) |
| tree | `ResourceTree` spawner entity that creates crystals within `radius_cells` up to `node_count`. | [resource-tree](openspec/specs/resource-tree/spec.md) |
| bale | Atomic raw-resource quantity carried/stored/spread (not credits; value applied at refinery). | [resource-harvesting](openspec/specs/resource-harvesting/spec.md) |
| resource category | Group id aggregating resource types (e.g. "tiberium"); basis for storage capacity and HUD totals. | [resource-storage](openspec/specs/resource-storage/spec.md) |
| resource type | Specific variant with `value`, `grow_rate`, color etc.; `ResourceType.parent_type` is a deprecated alias of `category`. | [resource-loadability](openspec/specs/resource-loadability/spec.md) · ResourceType.gd |
| deposited credits | Stored-resource balance subject to per-category storage capacity; what HUD displays (if `display_in_hud`). | [resource-storage](openspec/specs/resource-storage/spec.md) |
| free credits | Starting credits, sell refunds, crate bonuses, debug money — outside storage caps, excluded from the storage bar. | [player-data](openspec/specs/player-data/spec.md) · PlayerData.gd |
| storage capacity | Per-player per-category cap; refineries declare their own share via `EntityData.storage_capacity`. | [resource-storage](openspec/specs/resource-storage/spec.md) |
| production queue | Per-player list managed by ProductionManager; cost deducted gradually, multiple-factory speed bonus. | [production-manager](openspec/specs/production-manager/spec.md) |

## Power

| Term | Meaning | Where |
|------|---------|-------|
| power grid | Per-player aggregate of building power: `output` (Σ positive `power`) − `drain` (Σ \|negative\|). PowerGrid autoload is the authority; registered from tree add/remove of `PowerComponent`s. | [add-power-grid change](openspec/changes/add-power-grid/specs/power-grid/spec.md) · scripts/core/PowerGrid.gd |
| low power | Grid state where `sum < 0`; immediate on registry change. `drain = 0` grids are never low power. | [add-power-grid change](openspec/changes/add-power-grid/specs/power-grid/spec.md) |
| powered-down | Runtime offline state (`PowerComponent.is_online == false`) of a structure that *requires* power, under low power. Combat holds fire, radar reports offline, power-gated animation clips pause. Producers never power down in this phase. | [add-power-grid change](openspec/changes/add-power-grid/specs/power-grid/spec.md) |
| build rate | Production speed multiplier from power: 1.0 healthy; in low power `lerp(worst, best, output/drain)` (defaults 0.3 → 0.75). Slows production, never halts it. | [add-power-grid change](openspec/changes/add-power-grid/specs/power-grid/spec.md) · [add-power-grid design](openspec/changes/add-power-grid/design.md) |
| power bar | TS-style twin bar on the sidebar's left edge: black column backing a green output fill with a red drain fill in front (red rises above green on deficit). Fills map through `(value/2000)^0.4` and ease toward live PowerGrid targets. | [add-power-grid change](openspec/changes/add-power-grid/specs/power-grid/spec.md) · scripts/ui/PowerBar.gd |

## Radar & Minimap

| Term | Meaning | Where |
|------|---------|-------|
| RadarSystem | Per-player radar availability autoload: registers every `RadarComponent` from tree add/remove, exposes `player_has_radar(player_id)` and `force_online`, emits `radar_availability_changed` on flips. Availability is event-driven (power flips ride `radar_state_changed`). | [add-radar-minimap-gating change](openspec/changes/archive/2026-09-11-add-radar-minimap-gating/specs/radar/spec.md) · scripts/core/RadarSystem.gd |
| radar gate | Minimap live/offline state derived from local-player radar availability (or the debug `force_online` override). Offline shows a black `OFFLINE` placeholder with no input/composition; each flip plays a short static-noise transition. | [add-radar-minimap-gating change](openspec/changes/archive/2026-09-11-add-radar-minimap-gating/specs/gameplay-minimap/spec.md) · scripts/ui/Minimap.gd |

## Units & Combat

| Term | Meaning | Where |
|------|---------|-------|
| entity | Anything spawned from an `EntityData`: infantry, vehicle, building, aircraft, terrain, overlay, smudge. | [entity-factory](openspec/specs/entity-factory/spec.md) |
| warhead | Damage-application profile: base multiplier + per-armor-type multiplier table + effect flags. | [armor-types](openspec/specs/armor-types/spec.md) · WarheadData.gd |
| armor type | Target protection class; warhead's table keys select the final damage fraction. | [armor-types](openspec/specs/armor-types/spec.md) |
| projectile | Flight-behavior definition referenced by `WeaponData.projectile` string id. | [projectile-data](openspec/specs/projectile-data/spec.md) |
| veterancy | Promotion levels granting combat/speed/armor/rof multipliers, clamped at `veteran_cap`. | [global-rules](openspec/specs/global-rules/spec.md) |
| `experience` | Per-instance combat experience (`StatsComponent.experience`); rank is derived from it at thresholds 1 and 2. | [veterancy](openspec/specs/veterancy/spec.md) |
| `trainable` | Whether an entity's kills accumulate experience; units default on, buildings opt in. | [veterancy](openspec/specs/veterancy/spec.md) |
| `veteran_cap` | Ceiling on accumulated experience, so rank cannot exceed it; 2 enables elite. | [global-rules](openspec/specs/global-rules/spec.md) |
| crusher / crushable | Vehicle flags; crushers destroy crushable targets standing in an entered cell. | [vehicle-crush](openspec/specs/vehicle-crush/spec.md) |
| `weight` | Crush pairing + ice-breakage threshold (`ice_cracking_weight`). Explicitly not a speed factor. | [entity-data](openspec/specs/entity-data/spec.md) · [ice-drowning](openspec/specs/ice-drowning/spec.md) |
| hitscan | Damage applied instantly at fire time, no projectile travel. | [combat-firing](openspec/specs/combat-firing/spec.md) |
| threat posed | AI targeting priority hint on EntityData. | [combat-firing](openspec/specs/combat-firing/spec.md) |
| acquisition range | Mode A guard scan radius: longest `weapon.attack_range * CellUtil.CELL_SIZE` (horizontal). Mode B (sight radius) deferred to #444. | [guard-auto-engage](openspec/changes/add-guard-auto-engage/specs/guard-auto-engage/spec.md) |
| hold ground | `CombatComponent.set_target(..., hold_ground=true)`: fire without chasing; clears if target leaves weapon range. Player orders default `false` (chase). | [combat-firing](openspec/changes/add-guard-auto-engage/specs/combat-firing/spec.md) |
| socket | Named 3D attachment point on `ArtData.sockets` (a turret hardpoint, or a future anchor). Owns a `pivot` Transform3D, `yaw_free` capability, barrel length, and placeholder size; behavior references it by string id. | [turret-system change](openspec/specs/turrets/spec.md) · scripts/data/SocketData.gd |
| weapon mount group | Per-unit binding of one weapon to one or more sockets plus its firing discipline. A weapon absent from every group is body-mounted. | [turret-system change](openspec/specs/turrets/spec.md) · scripts/data/WeaponMountGroupData.gd |
| salvo | Fire discipline: every socket in a mount group fires on the same tick. | [turret-system change](openspec/specs/turrets/spec.md) |
| stagger | Fire discipline: sockets fire in order, each `fire_delay` seconds after the previous. | [turret-system change](openspec/specs/turrets/spec.md) |
| turret | A `yaw_free` socket that yaws to the target while the body holds course; a fixed socket keeps the whole-body facing gate. | [turret-system change](openspec/specs/turrets/spec.md) · scripts/components/TurretComponent.gd |
| flight model | Per-projectile behavior chosen by `ProjectileData` flags: teleport-detonate (`is_invisible`) vs real flight (straight + optional homing). One branch set inside ProjectileController — mirrors the locomotor pattern, not component nodes. | [projectile-system change](openspec/changes/archive/2026-08-27-projectile-system/specs/projectile-runtime/spec.md) · scripts/components/ProjectileController.gd |
| teleport-detonate | Invisible projectiles skip flight: spawn at the muzzle, position at the target coordinate, detonate at dispatch (same tick as the legacy hitscan path) through the hitbox pipeline. Behavior-preserving against the legacy hitscan path. | [projectile-system change](openspec/changes/archive/2026-08-27-projectile-system/specs/projectile-runtime/spec.md) |
| detonation trigger | Ordered first-match causes a projectile detonates: contact, close proximity while armed, overshoot (target distance stops decreasing), max range. Close detonations snap onto the victim's center. | [projectile-system change](openspec/changes/archive/2026-08-27-projectile-system/specs/projectile-runtime/spec.md) |
| arming | `ProjectileData.arm_delay` frames after spawn during which a projectile cannot detonate at all. Frame-based, not distance-based (original engine armed by distance). | scripts/data/ProjectileData.gd |

## Movement

| Term | Meaning | Where |
|------|---------|-------|
| locomotor | Registered movement-behavior class (`GlobalRules.locomotors`); sole authority on passability via terrain speeds. | [locomotor](openspec/specs/locomotor/spec.md) |
| movement zone | TS pathfinding domain-class metadata on EntityData; validated against the locomotor (`LOCOMOTOR_ZONES`) but doesn't gate passability. | [entity-data](openspec/specs/entity-data/spec.md) |
| climb tolerance | Max grade steps ascendable/descendable per cell transition. | [locomotor](openspec/specs/locomotor/spec.md) |
| hybrid locomotion | Hover / Jumpjet / Subterranean flags with distance thresholds deciding walk↔fly/dig switching. | [locomotor](openspec/specs/locomotor/spec.md) · [jumpjet-vertical-transitions](openspec/specs/jumpjet-vertical-transitions/spec.md) |
| speed ramp | Closed-form ramping of locomotor speed (accelerate/decelerate flags); targets move_speed directly with per-unit factors multiplying on top; crawl floor near arrival; resets at arrival/finish_stop. | [locomotor](openspec/specs/locomotor/spec.md) |
| `speed` (TS) | Per-unit movement rate on `EntityData`: the original TS `Speed` value in leptons per game frame (0 = immobile). Converted to world units/second by `GlobalRules.speed_to_units_per_second()`; `weight` never scales it. | [entity-data](openspec/specs/entity-data/spec.md) · [global-rules](openspec/specs/global-rules/spec.md) |
| movement time base | Logic ticks per second the content's tick-based values are authored against (`GlobalRules.logic_fps`; 30 = the project's 2× TS base, consistent with `build_speed` and the ROF base). Sets `move_speed = Speed × 2.56 × logic_fps × CELL_SIZE / 256` — `0.6 × Speed` u/s at 30 Hz. | [global-rules](openspec/specs/global-rules/spec.md) · [locomotor](openspec/specs/locomotor/spec.md) |
| greedy step | Pathfinder primitive: one-cell direct step toward goal when reachable without full A*. | [pathfinder](openspec/specs/pathfinder/spec.md) |
| greedy-first resolution | Try greedy step before computing an A* route. | [pathfinder](openspec/specs/pathfinder/spec.md) |
| stagnation fallback | Recovery when a unit stops making progress along its path. | [pathfinder](openspec/specs/pathfinder/spec.md) |
| height cost penalty | A* edge cost scaling with slope between cells. | [pathfinder](openspec/specs/pathfinder/spec.md) |

## Orders & Selection

| Term | Meaning | Where |
|------|---------|-------|
| order targeter | Component interface: each component declares which click targets it handles. | [order-system](openspec/specs/order-system/spec.md) · [entity-components](openspec/specs/entity-components/spec.md) |
| `OrderResult` | Funnel output data class mapping an input to per-entity orders. | [order-system](openspec/specs/order-system/spec.md) |
| docker | Unit docking at a building (e.g. harvester unloading); host rejects foreign dockers. | [dock-host-client](openspec/specs/dock-host-client/spec.md) |
| deploy / undeploy | Vehicle↔building transformation via `deploys_into` / `undeploys_into`. | [deploy-undeploy](openspec/specs/deploy-undeploy/spec.md) |
| stop command | Halts all selected units' activity; overridden by any later order. | [stop-command](openspec/specs/stop-command/spec.md) |
| fog-gated targeting | Entity targets must be visible to the local player (explored *and* currently visible); force-fire at a bare **cell** needs only the shroud lifted, so fog does not block it. | [order-system](openspec/specs/order-system/spec.md) |
| force fire | Ctrl-modified attack order (`OrderResult.MOD_FORCE_ATTACK`): bypasses the legal-target test, so a ground cell, an ally, an own unit, a neutral or a bridge becomes a valid target. Refused only by shroud — explored-but-fogged ground still fires. | [order-system](openspec/specs/order-system/spec.md) · scripts/hud/MouseHandler.gd |
| legal target | Entity an unmodified attack order may be issued at: hostile (`player_id >= 0` and `PlayerManager.is_enemy`). Force fire bypasses the test; unarmed entities never fire at all. | [combat-firing](openspec/specs/combat-firing/spec.md) |
| ground engagement | `CombatComponent` firing at a world position with no entity target — `_target_pos` is the source of truth, `_target` is null. Repeats on cooldown until a player move, the Stop command, or the shooter's death. | [combat-firing](openspec/specs/combat-firing/spec.md) · scripts/components/CombatComponent.gd |
| enemy selection | Non-local entities are selectable for viewing only: a selection never mixes local and non-local owners, and a non-local selection contributes no cursor or orders. | [selection-manager](openspec/specs/selection-manager/spec.md) · [order-system](openspec/specs/order-system/spec.md) |
| exit | Production spawn point config (`spawn_offset`, `exit_offset`, `exit_facing`); rally point destination follows. | [production-exit](openspec/specs/production-exit/spec.md) |
| load / unload | Infantry entering (boarding) vs ejecting from a transport. Load requires a stationary transport with free seats and never queues; unload runs via the deploy command and ejects one passenger per interval. | [add-transport-passengers](openspec/changes/add-transport-passengers/specs/transport-passengers/spec.md) |

## Rendering & Audio

| Term | Meaning | Where |
|------|---------|-------|
| cameo | Sidebar build icon image (`ArtData.cameo_path`). | [cameo-tooltip](openspec/specs/cameo-tooltip/spec.md) |
| MultiMesh bucket | Per-region instanced render batch for baked unit models; slots compacted, transforms synced per frame. | [unit-multimesh-rendering](openspec/specs/unit-multimesh-rendering/spec.md) |
| ghost | Destroyed-entity silhouette retained under fog/shroud ("tombstone" for units, fog ghost for buildings). | [fog-rendering](openspec/specs/fog-rendering/spec.md) |
| revealer | Entity-side registration granting visibility stamps into ShroudSystem. | [fog-of-war](openspec/specs/fog-of-war/spec.md) |
| shroud vs fog | Shroud = permanently-explored-or-black grid; fog = re-covering dynamic layer. Independently toggleable. | [fog-of-war](openspec/specs/fog-of-war/spec.md) · [fog-rendering](openspec/specs/fog-rendering/spec.md) |

## Art & Animation

| Term | Meaning | Where |
|------|---------|-------|
| animation clip | One GLB visual attached to entity art: a model, an offset, playback config, a `role`, and a power flag. `AnimClipData` entries in `ArtData.animations`. One file per clip — not merged into the base model. | [art-component change](openspec/changes/art-component-animation-engine/specs/art-component/spec.md) · scripts/data/AnimClipData.gd |
| clip role | What drives a clip: `ACTIVE` loops and is power-gated/damaged-swapped; `DOOR`, `PRODUCTION`, `BUILDUP`, etc. are one-shot lifecycle clips. | [art-component change](openspec/changes/art-component-animation-engine/specs/art-component/spec.md) |
| damaged clip | `AnimClipData.damaged_model_path`: a separate GLB shown in place of an `ACTIVE` clip at health ≤ 50%, reverting above. | [art-component change](openspec/changes/art-component-animation-engine/specs/art-component/spec.md) |
| theater variant | With `ArtData.new_theater`, an art path resolves to `<name>_<theater>.<ext>` (e.g. `gdi_conyard01_snow.glb`) when that file exists, else the generic path. Suffix is the full theater id, not the TS letter. | [art-component change](openspec/changes/art-component-animation-engine/specs/art-component/spec.md) · scripts/data/ArtData.gd |

## Visual Effects (FX)

| Term | Meaning | Where |
|------|---------|-------|
| `FxData` | One one-shot visual effect as a `.tres`: `kind` is `SPRITE` (animated billboard via `SpriteFrames`, PNG sequence or sprite sheet) or `PARTICLES` (embedded `ParticleProcessMaterial` + draw material). Purely visual — no audio field. | [fx-system](openspec/specs/fx-system/spec.md) · scripts/data/FxData.gd |
| `FxSystem` | Autoload that plays one-shot effects (`play(fx, transform)`) with a deterministic duration timer, and gates them to fog: no spawn in shroud/fog, live effects freeze while hidden. | [fx-system](openspec/specs/fx-system/spec.md) · scripts/core/FxSystem.gd |
| muzzle flash | One-shot effect played at a weapon's muzzle on each shot (`WeaponData.muzzle_fx`). | [combat-firing](openspec/specs/combat-firing/spec.md) |
| impact FX | One-shot effect played at a victim on each damaging hit (`WarheadData.impact_fx`), fired from the shared damage choke point so it covers projectile and hitscan hits. | [entity-factory](openspec/specs/entity-factory/spec.md) |

## Data Fields (high-drift picks)

Full dictionaries: scripts/data/*.gd. Only ambiguous pairs listed here.

| Term | Meaning | Where |
|------|---------|-------|
| `buildable_queue` vs `factory` | On produced entities: which queue they belong to vs on producing buildings: what they produce. Both strings reference the same namespace but point opposite directions. | scripts/data/EntityData.gd |
| `spawn_offset` vs `exit_offset` | Where a unit appears inside the building vs where it walks out to (local space). | [production-exit](openspec/specs/production-exit/spec.md) |
| `passengers` vs `storage` | Infantry seat count on transports vs raw-bale carry capacity on harvesters. | scripts/data/EntityData.gd |
| `pip_color` | Seat pip color for a passenger riding in a transport (per entity type, default white); harvesters' cargo pips are unaffected. | scripts/data/EntityData.gd |
| `strength` | Max hit points (legacy rules.ini name — do not rename casually). | scripts/data/EntityData.gd |
| `tech_level` | Per-type build gate; the house's current level must be at least this. `-1` = never buildable (original TS semantics). | scripts/data/EntityData.gd · [tech-level](openspec/specs/tech-level/spec.md) |
| current tech level | A player's live level (`PlayerData.tech_level`), resolved from the mission or the rules default; compared against `EntityData.tech_level` on the build list. | [tech-level](openspec/specs/tech-level/spec.md) |
| `powered` vs `is_online` | Data-level "requires power to function" flag (`EntityData.powered`, copied to PowerComponent) vs runtime state (`PowerComponent.is_online`, driven by the grid). Deliberately different names — never write `is_powered()` for the runtime state. | scripts/data/EntityData.gd · [add-power-grid change](openspec/changes/add-power-grid/specs/power-grid/spec.md) |

## Mission Scripting

| Term | Meaning | Where |
|------|---------|-------|
| match clock | The fixed 30 Hz logic tick that all simulation and mission scripting advance on; owns an integer frame counter and deadline scheduler. | [match-clock](openspec/specs/match-clock/spec.md) |
| trigger | A data record (stable id, owner house, tags, events, actions, difficulty flags) that fires when all its events are satisfied. | [trigger-engine](openspec/specs/trigger-engine/spec.md) |
| tag | The attachment handle that carries a trigger onto a location (general list, owner house list, map cell, or object) and holds its persistence. A trigger with no tag is never armed. | [trigger-engine](openspec/specs/trigger-engine/spec.md) |
| event | A trigger condition: standing (checked every tick — credits, flags, build exists, elapsed time) or temporal (satisfied only by a matching occurrence — destroyed, attacked, cell entry). | [trigger-engine](openspec/specs/trigger-engine/spec.md) |
| action | A trigger effect (win/lose, reveal, message, spawn, camera, sound, set/clear flag, timer control, destroy, enable/disable/force trigger). Dispatched from a deferred journal at the tick boundary. | [trigger-engine](openspec/specs/trigger-engine/spec.md) |
| persistence | A tag's lifetime: `volatile` (fire once, then destroy), `semi-persistent` (fire on the last remaining holder), `persistent` (fire on every satisfying tick and remember satisfied temporal events). | [trigger-engine](openspec/specs/trigger-engine/spec.md) |
| waypoint | A named map cell (`id` → grid cell) used by trigger actions (camera, reveal, reinforcement, meteor). | [scenario-state](openspec/specs/scenario-state/spec.md) |
| global flag | A mission-scoped named boolean visible to every house; set/clear actions and events. | [scenario-state](openspec/specs/scenario-state/spec.md) |
| local flag | A mission-scoped named boolean scoped to one house; distinct from a global of the same name. | [scenario-state](openspec/specs/scenario-state/spec.md) |
| mission timer | The mission's countdown clock, in whole logic seconds, driven by the match clock; expiry fires the timer-expired event. | [scenario-state](openspec/specs/scenario-state/spec.md) |

## Cross-Title Systems (unified-engine target)

Terms surfacing in multi-title research (TS/FS/RA2/YR). No authoritative spec exists yet for
most; anchors point to the research set until an OpenSpec change lands.

| Term | Meaning | Where |
|------|---------|-------|
| side | Faction axis in the house system (TS/FS: GDI/Nod; RA2: Allied/Soviet; YR adds ThirdSide). Sides group countries/houses. | [capability-matrix](docs/capability-matrix.md) |
| country | RA2/YR sub-faction (e.g. Britain, Korea, YuriCountry) with unique units and bonuses; gated by `RequiredHouses`/`ForbiddenHouses`, bound to art/palette/voice by list index. | [red-alert-2](docs/titles/red-alert-2.md) |
| superweapon | Building-mounted charged global power (Ion Cannon, Nuke, Chronosphere, Iron Curtain, Weather Storm, Psychic Dominator). Needs a generic charge/target/fire framework. | [capability-matrix](docs/capability-matrix.md) |
| support power | Charged power with no (or shared) host: Spy Plane, Psychic Reveal, Paradrop, Force Shield, Mutation, Domination. | [yuris-revenge](docs/titles/yuris-revenge.md) |
| superweapon charge | Per-player recharge timer; completed superweapons reveal their tile and share the timer with all players (YR contract). | [yuris-revenge](docs/titles/yuris-revenge.md) |
| mind control | Ownership override targeting a unit: temporary `MindControl` warhead control (capacity = weapon `Damage`), or permanent `PsychicDominator` capture. Needs a control-link manager. | [yuris-revenge](docs/titles/yuris-revenge.md) |
| garrison | Occupancy subtype: infantry/vehicles inside a building or bunker, with stat bonuses and optional fire-from-inside / power hook. | [yuris-revenge](docs/titles/yuris-revenge.md) |
| fire-from-transport | Passengers firing their own weapons from inside a transport (Battle Fortress) — separated from RA2's IFV passenger-driven weapon modes in the current `TransportComponent`. | [ra2](docs/titles/red-alert-2.md) |
| staged weapon / gattling stage | Multi-stage spin-up weapons (`IsGattling`, `WeaponStages`, `StageX`, `RateUp`/`RateDown`); odd stages AG, even AA. | [yuris-revenge](docs/titles/yuris-revenge.md) |
| prism support | RA2 weapon effect where supporting prism structures combine beams into one stronger shot. | [ra2](docs/titles/red-alert-2.md) |
| aura | Per-tick radius effect (heal, repair, sensor, reveal, mind control, slow/status) attached to an entity. | [capability-matrix](docs/capability-matrix.md) |
| status effect | Timed, serializable effect on an entity: EMP disable, cloak, berserk (allegiance override), poison/mutation, invulnerability. | [capability-matrix](docs/capability-matrix.md) |
| cloak / stealth | Hidden visual+targeting state with `Cloakable`/`CloakingSpeed`; countered by `Sensors` units/structures and attack dogs. | [ts-firestorm](docs/research/_raw/ts-firestorm.md) |
| sensor | Detection capability that reveals cloaked/subterranean units within range. | [ts-firestorm](docs/research/_raw/ts-firestorm.md) |
| gap generator / radar blackout | Bubble that hides friendly units from enemy radar/shroud and blacks out the enemy minimap in radius. | [ra2](docs/titles/red-alert-2.md) |
| spy infiltration | Spy entering an enemy building for an effect (blackout, money steal, reveal, sabotage, promotion). Distinct from engineer capture. | [ra2](docs/titles/red-alert-2.md) |
| crate | Pickup placed on the map granting money, heal, unit, reveal, firepower, armor, speed, or promotion. | [ts-firestorm](docs/research/_raw/ts-firestorm.md) |
| trigger / event / action | Mission-scripting primitive: condition (time, cell entry, destroyed, global) → action (reinforce, reveal, message, win/lose, ownership change). Engine shipped — see Mission Scripting above. | [trigger-engine](openspec/specs/trigger-engine/spec.md) |
| taskforce / teamtype / scripttype | AI/scripted team definitions (members, behavior flags, action lists) used by campaigns and skirmish AI. | [capability-matrix](docs/capability-matrix.md) |
| reinforcement | Trigger-driven spawn of units via land/sea/air/drop pod/paradrop entry. | [ts-firestorm](docs/research/_raw/ts-firestorm.md) |
| ion storm | TS/FS dynamic weather: lightning damage, disables radar/superweapons while active, reveals map. | [ts-firestorm](docs/research/_raw/ts-firestorm.md) |
| vein / veinhole | TS/FS growing tendril resource-hazard; veins around a Veinhole; distinct from tiberium crystals. | [ts-firestorm](docs/research/_raw/ts-firestorm.md) |
| visceroid | TS/FS tiberium lifeform; small visceroids merge into large ones; infantry can mutate. | [ts-firestorm](docs/research/_raw/ts-firestorm.md) |
| chrono / teleport locomotor | RA2/YR instant relocation with distance-scaled delay (Chronosphere, Chrono Legionnaire, Chrono Miner). | [ra2](docs/titles/red-alert-2.md) |
| game mode | Skirmish/multiplayer ruleset token (`GameModes=`); YR adds Team Alliance and a `cooperative` token. | [yuris-revenge](docs/titles/yuris-revenge.md) |
| ownership override | Runtime change of an entity's controlling player (mind control, capture); the control-link graph is serializable so it survives save/load. | [gap-analysis](docs/gap-analysis.md) |

## Undecided

User-owned choices — do **not** guess these when writing specs; ask, then record
the decision here.

- `archetype` vs `template` vs `type` — no decision yet. Note: `archetype`
  appears nowhere in code or specs today; `template` currently means only TS
  `.tem` terrain templates ([isotem-tooling](openspec/specs/isotem-tooling/spec.md)).
- **Isometric camera ratio** — keep the current 45°-yaw orthographic view (GLOSSARY
  `isometric view`) or move to a true 2:1 dimetric projection? Affects model authoring
  and all screen↔world math. No decision yet — see
  [unified-engine architecture](docs/architecture/unified-engine.md#4-isometric-3d-rendering-target).
- **Multi-title packaging** — expansion titles as delta data sets over a base (recommended in
  the research) vs merged standalone rule sets. No decision yet.
- **Target balance patch level** — for YR the final official patch is **1.001** (some data
  mirrors capture 1.000 and several costs differ). Use 1.001 as the default target unless
  decided otherwise. For TS/FS and RA2 the final patch is the default.
- **Shroud parity** — the original TS shroud is local-player-only, not per-house; the current
  `ShroudSystem` is per-player. Keep per-player (superset) or match original parity? No decision.
