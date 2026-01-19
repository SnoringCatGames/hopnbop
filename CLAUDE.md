# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Jump 'n Thump is a multiplayer action game built with Godot 4.5. It implements client-side prediction with rollback reconciliation for networked gameplay.

## Running the Game

Test multiplayer locally in Godot editor:
1. Debug > Customize Run Instances
2. Enable 3 instances with launch args:
   - Instance 1: `--server --preview`
   - Instance 2: `--client=1 --preview`
   - Instance 3: `--client=2 --preview`

Launch flags:
- `--server` - Run as server
- `--client=N` - Run as client N (1, 2, etc.)
- `--preview` - Local multi-instance testing mode

## Architecture

### Networking Layer (src/networking/)

The networking system is frame-based with rollback support:

- **NetworkMain** - Top-level controller, accessed via `G.network` singleton
- **NetworkFrameDriver** - Core frame simulation at 60 FPS, manages rollback buffer and reconciliation
- **ReconcilableNetworkedState** - Base class for all networked entities; implements client prediction + server authoritative reconciliation
- **ServerTimeTracker** - NTP-like clock sync between client and server
- **NetworkConnector** - ENet peer management (default port 4433)

**Frame Processing Flow:**
1. `_pre_network_process()` - Sync scene state from rollback buffer
2. `_network_process()` - Game logic executes (frame-synchronous)
3. `_post_network_process()` - Pack state for replication

All networked entities must extend ReconcilableNetworkedState and participate in this cycle.

### Game State (src/core/)

- **MatchState/MatchStateSynchronizer** - Replicated match data (players, kills, bumps)
- **PlayerMatchState** - Per-player metadata (name, connection status)
- **GamePanel** - Game lifecycle orchestrator, handles level spawning
- **LocalSession** - Per-client session state

### Character System (src/scaffolder/character/)

Reusable character framework:

- **Character** - Extends CharacterBody2D; manages velocity, collision, action state, surface contact
- **CharacterActionState** - State machine for movement (17+ action handlers for floor/wall/ceiling/air states)
- **CharacterStateFromServer** - Networked character state with rollback support
- **CharacterSurfaceState** - Tracks platform contact via raycasts

Action handlers in `src/scaffolder/character/action_handlers/` modify velocity and physics per frame.

### Player Implementation (src/player/)

- **Bunny** - Game-specific player extending the character system
- **PlayerActionSource** - Translates player input to action commands

### Level System (src/level/)

- **Level** - Scene container managing players_by_id dictionary and MultiplayerSpawner
- Server instantiates players for connected clients; clients receive spawned instances

## Networking Concepts Reference

This section documents game networking patterns used in this project. These concepts apply broadly to multiplayer game development.

### Client-Side Prediction

Without prediction, players experience input delay equal to their round-trip latency (e.g., 100ms ping = 100ms delay before seeing movement). Client-side prediction solves this by immediately simulating the predicted result of player inputs locally, providing instant visual feedback while the server validates those inputs in parallel.

**How it works:**
1. Player presses input → client immediately simulates the action locally
2. Input is sent to server with a sequence number
3. Client continues predicting future frames while awaiting confirmation
4. Server processes input and sends authoritative state back

### Server Reconciliation

When the server's authoritative state differs from the client's prediction, reconciliation corrects the client without visible stuttering.

**Reconciliation algorithm:**
1. Client receives server state with last-processed input sequence number
2. Client resets to server's confirmed state
3. Client replays all unacknowledged inputs on top of server state
4. Result becomes new prediction baseline

**Snap vs. Smooth reconciliation:**
- Snap: Instantly teleport to corrected position (causes visible jitter)
- Smooth: Gradually interpolate toward corrected position over several frames (this project uses smooth reconciliation via rollback buffer)

### Rollback Netcode

Rollback extends reconciliation by maintaining a buffer of historical states. When a mismatch is detected:
1. "Roll back" game state to the mismatched frame
2. Re-simulate all frames from that point with corrected data
3. Fast-forward back to present

This project's `NetworkFrameDriver` implements rollback with configurable buffer duration (default 1.5 seconds / ~90 frames at 60 FPS).

