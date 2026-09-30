# Unit Roster - ReSun

## Overview
The unit roster defines all playable units across factions, including their stats, abilities, and counter relationships. This creates strategic depth through rock-paper-scissors balance.

## Implementation Status (verified 2026-08-08)

**Roster is effectively TS-complete: 408 EntityData .tres files.**

| Type | Count | Notes |
|------|-------|-------|
| INFANTRY | 26 | GDI: light inf, disc thrower, engineer, medic, jumpjet, ghost stalker, chem spray, umagon. Nod: light/rocket inf, engineer, cyborg(s), chameleon spy, mutant hijacker, slavick, oxanna. Civilians/mutants. |
| VEHICLE | 38 | MCV, harvester(+docked), mammoth(+mk2), titan, wolverine, amphibious APC, disruptor, hover MLRS, hunter seeker, mobile sensor array; Nod buggy, cycle, stealth tank, tick tank, subterranean APC, devils tongue, artillery, ICBM, weed eater, mobile repair vehicle. |
| BUILDING | 168 | GDI 24, Nod 27, Neutral 6 (incl. guardtower, Scrin ship), ~110 civilian |
| AIRCRAFT | 8 | orca fighter/bomber/transport, carryall, dropship, drop pod, kodiak; banshee, harpy. **No weapons populated.** |
| TERRAIN | 44 | trees, ice (5), boxes, tiberium trees, vein tree, riparius |
| OVERLAY | 84 | walls/fences, rocks, tracks, 20 green + 12 blue crystal pods, veins |
| SMUDGE | 40 | burns, craters, scorch |

Weapons 44 .tres, warheads 27, armor 5, land types 6, locomotors 9, art ~325 .tres (43 with model_path; mostly placeholders). Buildable: 73.

Not implemented from this plan: counter-system logic, hero/special units with abilities, aircraft weapons.

**Plan-doc staleness:** the "~30 more .tres files" status below is massively stale — the roster is ~408 files.

## Historical Implementation Status (stale — kept for reference)

- ✅ EntityData.gd — single resource class with all entity properties
- ✅ WeaponData.gd — unlimited weapons per entity
- ✅ EntityFactory.gd — creates entities from data, adds components dynamically
- ✅ .tres files created for: E1, BGGY, HARV, MCV, GACNST, GAPOWR, NAPOWR, TREE01
- 🔄 Remaining: ~30 more .tres files (Issue #23), component logic (Issues #28-40) — *both done*

## Core Requirements

### 1. Infantry Units
| Unit | Faction | Role | Cost | Health | Special Ability |
|------|---------|------|------|--------|-----------------|
| Marine | GDI | Anti-infantry | 50 CR | 40 | Squad formation |
| Engineer | Both | Capture/repair | 250 CR | 30 | Build/capture structures |
| Terrorist | Nod | Sabotage | 600 CR | 25 | Self-destruct on death |

### 2. Vehicle Units  
| Unit | Faction | Role | Cost | Health | Special Ability |
|------|---------|------|------|--------|-----------------|
| APC | GDI | Transport | 700 CR | 300 | Carry 4 infantry |
| Tank Destroyer | GDI | Anti-tank | 1200 CR | 450 | Long-range anti-armor |
| Attack Car | Nod | Fast attack | 800 CR | 200 | Ramming damage |
| Nuke Launcher | Nod | Siege | 3000 CR | 600 | Nuclear strike ability |

### 3. Aircraft Units (Optional Phase)
- Fighter jets for anti-air coverage
- Bombers for ground assault capability  
- Transport helicopters for unit delivery
- All require airfield production structure

### 4. Hero/Special Units
| Unit | Faction | Role | Unlocks | Special Ability |
|------|---------|------|---------|-----------------|
| Commander GDI | GDI | Leader | Endgame | Call in orbital strike |
| Kane Clone | Nod | Leader | Endgame | Self-revive once |

### 5. Counter Relationships
- Infantry counters: Vehicles (via engineer capture)
- Anti-tank counters: Infantry with rockets, tank destroyers
- Air superiority counters: Anti-air units vs aircraft
- Base defense counters: Siege weapons vs buildings

## Technical Implementation

### Entity System Integration
All units are defined via the **composition-based entity system** (see GitHub Issue #22):

```
EntityData.tres (single resource, all properties)
    ↓ EntityFactory autoload
Entity.tscn + dynamically added components
```

- **One `EntityData.gd`** resource class with ALL properties
- Unit type determined by `entity_type` field (INFANTRY, VEHICLE, BUILDING, AIRCRAFT, TERRAIN)
- Weapons stored as `Array[WeaponData]` — unlimited weapons per entity
- Health via `strength` field → HealthComponent added if > 0
- Movement via `speed` field → MovementController added if > 0
- Combat via `weapons` array → CombatComponent added if non-empty

### Data Files
```
resources/entities/
├── infantry/
│   ├── e1_rifle_infantry.tres    # EntityData instance
│   ├── e2_disc_thrower.tres
│   └── engineer.tres
├── vehicles/
│   ├── bggy_attack_buggy.tres
│   ├── 4tnk_mammoth.tres
│   └── harv_harvester.tres
├── structures/
│   ├── gdi_conyard.tres
│   └── ...
└── terrain/
    ├── tree01.tres
    └── ...

resources/weapons/
├── minigun.tres                  # WeaponData instance
├── raider_cannon.tres
├── 120mm.tres
└── ...

resources/art/
├── infantry/
│   ├── e1_rifle_infantry_art.tres
│   └── ...
└── vehicles/
    ├── bggy_attack_buggy_art.tres
    └── ...
```

### Unit Template (EntityData)
```gdscript
# Example: E1 Rifle Infantry
{
    "id": "E1",
    "display_name": "Light Infantry",
    "entity_type": "INFANTRY",
    "strength": 125,
    "armor": "none",           # customizable string, not hardcoded
    "cost": 120,
    "tech_level": 1,
    "sight": 5,
    "speed": 5.0,
    "owner": ["GDI", "Nod"],
    "weapons": [WeaponData("minigun")],
    "movement_zone": "Infantry",
    "c4": false,
    "engineer": false
}
```

### Counter System Logic
- Define counters in GlobalRules or separate CounterData resource
- Apply multiplier when unit attacks counter target
- Display advantage indicator in UI (green/red arrows)
- Track combat effectiveness for balance tuning

## Integration Points
- Connect to production system for spawning templates
- Link with faction system for variant selection
- Coordinate with combat AI for targeted engagement
- Interface with economy for cost validation

## Related
- **Entity System**: See GitHub Issue #22 — composition-based architecture (IMPLEMENTED)
- **Faction Systems**: See `7-1_faction_systems.md` for faction bonuses/modifiers
- **Combat Weapons**: See `3-1_combat_weapons.md` for WeaponData system
- **Data Population**: See GitHub Issue #23 for .tres file creation
- **Component Issues**: See GitHub Issues #28-40 for component-specific implementation

## Historical Implementation Status (stale — kept for reference)

- ✅ EntityData.gd — single resource class with all entity properties
- ✅ WeaponData.gd — unlimited weapons per entity
- ✅ EntityFactory.gd — creates entities from data, adds components dynamically
- ✅ .tres files created for: E1, BGGY, HARV, MCV, GACNST, GAPOWR, NAPOWR, TREE01
- 🔄 Remaining: ~30 more .tres files (Issue #23), component logic (Issues #28-40) — *both done*

## Future Enhancements
- Dynamic unit balancing based on win rates
- Custom unit creation tools for modders
- Unit prestige systems (veterancy levels)
- Synergy bonuses when combining specific units
