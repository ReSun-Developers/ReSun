# Combat AI System - ReSun

## Overview
The combat AI governs how units behave during engagements, including target selection, engagement rules, and tactical decision-making. This creates believable enemy behavior and assists player unit automation.

## Implementation Status (verified 2026-08-08)

**Entirely greenfield — 0% implemented.** Units only fight when player-ordered (`CombatComponent.set_target`); there is no auto-engagement, no idle-guard, no chase state machine, no threat scoring, no retreat rules, and no GameAI/faction AI of any kind. The "Nod AI Opponent" is a `PlayerData.is_bot` flag only.

Not blocked on anything — it builds on the combat/hitscan system (`3-1`) and the order system (`2-2`). A first playable GDI Mission 01 can ship with a **static/passive Nod base** (the First Blood pattern), deferring scripted team AI (#238) until after the trigger engine (#237) exists.

---

## Core Requirements

### 1. Target Selection Logic
- Priority ranking: high-value targets first (factories > infantry)
- Proximity weighting: closer enemies prioritized
- Threat assessment based on weapon damage output
- Randomization to prevent predictable patterns

### 2. Combat States Machine
| State | Trigger | Behavior |
|-------|---------|----------|
| Idle | No threats detected | Patrol or return to base |
| Chase | Enemy enters detection radius | Move toward target |
| Attack | Within weapon range | Stop and fire weapons |
| Flee | Health critical (<30%) | Retreat to safety/repair |
| Pursue | Target moving away | Continue chase beyond original range |

### 3. Engagement Rules
- **Engagement Radius**: When to engage enemies
- **Retreat Threshold**: Health percentage triggering retreat
- **Fire Control**: When to stop firing (target destroyed)
- **Re-engagement**: Conditions for resuming attack after pause

### 4. Morale & Stamina Systems (Optional)
- Units lose morale under heavy fire
- Extended combat reduces unit effectiveness over time
- Rally mechanics allow recovery after retreat
- Optional system based on desired realism level

## Technical Implementation

### Scene Structure
```
CombatAI.tscn (attached to units)
├── TargetSelector.gd (enemy identification logic)
├── StateMachine.gd (combat state transitions)
└── MoraleSystem.gd (optional behavioral modifier)
```

### Key Scripts

#### TargetSelector.gd
- Scan all enemies within vision radius
- Calculate threat score for each target
- Select highest priority target based on faction strategy
- Update selection every combat tick (~0.5s intervals)

#### StateMachine.gd
- Handle state transitions with guard conditions
- Execute state-specific behaviors (move, attack, flee)
- Manage state timers and cooldowns
- Emit events for UI feedback when states change

### Target Selection Algorithm
```gdscript
func select_best_target(enemies):
    var best_target = null
    var highest_threat = 0.0
    
    for enemy in enemies:
        # Calculate threat based on weapon damage and distance
        var threat_score = enemy.dps * (1.0 / distance_to(enemy))
        
        # Apply faction-specific modifiers
        threat_score *= get_faction_preference(enemy.unit_type)
        
        if threat_score > highest_threat:
            highest_threat = threat_score
            best_target = enemy
    
    return best_target

func get_faction_preference(unit_type):
    # GDI prefers anti-infantry, Nod prioritizes tanks
    match faction:
        "GDI":
            if unit_type == "infantry": return 1.5
        "NOD":
            if unit_type == "vehicle": return 1.3
    return 1.0
```

### State Machine Transitions
- **Idle → Chase**: Enemy enters engagement radius AND has weapons
- **Chase → Attack**: Within weapon range of target
- **Attack → Flee**: Health drops below retreat threshold
- **Flee → Idle**: Reached safe distance or no longer pursued
- **Any → Idle**: Target destroyed or out of vision

## Integration Points
- Connect to combat system for damage/death events
- Link with pathfinding for movement during chase/flee states
- Coordinate with selection system for AI-controlled unit feedback
- Interface with economy on unit death (resource refunds)

## Future Enhancements
- Squad-level AI coordination (multiple units attacking together)
- Dynamic flanking behavior based on terrain
- Adaptive difficulty scaling AI aggression levels
- Unit-specific tactics (snipers stay back, tanks charge forward)