### Frame Synchronization

Deterministic simulation requires all clients to process the same inputs on the same frame numbers. This project uses:
- Fixed 60 FPS network tick rate (independent of render framerate)
- Server-authoritative frame numbering
- NTP-like clock synchronization (`ServerTimeTracker`) to estimate server time

### Lag Compensation

For hit detection in latency-sensitive actions (shooting), the server can "rewind" entity positions to where they appeared from the shooter's perspective, accounting for round-trip latency. This ensures high-ping players can still hit targets they visually aimed at.

### Authority Models

**Server-authoritative (used here):** Server is the source of truth. Clients predict locally but defer to server corrections. Prevents cheating but requires reconciliation.

**Client-authoritative:** Each client owns their character's state. Simpler but vulnerable to cheating. Sometimes used for non-competitive games.

**Hybrid:** Server authoritative for game logic, but clients have authority over their input timing.

## Godot Multiplayer Patterns

### MultiplayerSynchronizer

Continuously replicates configured properties from authority to other peers. Key concepts:
- Each synchronized entity needs its own MultiplayerSynchronizer instance
- Configure which properties to sync via the Replication panel
- Default authority is server (peer 1); can be changed per-node
- Visibility filters control which peers receive updates

**Dual Synchronizer Pattern:** Use separate synchronizers for spawn state (server authority) and input/player state (peer authority) to maintain proper isolation.

### MultiplayerSpawner

Replicates node instantiation/deletion across peers (including mid-game joins). Key concepts:
- Set `spawn_path` to define where spawned nodes appear in tree
- Configure Auto Spawn List for scenes to replicate automatically
- Only replicates creation/deletion, not ongoing state (use MultiplayerSynchronizer for that)
- Use `spawn_limit` to constrain maximum instances

### Input Isolation Pattern

For player characters, use a dedicated child node for player inputs while keeping character node authority with the server. This separates control handling from game logic, reducing synchronization errors.

### Replicated State Sub-node Pattern

Create a sub-node within entities specifically for replicated state. Other scripts reference this node, maintaining clear separation between networked and local-only state. This project uses this pattern with `CharacterStateFromServer`.

### Physics Considerations

Godot's physics engine doesn't natively support rewinding/re-simulation. Options:
1. Server-only physics with position sync (simple but high bandwidth)
2. Custom physics stepping (this project's approach via frame-based simulation)
3. External libraries (Netfox, MonkeNet) that provide rollback-compatible physics

## Key Patterns

### Adding Networked Entities

1. Extend ReconcilableNetworkedState
2. Define synced properties in `_get_packed_state()` and `_apply_packed_state()`
3. Set mismatch thresholds for rollback detection
4. Register with NetworkFrameDriver (automatic via scene tree)

### Adding Character Actions

1. Create handler in `src/scaffolder/character/action_handlers/`
2. Follow pattern: modify velocity based on surface state and input
3. Register in CharacterActionState

## Configuration

- **settings.tres** - Runtime settings (network, debug, gameplay)
- **project.godot** - Input actions, physics layers, rendering config

Debug toggles in settings: `dev_mode`, `draw_annotations`, `perf_tracker_enabled`, `debug_console_enabled`

## Code Style

GDScript formatter addon is installed (addons/gdscript_formatter). Format code before committing.

## References

Networking concepts and patterns:
- [Gabriel Gambetta's Client-Side Prediction and Server Reconciliation](https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html) - Definitive explanation of prediction/reconciliation
- [Godot High-Level Multiplayer Docs](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html) - Official Godot networking documentation
- [Godot Scene Replication (4.0)](https://godotengine.org/article/multiplayer-in-godot-4-0-scene-replication/) - MultiplayerSynchronizer/Spawner introduction

Godot networking addons (for reference, not used in this project):
- [Netfox](https://forum.godotengine.org/t/netfox-addons-for-online-multiplayer-games/36066) - Client-side prediction and server reconciliation addon
- [MonkeNet](https://github.com/grazianobolla/godot-monke-net) - C# addon with prediction, interpolation, lag compensation
