# Faction Systems - ReSun

## Overview
Faction systems define unique mechanics, units, buildings, and strategies for each playable side. This creates asymmetric gameplay that mirrors the original C&C: Tiberian Sun experience.

## Implementation Status (verified 2026-08-08)

| Aspect | Status | Notes |
|--------|--------|-------|
| GDI faction data | ✅ | `resources/factions/gdi.tres` + per-faction unit/building .tres |
| Nod faction data | ✅ | `resources/factions/nod.tres` |
| Faction asymmetry | 🟡 | Expressed purely via data (e.g. Nod stealth tank/obelisk, GDI mammoth); no mechanic bonuses |
| FactionManager autoload | ❌ | `Faction.gd` resource only; no `get_faction_bonus` |
| Faction-specific tech trees | 🟡 | Per-faction prerequisite data; no research/upgrade system |
| Special abilities | ❌ | `SpecialAbilityComponent.gd` is a data wrapper (`has_ability()` only); no ability logic |

**Plan-doc staleness:** the `FactionSystem.tscn` / `FactionManager.gd` / `TechTreeResolver.gd` scene structure never existed. Faction bonuses in `GlobalRules` (this doc's design) are not implemented.

## Historical Implementation Status (stale — kept for reference)

- ✅ EntityData.gd — single resource class with all entity properties
- ✅ EntityFactory.gd — creates entities from data, adds components dynamically
- ✅ GlobalRules.gd — default game values from rules.ini, customizable armor types
- 🔄 Remaining: Component logic (see issues #28-40), data population, integration — *component logic and data population done (22 components, 408 .tres); faction mechanics remain*

## Core Requirements

### 1. GDI Faction Mechanics
- **Playstyle**: Defensive, balanced, technology-focused
- **Unique Features**:
  - Stronger base defenses
  - Advanced repair capabilities
  - Shield/armor upgrades available earlier
  - Superior air unit support
- **Base Color Palette**: Blue/green/white (clean military aesthetic)

### 2. Nod Faction Mechanics  
- **Playstyle**: Aggressive, stealth-focused, guerrilla tactics
- **Unique Features**:
  - Stealth technology (camo units/buildings)
  - Faster production times
  - Sabotage abilities (destroy enemy structures)
  - Suicide unit variants
- **Base Color Palette**: Red/black/orange (dark militant aesthetic)

### 3. Unique Unit/Structure Differences
| Aspect | GDI | Nod |
|--------|-----|-----|
| Infantry | Marines with rifles | Stealth operatives |
| Vehicles | Heavy tanks, APCs | Fast attack cars, nukes |
| Air Units | Fighters, bombers | Stealth aircraft |
| Base Buildings | Reinforced walls | Camo concealers |
| Special Ability | Orbital strike | Nuclear launch |

### 4. Tech Tree Variations
- Faction-specific research paths
- Different prerequisite structures for unlocking
- Unique upgrades per faction (e.g., GDI shields, Nod camo)
- Asymmetric power curves (early vs late game strengths)

## Technical Implementation

### Entity System Integration
All faction entities (units, buildings, infantry) are defined via the **composition-based entity system** (see GitHub Issue #22):

```
EntityData.tres (single resource, all properties)
    ↓ EntityFactory autoload
Entity.tscn + dynamically added components
```

- **One `EntityData.gd`** resource class with ALL properties (no per-type subclasses)
- Faction assignment via `owner: PackedStringArray` and `faction: String` fields
- Faction-specific units are just EntityData instances with different component combinations
- `GlobalRules.gd` holds faction-wide bonuses (e.g., GDI repair speed, Nod production speed)

### Scene Structure
```
FactionSystem.tscn (Autoload Singleton)
├── FactionManager.gd (singleton faction logic)
└── TechTreeResolver.gd (unlock validation)
```

### Key Scripts

#### FactionManager.gd (Singleton)
- Track active faction per player
- Provide faction bonuses and modifiers via GlobalRules
- Resolve faction-specific unit/building variants
- Handle special ability cooldowns and costs

#### EntityFactory.gd (Autoload)
- Creates any entity from EntityData resource
- Components added dynamically based on data properties
- Faction determines which .tres data files are loaded

### Faction Data Structure
```gdscript
var factions = {
    "GDI": {
        "name": "Global Defense Initiative",
        "color": Color(0.2, 0.6, 0.9),
        "bonuses": {"repair_speed": 1.5, "shield_strength": 1.3},
        "units": ["marine", "apc", "tank_destroyer"],
        "buildings": ["con_yard", "power_plant", "tech_center"]
    },
    "NOD": {
        "name": "Children of Nod", 
        "color": Color(0.9, 0.2, 0.2),
        "bonuses": {"production_speed": 1.3, "stealth_duration": 2.0},
        "units": ["terrorist", "attack_car", "nuke_launcher"],
        "buildings": ["con_yard_stealth", "power_plant_dark", "temple"]
    }
}

func get_faction_bonus(faction, bonus_type):
    return factions[faction].bonuses[bonus_type]
```

### Tech Tree Resolution Logic
- Check prerequisite buildings exist before unlock
- Apply faction-specific prerequisites (different tech paths)
- Track research progress per player/faction
- Enable units/buildings when requirements met

## Integration Points
- Connect to unit production for variant spawning
- Link with economy system for faction cost modifiers
- Coordinate with combat AI for faction behavior patterns
- Interface with UI system for faction-specific menus

## Related
- **Entity System**: See GitHub Issue #22 — composition-based architecture (IMPLEMENTED)
- **Unit Roster**: See `7-2_unit_roster.md` for planned unit data
- **Mod/DLC Support**: EntityFactory supports layered data sets for faction extensions
- **Component Issues**: See GitHub Issues #28-40 for component-specific implementation tasks

## Historical Implementation Status (stale — kept for reference)

- ✅ EntityData.gd — single resource class with all entity properties
- ✅ EntityFactory.gd — creates entities from data, adds components dynamically
- ✅ GlobalRules.gd — default game values from rules.ini, customizable armor types
- 🔄 Remaining: Component logic (see issues #28-40), data population, integration — *component logic and data population done (22 components, 408 .tres); faction mechanics remain*

## Future Enhancements
- Additional factions (Scrin, Nod splinter groups)
- Faction reputation system affecting diplomacy
- Customizable faction loadouts in multiplayer
- Faction victory animations and cinematics
