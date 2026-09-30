# Main Menu & UI System - ReSun

## Overview
The main menu serves as the primary hub for player interaction, providing access to all game modes and settings. It must capture the C&C aesthetic while delivering modern usability standards.

## Implementation Status (verified 2026-08-08)

| Feature | Status | Notes |
|---------|--------|-------|
| Main menu screen | 🟡 | `MainMenu01.tscn` + `MainMenu01.gd` — TS-style visual; only "Exit" works; other buttons print placeholders |
| Menu → gameplay flow | ❌ | `MainScene.tscn` has an empty `Gameplay` node; no script loads a map into it; devs run map scenes standalone (`TestMap02.tscn`). `EntityMaskManager.gd:64` hardcodes a camera path that doesn't exist in the shipped scene |
| Loading screen | ❌ | `LoadingScreen.tscn` is an inert static ProgressBar, hidden |
| Pause | ❌ | No `get_tree().paused` anywhere; no pause menu/action |
| Game save/load | ❌ | Only map-editor JSON dialogs (`EditorSaveLoad.gd`) + `InputSettings` cfg; no gameplay save |
| Settings screens | ❌ | Headless `InputSettings` cfg (keybinds, edge-scroll toggle) — no UI panel |
| Faction selection | ❌ | Data-driven only (`PlayerData.faction_id`) |
| Tutorial/training | ❌ | — |
| Multiplayer lobby | ❌ | "Lan" button disabled; plan 8-1 future |

---

## Core Components

### 1. Main Menu Structure
- **Start Screen**: Title logo with animated background
- **Quick Access Buttons**:
  - Single Player Campaign
  - Skirmish/Custom Game
  - Multiplayer Lobby Browser
  - Options/Settings
  - Credits & About
  - Exit to OS

### 2. UI Design Principles
- **Visual Style**: C&C-inspired with modern polish
  - Metallic/green color palette (GDI theme)
  - Orange/red accents for enemy factions
  - Clean typography using Poppins font
- **Navigation**: Keyboard/mouse/controller friendly
- **Animations**: Smooth transitions between menu states

### 3. Settings System
| Category | Options |
|----------|---------|
| Video | Resolution, fullscreen, FOV, quality presets |
| Audio | Master volume, music/SFX/music sliders |
| Controls | Key rebinding, mouse sensitivity |
| Game | UI scale, camera speed, difficulty level |

### 4. Menu States & Transitions
- **MainMenu** → **LoadGame** (campaign select)
- **MainMenu** → **SkirmishSetup** (custom game config)
- **MainMenu** → **OptionsMenu** (settings panel)
- All transitions use crossfade animations (0.3s duration)

## Technical Implementation

### Scene Hierarchy
```
MenuRoot.tscn (Control node)
├── MainMenuScreen.tscn
│   ├── Background (AnimatedTextureRect)
│   ├── LogoContainer (CenterContainer)
│   └── ButtonPanel (VBoxContainer)
├── OptionsScreen.tscn (hidden by default)
├── LoadingOverlay.tscn
└── AudioManager.gd (singleton)
```

### Key Scripts

#### MainMenuController.gd
- Button navigation with arrow keys
- Sound effect triggers on hover/click
- Save/load player preferences
- Exit confirmation dialog

#### SettingsPanel.gd
- Slider value persistence to config file
- Video quality preset system
- Audio mixer controls
- Control scheme presets

### Asset Requirements
- UI background textures (1920x1080 minimum)
- Button hover/click sound effects
- Font assets (Poppins family already present)
- Menu background music loop

## Integration Points
- Connect to save/load system for settings persistence
- Link with audio system for menu SFX/music
- Coordinate with game manager for mode transitions

## Future Enhancements
- Online multiplayer lobby browser
- Achievements/trophy display
- Social media links integration
- Dynamic title screen based on recent play activity
