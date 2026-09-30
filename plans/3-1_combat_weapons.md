# Combat & Weapons System - ReSun

## Overview
The combat system handles all damage calculation, weapon mechanics, and unit health management. This is critical for balanced gameplay and engaging tactical decisions.

## Core Requirements

### 1. Damage Types
| Type | Effective Against | Resistance Examples |
|------|-------------------|---------------------|
| Bullet | Infantry, light vehicles | Armor reduces effectiveness |
| Explosive | Structures, armored units | Buildings take more damage |
| Energy | Vehicles, structures | Shields mitigate energy |
| Anti-Air | Aircraft only | Ground units immune |
| Siege | Buildings only | Units take reduced damage |

### 2. Weapon System Stats
- **Damage**: Base damage per shot/projectile
- **Fire Rate**: Time between shots (seconds)
- **Range**: Maximum target distance
- **Accuracy**: Probability of hitting (0.0 - 1.0)
- **Projectiles**: Number fired per volley
- **Splash Radius**: Area damage for explosives

### 3. Armor & Resistance
- Each unit has armor value reducing incoming damage
- Damage formula: `final_damage = base_damage * (1 - armor_resistance)`
- Resistances vary by damage type (e.g., tanks resist bullets)
- Overpenetration mechanics for high-damage weapons

### 4. Health Mechanics
- **Health Points**: Unit durability pool
- **Regeneration**: Passive healing over time when not in combat
- **Repair**: Active repair via engineer or self-repair ability
- **Death Effects**: Particle explosion, debris scatter, resource drop

## Technical Implementation

