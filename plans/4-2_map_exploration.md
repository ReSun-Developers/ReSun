# Map Exploration & Win Conditions - ReSun

## Overview
Map exploration tracking enables victory conditions based on territory control and provides feedback for strategic planning. This system works alongside the fog of war to create competitive gameplay objectives.

## Implementation Status (verified 2026-08-08)

**Entirely greenfield — 0% implemented.** No ExplorationManager, WinConditionSystem, VisionSharing, or RevealBlackout exists. There is no exploration tracking, no win-condition evaluation, and no victory/defeat triggers anywhere.

Note: for GDI Mission 01, a minimal win/lose (annihilation-style: destroy all Nod / lose refinery+barracks) will be built on the new trigger engine (#237) + objectives (#240) rather than the full exploration/domination machinery in this doc.

---

## Core Requirements

### 1. Exploration Tracking
- Monitor percentage of map explored by each player
- Track unique tiles visited vs total available tiles
- Handle neutral structures as exploration sources
- Account for vision-sharing mechanics between allies

### 2. Win Conditions
| Condition | Description | Typical Threshold |
|-----------|-------------|-------------------|
| Domination | Control X% of map area | 90-100% |
| Annihilation | Destroy all enemy units/buildings | 100% elimination |
| Objective | Capture specific points/objects | Varies by mission |
| Time Limit | Highest score within time limit | Score-based scoring |

### 3. Vision Sharing Mechanics
- Allies share vision within their combined radius
- Buildings provide shared vision to all allies
- Units only see what they personally detect
- Shared intel for coordinated attacks

### 4. Reveal/Blackout Systems
- **Reveals**: Temporary or permanent area exposure abilities
- **Blackouts**: Disable enemy vision in targeted region
- Scramble signals jam communications temporarily
- Strategic use affects fog of war state

## Technical Implementation

### Scene Structure
```
ExplorationManager.tscn (Autoload Singleton)
├── WinConditionSystem.gd (victory check logic)
├── VisionSharing.gd (ally coordination)
└── RevealBlackout.gd (ability effects)
```

### Key Scripts

#### WinConditionSystem.gd
- Evaluate win condition each game tick or on trigger events
- Calculate exploration percentage per player
- Check annihilation status for all factions
- Trigger victory/defeat sequences when conditions met

#### VisionSharing.gd
- Link ally units/buildings via shared vision list
- Update fog state when any ally sees enemy
- Handle temporary vision sharing (abilities)
- Maintain separate vision layers per faction

### Exploration Percentage Calculation
```gdscript
func calculate_exploration(player_id):
    var total_tiles = map_data.get_total_tiles()
    var explored_tiles = map_data.get_explored_tiles_for_player(player_id)
    
    return float(explored_tiles) / float(total_tiles) * 100.0

func check_domination_win(player_id):
    var exploration_pct = calculate_exploration(player_id)
    
    if exploration_pct >= domination_threshold:
        trigger_victory(player_id, "domination")
```

### Vision Sharing Implementation
- Store ally relationships in player data structure
- When unit detects enemy, mark all allies' vision updates
- Buildings with shared vision broadcast to allied network
- Temporary sharing via abilities (scramble, reveal)

## Integration Points
- Connect to fog of war for visibility state management
- Link with economy system for score calculation (resources destroyed)
- Coordinate with UI system for win condition progress display
- Interface with save/load for exploration persistence

## Future Enhancements
- Customizable victory conditions per map/mission
- Dynamic objectives that appear mid-game
- Team-based vision sharing in multiplayer
- Exploration bonuses (faster unit movement on explored terrain)
