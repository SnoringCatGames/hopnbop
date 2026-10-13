# Networking concepts reference

Educational reference moved verbatim from CLAUDE.md by H34
(2026-10-13). This section documents game networking patterns used in
this project. These concepts apply broadly to multiplayer game
development. Never imported into always-loaded context; read on
demand.

## Client-Side Prediction

Without prediction, players experience input delay equal to their round-trip latency (e.g., 100ms ping = 100ms delay before seeing movement). Client-side prediction solves this by immediately simulating the predicted result of player inputs locally, providing instant visual feedback while the server validates those inputs in parallel.

**How it works:**
1. Player presses input → client immediately simulates the action locally
2. Input is sent to server with a sequence number
3. Client continues predicting future frames while awaiting confirmation
4. Server processes input and sends authoritative state back

## Server Reconciliation

When the server's authoritative state differs from the client's prediction, reconciliation corrects the client without visible stuttering.

**Reconciliation algorithm:**
1. Client receives server state with last-processed input sequence number
2. Client resets to server's confirmed state
3. Client replays all unacknowledged inputs on top of server state
4. Result becomes new prediction baseline

**Snap vs. Smooth reconciliation:**
- Snap: Instantly teleport to corrected position (causes visible jitter)
- Smooth: Gradually interpolate toward corrected position over several frames (this project uses smooth reconciliation via rollback buffer)

## Rollback Netcode

Rollback extends reconciliation by maintaining a buffer of historical states. When a mismatch is detected:
1. "Roll back" game state to the mismatched frame
2. Re-simulate all frames from that point with corrected data
3. Fast-forward back to present

This project's `NetworkFrameDriver` implements rollback with configurable buffer duration (default 1.5 seconds / ~90 frames at 60 FPS).

## Frame Synchronization

Deterministic simulation requires all clients to process the same inputs on the same frame numbers. This project uses:
- Fixed 60 FPS network tick rate (independent of render framerate)
- Server-authoritative frame numbering
- NTP-like clock synchronization (`ServerTimeTracker`) to estimate server time

## Lag Compensation

For hit detection in latency-sensitive actions (shooting), the server can "rewind" entity positions to where they appeared from the shooter's perspective, accounting for round-trip latency. This ensures high-ping players can still hit targets they visually aimed at.

## Authority Models

**Server-authoritative (used here):** Server is the source of truth. Clients predict locally but defer to server corrections. Prevents cheating but requires reconciliation.

**Client-authoritative:** Each client owns their character's state. Simpler but vulnerable to cheating. Sometimes used for non-competitive games.

**Hybrid:** Server authoritative for game logic, but clients have authority over their input timing.

# Godot Multiplayer Patterns

## MultiplayerSynchronizer

Continuously replicates configured properties from authority to other peers. Key concepts:
- Each synchronized entity needs its own MultiplayerSynchronizer instance
- Configure which properties to sync via the Replication panel
- Default authority is server (peer 1); can be changed per-node
- Visibility filters control which peers receive updates

**Dual Synchronizer Pattern:** Use separate synchronizers for spawn state (server authority) and input/player state (peer authority) to maintain proper isolation.

## MultiplayerSpawner

Replicates node instantiation/deletion across peers (including mid-game joins). Key concepts:
- Set `spawn_path` to define where spawned nodes appear in tree
- Configure Auto Spawn List for scenes to replicate automatically
- Only replicates creation/deletion, not ongoing state (use MultiplayerSynchronizer for that)
- Use `spawn_limit` to constrain maximum instances

## Input Isolation Pattern

For player characters, use a dedicated child node for player inputs while keeping character node authority with the server. This separates control handling from game logic, reducing synchronization errors.

## Replicated State Sub-node Pattern

Create a sub-node within entities specifically for replicated state. Other scripts reference this node, maintaining clear separation between networked and local-only state. This project uses this pattern with `CharacterStateFromServer`.

## Physics Considerations

Godot's physics engine doesn't natively support rewinding/re-simulation. Options:
1. Server-only physics with position sync (simple but high bandwidth)
2. Custom physics stepping (this project's approach via frame-based simulation)
3. External libraries (Netfox, MonkeNet) that provide rollback-compatible physics

# References

Networking concepts and patterns:
- [Gabriel Gambetta's Client-Side Prediction and Server Reconciliation](https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html) - Definitive explanation of prediction/reconciliation
- [Godot High-Level Multiplayer Docs](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html) - Official Godot networking documentation
- [Godot Scene Replication (4.0)](https://godotengine.org/article/multiplayer-in-godot-4-0-scene-replication/) - MultiplayerSynchronizer/Spawner introduction

Godot networking addons (for reference, not used in this project):
- [Netfox](https://forum.godotengine.org/t/netfox-addons-for-online-multiplayer-games/36066) - Client-side prediction and server reconciliation addon
- [MonkeNet](https://github.com/grazianobolla/godot-monke-net) - C# addon with prediction, interpolation, lag compensation
