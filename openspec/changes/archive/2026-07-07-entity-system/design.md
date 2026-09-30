## Context

The ReSun project currently has a minimal entity system:
- `BuildingType.gd` — 9-field resource for buildings only
- 4 component scenes (Health, Hitbox, Select, MovementController) — manually wired per entity
- `NodBuggy.tscn` — hand-built scene with all 4 components
- 6 GDI building placeholder scenes — each with hardcoded component NodePaths
- No data-driven approach for units, infantry, or terrain objects

The original Tiberian Sun defines all entities via `rules.ini` (gameplay stats) and `art.ini` (visual properties). These flat key-value sections naturally map to a component-based architecture where properties trigger component addition.

**Constraints:**
- Redot 26.2 LTS (Forward Plus renderer)
- GDScript only — no C#
- Must support mod/DLC data sets in the future
- Must not break existing gameplay (NodBuggyDev.tscn kept as test entity)
- .tres files for all data (native Godot resources)

## Goals / Non-Goals

**Goals:**
- Single `EntityData.gd` resource class with ALL entity properties (composition, not inheritance)
- Single `Entity.tscn` base scene — components added dynamically by EntityFactory
- Unlimited weapons per entity (Array[WeaponData])
- Unlimited active animations per entity (Array[ActiveAnimData])
- Customizable armor system (string-based, not hardcoded enum)
- Load-time validation with error logging (don't crash, degrade gracefully)
- Mod/DLC support via EntityFactory.register_data_set()
- Separate ArtData resource per entity (visual properties isolated from gameplay)
- GlobalRules resource for default game values (from rules.ini [General])

**Non-Goals:**
- Map/mission override system (design supports it, implement in later phase)
- Full INI parser (manual .tres creation for now)
- Complete unit roster (start with ~10-15 entities, expand incrementally)
- Combat AI target selection (separate system)
- Networking/multiplayer entity sync

## Decisions

### Decision 1: Single EntityData class (not per-type subclasses)

**Choice**: One `EntityData.gd` with ALL properties for ALL entity types.

**Alternatives considered:**
- Per-type subclasses (InfantryData, VehicleData, BuildingData) — rejected because composition means any entity can have any combination of properties. A vehicle with a factory (mobile war factory) is just an EntityData with `factory = "VehicleType"`.

**Rationale**: Rules.ini sections share most properties. The differences are which properties are *used*, not which ones *exist*. A single class with defaults for unused fields is simpler and more flexible.

### Decision 2: Component scenes only when child nodes needed

**Choice**: Components that need child nodes (CollisionShape3D, AnimationPlayer, mesh) get `.tscn` scenes. Pure data/logic components are `.gd` only.

**Components with .tscn:** HealthComponent, HitboxComponent, SelectComponent, CombatComponent, MovementController, ArtComponent

**Components as .gd only:** StatsComponent, FoundationComponent, PowerComponent, RadarComponent, FactoryComponent, TransportComponent, SpecialAbilityComponent

**Rationale**: Avoids unnecessary scene overhead for data-only components. Follows existing pattern — HealthComponent already has a scene because it's used by Area3D.

### Decision 3: Weapons as Array[WeaponData] (not fixed slots)

**Choice**: `EntityData.weapons: Array[WeaponData]` — unlimited weapons per entity.

**Alternatives considered:**
- Fixed primary/secondary/elite slots — rejected because some entities need 3+ weapons (Mammoth Tank has cannon + missiles + machine gun in original game).

**Rationale**: Matches rules.ini where entities can have Primary, Secondary, and Elite weapons. Array allows any count. Elite weapons stored in separate `elite_weapons` array.

### Decision 4: Customizable armor system (string-based)

**Choice**: `armor: String` on EntityData, resolved via `GlobalRules.armor_types: Dictionary`.

**Alternatives considered:**
- Hardcoded enum (NONE, WOOD, LIGHT, HEAVY, CONCRETE) — rejected because mods/DLCs need custom armor types.

**Rationale**: Rules.ini uses string keys for armor. Dictionary lookup is flexible. Adding a new armor type requires zero code changes — just add to GlobalRules.armor_types.

### Decision 5: Separate ArtData per entity

**Choice**: `ArtData.gd` as a separate resource referenced by `EntityData.art_data`.

**Alternatives considered:**
- Art properties inline on EntityData — rejected because art data is large (model paths, animation offsets, FLH positions) and clutters gameplay data.

**Rationale**: Art.ini data is purely visual. Keeping it separate means gameplay scripts don't load art paths. ArtData can be swapped for skin variants without touching gameplay logic.

### Decision 6: EntityFactory as autoload

**Choice**: `EntityFactory.gd` registered as autoload singleton in project.godot.

**Alternatives considered:**
- Regular node in gameplay scene — rejected because entities can be spawned from anywhere (BuildingManager, unit production, crate drops).

**Rationale**: Autoload is always available. Mod/DLC data sets register via `register_data_set()` on the autoload.

### Decision 7: Validation on load, not on spawn

**Choice**: Validate EntityData when loaded from .tres, log errors, continue.

**Alternatives considered:**
- Validate on spawn — rejected because errors should be caught early (at data creation time), not at runtime when a unit is built.

**Rationale**: Early detection. push_warning() logs the error but doesn't crash. The entity spawns with whatever valid data it has.

## Risks / Trade-offs

**[Risk] Single EntityData class becomes bloated** → Mitigation: Fields have sensible defaults (0, false, ""). Only populated fields matter. Documentation groups fields by component.

**[Risk] Component wiring (NodePath exports) is fragile** → Mitigation: EntityFactory wires components programmatically after instantiation. No manual NodePath wiring in .tscn files.

**[Risk] Mod data sets override base data silently** → Mitigation: EntityFactory logs when a mod overrides a base entity. Register order is explicit.

**[Risk] Breaking BuildingManager during migration** → Mitulation: Keep existing NodBuggyDev.tscn as test entity. Update BuildingManager incrementally — first support both old and new paths, then remove old.

**[Trade-off] No map override system yet** → Accepted: Design supports it (MapOverride resource), but implementation deferred. Can add without breaking entity system.

**[Trade-off] Manual .tres creation** → Accepted: ~40 entities × 2 resources (EntityData + ArtData) = ~80 .tres files. Tedious but stable. INI parser can be a later tool.

## Migration Plan

1. **Phase 1**: Create new data classes and components alongside existing system
2. **Phase 2**: Create EntityFactory and Entity.tscn
3. **Phase 3**: Create .tres data files for existing entities (NodBuggy, GDI buildings)
4. **Phase 4**: Update BuildingManager to use EntityFactory (dual-path: old BuildingType + new EntityData)
5. **Phase 5**: Remove old BuildingType.gd and resources/buildings/*.tres
6. **Rollback**: If EntityFactory breaks, revert BuildingManager to use old BuildingType path. NodBuggyDev.tscn always works as fallback.

## Open Questions

- Should the `entity_type` field be an enum or string? (Leaning toward enum for type safety, but string for flexibility)
- How to handle the CivilianGuardTower01.tscn which currently has no components? (Add via EntityFactory with minimal data)
- Should ArtComponent have an AnimationPlayer child, or manage animations via code? (Leaning toward AnimationPlayer for editor preview)
