# Networking Architecture

# FIXME: LEFT OFF HERE: Review this.

## Table of Contents

1. [Overview](#overview)
2. [Architecture Diagram](#architecture-diagram)
3. [Core Networking Systems](#core-networking-systems)
4. [Client-Side Prediction](#client-side-prediction)
5. [Server Reconciliation](#server-reconciliation)
6. [Rollback and Re-simulation](#rollback-and-re-simulation)
7. [Data Flow](#data-flow)
8. [Implementation Guide](#implementation-guide)

## Overview

Jump 'n Thump implements a sophisticated client-server networking architecture
using **client-side prediction with server reconciliation and rollback
netcode**. This approach provides:

- **Instant responsiveness**: Players see their actions immediately without
  waiting for server confirmation
- **Server authority**: The server is the source of truth, preventing cheating
- **Smooth corrections**: Prediction errors are corrected seamlessly through
  rollback
- **Deterministic simulation**: Fixed 60 FPS frame-based logic ensures
  consistency

This architecture is commonly used in competitive multiplayer games where both
responsiveness and fairness are critical (e.g., fighting games, competitive
shooters).

### Key Concepts

- **Frame-synchronous simulation**: Game logic runs at fixed 60 FPS,
  independent of render framerate
- **Rollback buffer**: Historical state storage (default 1.5 seconds / ~90
  frames)
- **Client prediction**: Clients simulate their own actions immediately
- **Server reconciliation**: Server corrections trigger re-simulation from
  mismatch point
- **NTP-like time sync**: Clock synchronization to align client and server
  frames

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         NetworkMain                              │
│                    (G.network singleton)                         │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────────┐  │
│  │ ServerTime     │  │ NetworkConn.   │  │ NetworkFrame     │  │
│  │ Tracker        │  │                │  │ Driver           │  │
│  │                │  │                │  │                  │  │
│  │ - NTP sync     │  │ - ENet peers   │  │ - 60 FPS sim     │  │
│  │ - Clock offset │  │ - Connect/disc │  │ - Rollback coord │  │
│  │ - Time est.    │  │ - Status track │  │ - Frame index    │  │
│  └────────────────┘  └────────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│              ReconcilableNetworkedState (base class)             │
│                                                                   │
│  Every networked entity extends this to participate in:          │
│  - Frame-synchronous processing (_pre, _network, _post)          │
│  - State replication via MultiplayerSynchronizer                 │
│  - Rollback buffer management (RollbackBuffer)                   │
│  - Mismatch detection and reconciliation                         │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Game Entities                                │
│  ┌──────────────────────┐      ┌──────────────────────┐         │
│  │ CharacterState       │      │ PlayerInputFrom      │         │
│  │ FromServer           │      │ Client               │         │
│  │                      │      │                      │         │
│  │ Server-authoritative │      │ Client-authoritative │         │
│  │ - position           │      │ - input actions      │         │
│  │ - velocity           │      │ - timestamps         │         │
│  │ - action state       │      │                      │         │
│  └──────────────────────┘      └──────────────────────┘         │
│           (pair)                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Core Networking Systems

### 1. NetworkMain

**Location**: `src/networking/network_main.gd`

**Purpose**: Top-level coordinator and singleton accessor for all networking
subsystems.

**Responsibilities**:
- Instantiates and manages three child systems: `time`, `connector`,
  `frame_driver`
- Determines machine role (server vs client) from command-line arguments
- Provides convenient accessors to common networking state
- Emits signals for local authority changes

**Key Properties**:
```gdscript
var is_server: bool              # True if this machine is the server
var is_client: bool              # True if this machine is a client
var local_peer_id: int                # Multiplayer peer ID for this machine
var server_frame_index: int      # Current server frame number
var server_frame_time_usec: int  # Frame-aligned server time
```

**Usage**: Access via `G.network` singleton throughout the codebase.

---

### 2. ServerTimeTracker

**Location**: `src/networking/server_time_tracker.gd`

**Purpose**: Provides clients with accurate estimates of server time using
NTP-like clock synchronization.

**Why It's Needed**: Networked state includes timestamps. Clients must convert
these timestamps to frame indices to know where in their rollback buffer to
store the data. Without synchronized clocks, this conversion would be
inaccurate.

**Algorithm (NTP)**:

1. **Client sends request** (T1 = client local time)
2. **Server receives** (T2 = server time)
3. **Server responds** (T3 = server time)
4. **Client receives** (T4 = client local time)

From these four timestamps:
- **Round-trip time**: `RTT = (T4 - T1) - (T3 - T2)`
- **Clock offset**: `offset = ((T2 - T1) + (T3 - T4)) / 2`

The client then estimates server time as:
```gdscript
server_time = local_time + clock_offset
```

**Smoothing**: Maintains a sliding window of 5 samples and uses the average
offset for stability.

**Auto-sync**:
- Initial burst: Every 0.2 seconds until 5 samples collected
- Normal operation: Every 5.0 seconds to handle clock drift
- Triggered immediately on connection

**Drift Correction**: The `force_clock_offset()` method allows manual
adjustment when authoritative network state indicates the estimate has drifted.
This adjustment is applied to all historical samples to prevent the running
average from reverting the correction.

---

### 3. NetworkConnector

**Location**: `src/networking/network_connector.gd`

**Purpose**: Manages the low-level ENet transport layer for peer connections.

**Responsibilities**:
- Creates and configures ENet server peers (server-side)
- Creates and configures ENet client peers (client-side)
- Tracks connection status (`is_connected_to_server`)
- Handles `peer_connected` and `peer_disconnected` signals
- Manages graceful disconnection and session cleanup

**Configuration** (from `G.settings`):
- `server_port`: Default 4433
- `server_ip_address`: For clients to connect
- `max_client_count`: Maximum simultaneous clients

**Server Flow**:
```gdscript
G.network.connector.server_enable_connections()
# Creates ENet server, starts listening for connections
```

**Client Flow**:
```gdscript
G.network.connector.client_connect_to_server()
# Creates ENet client, connects to server_ip_address:server_port
```

**Connection Events**: Listens to Godot's `multiplayer.peer_connected` and
`multiplayer.peer_disconnected` signals to update internal state and log
connection events.

---

### 4. NetworkFrameDriver

**Location**: `src/networking/network_frame_driver.gd`

**Purpose**: The heart of the networking system. Orchestrates frame-synchronous
simulation at 60 FPS and coordinates rollback reconciliation.

**Frame Timing**:
- **Target FPS**: 60 (TARGET_NETWORK_FPS)
- **Time step**: ~16,666 microseconds (1/60 second)
- **Frame alignment**: Each frame has a canonical timestamp at its midpoint

**Frame Indices**: The `server_frame_index` is incremented directly on each
physics tick, ensuring perfect synchronization with Godot's physics loop. Frame
timestamps are calculated from the index:
```gdscript
frame_time_usec = get_time_usec_from_frame_index(server_frame_index)
```

Wall-clock time is periodically re-synced (every 30 seconds) to maintain
accurate timestamps for logging, but frame progression is driven purely by
physics callbacks.

**Registered Nodes**: Maintains arrays of:
- `_networked_state_nodes`: All `ReconcilableNetworkedState` instances
- `_network_frame_processor_nodes`: All `NetworkFrameProcessor` instances

These nodes are automatically registered/unregistered via `_enter_tree()` and
`_exit_tree()`.

**Frame Processing Cycle**:

Called from `_pre_physics_process()` every physics frame (which should match
the 60 FPS target):

```gdscript
func _pre_physics_process(delta: float):
	if not _is_frame_tracking_initialized:
		_initialize_frame_tracking()  # Defer until ServerTimeTracker ready
		return

	server_frame_index += 1  # Increment directly on each physics tick
	_run_network_process()

func _run_network_process():
	_update_server_frame_time()  # Update frame timestamp

	if _queued_rollback_frame_index > 0:
		_rollback_and_reprocess()  # Handle rollback if queued
		_queued_rollback_frame_index = 0

	_network_process()  # Simulate current frame
```

The `_network_process()` method coordinates all registered nodes through three
phases:

1. **Pre-process**: All `ReconcilableNetworkedState` nodes call
   `_pre_network_process()`
   - Restore state from rollback buffer (frame N-1)
   - Sync state to scene hierarchy

2. **Process**: All nodes call `_network_process()`
   - Game logic executes (movement, physics, input handling)
   - This is where game simulation happens

3. **Post-process**: All `ReconcilableNetworkedState` nodes call
   `_post_network_process()`
   - Sync state from scene hierarchy back to properties
   - Pack and store state in rollback buffer
   - Replicate state over network (if authoritative)

**Rollback Queueing**:
```gdscript
func queue_rollback(p_conflicting_frame_index: int) -> bool
```
- Schedules a rollback to occur on the next frame processing cycle
- Multiple rollback requests are coalesced (earliest frame wins)
- Validates that the requested frame is within buffer range

**Rollback Execution**:
```gdscript
func _rollback_and_reprocess()
```
- Rewinds `server_frame_index` to the rollback target
- Re-simulates all frames from rollback target to present
- Does NOT re-simulate the current frame (that happens afterward in the normal
  flow)

**Fast-forward**:
```gdscript
func fast_forward(new_frame_index: int)
```
- Used when the client falls behind server
- Rapidly simulates frames to catch up
- Triggered when receiving networked state from the future

**Rollback Buffer Management**:
- Buffer size: `ceil(rollback_buffer_duration_sec * 60)` frames (default ~90)
- Oldest accessible: `server_frame_index - rollback_buffer_size + 3`
  - The +3 accounts for needing N-1 and N-2 frames during processing

---

### 5. NetworkFrameProcessor

**Location**: `src/networking/network_frame_processor.gd`

**Purpose**: Helper node that bridges `NetworkFrameDriver` and game logic nodes
that need frame-synchronous processing but don't extend
`ReconcilableNetworkedState`.

**Usage Pattern**:
1. Add `NetworkFrameProcessor` as a child of your networked node
2. Set `root_path` to point to the node with `_network_process()`
3. NetworkFrameDriver automatically calls `root._network_process()` each frame

**Example Use Cases**:
- Match state coordinator (doesn't replicate, but needs frame-sync logic)
- Spawn managers
- Game mode controllers

**Configuration Warnings**: Editor displays warnings if:
- `root_path` is empty
- `root_path` points to invalid node
- Target node lacks `_network_process()` method

---

### 6. ReconcilableNetworkedState

**Location**: `src/networking/reconcilable_network_state.gd`

**Purpose**: Base class for all networked entities requiring client prediction,
state replication, and rollback reconciliation.

**Architecture**: Bridges three systems:

1. **Godot MultiplayerSynchronizer**: Replicates `packed_state` across network
2. **RollbackBuffer**: Stores historical states for rollback
3. **NetworkFrameDriver**: Coordinates frame-synchronous processing

**Server-Authoritative vs Client-Authoritative**:

Controlled by `is_server_authoritative` property:

- **Server-authoritative** (default): Server is source of truth
  - Used for: entity positions, velocities, health, game state
  - Authority: Server (peer ID 1)
  - Clients predict locally, server corrects mismatches

- **Client-authoritative**: Client is source of truth
  - Used for: player input
  - Authority: Owning client (specific peer ID)
  - Client sends input immediately, server processes it

**Typical Pattern**: Paired nodes
```
Player (Node2D)
├── CharacterStateFromServer (ReconcilableNetworkedState)
│   └── is_server_authoritative = true
└── PlayerInputFromClient (ReconcilableNetworkedState)
	└── is_server_authoritative = false
```

**Subclass Requirements**:

1. **Mark with @tool**: Enables editor validation
   ```gdscript
   @tool
   class_name MyNetworkedState
   extends ReconcilableNetworkedState
   ```

2. **Define synced properties and thresholds**:
   ```gdscript
   var position := Vector2.ZERO
   var velocity := Vector2.ZERO

   var _synced_properties_and_rollback_diff_thresholds := {
	   "position": 1.0,      # 1 pixel difference triggers rollback
	   "velocity": 10.0,     # 10 pixels/sec difference triggers rollback
   }
   ```

3. **Implement `_get_default_values()`**:
   ```gdscript
   func _get_default_values() -> Array:
	   return [Vector2.ZERO, Vector2.ZERO]
   ```

4. **Implement `_sync_to_scene_state(previous_state: Array)`**:
   ```gdscript
   func _sync_to_scene_state(_previous_state: Array) -> void:
	   root.position = position
	   root.velocity = velocity
   ```

5. **Implement `_sync_from_scene_state()`**:
   ```gdscript
   func _sync_from_scene_state() -> void:
	   position = root.position
	   velocity = root.velocity
   ```

**Frame Processing Lifecycle**:

Called by `NetworkFrameDriver` in sequence:

1. **`_pre_network_process()`** (internal):
   - Sets `timestamp_index = G.network.server_frame_index`
   - Resets `frame_authority = FrameAuthority.UNKNOWN`
   - Unpacks state from rollback buffer (frame N-1)
   - Calls `_sync_to_scene_state()` with previous frame (N-2) for
	 just_pressed/just_released detection

2. **`_network_process()`** (override in subclass if needed):
   - Default: Emits `network_processed` signal
   - Subclasses can override for custom per-frame logic

3. **`_post_network_process()`** (internal):
   - Calls `_sync_from_scene_state()` to read scene changes
   - If authoritative, packs state for network replication
   - Packs state for rollback buffer storage

**State Replication**:

The `packed_state` property is configured in MultiplayerSynchronizer and
contains:
- All property values from `_synced_properties_and_rollback_diff_thresholds`
- Timestamp (in microseconds)

When `packed_state` changes (received from network):
- `_handle_new_authoritative_state()` is called
- State is validated (not too old, within buffer range)
- Mismatch detection runs (if state is in the past)
- If mismatch detected, rollback is queued
- State is stored in rollback buffer

**Mismatch Detection**:

When receiving authoritative state for a past frame:

1. Retrieve predicted state from rollback buffer
2. Compare each property against threshold
3. Comparison logic:
   - **Bool/String**: Exact match required
   - **Int/Float**: `abs(buffer - networked) >= threshold`
   - **Vector2**: `distance_squared >= threshold * threshold`

4. If any property exceeds threshold:
   - Log mismatch details
   - Call `G.network.frame_driver.queue_rollback(frame_index)`

**Fast-forward**:

If received state is from the future (client behind server):
- Calculate frames behind
- Adjust ServerTimeTracker's clock offset
- Call `frame_driver.fast_forward()` to catch up

---

### 7. RollbackBuffer

**Location**: `src/networking/rollback_buffer.gd`

**Purpose**: Circular buffer specialized for storing historical frame states
with networking-specific features.

**Extends**: `CircularBuffer` (general-purpose circular buffer)

**Key Features**:

1. **Pre-filled with defaults**: Initialized with default state for all frames
2. **Negative index support**: Indices -1 and -2 are valid
   - `-1`: Default "previous" state for frame 0
   - `-2`: Used when accessing N-2 from frame 0
3. **Arbitrary index setting**: Can set non-sequential frames (e.g., 10, then
   15)
4. **Automatic back-filling**: Fills gaps with last-known state
5. **Array pooling**: Uses `ArrayPool` for memory efficiency

**Storage Format**:

Each frame stores an Array:
```
[property_value_1, property_value_2, ..., FrameAuthority]
```

`FrameAuthority` enum:
- `UNKNOWN`: Not yet simulated this frame
- `AUTHORITATIVE`: State came from authoritative source (server or owning
  client)
- `PREDICTED`: State was predicted locally

**Back-filling**:

When setting frame 15 after frame 10:
```gdscript
buffer.backfill_to_with_last_state(14)
```
- Copies frame 10's state to frames 11-14
- Marks them as `PREDICTED`
- Then frame 15 can be set normally

**Memory Management**:

Uses `ArrayPool.acquire()` and `ArrayPool.release()` to reuse arrays:
- Reduces allocation overhead during high-frequency rollback
- Optimization: When setting a frame, if old and new arrays have same size,
  copies values into existing array instead of replacing

**Circular Behavior**:

With capacity 90:
- Frames 0-89 initially stored
- When frame 90 is set, overwrites frame 0
- Oldest accessible frame moves forward with each push

---

## Client-Side Prediction

Client-side prediction solves the input delay problem inherent in networked
games. Without prediction, a player with 100ms ping would experience 100ms
delay between pressing a button and seeing their character move.

### How It Works

**Step 1: Local Input Processing**

When the player presses a key (e.g., "move right"):

1. Input is captured in `PlayerActionSource` or similar
2. Input is immediately written to the local `PlayerInputFromClient` state
3. Because this node is client-authoritative, the client has permission to
   modify it

**Step 2: Immediate Local Simulation**

During the current frame's `_network_process()`:

1. Character reads the input from `PlayerInputFromClient`
2. Character simulates movement based on input
3. Character's new position/velocity is written to `CharacterStateFromServer`
4. Character moves on screen instantly

**Step 3: Input Replication to Server**

After `_post_network_process()`:

1. `PlayerInputFromClient` (client-authoritative) packs its state
2. `packed_state` is replicated via `MultiplayerSynchronizer` to server
3. State includes timestamp so server knows which frame it belongs to

**Step 4: Client Stores Predicted State**

In `_post_network_process()`:

1. Character state is packed into rollback buffer
2. State is marked as `PREDICTED` (frame_authority)
3. This prediction will be validated when server response arrives

**Step 5: Continued Prediction**

Each subsequent frame:
- Client continues simulating based on local input
- All states stored in rollback buffer as `PREDICTED`
- No waiting for server confirmation

### Example Timeline

```
Frame 100: Player presses RIGHT
  ├─ Client: Input captured, position changes from 50→55 (instantly visible)
  ├─ Client: Input sent to server with timestamp F100
  └─ Client: State stored in buffer[100] as PREDICTED

Frame 101: Player holds RIGHT
  ├─ Client: Position changes from 55→60 (continues predicting)
  └─ Client: State stored in buffer[101] as PREDICTED

Frame 102: Server processes F100 input
  ├─ Server: Receives input for F100
  ├─ Server: Simulates F100, calculates position = 55
  ├─ Server: Sends authoritative state to client with timestamp F100

Frame 105: Client receives server state for F100
  ├─ Client: Compares server(55) vs buffer[100](55)
  ├─ Client: Match! No rollback needed
  └─ Client: Marks buffer[100] as AUTHORITATIVE
```

### Why This Matters

- **Player experiences**: Zero input delay, game feels responsive
- **Server maintains**: Authority over game state, prevents cheating
- **Smooth gameplay**: Most predictions are correct, no visible corrections

---

## Server Reconciliation

When the server's authoritative state differs from the client's prediction, the
client must reconcile the difference. This is where rollback comes in.

### Mismatch Detection

**When Client Receives Authoritative State**:

In `ReconcilableNetworkedState._handle_new_authoritative_state()`:

1. Extract timestamp from `packed_state`
2. Convert timestamp to frame index
3. Check if frame is in the past (already predicted locally)
4. If yes, compare against rollback buffer

**Comparison Logic**:

For each property in `_synced_properties_and_rollback_diff_thresholds`:

```gdscript
var buffer_value = buffer[frame_index][property_index]
var network_value = packed_state[property_index]
var threshold = thresholds[property_name]

if _check_do_values_mismatch(buffer_value, network_value, threshold):
	return true  # Mismatch detected!
```

Threshold semantics:
- `position: 1.0`: Mismatch if positions differ by ≥1 pixel
- `velocity: 10.0`: Mismatch if velocities differ by ≥10 pixels/sec
- `is_grounded: 0`: Exact match required (boolean)

**Why Thresholds?**: Floating-point imprecision and minor timing differences
can cause tiny divergences. Thresholds prevent unnecessary rollbacks for
insignificant differences.

### Example: Prediction Error

```
Frame 100: Player presses JUMP
  Client predicts: position.y = 200 (jumped 5 pixels)

  Network delay: 50ms (3 frames)

Frame 103: Server simulates F100
  Server calculates: position.y = 201 (slightly different physics)
  Server sends: F100 state with position.y = 201

Frame 106: Client receives server F100 state
  Client compares:
	- buffer[100].position.y = 200 (predicted)
	- network[100].position.y = 201 (authoritative)
	- difference = 1 pixel
	- threshold = 1.0 pixel
	- 1 >= 1.0 → MISMATCH DETECTED!

  Client queues rollback to frame 100
```

### Rollback is Queued

When mismatch detected:

```gdscript
G.network.frame_driver.queue_rollback(conflicting_frame_index)
```

- `_queued_rollback_frame_index` is set to the rollback target (frame + 1)
- If multiple mismatches in same frame, earliest frame wins
- Rollback executes on next `_run_network_process()` cycle

### Why Queue Instead of Immediate?

- Multiple state mismatches might arrive in the same frame
- Coalescing them into a single rollback is more efficient
- Ensures consistent processing order

---

## Rollback and Re-simulation

Rollback netcode is the technique of "rewinding time" to correct prediction
errors.

### Rollback Execution

**Triggered In**: `NetworkFrameDriver._rollback_and_reprocess()`

**Process**:

```gdscript
func _rollback_and_reprocess():
	var original_frame_index = server_frame_index  # e.g., 106
	var rollback_target = _queued_rollback_frame_index  # e.g., 101

	# Step 1: Rewind time
	server_frame_index = rollback_target  # 101
	server_frame_time_usec = (rollback_target * TIME_STEP_USEC)

	# Step 2: Re-simulate from rollback_target to (original - 1)
	while server_frame_index < original_frame_index:
		_network_process()  # Re-simulate frame
		server_frame_index += 1

	# Step 3: Restore current time
	server_frame_index = original_frame_index  # 106
	server_frame_time_usec = original_frame_time_usec

	# Current frame will be simulated normally afterward
```

### What Happens During Re-simulation?

For each frame from rollback target to present:

**1. Pre-process** (`_pre_network_process`):
- Load state from rollback buffer (which now contains authoritative server
  state)
- Sync to scene (character moves to corrected position)

**2. Process** (`_network_process`):
- Game logic executes with corrected starting state
- Input from `PlayerInputFromClient` (which was stored in its rollback buffer)
  is reapplied
- Character movement is recalculated

**3. Post-process** (`_post_network_process`):
- New state (with corrections) is written back to scene
- Updated state overwrites old predicted state in rollback buffer
- Character now has corrected position

### Example: Full Rollback Cycle

```
Current: Frame 106
Rollback target: Frame 101 (mismatch detected)

Buffer before rollback:
  [100]: PREDICTED, pos=(100, 50)
  [101]: PREDICTED, pos=(105, 50)  ← Mismatch: server says (105, 48)
  [102]: PREDICTED, pos=(110, 50)
  [103]: PREDICTED, pos=(115, 50)
  [104]: PREDICTED, pos=(120, 50)
  [105]: PREDICTED, pos=(125, 50)
  [106]: PREDICTED, pos=(130, 50)

Server says: Frame 101 should be pos=(105, 48) [2 pixels lower]

Rollback process:

1. Rewind to Frame 101
   - server_frame_index = 101

2. Re-simulate Frame 101:
   - Load server state: pos=(105, 48)
   - Apply input (still holding RIGHT)
   - Calculate new state: pos=(110, 48)
   - Store in buffer[101]: AUTHORITATIVE, pos=(105, 48)

3. Re-simulate Frame 102:
   - Load from buffer[101]: pos=(110, 48)
   - Apply input
   - Calculate: pos=(115, 48)
   - Store in buffer[102]: PREDICTED, pos=(115, 48)

4. Re-simulate Frame 103:
   - Load from buffer[102]: pos=(115, 48)
   - Apply input
   - Calculate: pos=(120, 48)
   - Store in buffer[103]: PREDICTED, pos=(120, 48)

5. Continue re-simulating 104, 105...

6. Return to Frame 106
   - Continue normal simulation

Buffer after rollback:
  [100]: PREDICTED, pos=(100, 50)
  [101]: AUTHORITATIVE, pos=(105, 48)  ← Corrected
  [102]: PREDICTED, pos=(110, 48)      ← Re-predicted
  [103]: PREDICTED, pos=(115, 48)      ← Re-predicted
  [104]: PREDICTED, pos=(120, 48)      ← Re-predicted
  [105]: PREDICTED, pos=(125, 48)      ← Re-predicted
  [106]: PREDICTED, pos=(130, 48)      ← Re-predicted

Result: Character position shifts 2 pixels down, but movement continues
smoothly.
```

### Visual Impact

**Ideal Case**: Prediction was almost correct
- 1-2 pixel correction over 6 frames
- Player doesn't notice the correction
- Appears completely smooth

**Worst Case**: Large prediction error
- Noticeable "snap" or "rubber-band" effect
- Player teleports to correct position
- Future enhancement: visual interpolation to smooth this

### Why Re-simulate Everything?

You might wonder: "Why not just apply the correction and continue?"

The answer: **Determinism**

Game physics often depends on previous state:
- A character's jump height depends on their exact velocity when jumping
- Collision detection depends on precise positions
- State machines depend on previous action states

If Frame 101 is wrong, then Frame 102's simulation (which used 101 as input)
is also wrong. We must re-simulate with the corrected Frame 101 to get the
correct Frame 102, and so on.

### Multiple Entities

When rollback occurs, ALL `ReconcilableNetworkedState` entities participate:

```
Rollback to Frame 101:
  - Player 1: Re-simulates movement
  - Player 2: Re-simulates movement
  - Projectile: Re-simulates trajectory
  - Game state: Re-simulates score/timers
```

This ensures all entities remain in sync with the corrected timeline.

---

## Data Flow

### Client-Side Data Flow (Normal Frame)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Input Capture                                             │
│    PlayerActionSource reads keyboard/gamepad                 │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Pre-Network Process (_pre_network_process)               │
│    ┌─────────────────────────────────────────────┐          │
│    │ ReconcilableNetworkedState:                 │          │
│    │ - Restore from rollback buffer (N-1)        │          │
│    │ - Call _sync_to_scene_state()               │          │
│    │   └─> Character.position = state.position   │          │
│    └─────────────────────────────────────────────┘          │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Network Process (_network_process)                       │
│    ┌─────────────────────────────────────────────┐          │
│    │ Game Logic:                                 │          │
│    │ - Read input from PlayerInputFromClient     │          │
│    │ - Apply physics (velocity, gravity)         │          │
│    │ - Handle collisions                         │          │
│    │ - Update animations                         │          │
│    │ Character.position changes                  │          │
│    └─────────────────────────────────────────────┘          │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Post-Network Process (_post_network_process)             │
│    ┌─────────────────────────────────────────────┐          │
│    │ ReconcilableNetworkedState:                 │          │
│    │ - Call _sync_from_scene_state()             │          │
│    │   └─> state.position = Character.position   │          │
│    │ - Pack state for network (if authoritative) │          │
│    │ - Store in rollback buffer as PREDICTED     │          │
│    └─────────────────────────────────────────────┘          │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Replication                                               │
│    MultiplayerSynchronizer sends packed_state to server      │
└─────────────────────────────────────────────────────────────┘
```

### Server-Side Data Flow (Normal Frame)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Receive Client Input                                      │
│    PlayerInputFromClient.packed_state updated                │
│    (MultiplayerSynchronizer handles replication)             │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Pre-Network Process                                       │
│    - Restore server's rollback buffer state (N-1)            │
│    - Sync to scene                                           │
└────────────────┬────────────────────────────────────────────┘
				 │
				 ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Network Process                                           │
│    - Read input from PlayerInputFromClient (from client)     │
│    - Apply same physics/game logic as client                 │
│    - Calculate authoritative position                        │
└────────────────┬────────────────────────────────────────────┘
				 │
				 ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Post-Network Process                                      │
│    - Sync from scene to state                                │
│    - Pack state for network (server is authoritative)        │
│    - Store in rollback buffer as AUTHORITATIVE               │
└────────────────┬────────────────────────────────────────────┘
				 │
				 ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Replication to All Clients                                │
│    CharacterStateFromServer.packed_state sent to all clients │
└─────────────────────────────────────────────────────────────┘
```

### Client Receives Server State (Reconciliation)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Receive Server State                                      │
│    CharacterStateFromServer.packed_state updated             │
└────────────────┬────────────────────────────────────────────┘
				 │
				 ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Handle New Authoritative State                            │
│    _handle_new_authoritative_state()                         │
│    ┌─────────────────────────────────────┐                  │
│    │ - Extract frame index from timestamp │                  │
│    │ - Is this frame in the past?        │                  │
│    │   YES: Check for mismatch           │                  │
│    └─────────────┬───────────────────────┘                  │
└──────────────────┼─────────────────────────────────────────┘
				   │
		┌──────────┴──────────┐
		│                     │
		▼                     ▼
   NO MISMATCH           MISMATCH DETECTED!
		│                     │
		▼                     ▼
┌──────────────┐    ┌────────────────────────┐
│ 3a. Store    │    │ 3b. Queue Rollback     │
│ server state │    │ - Log mismatch details │
│ in buffer as │    │ - Call queue_rollback()│
│ AUTHORITATIVE│    │ - Store server state   │
└──────────────┘    └────────┬───────────────┘
							  │
							  ▼
				   ┌────────────────────────┐
				   │ 4. Rollback Executes   │
				   │ (Next Frame)           │
				   │ - Rewind to conflict   │
				   │ - Re-simulate to now   │
				   └────────────────────────┘
```

---

## Implementation Guide

This section provides a step-by-step guide for implementing rollback networking
in a new Godot game using this framework.

### Prerequisites

1. **Copy Networking Folder**: Copy `src/networking/` to your project
2. **Copy Dependencies**: Copy these supporting classes:
   - `src/utils/circular_buffer.gd`
   - `src/utils/array_pool.gd`
   - `src/utils/scaffolder_time.gd` (for PHYSICS_FPS constant)
3. **Set Up Singleton**: Add NetworkMain to autoload as `G.network`
4. **Configure Settings**: Create settings resource with networking properties

### Step 1: Define Networked Properties

Identify what needs to be synchronized for your game entity.

**Example: Platformer Character**
- Position (Vector2)
- Velocity (Vector2)
- Action state (String: "idle", "walk", "jump", "fall")
- Facing direction (int: -1 or 1)
- Is grounded (bool)

**Example: Player Input**
- Move direction (Vector2: -1 to 1 on each axis)
- Jump pressed (bool)
- Attack pressed (bool)

### Step 2: Create Server-Authoritative State Class

Create a script extending `ReconcilableNetworkedState`:

```gdscript
@tool
class_name CharacterStateFromServer
extends ReconcilableNetworkedState

# Synced properties
var position := Vector2.ZERO
var velocity := Vector2.ZERO
var action_state := "idle"
var facing_direction := 1
var is_grounded := false

# Define which properties to sync and their mismatch thresholds
var _synced_properties_and_rollback_diff_thresholds := {
	"position": 1.0,           # 1 pixel tolerance
	"velocity": 10.0,          # 10 px/s tolerance
	"action_state": 0,         # Exact match required
	"facing_direction": 0,     # Exact match required
	"is_grounded": 0,          # Exact match required
}

func _get_default_values() -> Array:
	return [
		Vector2.ZERO,  # position
		Vector2.ZERO,  # velocity
		"idle",        # action_state
		1,             # facing_direction
		false,         # is_grounded
	]

func _sync_to_scene_state(_previous_state: Array) -> void:
	# Update scene from network state
	var character := root as CharacterBody2D
	if character:
		character.position = position
		character.velocity = velocity
		# Update other character properties...

func _sync_from_scene_state() -> void:
	# Update network state from scene
	var character := root as CharacterBody2D
	if character:
		position = character.position
		velocity = character.velocity
		# Read other character properties...
```

### Step 3: Create Client-Authoritative Input Class

Create a script for player input:

```gdscript
@tool
class_name PlayerInputFromClient
extends ReconcilableNetworkedState

# Input properties
var move_direction := Vector2.ZERO
var jump_pressed := false
var attack_pressed := false

var _synced_properties_and_rollback_diff_thresholds := {
	"move_direction": 0,  # Exact match
	"jump_pressed": 0,    # Exact match
	"attack_pressed": 0,  # Exact match
}

func _get_default_values() -> Array:
	return [
		Vector2.ZERO,  # move_direction
		false,         # jump_pressed
		false,         # attack_pressed
	]

func _sync_to_scene_state(_previous_state: Array) -> void:
	# Input doesn't usually drive scene directly
    # Character reads from this during _network_process
    pass

func _sync_from_scene_state() -> void:
    # Input is captured separately (see Step 4)
    pass
```

### Step 4: Set Up Scene Hierarchy

Create your character scene:

```
Character (CharacterBody2D)
├── Sprite2D
├── CollisionShape2D
├── StateFromServer (CharacterStateFromServer)
│   └── root_path: ".."
└── InputFromClient (PlayerInputFromClient)
    └── root_path: ".."
```

**Important Configuration**:
- `StateFromServer.is_server_authoritative = true`
- `InputFromClient.is_server_authoritative = false`
- Both nodes have `root_path` pointing to parent Character node

### Step 5: Capture Player Input

Create an input handler that writes to `InputFromClient`:

```gdscript
# In Character script or separate InputHandler script
func _input(event):
    if not is_multiplayer_authority():
        return  # Only local player captures input

    var input_state := get_node("InputFromClient") as PlayerInputFromClient
    if not input_state:
        return

    # Read input
    var move_x = Input.get_axis("move_left", "move_right")
    var move_y = Input.get_axis("move_up", "move_down")

    # Write to networked input state
    input_state.move_direction = Vector2(move_x, move_y)
    input_state.jump_pressed = Input.is_action_pressed("jump")
    input_state.attack_pressed = Input.is_action_pressed("attack")
```

**Important**: Write input to the networked state, not directly to character
logic. This ensures input participates in rollback.

### Step 6: Implement Game Logic in _network_process

Character logic should read from `InputFromClient` and modify the
CharacterBody2D:

```gdscript
# In Character script
func _network_process() -> void:
    var input_state := get_node("InputFromClient") as PlayerInputFromClient
    if not input_state:
        return

    # Read input (works on both client and server)
    var move_dir := input_state.move_direction
    var jump := input_state.jump_pressed

    # Apply game logic
    if is_on_floor():
        if jump:
            velocity.y = JUMP_VELOCITY
        velocity.x = move_dir.x * MOVE_SPEED
    else:
        velocity.y += GRAVITY * NetworkFrameDriver.TARGET_NETWORK_TIME_STEP_SEC
        velocity.x = lerp(velocity.x, move_dir.x * MOVE_SPEED, AIR_CONTROL)

    # Apply movement
    move_and_slide()

    # Update action state
    if is_on_floor():
        if abs(velocity.x) > 1.0:
            action_state = "walk"
        else:
            action_state = "idle"
    else:
        if velocity.y < 0:
            action_state = "jump"
        else:
            action_state = "fall"
```

**Critical**: Use `_network_process()` instead of `_physics_process()` for all
networked logic. This ensures it participates in rollback.

### Step 7: Add NetworkFrameProcessor (If Needed)

If you have game systems that need frame-sync but don't extend
`ReconcilableNetworkedState`:

```
MatchController (Node)
└── NetworkFrameProcessor
	└── root_path: ".."
```

Then implement `_network_process()` in MatchController:

```gdscript
func _network_process() -> void:
	# Frame-synchronous game logic
	match_time += NetworkFrameDriver.TARGET_NETWORK_TIME_STEP_SEC
	if match_time >= MATCH_DURATION:
		end_match()
```

### Step 8: Handle Spawning

**Server Side**: Spawn characters for connected clients

```gdscript
# In Level or GameController
func _on_peer_connected(peer_id: int):
	if not G.network.is_server:
		return

	var character_scene = preload("res://character.tscn")
	var character = character_scene.instantiate()
	character.name = "Character_%d" % peer_id

	# Set peer_id before adding to tree
	var state_from_server = character.get_node("StateFromServer")
	state_from_server.peer_id = peer_id

	add_child(character, true)  # true = force readability
```

**Important**: Set `peer_id` before adding to tree. This determines
which client has input authority.

### Step 9: Testing

**Single-Player Test**:
1. Run normally
2. Verify character moves correctly
3. Check console for networking warnings

**Multi-Instance Test** (Godot Editor):
1. Debug > Customize Run Instances
2. Enable 3 instances:
   - Instance 1: `--server --preview`
   - Instance 2: `--client=1 --preview`
   - Instance 3: `--client=2 --preview`
3. Run and verify:
   - Both clients see both characters
   - Input is responsive
   - Characters stay in sync

**Network Condition Test**:
1. Add artificial latency (if available)
2. Verify rollback corrections are smooth
3. Check console for rollback logs

### Step 10: Tuning Rollback Thresholds

Monitor console for rollback frequency:

**Too many rollbacks**:
- Increase thresholds (e.g., `"position": 1.0` → `2.0`)
- Check for non-deterministic logic (RNG, Time.get_ticks_msec, etc.)

**Characters desync**:
- Decrease thresholds
- Verify server and client use identical physics
- Check for client-only logic (animations, particles)

**Finding the balance**:
- Position: 1-3 pixels is typical
- Velocity: 10-50 pixels/sec is typical
- Start conservative (lower thresholds) and increase if needed

### Step 11: Separate Visual from Physics

For best results, separate visual state (animations, effects) from physics
state:

```
Character (CharacterBody2D)  ← Physics state (synced)
├── StateFromServer
├── InputFromClient
└── Visual (Node2D)          ← Visual state (client-only)
	├── Sprite2D
	├── AnimationPlayer
	└── Particles
```

This allows rollback to correct physics without creating visual artifacts.

### Step 12: Future Enhancements

**Rollback Visual Interpolation** (see FIXME comments in
network_frame_driver.gd):
- Copy pre-rollback state
- Smoothly interpolate visual node from pre-rollback to post-rollback over
  several frames
- Eliminates visible "snapping"

**Pause Support**:
- Networked pause state in MatchState
- Track cumulative pause time
- Adjust frame calculations to account for paused time

**Lag Compensation** (for hit detection):
- Server rewinds other players' positions to match shooter's view
- Ensures shots that looked like hits are registered as hits

### Common Pitfalls

1. **Non-deterministic logic**: Using `randf()`, `Time.get_ticks_msec()`, or
   accessing non-networked state during `_network_process()`
   - **Solution**: Use seeded RNG, frame index for timing, only read networked
	 state

2. **Forgetting @tool annotation**: Subclasses of ReconcilableNetworkedState
   must be marked `@tool`
   - **Solution**: Always add `@tool` at top of script

3. **Mixing _physics_process and _network_process**: Physics logic split
   between both
   - **Solution**: Move ALL networked logic to `_network_process()`

4. **Wrong root_path**: ReconcilableNetworkedState points to wrong node
   - **Solution**: Verify in editor, check for configuration warnings

5. **Threshold too low**: Constant rollbacks from floating-point differences
   - **Solution**: Use thresholds > 0 for numeric types

6. **Not handling fast-forward**: Client falls behind and never catches up
   - **Solution**: Framework handles this automatically via
	 ServerTimeTracker.force_clock_offset

7. **Spawning without setting peer_id**: Authority not assigned
   correctly
   - **Solution**: Set `state_from_server.peer_id` before adding to tree

---

## Conclusion

This networking architecture provides a robust foundation for responsive,
cheat-resistant multiplayer games. Key takeaways:

1. **Client prediction** eliminates input delay
2. **Server authority** prevents cheating
3. **Rollback reconciliation** corrects prediction errors seamlessly
4. **Frame-synchronous simulation** ensures determinism
5. **NTP-like time sync** aligns client and server frames

The framework handles the complex networking plumbing, allowing you to focus on
game logic. By following the implementation guide and understanding the data
flow, you can build responsive multiplayer games with confidence.

### Further Reading

- [Gabriel Gambetta's Client-Server Game Architecture](https://www.gabrielgambetta.com/client-server-game-architecture.html)
- [Valve's Source Engine Networking](https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking)
- [Overwatch Gameplay Architecture](https://www.youtube.com/watch?v=W3aieHjyNvw)
- [Godot High-Level Multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
