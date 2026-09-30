# Multiplayer Support - ReSun

## Overview
Multiplayer support enables competitive and cooperative gameplay between multiple players over a network. This is critical for long-term engagement and community building.

## Implementation Status (verified 2026-08-08)

**Entirely greenfield — 0% implemented.** Zero network code in `scripts/`: no `MultiplayerAPI`, `ENetMultiplayerPeer`, `rpc`, peer management, lobby, matchmaking, or replay recording. The only trace is a comment in `scripts/components/DockUnloadComponent.gd:85` — "Needs entity ownership tracking for multiplayer." The MainMenu "Lan" button is disabled.

Not on the critical path for GDI Mission 01 or skirmish (single-player + local AI scope).

---

## Core Requirements

### 1. Network Architecture Design
- **Model**: Lockstep deterministic simulation or authoritative server
- **Sync Method**: Frame-based state synchronization every tick (0.1s)
- **Latency Handling**: Client prediction with server reconciliation
- **Connection Types**: Direct IP, relay servers, matchmaking service

### 2. Game State Sync System
- Broadcast all player commands each frame to connected clients
- Validate and reconcile discrepancies between players
- Handle desync recovery through state snapshots
- Maintain consistent game state across all participants

### 3. Lobby & Matchmaking Features
- **Lobby Creation**: Host sets map, factions, victory conditions
- **Player Slots**: 2-8 player support with AI filler options
- **Ready State**: Players confirm readiness before starting match
- **Kicking/Banning**: Host moderation tools for fair play

### 4. Replay System
- Record all inputs and random seeds during matches
- Allow playback without full game simulation
- Support fast-forward, pause, rewind functionality
- Save replays to file system with metadata tagging

## Technical Implementation

### Scene Structure
```
MultiplayerSystem.tscn (Autoload Singleton)
├── NetworkManager.gd (connection handling)
├── StateSync.gd (game state replication)
└── ReplayRecorder.gd (input logging)
```

### Key Scripts

#### NetworkManager.gd
- Manage peer connections via ENet or custom UDP implementation
- Handle login/lobby creation and player joining
- Synchronize game metadata before match start
- Disconnect handling for late leavers

#### StateSync.gd
- Broadcast command queue to all peers each tick
- Receive remote commands and apply locally
- Detect desyncs by comparing state hashes
- Request snapshot correction when mismatch detected

### Network Architecture Example (Lockstep)
```gdscript
# Each frame, send player inputs to all peers
func broadcast_commands(player_input_data):
    var packet = Packet2D.new()
    packet.put_var(player_input_data)  # Serialize all commands
    
    for peer in multiplayer.get_peers():
        multiplayer.rpc_id(peer, "receive_commands", packet.get_data())

# Receive and apply remote commands
@rpc("any_peer")
func receive_commands(data):
    var input_queue = data.get_var()
    for command in input_queue:
        process_command(command)
    
    # Verify state consistency
    if calculate_state_hash() != expected_hash:
        request_snapshot_correction()
```

### Replay Recording Logic
- Log every player input with frame timestamp
- Store random seed for procedural generation consistency
- Serialize game state snapshots periodically (every 60 frames)
- On replay playback, re-simulate using recorded inputs

## Integration Points
- Connect to game manager for match initialization
- Link with save/load system for replay storage
- Coordinate with UI for lobby interface creation
- Interface with network tools for debugging connectivity

## Future Enhancements
- Ranked matchmaking with ELO ratings
- Spectator mode for watching matches
- Cross-platform play support (PC, console)
- Anti-cheat measures and validation systems
