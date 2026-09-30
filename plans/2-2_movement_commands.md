# Unit Movement & Commands System - ReSun

## Overview
The movement system handles all unit navigation and command execution, translating player inputs into in-game actions. This includes basic movement, attack orders, formation management, and pathfinding integration.

**Grid cell size: 2m × 2m.** Each vehicle unit occupies exactly one cell (occupancy radius = ~1.0 m). Movement is continuous — units slide smoothly across cell boundaries without snapping or grid-lock stepping.

## Implementation Status (verified 2026-08-08)

| Command | Status | Notes |
|---------|--------|-------|
| Move | ✅ | Left-click ground → `SelectionManager.request_move` with formation offsets (clamped ±2-cell) |
| Attack | ✅ | Left-click/Ctrl+Left-click enemy → `CombatComponent.get_order_for_target` (ATTACK prio 30) → chase + fire. `Ctrl+Left` is the explicit attack: engage only that target, suppress auto-acquire en route (once #261 lands) |
| Attack-Move (Ctrl+Shift+Left) | ❌ | Not implemented — #264 |
| Patrol | ❌ | Not implemented |
| Gather | ✅ | `HarvestComponent` HARVEST/ENTER orders + full dock loop |
| Formation menu | ❌ | Static click-offset formation only; no `FormationComponent` |
| Group hotkeys 1–0 | ❌ | Not bound in `project.godot` |
| Real shift-queue | ❌ | `queued` flag cosmetic; path replaced, not appended |

Order pipeline (implemented): `MouseHandler` → `OrderSystem` (active generator) → `UnitOrderGenerator` / `SellOrderGenerator` / `RepairOrderGenerator` → `OrderResolver` (highest priority wins) → `OrderResult.execute`. See `5-1_rts_interface.md` §6.

Tests: `test_order_resolver.gd`, `test_unit_order_generator.gd`, `test_movement_controller_infantry.gd`, `test_selection_manager.gd`.

**Note:** Right-click is deselect/cancel only (never issues orders); left-click is select/act. This doc's Phase 1 "right-button drag pan" and attack-on-right-click were superseded by the input-role convention. Mouse model (2026-09-14): `Ctrl+Left` = explicit attack (target only), `Ctrl+Shift+Left` = attack-move, `Alt+Left` = force-move, `Shift` = queue.

---

## Core Requirements

### 1. Command Types
| Command | Input | Behavior |
|---------|-------|----------|
| Move | Left-click → destination | Pathfind to location, stop when arrived |
| Attack | Left-click enemy (or `Ctrl+Left` for explicit target-only) | Move to target and engage in combat; `Ctrl+Left` suppresses auto-acquire en route |
| Attack-Move | `Ctrl+Shift+Left` area | Move through area while engaging enemies encountered, then resume (#264) |
| Force-move | `Alt+Left` | Move ignoring enemies |
| Patrol | Double-click or patrol button | Cycle between waypoints indefinitely (future) |
| Gather | Right-click resource node (UI) | Navigate to resource, collect, return to base |
| Formation | Formation menu + position | Maintain specific formation during movement (future) |

### 2. Path Following Execution — Phase 1 (Current)
- **Kinematic movement**: `global_position += direction * speed * delta` — no physics bodies, units pass through static geometry without pushing (straight-line only; navmesh integration handles wall avoidance in Phase 2).
- **Y-axis rotation via look_at() on XZ plane** each `_physics_process()` tick: `$MeshRoot.look_at(global_position + Vector3(direction.x, target_y, direction.z))` where `target_y = global_position.y`. This prevents pitch/roll artifacts when the click position has a different elevation.
- **Smooth sliding between cells**: Units glide continuously across 2m grid boundaries — no snapping or discrete stepping. Movement is determined by `(speed * delta)` per physics tick, independent of cell size.
- **Radial repulsion steering for obstacle avoidance** (Phase 1): Each unit checks all nearby entities within ~3 m radius during `_physics_process()`. If another vehicle's center falls within `cell_radius × 2` distance (~2.0 m), a push-away force is computed as `(unit_position - neighbor_center).normalized() / (distance²)` and added to the movement direction vector before normalization. This produces natural flow-around behavior without any global pathfinding — units naturally form lanes or queue behind each other when paths converge, matching Tiberian Sun's traffic feel.
- **Arrival detection**: When `(target - global_position).length() <= arrival_threshold` (default 1.0 m), the unit transitions to Idle and emits an `arrived` signal.

### 2b. Path Following Execution — Phase 2+ (Navmesh Integration)
- Follow computed waypoint arrays from NavigationServer3D or A*.
- Replace single `_current_target` with `_waypoints: PackedVector3Array` + index tracking in MovementController.
- Radial repulsion steering remains as the local obstacle avoidance layer on top of global pathfinding — this architecture requires no changes since both phases use the same kinematic update loop and the `direction` vector is simply sourced from navmesh waypoints instead of a single target position.

### 3. Attack-Move Logic (Phase 2+)
- Combine movement path with combat radius checks.
- Engage enemies encountered along route automatically — priority: destroy threats before continuing path.
- Fallback to simple move if no enemies detected.

### 4. Formation System
| Formation | Use Case | Behavior |
|-----------|----------|----------|
| Line | Anti-infantry spread | Units in horizontal line, even spacing |
| Column | Fast movement through narrow terrain | Single file, faster travel |
| Wedge | Combat advance | V-shape with leader at front |
| Diamond | Balanced defense | Central unit protected by surrounding units |
| Scatter | Area coverage | Max separation for resource gathering |

## Technical Implementation

### Scene Structure (Phase 1)
```
EntityRoot.tscn (Node3D / MeshInstance3D — the glb mesh IS the root for NodBuggy)
├── HealthComponent.gd
├── HitboxComponent.gd
└── SelectComponent.gd
└── MovementController.gd   ← new child component, extends Node3D

MovementController.tscn (Node3D with script attached — follows existing pattern)
```

### Key Scripts — Phase 1

#### MovementController.gd
- **Extends `Node3D`** (kinematic movement only; no CharacterBody3D/physics bodies in Phase 1). Vehicles glide over terrain without physics collision overhead. A downward raycast for Y-axis terrain following is deferred to Phase 2 after the input flow is validated.
- State machine: `{ IDLE, MOVING }` — enum-based state transitions on arrival detection and new target assignment.
- `_physics_process(delta)`: compute direction → rotate mesh root via `look_at()` on XZ plane (Y component preserved from current position to prevent pitch/roll artifacts per gameidea tutorial lessons) → apply radial repulsion steering against nearby units within ~3 m radius → translate by `(direction + repulsion).normalized() * move_speed * delta` → check arrival threshold.
- **Radial repulsion steering**: iterate all nodes in "entities" group; for each unit where `distance_to(neighbor) < cell_radius × 2`, add push-away force normalized by distance² to the movement direction before final normalization and translation. No grid occupancy map required — proximity-based steering produces natural lane formation without global pathfinding.
- Exports: `move_speed` (float = 8.0), `arrival_threshold` (float = 1.0, ~half-cell), `cell_radius` (float = 1.0, half of 2m cell size). Optional `rotation_target_path: NodePath` — defaults to self for scenes where the mesh root IS the scene root (e.g., NodBuggy's `.glb`).

#### MouseHandler.gd (Phase 1 extension)
- `_get_ground_position_at_mouse(ground_mask = 1)` method: casts ray from camera through cursor at default collision layer, returns `result.position` or sentinel `Vector3.INF`.
- `_handle_single_click()`: after entity raycast miss (mask `1 << 15`, no collider found), cast ground plane ray. If units are selected and terrain hit found (`position != Vector3.INF`), call `SelectionManager.request_move(ground_pos)`. Left-click on entities still selects them as before — box-select and hover preview paths remain unchanged.

#### SelectionManager.gd (Phase 1 extension)
- New signal: `signal move_requested(position: Vector3)`
- Public method: `request_move(target_position: Vector3)` iterates over existing `selected_entities` array, checks each parent for `"MovementController"` child via `has_node("MovementController")`, calls `movement_controller.set_target_position(target_position)`. Entities without MovementController (structures like GDIConyard) are silently skipped.

### Path Following Algorithm — Phase 1
```gdscript
# Core movement loop in _physics_process(delta):
func _physics_process(delta: float) -> void:
    if current_state != State.MOVING: return
    
    var direction := (_current_target - global_position).normalized()
    
    # Radial repulsion steering against nearby units (Phase 1 obstacle avoidance)
    for entity in get_tree().get_nodes_in_group("entities"):
        var neighbor_dist := global_position.distance_to(entity.global_position)
        if neighbor_dist < cell_radius * 2.0:
            var push_away := (global_position - entity.global_position).normalized() / squaref(neighbor_dist)
            direction += push_away
    
    # Rotate mesh root on XZ plane — Y component preserved to prevent pitch/roll
    rotation_target.look_at(global_position + Vector3(direction.x, 0.0, direction.z))
    
    # Translate kinematically (no physics bodies in Phase 1)
    global_position += direction.normalized() * move_speed * delta
    
    # Arrival detection
    if (_current_target - global_position).length() <= arrival_threshold:
        current_state = State.IDLE
        arrived.emit(global_position)

# Square helper — avoids sqrt for performance-critical inner loop comparison
func squaref(v: float) -> float: return v * v
```

### Command Input Flow (Phase 1)
| Player Action | Result |
|---------------|--------|
| Left-click on entity | OrderSystem resolves component orders (attack, harvest, deploy, etc.); if no order matches and entity is local, selects it |
| Left-click on empty ground | OrderSystem.get_orders(null, ...) → UnitOrderGenerator returns group move OrderResult → execute callback calls SelectionManager.request_move(pos) with formation logic |
| Left-click on empty ground with no units selected | No action taken (silent) |
| Right-click anywhere | Always calls `selection_manager.deselect_all()` regardless of what's under cursor. No movement logic runs from right-click. |

### Order Resolution Flow
```
MouseHandler._handle_left_click_normal()
  → _build_modifiers(shift_pressed)
  → OrderSystem.get_orders(target, target_cell, target_pos, modifiers)
    → UnitOrderGenerator.get_orders()
      → if target == null (terrain): return [OrderResult(execute = sm.request_move(pos))]
      → if target != null: return OrderResolver.resolve_all(selected_entities, target, ...)
        → per entity: iterate components with get_order_for_target()
        → return Array[OrderResult] — one per matching entity
  → for each order: order.execute.call()
```

### Formation Management (Phase 3+)
- Calculate formation offsets relative to leader unit.
- Each unit maintains offset while following leader's path.
- Dynamic reformation when terrain constraints prevent ideal spacing (requires navmesh integration).
- Break formation on attack-move commands (spread for combat).

## Integration Points
- Connect to navigation system for path calculation requests (Phase 2+ navmesh integration)
- Link with combat system for attack-move integration
- Coordinate with selection system for group command handling
- Interface with minimap for movement preview visuals

## Phase Timeline Summary

| Phase | Features | Dependencies |
|-------|----------|-------------|
| **Phase 1 (current)** | Kinematic straight-line move via left-click, Y-axis rotation on XZ plane, radial repulsion steering between units, arrival detection, GroundPlane scene for raycast targets | Existing MouseHandler + SelectionManager infrastructure; no physics bodies needed |
| **Phase 2** | Navmesh-based A* pathfinding (Redot `NavigationServer3D` or custom grid), waypoint array support in MovementController, downward terrain-following raycast for Y-axis correction at runtime, multi-waypoint movement with smooth interpolation | Requires navmesh generation pipeline; map scenes already have GroundPlane from Phase 1 |
| **Phase 2b** | Attack orders (left-click on enemy units) — reuses MovementController's waypoint array but appends combat-enage waypoints after reaching target zone | Combat weapons system must exist first |
| **Phase 3+** | Formation management, command queuing UI with drag-drop, attack-move logic, patrol routes, gather/resource-return behavior | Requires navmesh integration + faction/roster systems to be in place |

## Future Enhancements (Post-Phase 1)
- Advanced formation morphing (smooth transitions between shapes) — Phase 3+
- Terrain-aware formations that adapt to narrow passages automatically — requires navmesh, Phase 3+
- Command queuing UI with drag-drop reordering of move/attack orders
- Formation presets saved per faction/unit type — post-release content
