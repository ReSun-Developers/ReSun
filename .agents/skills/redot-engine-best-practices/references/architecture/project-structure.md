# Project Structure Conventions

Recommended directory layout for Redot 26.2 LTS projects using the component-based architecture pattern. This structure is AI-navigable: scripts, scenes, and assets are organized so that related files share both path proximity and naming alignment.

## Top-Level Layout

```
project/
├── project.godot              # Engine config + autoload registration
├── scripts/                    # All GDScript source (.gd)
│   ├── components/            # Reusable entity behavior (HealthComponent, HitboxComponent)
│   ├── core/                  # Engine-level systems / Autoloads (SelectionManager, SceneManager)
│   ├── hud/                   # Camera, mouse input, UI overlays during gameplay
│   └── ui/                    # Menu logic, HUD elements not tied to a specific entity scene
├── scenes/                    # All packed scenes (.tscn) — mirrors scripts structure + entities
│   ├── components/            # Component entity definitions (HealthComponent.tscn matching HealthComponent.gd)
│   ├── core/                  # Core system scenes (Gameplay container, BoundsSystem)
│   ├── environment/           # Lighting, world settings, HDRI maps
│   ├── entities/              # Placeable game units and structures
│   │   ├── infantry/          # Faction-agnostic or single-faction infantry types
│   │   └── structures/        # Buildings per faction: gdi/, nod/, neutral/
│   ├── hud/                   # Camera, MouseHandler scene instances (wired to autoloads)
│   ├── maps/                  # Playable map definitions (.tscn that instance entities + camera setup)
│   └── ui/                    # Menu scenes (MainMenu.tscn, MainMenuItem.tscn)
├── assets/                    # External resources — never edited by hand in the engine editor
│   ├── models/                # .glb / .gltf mesh files (+ exported texture PNGs per model dir)
│   ├── textures/              # Surface textures (.png, .jpg) for materials and terrain tiles
│   ├── hdri/                  # Environment map HDRIs (e.g., syferfontein_6d_clear_1k.hdr)
│   ├── fonts/                 # TTF font families used in UI labels
│   └── ui/                    # Menu background images, HUD overlays, icons
├── shaders/                   # All .gdshader files — one shader per file at top level or subfolders by category
└── plans/                     # Design documents, system specs (not engine-scene dependent)
```

## Scene-to-Script Naming Convention

Every `.tscn` scene that has a script should share the same base name:

| Script | Scene File | Relationship |
|--------|-----------|--------------|
| `scripts/components/HealthComponent.gd` | `scenes/components/HealthComponent.tscn` | 1-to-1 — component entity definition |
| `scripts/core/SelectionManager.gd` | *(no scene)* | Autoload singleton attached to a map/container scene, not its own .tscn |
| `scripts/hud/CameraController.gd` | `scenes/hud/Camera01.tscn` (named "Camera") | 1-to-1 — HUD subsystem instance |

**Exception:** Entity scenes that bundle multiple component children (`NodBuggy.tscn`) do **not** share a single script file. Instead, each child node has its own component script attached:
```
NodBuggy.tscn (root)
├── HealthComponent    → HealthComponent.gd
├── HitboxComponent     → HitboxComponent.gd
└── SelectComponent     → SelectComponent.gd
```

## Scene Composition Rules

1. **Components are child scenes** — each component script has a matching `.tscn` that defines the node hierarchy for that component (e.g., `HealthComponent.tscn` is just a Node3D root with no children). Entity scenes instance these as children via `[node name="..." parent="." index="N" instance=ExtResource("...")]`.

2. **NodePath exports wire sibling references** — components reference each other through exported `@export var health_component: HealthComponent` fields set to NodePaths in the scene editor (e.g., `health_component = NodePath("../HealthComponent")`). This avoids hardcoding script-level type references and keeps scenes self-contained.

3. **Maps are containers, not standalone games** — a map scene (`MapBase01.tscn`, `TestMap01.tscn`) instances the camera system, mouse handler, bounds system, lighting, and entity entities as children. The main entry point (`MainScene.tscn` or project.godot default_scene) should instance one of these maps at runtime rather than having all logic in a single scene file.

4. **Autoloads are registered in `project.godot`, not scenes** — the only autoload currently is `SelectionManager`. New system-level singletons (GameManager, EventBus) must be added to Project Settings → Autoload with their script path and name. They do NOT need dedicated `.tscn` files.

## File Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Script class names | `PascalCase` | `HealthComponent`, `SelectionManager` |
| Scene file names | `PascalCase` (matches scene root node name) | `NodBuggy.tscn`, `MainScene.tscn` |
| Entity scenes under entities/ | Faction/category prefix optional, always PascalCase | `GDIConyard01.tscn`, `CivilianGuardTower01.tscn` |
| Component script files | Same as class name: `PascalCase.gd` | `HealthComponent.gd` |
| Shader files | `PascalCase + NumberSuffix.gdshader` | `MainMenuItemBlur01.gdshader` |
