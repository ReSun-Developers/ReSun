# per-player-data-and-logic

Per-player data and logic infrastructure for ReSun. Adds PlayerManager autoload, PlayerData, Faction, MapConfig resources. Refactors EconomyManager, BuildingManager, ProductionManager, Sidebar, PrerequisiteSystem to use centralized player state.

## Key Decisions

- **No ProductionState extraction** — queue state stays on ProductionManager
- **Faction as .tres resource** — data-driven, matches EntityData pattern
- **MapConfig as scene child node** — PlayerManager finds it by type at _ready()
- **PlayerConfig as inner class** — fields: player_id, faction_id, team_id, color, spawn_index, display_name, is_bot, starting_credits, starting_units, power_output
- **Estateless EconomyManager** — swaps data source, keeps API and signals
- **Local player ID via method call** — `PlayerManager.get_local_player_id()`, no caching
- **First autoload** — PlayerManager loads before all others
