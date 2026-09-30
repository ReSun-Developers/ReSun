## Context

ReSun has 11 autoloads. EconomyManager owns PlayerData instances in a lazy `_players` dict. BuildingManager, Sidebar, and ProductionManager hardcode `player_id = 0`. No concept of "local player", no team relationships, no faction identity. This blocks component implementation that needs owner tracking (HealthComponent, CombatComponent, FactoryComponent, PowerComponent).

Current state:
- `PlayerData.gd`: 4 lines — `player_id` + `credits`
- `EconomyManager.gd`: 48 lines — owns `_players` dict, lazy creation, emits signals
- `BuildingManager.gd`: hardcodes `em.deduct(0, ...)` at lines 147, 611; `ps.register_building(0, ...)` at line 35; `pm.clear_waiting_for_placement(0)` at line 170
- `Sidebar.gd`: hardcodes `player_id != 0` at line 499; `pm.get_ready_buildings(0)` at line 367; 6+ more `pm.get_queue_key(0, ...)` calls
- `ProductionManager.gd`: hardcodes `0` in `clear_waiting_for_placement` and `cancel_ready_building`

## Goals / Non-Goals

**Goals:**
- Centralized player registry (PlayerManager autoload)
- Rich PlayerData with identity, faction, team, color, bot flag
- Team-based relationship queries (is_enemy)
- Local player ID lookup (get_local_player_id)
- MapConfig for per-map player setup (scene child node, PlayerConfig inner class)
- Stateless EconomyManager (reads from PlayerManager)

**Non-Goals:**
- Network sync / multiplayer (deferred to Phase 8)
- AI bot behavior (data layer only — is_bot flag)
- Lobby UI for player setup (MapConfig is hand-crafted .tres per map)
- Fog of war / shroud per-player (separate system)
- Power grid per-player (separate system)
- ProductionState extraction (queue state stays on ProductionManager)
- Starting units spawning (field exists in MapConfig, no spawn system yet)

## Decisions

### D1: PlayerManager as thin registry

**Decision**: PlayerManager is a new autoload that owns PlayerData instances and provides lookup methods. It does NOT own economy logic, production queues, or any gameplay systems. It loads BEFORE all other autoloads.

**Rationale**: Keeps concerns separated. EconomyManager continues to own economy logic (add/deduct/signals). ProductionManager continues to own queue processing. PlayerManager is just the "who is in this game" registry.

**Alternative considered**: Centralized state owner where PlayerManager owns ALL per-player state. Rejected because it would require refactoring EconomyManager, ProductionManager, and PrerequisiteSystem to delegate to PlayerManager — massive churn for no gameplay benefit.

### D2: No ProductionState extraction

**Decision**: Queue state (`_queues`, `_active_index`, `_deduction_accums`, `_waiting_for_placement`, `_ready_to_place`) stays internal to ProductionManager. No new resource.

**Rationale**: ProductionManager is the ONLY consumer of queue state. Extracting it creates two objects to stay in sync for zero callers. The string-key approach (`"0:infantry"`) already works.

**Alternative considered**: ProductionState as separate resource on PlayerData. Rejected as over-engineering for one consumer. Extract when Sidebar or replay needs direct access.

### D3: Team-based relationships

**Decision**: `team_id: int` on PlayerData. Same team = ally, different team = enemy. PlayerManager provides `is_enemy(a_id, b_id) -> bool` and `get_players_by_team(team_id)`.

**Rationale**: Classic C&C is always team-based (2v2, FFA). No asymmetric diplomacy. Simple and sufficient. Both methods are one-liners and the core reason for team_id.

**Alternative considered**: OpenRA-style bitmask relationships. Rejected as overkill — supports asymmetric alliances that C&C never uses.

### D4: Faction as Resource

**Decision**: `Faction` resource (.tres) with id, display_name, color. Stored under `resources/factions/`. Referenced by `PlayerData.faction_id`.

**Rationale**: Data-driven. Adding a new faction means creating a .tres file, not changing code. Matches existing EntityData pattern. Sidebar's `CAMEO_COLORS` dict becomes `PlayerManager.get_faction_color(player_id)`.

**Alternative considered**: Faction info as const dict or inline on PlayerData. Rejected because it doesn't scale and mixes display logic with data.

### D5: MapConfig per-map (scene child node)

**Decision**: `MapConfig` resource with PlayerConfig inner class. MapConfig is a child node of the map scene. PlayerManager finds it by type at `_ready()`. If no MapConfig found, creates defaults (player 0 = human, player 1 = AI bot).

**Rationale**: Matches Redot's scene composition pattern. Maps can define their own player configurations without code changes. Fallback ensures backward compatibility.

**Alternative considered**: Each map script calls `PlayerManager.add_player()` directly. Rejected because it doesn't support non-programmers setting up maps.

**PlayerConfig inner class fields**: player_id, faction_id, team_id, color, spawn_index, display_name, is_bot, starting_credits (-1 = use GlobalRules.default), starting_units (PackedStringArray, field only — no spawning yet), power_output (int, field only — no power system yet).

### D6: EconomyManager stays stateless

**Decision**: EconomyManager calls `PlayerManager.get_player_data(player_id)` instead of its own `_players` dict. Signals stay on EconomyManager. Callers don't change their signal connections.

**Rationale**: Minimal churn. EconomyManager's API doesn't change — just its internal data source. Sidebar, ProductionManager, etc. continue connecting to EconomyManager signals.

**Alternative considered**: Move signals to PlayerManager. Rejected because it would require updating every signal connection in the codebase.

### D7: Local player ID via method call

**Decision**: Callers use `PlayerManager.get_local_player_id()` when needed. No caching, no constants.

**Rationale**: The method call is trivially fast. Caching adds state that can drift. Constant defeats the purpose of PlayerManager. Verbose but explicit.

### D8: MapConfig starting_credits override

**Decision**: MapConfig.starting_credits overrides GlobalRules.starting_credits when set (-1 = use GlobalRules default).

**Rationale**: Maps should be able to set custom starting credits. The -1 sentinel for "use default" is clean.

### D9: is_bot on PlayerData

**Decision**: PlayerData includes `is_bot: bool` field. Set by MapConfig. No AI logic yet — data layer only.

**Rationale**: Completes the player identity model. AI systems will read this flag when implemented.

## Risks / Trade-offs

- **Autoload count**: 11 → 12. PlayerManager loads BEFORE EconomyManager (EconomyManager reads from it in _ready).
- **Test breakage**: EconomyManager tests call `_em.add(0, 500, ...)` directly. After refactor, tests need PlayerManager setup in scene tree.
- **ProductionManager queue migration NOT included**: Queue state stays on ProductionManager. String keys (`"0:infantry"`) remain. No structural change to ProductionManager beyond replacing hardcoded `0`.
- **is_in_group("enemy") gap**: CombatComponent and TransportComponent check this but nothing assigns entities to the "enemy" group. This change adds team_id but doesn't fix targeting — separate task.
- **MapConfig has no loader UI**: Every new map needs a hand-crafted .tres. No UI for player setup. Acceptable for now.
- **Starting units not spawned**: MapConfig.starting_units field exists but no spawn system. Field is data-only.
- **Power output not used**: MapConfig.power_output field exists but no power system. Field is data-only.