### Entity System Integration
Weapons are defined as `WeaponData` resources referenced by `EntityData.weapons: Array[WeaponData]` (see GitHub Issue #22):

```
WeaponData.tres (per weapon type)
    ↓ referenced by
EntityData.tres (weapons array)
    ↓ created by
EntityFactory autoload → CombatComponent
```

- **Unlimited weapons per entity** — not just primary/secondary
- Weapons stored as `Array[WeaponData]` in EntityData
- CombatComponent added when `weapons.size() > 0`
- Elite weapons stored separately in `EntityData.elite_weapons: Array[WeaponData]`

### Warhead System
Warheads define damage types and modifiers (from rules.ini [Warheads] section):

```
WarheadData extends Resource
├── id: String              # "HE", "AP", "Fire", "Sonic", etc.
├── damage_modifier: float  # multiplier vs armor types
├── cell_spread: float      # area damage spread
├── death_anim: String      # explosion animation
└── ...
```

### Armor System (Customizable)
Armor types stored in `GlobalRules.armor_types: Dictionary` — not hardcoded:

```
# From rules.ini Armor= field (string-based)
"none":    { "modifier": 1.0 }
"wood":    { "modifier": 0.7 }
"light":   { "modifier": 0.6 }
"heavy":   { "modifier": 0.4 }
"concrete":{ "modifier": 0.3 }
# Can add unlimited types: "flak", "energy", "shield", etc.
```

### Key Scripts

#### WeaponData.gd (Resource)
```gdscript
class_name WeaponData extends Resource
@export var id: String = ""
@export var damage: int = 0
@export var rate_of_fire: float = 1.0
@export var range: float = 1.0           # in cells
@export var warhead: String = "HE"
@export var projectile: String = ""
@export var fire_flh: Vector3 = Vector3.ZERO
@export var barrel_length: float = 0.0
@export var anti_air: bool = false
@export var anti_ground: bool = true
@export var splash_radius: float = 0.0
@export var ammo: int = -1               # -1 = unlimited
```

#### CombatComponent.gd (Component)
- Fire rate timer management
- Range check against target distance
- Accuracy roll for hit determination
- Spawn projectiles or apply hitscan damage directly
- Supports unlimited weapons via array iteration

#### HealthComponent.gd (EXISTING)
- Track current health/max health ratio
- Apply damage with armor calculation (from GlobalRules.armor_types)
- Trigger death when health ≤ 0
- Handle repair/regeneration over time

### Damage Calculation Logic
```gdscript
func calculate_damage(damage_type, base_damage, target_armor):
    # Get resistance values from unit stats
    var resistance = target_armor.get_resistance(damage_type)
    
    # Apply armor reduction
    var final_damage = base_damage * (1.0 - resistance)
    
    # Floor at minimum damage (1 point always gets through)
    return max(1, floor(final_damage))

func take_damage(amount, damage_type):
    current_health -= calculate_damage(damage_type, amount, armor)
    
    if current_health <= 0:
        on_unit_destroyed()
```

### Weapon Firing System
- Check range before firing
- Perform accuracy roll (random 0.0-1.0 vs weapon accuracy)
- On hit: apply damage to target's HealthComponent
- On miss: spawn impact effect at target location
- Cooldown timer prevents spamming attacks

## Integration Points
- Connect to unit system for weapon/health component attachment
- Link with pathfinding for movement while attacking
- Coordinate with selection for targeting feedback visuals
- Interface with economy for death resource refunds

## Related
- **Entity System**: See GitHub Issue #22 — composition-based architecture (IMPLEMENTED)
- **Unit Roster**: See `7-2_unit_roster.md` for unit weapon assignments
- **Combat AI**: See `3-2_combat_ai.md` for target selection logic
- **Component Issues**: See GitHub Issues #28-40 for component-specific implementation
- **CombatComponent**: Issue #28 — implement firing logic, target acquisition, turret rotation
- **HitboxComponent**: Issue #29 — implement damage detection and forwarding
- **HealthComponent**: Issue #30 — implement armor calculation, death effects, regen

## Implementation Status (verified 2026-08-08)

- ✅ WeaponData.gd — unlimited weapons per entity via `Array[WeaponData]` (44 .tres)
- ✅ WarheadData.gd — **exists** (`scripts/data/WarheadData.gd`, 27 .tres) — the ❌ below is stale
- ✅ GlobalRules.armor_types — **wired end-to-end** via `ArmorType` (5 .tres) + `GlobalRules.get_warhead_armor_multiplier`; warhead → armor → clamped damage chain works (the ❌ below is stale)
- ✅ CombatComponent — **real firing logic**: chase-to-range, cooldowns (`60/rof`), hitscan damage, veteran multiplier, fire sounds, jumpjet air approach (the ❌ "no firing logic" below is stale)
- ✅ HitboxComponent — detects damage; note: damage currently routes via CombatComponent hitscan, not projectile-triggered hitbox
- ✅ HealthComponent — `take_damage()` (veteran armor reduction), `heal`, `health_zero` signal; **death handler exists** — EntityFactory frees node + plays death voice, BuildingManager unregisters cells (the ❌ below is stale)
- ✅ Attack command (#79) — resolved via order system (no `request_attack`; `CombatComponent.get_order_for_target`)

**Remaining:**
- Runtime projectiles (#78, #89) — `ProjectileData.gd` schema exists; no Projectile node/system. Damage is pure hitscan.
- `splash_radius` (AoE), `anti_air`/`anti_ground` enforcement, `is_laser`/`is_sonic`/`is_railgun`, `ambient_damage`, accuracy rolls, ammo/volley — data-only, unused
- Turret rotation (`turret`/`turret_anim` data, no logic)
- Death effects (explosions, debris, resource drop) — death = voice + free only
- Passive regeneration / dock-based repair — not implemented
- **Combat AI is entirely separate** — see `3-2_combat_ai.md` (greenfield)

## Historical Status (stale — kept for reference)

- ✅ WeaponData.gd — unlimited weapons per entity via `Array[WeaponData]`
- ❌ WarheadData.gd — **does not exist yet** (listed in #23 but not created) — *STALE, now implemented*
- ❌ GlobalRules.armor_types — referenced but unused, chain broken without WarheadData — *STALE, now wired*
- ✅ CombatComponent — stores weapons, turret info, threat posed (no firing logic) — *firing now implemented*
- ✅ HitboxComponent — detects projectile hits, forwards to HealthComponent (no projectile to trigger it)
- ✅ HealthComponent — take_damage(), health_zero signal (no death handler listens) — *death handler now exists*

## Gaps (added 2026-07-18, status updated 2026-08-08)

### Projectile System (Issue #78) — STILL OPEN
- No projectile nodes exist — hitscan is used for all damage
- Need: Projectile Node3D scene + ProjectileData resource
- WeaponData already has `projectile` and `speed` fields

### Attack Command (Issue #79) — RESOLVED
- ~~SelectionManager has no `request_attack()`~~ — attacks route through the order system (`CombatComponent.get_order_for_target` → ATTACK prio 30)
- ~~MouseHandler has no left-click-on-enemy handler~~ — implemented
- ~~CombatComponent has no `set_target()` entry point from player input~~ — `set_target` exists
- Entity ownership (player_id) + `PlayerManager.is_enemy()` target filtering — implemented

### WarheadData (Issue #23 gap) — RESOLVED
- ~~WeaponData.warhead is a String but no WarheadData class exists~~ — `scripts/data/WarheadData.gd` + 27 .tres
- Chain: weapon warhead string → WarheadData → damage type → armor modifier — **works end-to-end** (`get_warhead_armor_multiplier`)

### Death Handler (Issue #82) — RESOLVED
- ~~health_zero signal fires but nothing listens~~ — `EntityFactory._on_entity_death` (free + voice) and `BuildingManager` (cell/prereq unregister) both listen
- ~~Destroyed buildings persist as ghosts occupying cells~~ — cells are freed on death

## Future Enhancements
- Cover mechanics (units gain defense behind obstacles)
- Flanking bonuses based on attack angle
- Weapon upgrade trees per faction
- Special abilities with cooldowns and resource costs
