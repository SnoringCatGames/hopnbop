# NETWORKING_ARCHITECTURE.md - Continuation (Sections 4-15)

This file contains the remaining sections to be appended to NETWORKING_ARCHITECTURE.md

# FIXME: Review this.

---

## 4. Frame-Synchronous Simulation

This section provides an in-depth explanation of the frame-based simulation engine that drives all networked gameplay. Understanding this system is critical for implementing networked features and debugging rollback issues.

### 4.1 Core Principles

**Fixed 60 FPS Network Tick**

```gdscript
# src/networking/network_frame_driver.gd
const TARGET_NETWORK_FPS = 60
const TARGET_NETWORK_TIME_STEP_SEC = 1.0 / 60  # 0.01666...
const TARGET_NETWORK_TIME_STEP_USEC = floori(1_000_000 / 60)  # 16666 µs
```

The network simulation runs at a fixed 60 frames per second, independent of the render framerate. This ensures:
- **Deterministic physics:** Same inputs → same outputs
- **Predictable rollback:** Know exactly when to rewind
- **Frame-aligned state:** All clients reference same frame indices

**Frame Index as Canonical Time**

```gdscript
var server_frame_index: int = 0  # Increments every physics tick
```

Instead of using timestamps, all networked state is indexed by `server_frame_index`. This eliminates clock drift issues and makes rollback straightforward.

### 4.2 Frame Processing Loop

Every physics tick (`_physics_process` at 60 Hz), the NetworkFrameDriver executes:

```gdscript
func _pre_physics_process(_delta: float) -> void:
    if _is_paused:
        return

    if not _is_frame_tracking_initialized:
        _initialize_frame_tracking()
        return

    # Increment frame index directly on each physics tick
    server_frame_index += 1

    _run_network_process()
```

**Key Points:**

1. **Frame index increments first** - Before processing the frame
2. **Pause handling** - When paused, frame index doesn't advance
3. **Initialization guard** - Waits for NTP clock sync before starting

### 4.3 Three-Phase Frame Processing

For each frame, `_network_process()` calls three methods on every `ReconcilableNetworkedState` node:

```gdscript
func _network_process() -> void:
    # Phase 1: Restore scene state from rollback buffer
    for node in _networked_state_nodes:
        node._pre_network_process()

    # Phase 2: Execute game logic (movement, collision, input)
    for node in _networked_state_nodes:
        node._network_process()
    for node in _network_frame_processor_nodes:
        node._network_process()

    # Phase 3: Pack scene state → properties & rollback buffer
    for node in _networked_state_nodes:
        node._post_network_process()
```

#### Phase 1: _pre_network_process (Restore from Buffer)

**Purpose:** Sync scene state from rollback buffer for current frame.

**Implementation in ReconcilableNetworkedState:**

```gdscript
func _pre_network_process() -> void:
    if not is_instance_valid(G.network.frame_driver.rollback_buffer):
        return

    var frame_index := G.network.frame_driver.server_frame_index
    var buffered_state: Array = (
        G.network.frame_driver.rollback_buffer.get_at(frame_index)
    )

    if buffered_state.is_empty():
        return

    # Apply buffered state to scene (position, velocity, etc.)
    _sync_to_scene_state(buffered_state)
```

**Why needed:** During rollback, the buffer contains corrected server states. This phase ensures the scene reflects that correct state before simulating forward.

**Example for Character:**

```gdscript
# CharacterStateFromServer._sync_to_scene_state()
func _sync_to_scene_state(state: Array) -> void:
    var character := get_parent() as Character

    character.position = Vector2(state[0], state[1])
    character.velocity = Vector2(state[2], state[3])
    character.is_on_floor_state = state[4]
    character.is_on_wall_state = state[5]
    character.is_on_ceiling_state = state[6]
    # ... other properties
```

#### Phase 2: _network_process (Execute Game Logic)

**Purpose:** Run game logic for this frame (movement, physics, input handling).

**Implementation in Character:**

```gdscript
func _network_process() -> void:
    var frame_index := G.network.frame_driver.server_frame_index

    # Get input for this frame
    var instructions := _get_instructions_for_frame(frame_index)

    # Let action handlers modify velocity based on input and surface state
    action_state.process(instructions, TARGET_NETWORK_TIME_STEP_SEC)

    # Apply velocity via Godot's physics
    move_and_slide()

    # Update surface contact detection
    surface_state.update()
```

**This is where gameplay happens:**
- Input processed
- Velocity calculated by action handlers
- Collision resolved via `move_and_slide()`
- Surface state updated (is_on_floor, is_on_wall, etc.)

**Determinism Requirement:**

Given identical:
- Input state
- Start state (position, velocity, etc.)

This phase MUST produce identical:
- End state

Any randomness or time-dependent logic breaks rollback. Use `frame_index` as seed if randomness needed.

#### Phase 3: _post_network_process (Pack State to Buffer)

**Purpose:** Record current state to rollback buffer and replicated properties.

```gdscript
func _post_network_process() -> void:
    var frame_index := G.network.frame_driver.server_frame_index

    # Pack scene state → array
    var current_state: Array = _sync_from_scene_state()

    # Store in rollback buffer
    G.network.frame_driver.rollback_buffer.set_at(frame_index, current_state)

    # Update replicated properties (for network sync)
    packed_state = current_state
    packed_state_frame_index = frame_index
    packed_state_authority = (
        FrameAuthority.AUTHORITATIVE if G.network.is_server
        else FrameAuthority.PREDICTED
    )
```

**Example Packing:**

```gdscript
func _sync_from_scene_state() -> Array:
    var character := get_parent() as Character

    return [
        character.position.x,
        character.position.y,
        character.velocity.x,
        character.velocity.y,
        character.is_on_floor_state,
        character.is_on_wall_state,
        character.is_on_ceiling_state,
        # ... other synced properties
    ]
```

### 4.4 Visual Timeline of Frame Processing

```
Time →   Frame N-1      Frame N        Frame N+1
         ──────────────────────────────────────────

Server:  │   Pack     │ Restore │ Simulate │ Pack │
Client:  │     ↓      │    ↓    │    ↓     │  ↓   │
Buffer:  │ [State N-1]  Load   Process   Save [State N+1]
         │            N-1→scene  logic  scene→N          │
         └──────────────────────────────────────────────────┘

Detailed breakdown for Frame N:
  _pre_network_process():
    - Load buffer[N] (or buffer[N-1] if N not yet stored)
    - Apply to scene: position, velocity, etc.

  _network_process():
    - Read input for frame N
    - Action handlers modify velocity
    - move_and_slide() updates position
    - Surface detection updates is_on_floor

  _post_network_process():
    - Read position, velocity from scene
    - Pack into array
    - Store to buffer[N]
    - Set packed_state for replication
```

### 4.5 Client-Side Prediction Flow

The three-phase system enables client-side prediction with server reconciliation:

```
Client Timeline (100ms ping example):

Frame 100: Player presses jump button
  ↓
  [Phase 1] Load buffer[99] state
  [Phase 2] Apply jump input → velocity.y = -400
  [Phase 3] Save to buffer[100]
  ↓
  Send RPC to server: input_bitmask, frame_index=100
  ↓
Frame 101: Continue predicting (still in air)
  [Phase 1] Load buffer[100]
  [Phase 2] No input, gravity applies
  [Phase 3] Save to buffer[101]
  ↓
Frame 102-105: Continue predicting
  ↓
Frame 106: Server state arrives (for frame 100)
  ↓
  Compare server_state[100] to buffer[100]:
    - position.x: 150.0 (server) vs 150.2 (client) → diff = 0.2 < threshold (1.0) ✓
    - position.y: 200.0 (server) vs 199.5 (client) → diff = 0.5 < threshold (1.0) ✓
    - velocity.y: -400 (server) vs -400 (client) → diff = 0 ✓
  ↓
  No mismatch → prediction was accurate, continue
```

**Mismatch Example:**

```
Frame 106: Server state arrives (for frame 100)
  ↓
  Compare server_state[100] to buffer[100]:
    - position.y: 200.0 (server) vs 195.0 (client) → diff = 5.0 > threshold (1.0) ✗
  ↓
  Mismatch detected! queue_rollback(100)
  ↓
Frame 107: Rollback executes
  [1] Restore to frame 100 with server's authoritative state
  [2] Re-simulate 100→107 with corrected start state
  [3] Pack corrected states for 100-107
  ↓
  Continue from corrected state
```

### 4.6 ReconcilableNetworkedState: The Core Abstraction

Every networked entity extends this base class:

```gdscript
class_name ReconcilableNetworkedState
extends MultiplayerSynchronizer

# Identity (set by server at spawn)
var player_id: int = 0

# Replicated state (synced via MultiplayerSynchronizer)
var packed_state: Array = []
var packed_state_frame_index: int = 0
var packed_state_authority: FrameAuthority = FrameAuthority.UNKNOWN

signal player_id_changed(new_player_id: int)

# Configuration: Which properties sync and their mismatch thresholds
var _synced_properties_and_rollback_diff_thresholds := {}

# Subclasses must implement these three methods:
func _get_default_values() -> Array:
    # Return default state array
    # Example: return [0.0, 0.0, 0.0, 0.0, false, false, false]
    pass

func _sync_to_scene_state(packed_state: Array) -> void:
    # Apply packed_state to scene nodes (position, velocity, etc.)
    # Example: character.position = Vector2(packed_state[0], packed_state[1])
    pass

func _sync_from_scene_state() -> Array:
    # Pack scene state → array
    # Example: return [character.position.x, character.position.y, ...]
    pass
```

**Threshold Configuration Example:**

```gdscript
# CharacterStateFromServer._ready()
func _ready():
    super._ready()

    _synced_properties_and_rollback_diff_thresholds = {
        "position.x": 1.0,        # 1 pixel tolerance
        "position.y": 1.0,
        "velocity.x": 10.0,       # 10 px/sec tolerance
        "velocity.y": 10.0,
        "is_on_floor": 0,         # Exact match required (boolean)
        "is_on_wall": 0,
        "is_on_ceiling": 0,
    }
```

**Why Thresholds?**

Network jitter and floating-point precision can cause tiny differences in calculations. Thresholds prevent unnecessary rollbacks for imperceptible differences.

**Example:** Client calculates `position.x = 100.001`, server calculates `100.002`. With 1-pixel threshold, this doesn't trigger rollback.

### 4.7 Frame Time Calculations

Although frames are canonical, timestamps are calculated for logging and NTP sync:

```gdscript
func get_time_usec_from_frame_index(frame_index: int) -> int:
    var adjusted_frame := frame_index + _cumulative_paused_frames
    return floori(
        adjusted_frame * TARGET_NETWORK_TIME_STEP_USEC +
        TARGET_NETWORK_TIME_STEP_USEC * 0.5
    )
```

**Pause Handling Example:**

```
Frames:      ... 98  99  100 [PAUSE 5 sec] 101 102 ...
Timestamps:  ... 1633 1650 1666           1666+300frames ...
                                          = 6666 µs

_cumulative_paused_frames = 300 frames (5 seconds * 60 FPS)

Frame 101 time = (101 + 300) * 16666 = 6,682,866 µs
```

Frame indices remain continuous (100→101), but timestamps skip the paused duration.

### 4.8 Periodic Wall-Clock Re-Sync

Every 30 seconds, frame time is re-synced to actual wall-clock time:

```gdscript
const WALL_CLOCK_RESYNC_INTERVAL_SEC = 30.0

func _resync_frame_time_to_wall_clock() -> void:
    var actual_time := G.network.server_time_usec_not_frame_aligned
    var frame_time := get_time_usec_from_frame_index(server_frame_index)
    var drift := actual_time - frame_time

    if absf(drift) > 1_000_000:  # 1 second
        G.warning(
            "Large timestamp drift: %d ms at frame %d" %
            [drift / 1000, server_frame_index]
        )

    # Sync frame time to wall-clock
    server_frame_time_usec = actual_time
```

**Why Needed:**

Cumulative floating-point errors can cause frame-based time to drift from wall-clock. Periodic re-sync keeps timestamps accurate for logging while maintaining frame-based simulation.

---

## 5. Rollback Reconciliation

This section details the rollback mechanism that corrects client predictions when they diverge from server authority.

### 5.1 RollbackBuffer: Frame History Storage

The `RollbackBuffer` (`src/networking/rollback_buffer.gd`) extends `CircularBuffer` to store state snapshots at each frame:

```gdscript
class_name RollbackBuffer
extends CircularBuffer

# Stores ~90 frames (1.5 seconds at 60 FPS)
const DEFAULT_DURATION_SEC = 1.5

func _init(duration_sec: float = DEFAULT_DURATION_SEC):
    var capacity := ceili(duration_sec * TARGET_NETWORK_FPS)
    super._init(capacity)
```

**Structure:**

```
Circular buffer (capacity 90):

Index:   [0]  [1]  [2]  ...  [87] [88] [89]  → wraps to [0]
         ─────────────────────────────────
Frame:    5    6    7   ...   92   93   94
State:   [pos, vel, on_floor, PREDICTED]
         [pos, vel, on_floor, AUTHORITATIVE]
         [pos, vel, on_floor, PREDICTED]
```

Each entry contains:
- Packed state array (position, velocity, etc.)
- Frame authority (UNKNOWN, AUTHORITATIVE, PREDICTED)
- Frame index (implicit from buffer position)

**Special Indices:**

```gdscript
const NEGATIVE_INDEX_1 = -1  # Default "previous" for frame 0
const NEGATIVE_INDEX_2 = -2  # For accessing N-2 when at frame 0
```

These allow consistent `_pre_network_process` logic even at simulation start.

### 5.2 Mismatch Detection Algorithm

When server state arrives, compare it to client's predicted state in the buffer:

```gdscript
# ReconcilableNetworkedState._on_packed_state_changed()
func _check_for_rollback_from_networked_state(networked_state: Array) -> void:
    var networked_frame_index := packed_state_frame_index
    var buffer := G.network.frame_driver.rollback_buffer

    # Get predicted state from buffer
    var buffered_state: Array = buffer.get_at(networked_frame_index)

    if buffered_state.is_empty():
        return  # No prediction to compare

    # Compare each synced property
    var mismatched_properties := _get_mismatched_properties(
        networked_state,
        buffered_state,
        networked_frame_index
    )

    if not mismatched_properties.is_empty():
        G.print(
            "Mismatch at frame %d: %s" %
            [networked_frame_index, str(mismatched_properties)],
            ScaffolderLog.CATEGORY_NETWORK_SYNC
        )

        # Queue rollback to this frame
        G.network.frame_driver.queue_rollback(networked_frame_index)
```

**Detailed Comparison:**

```gdscript
func _get_mismatched_properties(
    networked_state: Array,
    buffered_state: Array,
    frame_index: int
) -> Array:
    var mismatched := []

    for property_name in _synced_properties_and_rollback_diff_thresholds.keys():
        var threshold := _synced_properties_and_rollback_diff_thresholds[property_name]
        var property_index := _get_property_index(property_name)

        var networked_value = networked_state[property_index]
        var buffered_value = buffered_state[property_index]

        if _check_mismatch(buffered_value, networked_value, threshold):
            mismatched.append(property_name)

    return mismatched

func _check_mismatch(
    buffered_value: Variant,
    networked_value: Variant,
    threshold: float
) -> bool:
    # Handle different types
    if buffered_value is float or buffered_value is int:
        return absf(buffered_value - networked_value) > threshold

    if buffered_value is Vector2:
        return buffered_value.distance_to(networked_value) > threshold

    if buffered_value is bool:
        return buffered_value != networked_value  # Exact match required

    # Default: exact equality
    return buffered_value != networked_value
```

### 5.3 Rollback & Re-simulation Process

When mismatch detected, rollback corrects client state:

```gdscript
# NetworkFrameDriver.queue_rollback()
func queue_rollback(frame_index: int) -> void:
    # Only queue if earlier than current queued frame
    if _queued_rollback_frame_index == 0 or (
        frame_index < _queued_rollback_frame_index
    ):
        _queued_rollback_frame_index = frame_index

# NetworkFrameDriver._run_network_process()
func _run_network_process() -> void:
    _update_server_frame_time()

    if _queued_rollback_frame_index > 0:
        _rollback_and_reprocess()
        _queued_rollback_frame_index = 0

    _network_process()
```

**Rollback Algorithm:**

```gdscript
func _rollback_and_reprocess() -> void:
    var rollback_start_time := Time.get_ticks_usec()

    # Save current state
    var original_frame_index := server_frame_index
    var original_frame_time := server_frame_time_usec

    # Rewind to conflict frame
    server_frame_index = _queued_rollback_frame_index
    server_frame_time_usec = get_time_usec_from_frame_index(server_frame_index)

    # Re-simulate all frames between conflict and present
    var frame_count := 0
    while server_frame_index < original_frame_index:
        _network_process()  # This calls 3-phase processing
        server_frame_time_usec += TARGET_NETWORK_TIME_STEP_USEC
        server_frame_index += 1
        frame_count += 1

    # Restore current frame index
    server_frame_index = original_frame_index
    server_frame_time_usec = original_frame_time_usec

    # Track metrics
    last_rollback_frame_count = frame_count
    last_rollback_duration_usec = Time.get_ticks_usec() - rollback_start_time
    total_rollbacks += 1

    G.print(
        "Rollback complete: re-simulated %d frames in %d µs" %
        [frame_count, last_rollback_duration_usec],
        ScaffolderLog.CATEGORY_NETWORK_SYNC
    )
```

**Visual Example:**

```
Original state:
Frame:     100   101   102   103   104   105
Client:   [PRED][PRED][PRED][PRED][PRED][PRED]
Server:   [AUTH]

Server state for frame 102 arrives, mismatch detected:

Rollback process:
1. server_frame_index = 102
2. Load buffer[102] (server's authoritative state)
3. Re-simulate frame 102:
     [Phase 1] Load buffer[102] (server state)
     [Phase 2] Process frame 102
     [Phase 3] Save corrected state to buffer[102]
4. Increment to 103, repeat
5. Continue through 103, 104
6. Restore to frame 105 (current)

Result:
Frame:     100   101   102   103   104   105
Client:   [PRED][PRED][AUTH][PRED][PRED][PRED]
                      ↑ Corrected with server state
                        ↑ Re-simulated with correction
                              ↑ Re-simulated
                                    ↑ Current frame
```

### 5.4 Fast-Forward Mechanism

When client falls behind server (packet loss or slow processing):

```gdscript
# ReconcilableNetworkedState._on_packed_state_changed()
func _on_packed_state_changed(_previous_value: Array) -> void:
    var networked_frame_index := packed_state_frame_index
    var current_frame_index := G.network.frame_driver.server_frame_index

    # Check if state is from the future (more than 1 frame ahead)
    if networked_frame_index > current_frame_index + 1:
        var frames_behind := networked_frame_index - 1 - current_frame_index

        G.print(
            "Client behind by %d frames, fast-forwarding" % frames_behind,
            ScaffolderLog.CATEGORY_NETWORK_SYNC
        )

        # Adjust NTP clock offset
        var time_delta_usec := (
            frames_behind * TARGET_NETWORK_TIME_STEP_USEC
        )
        G.network.time.force_clock_offset(time_delta_usec)

        # Fast-forward to catch up
        G.network.frame_driver.fast_forward(networked_frame_index - 1)
```

**Fast-Forward Implementation:**

```gdscript
func fast_forward(new_frame_index: int) -> void:
    var fast_forward_start_time := Time.get_ticks_usec()

    var original_frame_index := server_frame_index
    var frame_count := new_frame_index - original_frame_index

    # Simulate all skipped frames
    while server_frame_index < new_frame_index:
        server_frame_index += 1
        server_frame_time_usec = get_time_usec_from_frame_index(server_frame_index)
        _network_process()

    # Track metrics
    last_fastforward_frame_count = frame_count
    last_fastforward_duration_usec = Time.get_ticks_usec() - fast_forward_start_time
    total_fastforwards += 1
```

### 5.5 Performance Metrics

Track rollback performance for debugging:

```gdscript
# NetworkFrameDriver
var last_rollback_frame_count: int = 0
var last_rollback_duration_usec: int = 0
var total_rollbacks: int = 0

var last_fastforward_frame_count: int = 0
var last_fastforward_duration_usec: int = 0
var total_fastforwards: int = 0
```

**Typical Performance:**

- **Rollback duration:** 50-500 µs for 5-10 frames
- **Fast-forward duration:** 100-1000 µs for 10-30 frames
- **Rollback frequency:** 0-5 per second (depends on network jitter)

**Performance concerns:**

If `last_rollback_duration_usec > 5000` (5ms), consider:
- Reducing rollback buffer size
- Optimizing `_network_process` logic
- Increasing mismatch thresholds

### 5.6 Buffer Back-Filling

When non-sequential states arrive (e.g., frame 10 → frame 15):

```gdscript
# ReconcilableNetworkedState._back_fill_rollback_buffer()
func _back_fill_rollback_buffer(
    from_frame_index: int,
    to_frame_index: int,
    state: Array
) -> void:
    # Fill gaps with predicted state
    for frame_index in range(from_frame_index + 1, to_frame_index):
        var existing_state := buffer.get_at(frame_index)

        if existing_state.is_empty():
            # Copy the last-known state, mark as PREDICTED
            var filled_state := state.duplicate()
            buffer.set_at(frame_index, filled_state)
```

**Example:**

```
Buffer state:
Frame:  10   11   12   13   14   15
State: [X]  [ ]  [ ]  [ ]  [ ]  [Y]

Back-fill 11-14 with state from frame 10:
Frame:  10   11   12   13   14   15
State: [X]  [X]  [X]  [X]  [X]  [Y]
            ↑ PREDICTED copies
```

---

## 6. Clock Synchronization (NTP)

This section explains how clients synchronize their clocks with the server using an NTP-like algorithm.

### 6.1 ServerTimeTracker Overview

The `ServerTimeTracker` (`src/networking/server_time_tracker.gd`) implements a simplified Network Time Protocol (NTP) to estimate server time on clients:

```gdscript
class_name ServerTimeTracker

# Calculated offset from local time to server time
var clock_offset_usec: int = 0

# Smoothed round-trip time to server
var round_trip_time_usec: int = 0

# Sliding window of recent measurements
var _recent_offset_samples: Array[int] = []
var _recent_rtt_samples: Array[int] = []
const SMOOTHING_WINDOW_SIZE = 5
```

**Purpose:**
- Clients need to know "what time is it on the server?" to correctly align frame indices
- Direct timestamps are unreliable due to clock drift and network jitter
- NTP provides accurate time estimation accounting for latency

### 6.2 Four-Timestamp Algorithm

The NTP-like protocol uses four timestamps to calculate offset and RTT:

```
Client                                    Server
  |                                         |
  | T1: Send ping                           |
  |─────────────────────────────────────────>|
  |                                         | T2: Receive ping
  |                                         |
  |                                         | T3: Send pong
  |<─────────────────────────────────────────|
  | T4: Receive pong                        |
  |                                         |

Round-trip time (RTT) = (T4 - T1) - (T3 - T2)
Clock offset = ((T2 - T1) + (T3 - T4)) / 2
```

**Implementation:**

```gdscript
# Client sends ping
@rpc("any_peer", "unreliable")
func _client_rpc_sync_time_request(client_send_time_usec: int) -> void:
    var server_receive_time_usec := Time.get_ticks_usec()
    var peer_id := multiplayer.get_remote_sender_id()

    # Server immediately responds with pong
    _server_rpc_sync_time_response.rpc_id(
        peer_id,
        client_send_time_usec,       # T1
        server_receive_time_usec,     # T2
        Time.get_ticks_usec()         # T3 (send time)
    )

# Client receives pong
@rpc("authority", "unreliable")
func _server_rpc_sync_time_response(
    client_send_time_usec: int,      # T1
    server_receive_time_usec: int,   # T2
    server_send_time_usec: int       # T3
) -> void:
    var client_receive_time_usec := Time.get_ticks_usec()  # T4

    # Calculate RTT and offset
    var rtt := (client_receive_time_usec - client_send_time_usec) - \
               (server_send_time_usec - server_receive_time_usec)

    var offset := ((server_receive_time_usec - client_send_time_usec) + \
                   (server_send_time_usec - client_receive_time_usec)) / 2

    _add_measurement(offset, rtt)
```

### 6.3 Smoothing with Sliding Window

Raw measurements are noisy due to network jitter. Use a sliding window to smooth:

```gdscript
func _add_measurement(offset: int, rtt: int) -> void:
    # Add to sliding window
    _recent_offset_samples.append(offset)
    _recent_rtt_samples.append(rtt)

    # Keep only last N samples
    if _recent_offset_samples.size() > SMOOTHING_WINDOW_SIZE:
        _recent_offset_samples.pop_front()
        _recent_rtt_samples.pop_front()

    # Use median to filter outliers
    clock_offset_usec = _calculate_median(_recent_offset_samples)
    round_trip_time_usec = _calculate_median(_recent_rtt_samples)

    time_sync_updated.emit()

func _calculate_median(samples: Array[int]) -> int:
    if samples.is_empty():
        return 0

    var sorted := samples.duplicate()
    sorted.sort()

    var mid := sorted.size() / 2
    if sorted.size() % 2 == 0:
        return (sorted[mid - 1] + sorted[mid]) / 2
    else:
        return sorted[mid]
```

**Why Median Instead of Average?**

Median is robust against outliers (e.g., occasional packet loss causing 200ms spike doesn't skew the estimate).

### 6.4 Start Time Offset Synchronization

In addition to clock offset, clients need to know when the server started:

```gdscript
# Server broadcasts start time
@rpc("authority", "call_local", "reliable")
func _server_rpc_sync_start_time_offset(
    server_start_time_usec: int
) -> void:
    var local_start_time_usec := G.network.start_time_usec
    _start_time_offset_usec = server_start_time_usec - local_start_time_usec

    G.print(
        "Synced start time offset: %d µs" % _start_time_offset_usec,
        ScaffolderLog.CATEGORY_NETWORK_SYNC
    )
```

This allows clients to align their `server_frame_index` correctly at simulation start.

### 6.5 Pause Handling

When paused, cumulative pause time is tracked:

```gdscript
var _cumulative_paused_usec: int = 0
var _last_pause_start_usec: int = 0

func on_pause() -> void:
    _last_pause_start_usec = Time.get_ticks_usec()

func on_unpause() -> void:
    var pause_duration := Time.get_ticks_usec() - _last_pause_start_usec
    _cumulative_paused_usec += pause_duration
```

This ensures timestamps remain accurate even after pauses.

### 6.6 Accessing Server Time

```gdscript
# Get current estimated server time
var estimated_server_time_usec: int:
    get:
        return Time.get_ticks_usec() + clock_offset_usec

# Get server time accounting for start offset
var server_time_since_start_usec: int:
    get:
        return estimated_server_time_usec - G.network.start_time_usec - \
               _start_time_offset_usec - _cumulative_paused_usec
```

---

## 7. Multi-Player Per Client

This section covers support for multiple players controlled by a single client (local multiplayer).

### 7.1 Why Support Multiple Players Per Client?

**Use Cases:**
- Local couch co-op (2-4 players on one machine)
- Splitscreen gameplay
- Testing (simulate multiple players from one client)

**Design Requirements:**
1. Each player needs unique `player_id` (globally unique across all clients)
2. Each player needs input device mapping (keyboard vs gamepad 1 vs gamepad 2)
3. Server must track which `player_id`s belong to which `peer_id`
4. Character spawning must create N characters for N players

### 7.2 Input Device Mapping

`LocalSession` (`src/core/local_session.gd`) configures devices for local players:

```gdscript
class_name LocalSession

# How many local players on this client?
var local_player_count: int = 1

# Input device for each local player
var device_configs: Array[DeviceConfig] = []

# GameLift session IDs (or empty for preview mode)
var session_ids: Array[String] = []

# Server-assigned player_ids (filled after declaration)
var player_ids: Array[int] = []
```

**DeviceConfig:**

```gdscript
class_name DeviceConfig

enum Type {
    KEYBOARD,
    GAMEPAD
}

var type: Type = Type.KEYBOARD
var gamepad_index: int = 0  # Which gamepad (0, 1, 2, 3)
```

**Example Setup (2 players):**

```gdscript
var session = LocalSession.new()
session.local_player_count = 2
session.device_configs = [
    DeviceConfig.new(DeviceConfig.Type.KEYBOARD),
    DeviceConfig.new(DeviceConfig.Type.GAMEPAD, 0)
]
```

### 7.3 Input Device Manager

`InputDeviceManager` (`src/scaffolder/input/input_device_manager.gd`) maps `local_player_index` to device:

```gdscript
class_name InputDeviceManager

# Map local_player_index → DeviceConfig
var _device_map := {}

func configure_devices(device_configs: Array[DeviceConfig]) -> void:
    _device_map.clear()

    for local_index in range(device_configs.size()):
        _device_map[local_index] = device_configs[local_index]

func get_input_for_player(local_player_index: int) -> Dictionary:
    var device := _device_map.get(local_player_index)

    if device == null:
        return {}

    if device.type == DeviceConfig.Type.KEYBOARD:
        return _read_keyboard_input()
    else:
        return _read_gamepad_input(device.gamepad_index)
```

### 7.4 Player Spawning Flow

**Step 1: Client Declares Players**

```gdscript
# NetworkConnector (client side)
func declare_players() -> void:
    var session := G.local_session

    # Send session IDs to server (or empty array for preview mode)
    _server_rpc_declare_players.rpc(session.session_ids)
```

**Step 2: Server Assigns Player IDs**

```gdscript
# NetworkConnector (server side)
@rpc("any_peer", "call_local", "reliable")
func _server_rpc_declare_players(session_ids: Array) -> void:
    var peer_id := multiplayer.get_remote_sender_id()

    var assigned_ids: Array[int] = []

    for local_player_index in range(session_ids.size()):
        # Assign sequential player_id
        assigned_ids.append(_next_player_id)

        # Track mappings
        _player_id_to_peer_id[_next_player_id] = peer_id
        _player_id_to_local_player_index[_next_player_id] = local_player_index

        _next_player_id += 1

    # Validate session IDs with GameLift (if enabled)
    if G.game_lift.is_enabled:
        _validate_player_sessions(peer_id, session_ids)

    # Send IDs back to client
    _client_rpc_receive_player_ids.rpc_id(peer_id, assigned_ids)

    # Notify level to spawn players
    peer_players_declared.emit(peer_id, assigned_ids)
```

**Step 3: Client Receives IDs**

```gdscript
@rpc("authority", "call_local", "reliable")
func _client_rpc_receive_player_ids(assigned_ids: Array[int]) -> void:
    G.local_session.player_ids = assigned_ids

    G.print(
        "Received player IDs: %s" % str(assigned_ids),
        ScaffolderLog.CATEGORY_GAME_STATE
    )

    player_ids_received.emit(assigned_ids)
```

**Step 4: Level Spawns Characters**

```gdscript
# NetworkedLevel._server_register_players_for_peer()
func _server_register_players_for_peer(
    peer_id: int,
    assigned_ids: Array[int]
) -> void:
    for local_index in range(assigned_ids.size()):
        var player_id := assigned_ids[local_index]

        # Instantiate player character
        var player: Player = G.settings.default_player_scene.instantiate()
        player.player_id = player_id
        player.name = "Player_%d" % player_id
        player.global_position = _get_player_spawn_position()

        # Track in dictionaries
        players_by_id[player_id] = player
        if not peer_to_player_ids.has(peer_id):
            peer_to_player_ids[peer_id] = []
        peer_to_player_ids[peer_id].append(player_id)

        # Add to scene (MultiplayerSpawner replicates to all clients)
        players_node.add_child(player)
```

### 7.5 Three-Node Player Architecture

Each player character uses three synchronized nodes:

```
Player (CharacterBody2D)
├─ CharacterStateFromServer (MultiplayerSynchronizer, server authority)
│  └─ Replicates: position, velocity, is_on_floor, etc.
├─ PlayerInputFromClient (MultiplayerSynchronizer, peer authority)
│  └─ Replicates: input_bitmask (from owning peer only)
└─ ForwardedPlayerInputFromServer (MultiplayerSynchronizer, server authority)
   └─ Replicates: input_bitmask (server forwards to all clients)
```

**Authority Assignment:**

```gdscript
# Player._ready()
func _ready():
    # Server authority for physics state
    %CharacterStateFromServer.set_multiplayer_authority(NetworkConnector.SERVER_ID)

    # Peer authority for input (only owning peer can send input)
    %PlayerInputFromClient.set_multiplayer_authority(peer_id)

    # Server authority for forwarded input (server broadcasts to all)
    %ForwardedPlayerInputFromServer.set_multiplayer_authority(NetworkConnector.SERVER_ID)
```

**Why Three Nodes?**

1. **CharacterStateFromServer:** Server simulates physics, sends authoritative state to all clients
2. **PlayerInputFromClient:** Owning client sends input directly to server (low latency)
3. **ForwardedPlayerInputFromServer:** Server forwards input to other clients (for spectating, replays, etc.)

### 7.6 Derived Properties: peer_id and local_player_index

`ReconcilableNetworkedState` derives `peer_id` and `local_player_index` from `PlayerMatchState`:

```gdscript
# ReconcilableNetworkedState
var peer_id: int:
    get:
        if Engine.is_editor_hint():
            return _stored_peer_id

        # Look up from MatchState
        var player_state := G.match_state.get_player(player_id)
        if player_state != null:
            return player_state.peer_id
        else:
            return _stored_peer_id  # Fallback for tests

var local_player_index: int:
    get:
        if Engine.is_editor_hint():
            return _stored_local_player_index

        var player_state := G.match_state.get_player(player_id)
        if player_state != null:
            return player_state.local_player_index
        else:
            return _stored_local_player_index
```

**Why Derived?**

- `peer_id` and `local_player_index` are constant for a player's lifetime
- Stored once in `PlayerMatchState`, looked up on demand
- Avoids replicating redundant data on every character

---

## 8. GameLift Integration

This section covers AWS GameLift integration for session management and player authentication.

### 8.1 GameLift Overview

**AWS GameLift** is a managed service for deploying multiplayer game servers on EC2 instances.

**Key Concepts:**
- **Fleet:** Collection of EC2 instances running game servers
- **Game Session:** A single match instance (e.g., one 4-player game)
- **Player Session:** A player's slot in a game session (tied to authentication token)
- **Session ID:** GameLift-issued authentication token per player

**Two-Level Authority Model:**

```
GameLift Layer (Authentication):
  session_id (UUID) → validates player is authorized to join

Gameplay Layer (Identity):
  player_id (sequential int) → unique ID for game logic
```

### 8.2 GameLiftManager Structure

`GameLiftManager` (`src/networking/game_lift_manager.gd`) wraps the native GameLift SDK:

```gdscript
class_name GameLiftManager

# Is GameLift enabled? (false in preview mode)
var is_enabled: bool = false

# Mappings between GameLift and gameplay IDs
var _player_to_session := {}  # player_id → session_id
var _session_to_player := {}  # session_id → player_id
var _player_to_peer := {}     # player_id → peer_id

# GameLift SDK reference
var _sdk: GameLiftServerSdk = null
```

### 8.3 Server Lifecycle

**Initialization:**

```gdscript
func initialize() -> void:
    # Check if running on GameLift fleet
    if not OS.has_feature("gamelift"):
        G.print("GameLift not enabled (preview mode)")
        is_enabled = false
        return

    is_enabled = true

    # Load SDK
    _sdk = GameLiftServerSdk.new()

    # Initialize SDK
    var init_result := _sdk.init_sdk()
    if init_result != GameLiftServerSdk.Status.OK:
        G.error("GameLift SDK init failed: %s" % init_result)
        return

    # Notify GameLift server is ready
    var process_params := GameLiftServerSdk.ProcessParameters.new()
    process_params.on_start_game_session = _on_game_session_started
    process_params.on_process_terminate = _on_process_terminate_requested
    process_params.on_health_check = _on_health_check
    process_params.port = G.settings.server_port

    var ready_result := _sdk.process_ready(process_params)
    if ready_result != GameLiftServerSdk.Status.OK:
        G.error("GameLift process_ready failed: %s" % ready_result)
```

**Game Session Started:**

```gdscript
func _on_game_session_started(game_session: GameLiftServerSdk.GameSession) -> void:
    G.print("GameLift game session started: %s" % game_session.game_session_id)

    # Activate game session
    var activate_result := _sdk.activate_game_session()
    if activate_result != GameLiftServerSdk.Status.OK:
        G.error("Failed to activate game session: %s" % activate_result)

    # Server remains paused until all players connect
    game_session_started.emit(game_session)
```

### 8.4 Player Session Validation

When client sends `session_ids`, server validates with GameLift:

```gdscript
# NetworkConnector._validate_player_sessions()
func _validate_player_sessions(
    peer_id: int,
    session_ids: Array
) -> void:
    if not G.game_lift.is_enabled:
        return  # Skip in preview mode

    for local_index in range(session_ids.size()):
        var session_id: String = session_ids[local_index]
        var player_id := _get_player_id_for_peer_and_local_index(peer_id, local_index)

        # Call GameLift SDK to validate
        var result := G.game_lift.sdk.accept_player_session(session_id)

        if result == GameLiftServerSdk.Status.OK:
            G.print(
                "Player session validated: %s → player_id %d" %
                [session_id, player_id]
            )

            # Record mappings
            G.game_lift._player_to_session[player_id] = session_id
            G.game_lift._session_to_player[session_id] = player_id
            G.game_lift._player_to_peer[player_id] = peer_id
        else:
            G.error(
                "Player session validation failed for %s: %s" %
                [session_id, result]
            )

            # Disconnect peer
            multiplayer.disconnect_peer(peer_id)
```

**Why Validate?**

GameLift ensures only authorized players can join. Without validation, any client could connect and claim a slot.

### 8.5 Pause-Until-Ready Pattern

Server starts paused and unpauses when all expected players connect:

```gdscript
# GamePanel._on_all_players_connected()
func _on_all_players_connected() -> void:
    if G.game_lift.is_enabled:
        # Notify GameLift all players connected
        G.game_lift.notify_all_players_connected()

    # Unpause frame driver
    G.network.frame_driver.unpause()

    G.print("All players connected, game starting")
```

**GameLift Notification:**

```gdscript
func notify_all_players_connected() -> void:
    if not is_enabled:
        return

    var result := _sdk.update_player_session_creation_policy(
        GameLiftServerSdk.PlayerSessionCreationPolicy.DENY_ALL
    )

    if result == GameLiftServerSdk.Status.OK:
        G.print("GameLift: all players connected, denying new sessions")
```

### 8.6 Graceful Shutdown

When GameLift terminates the process:

```gdscript
func _on_process_terminate_requested() -> void:
    G.print("GameLift requesting process termination")

    # Notify clients
    G.network.connector._client_rpc_notify_server_shutdown.rpc()

    # Wait for clients to disconnect
    await get_tree().create_timer(5.0).timeout

    # Notify GameLift shutdown complete
    var result := _sdk.process_ending()
    if result == GameLiftServerSdk.Status.OK:
        G.print("GameLift process ending acknowledged")

    # Exit
    get_tree().quit()
```

### 8.7 Preview Mode (Local Testing)

When `--preview` flag is set, GameLift is disabled:

```gdscript
# Launch with: godot --server --preview
# session_ids array is empty
# No validation, no GameLift SDK calls
# Server immediately unpauses (no waiting for player sessions)
```

This allows local testing without GameLift infrastructure.

### 8.8 Managed vs Anywhere Fleets

**Managed Fleets:**
- GameLift provisions EC2 instances
- Automatic scaling based on player demand
- Built-in health checks and crash recovery

**Anywhere Fleets:**
- Run on your own hardware (on-prem or other cloud)
- Register with GameLift for matchmaking
- Manual scaling and health management

This project supports both via conditional SDK initialization.

---

## 9. Pause & Synchronization

This section covers pause mechanics and synchronized game start.

### 9.1 Pause State Management

`NetworkFrameDriver` manages pause state:

```gdscript
var _is_paused: bool = true  # Starts paused
var _pause_frame_index: int = 0
var _cumulative_paused_frames: int = 0

func pause() -> void:
    if _is_paused:
        return

    _is_paused = true
    _pause_frame_index = server_frame_index

    if G.network.is_server:
        _client_rpc_notify_pause.rpc()

    G.print("Game paused at frame %d" % _pause_frame_index)

func unpause() -> void:
    if not _is_paused:
        return

    var paused_frame_count := server_frame_index - _pause_frame_index
    _cumulative_paused_frames += paused_frame_count

    _is_paused = false

    if G.network.is_server:
        _client_rpc_notify_unpause.rpc()

    G.print("Game unpaused, skipped %d frames" % paused_frame_count)
```

### 9.2 Synchronized Start

**Server-Side Flow:**

```gdscript
# GamePanel (server)
func _on_level_added(level: Level) -> void:
    # Level added but game still paused
    is_level_fully_loaded = true

    # Wait for all players to connect
    G.network.connector.all_players_connected.connect(_on_all_players_connected)

func _on_all_players_connected() -> void:
    # All players ready, unpause
    G.network.frame_driver.unpause()
```

**Client-Side Flow:**

```gdscript
# Client receives unpause RPC
@rpc("authority", "call_local", "reliable")
func _client_rpc_notify_unpause() -> void:
    unpause()

    # Clean up rollback buffer (reset to pause frame state)
    _cleanup_rollback_buffer_after_unpause()
```

### 9.3 Buffer Cleanup After Pause

When unpausing, reset all buffered frames to the pause state:

```gdscript
func _cleanup_rollback_buffer_after_unpause() -> void:
    if not is_instance_valid(rollback_buffer):
        return

    # Get state at pause frame
    var pause_state := rollback_buffer.get_at(_pause_frame_index)

    if pause_state.is_empty():
        return

    # Reset all frames from pause to current
    for frame_index in range(_pause_frame_index + 1, server_frame_index + 1):
        rollback_buffer.set_at(frame_index, pause_state.duplicate())
```

**Why?**

During pause, no simulation occurs, so frames should all have identical state. This prevents spurious rollbacks when resuming.

### 9.4 Client-Requested Pause (Optional)

Clients can request pause (subject to rate limiting):

```gdscript
# Client
func request_pause() -> void:
    if _can_request_pause():
        _server_rpc_request_pause.rpc()

# Server
@rpc("any_peer", "reliable")
func _server_rpc_request_pause() -> void:
    var peer_id := multiplayer.get_remote_sender_id()

    # Rate limiting: max 1 pause per peer per 10 seconds
    if not _check_pause_rate_limit(peer_id):
        G.warning("Pause request from peer %d denied (rate limit)" % peer_id)
        return

    pause()
```

---

## 10. State Replication Patterns

This section documents common patterns for replicating game state.

### 10.1 MatchState Synchronization

`MatchState` (`src/core/match_state.gd`) replicates high-level match data:

```gdscript
class_name MatchState

# Packed array of player states (for efficient replication)
var packed_players: Array = []

# Dictionary for fast lookup
var players_by_id := {}  # player_id → PlayerMatchState

# Kill tracking (paired indices: [killer_id, killed_id, killer_id, killed_id, ...])
var packed_kills: PackedInt32Array = []

# Bump tracking
var packed_bumps: PackedInt32Array = []
```

**Replication Config:**

```
MultiplayerSynchronizer settings:
- Authority: Server (peer 1)
- Replication interval: 0.0 (every frame)
- Delta compression: false
- Synced properties:
  - packed_players (Array)
  - packed_kills (PackedInt32Array)
  - packed_bumps (PackedInt32Array)
```

### 10.2 Two-Tier Signal Architecture

**Low-Level Signals (Data Changed):**

```gdscript
signal players_updated()
signal kills_updated()
signal bumps_updated()
```

Emitted when packed arrays change. Used internally by synchronizer.

**High-Level Signals (Game Events):**

```gdscript
signal player_joined(player_id: int)
signal player_left(player_id: int)
signal player_killed(killer_id: int, killed_id: int)
signal players_bumped(bumper_id: int, bumped_id: int)
```

Emitted by `MatchStateSynchronizer` after parsing packed arrays. UI connects to these.

**Example:**

```gdscript
# MatchStateSynchronizer._on_packed_players_changed()
func _on_packed_players_changed(_previous: Array) -> void:
    var current_ids := _extract_player_ids(G.match_state.packed_players)
    var previous_ids := _extract_player_ids(_previous)

    # Detect joins
    for player_id in current_ids:
        if player_id not in previous_ids:
            G.match_state.player_joined.emit(player_id)

    # Detect leaves
    for player_id in previous_ids:
        if player_id not in current_ids:
            G.match_state.player_left.emit(player_id)

    # Emit low-level signal
    G.match_state.players_updated.emit()
```

### 10.3 Kill & Bump Tracking with Paired Arrays

`PackedInt32Array` is efficient for replicating event streams:

```gdscript
# Server: Player 3 killed Player 7
func record_kill(killer_id: int, killed_id: int) -> void:
    packed_kills.append(killer_id)
    packed_kills.append(killed_id)

    # Triggers replication
    notify_property_list_changed()

# Client: Parse kills
func _on_packed_kills_changed(previous: PackedInt32Array) -> void:
    # Find new entries (compare sizes)
    var new_count := (packed_kills.size() - previous.size()) / 2

    for i in range(new_count):
        var index := previous.size() + i * 2
        var killer_id := packed_kills[index]
        var killed_id := packed_kills[index + 1]

        player_killed.emit(killer_id, killed_id)
```

**Why Paired Array?**

- More efficient than Array[Dictionary]
- Preserves order (chronological events)
- Delta compression works well (append-only)

### 10.4 Dual Synchronizer Pattern

For player characters, use two separate synchronizers:

**Spawner (Server Authority):**

```gdscript
# Spawns player character nodes
%PlayerSpawner (MultiplayerSpawner)
  - Authority: Server
  - Spawn path: /root/Level/Players
  - Scenes: [res://src/player/bunny.tscn]
```

**Input State (Peer Authority):**

```gdscript
# PlayerInputFromClient (per player)
%PlayerInputFromClient (MultiplayerSynchronizer)
  - Authority: peer_id (owning peer)
  - Synced properties: [input_bitmask]
```

**Why Separate?**

Spawning requires server authority (prevent client-side spawning exploits). Input requires peer authority (low-latency local input). Using separate synchronizers isolates these concerns.

---

## 11. Debugging & Observability

This section covers debugging tools and common issues.

### 11.1 Logging Categories

Use `ScaffolderLog` categories for filtered logging:

```gdscript
# Network synchronization (rollback, time sync)
G.print("Rollback triggered", ScaffolderLog.CATEGORY_NETWORK_SYNC)

# Connection events (peer join/leave)
G.print("Peer connected", ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)

# Game state changes (player spawn, kills)
G.print("Player spawned", ScaffolderLog.CATEGORY_GAME_STATE)

# Core system initialization
G.print("NetworkMain ready", ScaffolderLog.CATEGORY_CORE_SYSTEMS)
```

**Filtering in settings:**

```gdscript
# settings.tres
enabled_log_categories = [
    ScaffolderLog.CATEGORY_NETWORK_SYNC,
    ScaffolderLog.CATEGORY_GAME_STATE
]
```

### 11.2 Performance Metrics

`NetworkFrameDriver` exposes rollback and fast-forward metrics:

```gdscript
# Rollback stats
var last_rollback_frame_count: int
var last_rollback_duration_usec: int
var total_rollbacks: int

# Fast-forward stats
var last_fastforward_frame_count: int
var last_fastforward_duration_usec: int
var total_fastforwards: int

# Access via
G.network.frame_driver.last_rollback_duration_usec
```

**Example Debug UI:**

```gdscript
func _process(_delta):
    $RollbackLabel.text = "Rollbacks: %d (last: %d frames in %d µs)" % [
        G.network.frame_driver.total_rollbacks,
        G.network.frame_driver.last_rollback_frame_count,
        G.network.frame_driver.last_rollback_duration_usec
    ]
```

### 11.3 Common Issues & Solutions

**Issue: "Rollback buffer missing required frame"**

```
ERROR: Rollback buffer doesn't contain frame 105
```

**Cause:** Entity tried to restore from buffer before initialization complete.

**Solution:** Ensure `_is_frame_tracking_initialized` is true before accessing buffer:

```gdscript
func _pre_network_process():
    if not G.network.frame_driver._is_frame_tracking_initialized:
        return
    # ... rest of logic
```

**Issue: "Rejecting too-distant-future state"**

```
WARNING: Received state for frame 200, current frame 150 (50 ahead)
```

**Cause:** Client clock drift (NTP offset incorrect).

**Solution:** Check `ServerTimeTracker.clock_offset_usec`. If drifting, increase smoothing window or investigate network jitter.

**Issue: "Prediction state mismatch" (frequent rollbacks)**

```
INFO: Mismatch at frame 105: ["position.y"]
INFO: Rollback triggered for frame 105
```

**Cause (Normal):** Network jitter or physics non-determinism (expected occasionally).

**Cause (Problematic):** If >10 rollbacks/second, check:
- Mismatch thresholds too tight
- Non-deterministic logic in `_network_process`
- Floating-point precision issues

**Solution:** Increase thresholds or add determinism guards:

```gdscript
# Use frame_index as seed for randomness
var rng := RandomNumberGenerator.new()
rng.seed = G.network.frame_driver.server_frame_index
```

**Issue: "Player spawned but invisible"**

**Cause:** Spawn occurred before client loaded level scene.

**Solution:** Ensure level is fully loaded before spawning:

```gdscript
# GamePanel (server)
if not is_level_fully_loaded:
    await level_fully_loaded  # Wait for signal
# Now spawn players
```

---

## 12. Advanced Topics

This section covers advanced implementation details.

### 12.1 ArrayPool Memory Optimization

`ArrayPool` (`src/scaffolder/util/array_pool.gd`) reuses Array instances to reduce GC pressure:

```gdscript
class_name ArrayPool

# Global pool per type
static var _pools := {}

static func acquire(type_hint: int = TYPE_NIL) -> Array:
    if not _pools.has(type_hint):
        _pools[type_hint] = []

    var pool: Array = _pools[type_hint]

    if pool.is_empty():
        return []  # Create new
    else:
        return pool.pop_back()  # Reuse

static func release(array: Array, type_hint: int = TYPE_NIL) -> void:
    array.clear()  # Clear contents

    if not _pools.has(type_hint):
        _pools[type_hint] = []

    _pools[type_hint].append(array)  # Return to pool
```

**Usage in CircularBuffer:**

```gdscript
func get_at(frame_index: int) -> Array:
    var slot := _frame_index_to_slot(frame_index)

    if _data[slot].is_empty():
        return ArrayPool.acquire()  # From pool
    else:
        return _data[slot].duplicate()  # Copy existing

# Remember to release when done
func _cleanup():
    for array in _data:
        ArrayPool.release(array)
```

**Testing Note:** Tests MUST call `ArrayPool.clear_all_pools()` in `before_each()` and `after_each()` to prevent pool contamination between tests.

### 12.2 FrameAuthority Enum

Tracks whether a buffered state is authoritative or predicted:

```gdscript
enum FrameAuthority {
    UNKNOWN = 0,       # Not yet determined
    AUTHORITATIVE = 1, # From server (ground truth)
    PREDICTED = 2      # Client prediction
}

# Set when packing state
packed_state_authority = (
    FrameAuthority.AUTHORITATIVE if G.network.is_server
    else FrameAuthority.PREDICTED
)
```

**Use Case:** When back-filling buffer gaps, mark filled frames as PREDICTED to distinguish from actual server states.

### 12.3 Negative Buffer Indices (-1, -2)

`CircularBuffer` supports negative indices for consistent "previous frame" logic:

```gdscript
# At frame 0, "previous" frame is -1
var previous_state := buffer.get_at(server_frame_index - 1)

# CircularBuffer._frame_index_to_slot()
func _frame_index_to_slot(frame_index: int) -> int:
    if frame_index == NEGATIVE_INDEX_1:
        return _capacity  # Special slot for -1
    elif frame_index == NEGATIVE_INDEX_2:
        return _capacity + 1  # Special slot for -2
    else:
        return frame_index % _capacity
```

**Why?**

Eliminates special-case logic at simulation start. Character action handlers can always reference `frame - 1` without bounds checking.

### 12.4 Back-Filling Algorithm

When non-sequential states arrive (e.g., frame 10 → 15), fill gaps with last-known state:

```gdscript
func _back_fill_rollback_buffer(
    from_frame_index: int,
    to_frame_index: int,
    state: Array
) -> void:
    for frame_index in range(from_frame_index + 1, to_frame_index):
        var existing_state := buffer.get_at(frame_index)

        if existing_state.is_empty():
            # Copy state, mark as PREDICTED
            var filled_state := state.duplicate()
            buffer.set_at(frame_index, filled_state)
```

**Example:**

```
Server sends states: 100, 105 (skipped 101-104)
Client back-fills 101-104 with state[100]
```

This ensures rollback can rewind to any frame without missing data.

---

## 13. Testing Architecture

This section summarizes the testing framework and key test files.

### 13.1 Test Organization

```
res://test/
├── unit/                           # Isolated unit tests
│   ├── scaffolder/
│   │   ├── test_circular_buffer.gd       # 47 tests
│   │   ├── test_array_pool.gd            # 13 tests
│   │   └── test_surface_state.gd
│   └── networking/
│       ├── test_rollback_buffer.gd       # 20 tests
│       ├── test_server_time_tracker.gd   # 12 tests
│       └── test_network_frame_driver.gd  # 14+ tests
└── integration/                    # Multi-component tests
    ├── test_rollback_flow.gd             # 10 tests
    ├── test_state_synchronization.gd     # 10+ tests
    └── test_frame_timing.gd
```

### 13.2 Key Test Files

**test_circular_buffer.gd (47 tests):**
- Wrapping behavior
- Capacity management
- Negative index handling
- ArrayPool integration

**test_rollback_buffer.gd (20 tests):**
- Frame storage and retrieval
- Back-filling gaps
- Authority tracking
- Mismatch detection

**test_network_frame_driver.gd (14+ tests):**
- Frame increment logic
- Pause/unpause
- Rollback triggering
- Fast-forward

**test_server_time_tracker.gd (12 tests):**
- NTP offset calculation
- RTT smoothing
- Start time sync
- Pause handling

### 13.3 Critical Test Patterns

**ArrayPool Cleanup (Mandatory):**

```gdscript
extends GutTest

func before_each():
    ArrayPool.clear_all_pools()

func after_each():
    ArrayPool.clear_all_pools()
```

**Type Hints for Arrays:**

```gdscript
# Correct
var state: Array = buffer.get_at(5)
assert_eq(state[0], 100.0)

# Incorrect (may fail)
var state = buffer.get_at(5)
```

**Mocking NetworkMain:**

```gdscript
var MockNetworkMain = double(NetworkMain)
stub(MockNetworkMain, 'is_server').to_return(true)
stub(MockNetworkMain, 'get_current_tick').to_return(100)

G.network = MockNetworkMain.new()
```

### 13.4 Running Tests

**Editor:**
- Open GUT panel → Select test file → Run All

**Command Line (Recommended):**

```bash
# Run specific file
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gtest=res://test/unit/networking/test_rollback_buffer.gd -gexit

# Run all unit tests (use specific files for reliability)
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gdir=res://test/unit -gexit
```

**CI/CD Integration:**

```bash
# Export results for CI
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gdir=res://test/unit -gexit -gjunit_xml_file=results.xml

# Check exit code
if [ $? -ne 0 ]; then
  echo "Tests failed"
  exit 1
fi
```

---

## 14. Reference Tables

This section provides quick-reference tables for common lookups.

### 14.1 Key Constants

| Constant | Value | Location | Purpose |
|----------|-------|----------|---------|
| `TARGET_NETWORK_FPS` | 60 | NetworkFrameDriver | Fixed network tick rate |
| `TARGET_NETWORK_TIME_STEP_SEC` | 0.01666... | NetworkFrameDriver | Frame duration in seconds |
| `TARGET_NETWORK_TIME_STEP_USEC` | 16666 | NetworkFrameDriver | Frame duration in microseconds |
| `ROLLBACK_BUFFER_DURATION_SEC` | 1.5 | RollbackBuffer | Buffer capacity (90 frames) |
| `SERVER_ID` | 1 | NetworkConnector | Server's peer_id |
| `SMOOTHING_WINDOW_SIZE` | 5 | ServerTimeTracker | NTP sample window |
| `WALL_CLOCK_RESYNC_INTERVAL_SEC` | 30.0 | NetworkFrameDriver | Timestamp re-sync interval |

### 14.2 RPC Summary

| RPC Name | Authority | Reliability | Purpose |
|----------|-----------|-------------|---------|
| `_server_rpc_declare_players` | any_peer | reliable | Client sends session IDs to server |
| `_client_rpc_receive_player_ids` | authority | reliable | Server sends assigned player_ids to client |
| `_client_rpc_sync_time_request` | any_peer | unreliable | Client requests NTP sync |
| `_server_rpc_sync_time_response` | authority | unreliable | Server responds with timestamps |
| `_client_rpc_notify_pause` | authority | reliable | Server notifies clients of pause |
| `_client_rpc_notify_unpause` | authority | reliable | Server notifies clients of unpause |
| `_server_rpc_sync_start_time_offset` | authority | reliable | Server syncs start time to clients |
| `_client_rpc_notify_server_shutdown` | authority | reliable | Server notifies clients of shutdown |

### 14.3 File Map

| Component | File Path | Key Classes |
|-----------|-----------|-------------|
| Network coordinator | `src/networking/network_main.gd` | NetworkMain |
| Frame simulation | `src/networking/network_frame_driver.gd` | NetworkFrameDriver |
| Player ID assignment | `src/networking/network_connector.gd` | NetworkConnector |
| State synchronization | `src/networking/reconcilable_network_state.gd` | ReconcilableNetworkedState |
| Clock sync | `src/networking/server_time_tracker.gd` | ServerTimeTracker |
| Rollback buffer | `src/networking/rollback_buffer.gd` | RollbackBuffer |
| Circular buffer | `src/scaffolder/util/circular_buffer.gd` | CircularBuffer |
| Array pool | `src/scaffolder/util/array_pool.gd` | ArrayPool |
| GameLift integration | `src/networking/game_lift_manager.gd` | GameLiftManager |
| Player identity | `src/core/player_match_state.gd` | PlayerMatchState |
| Match state | `src/core/match_state.gd` | MatchState |
| Match state sync | `src/core/match_state_synchronizer.gd` | MatchStateSynchronizer |
| Local session | `src/core/local_session.gd` | LocalSession |
| Game lifecycle | `src/core/game_panel.gd` | GamePanel |
| Character physics | `src/scaffolder/character/character_state_from_server.gd` | CharacterStateFromServer |
| Client input | `src/scaffolder/character/player_input_from_client.gd` | PlayerInputFromClient |
| Forwarded input | `src/scaffolder/character/forwarded_player_input_from_server.gd` | ForwardedPlayerInputFromServer |
| Character base | `src/scaffolder/character/character.gd` | Character |
| Action state machine | `src/scaffolder/character/character_action_state.gd` | CharacterActionState |
| Surface detection | `src/scaffolder/character/character_surface_state.gd` | CharacterSurfaceState |
| Player spawning | `src/level/networked_level.gd` | NetworkedLevel |
| Input devices | `src/scaffolder/input/input_device_manager.gd` | InputDeviceManager |

### 14.4 Signal Reference

| Signal | Emitter | Parameters | Purpose |
|--------|---------|------------|---------|
| `peer_players_declared` | NetworkConnector | `peer_id: int, assigned_ids: Array[int]` | Server assigned player_ids to peer |
| `player_ids_received` | NetworkConnector | `assigned_ids: Array[int]` | Client received player_ids from server |
| `all_players_connected` | NetworkConnector | none | All expected players connected |
| `player_joined` | MatchState | `player_id: int` | Player joined match |
| `player_left` | MatchState | `player_id: int` | Player left match |
| `player_killed` | MatchState | `killer_id: int, killed_id: int` | Player killed another |
| `players_bumped` | MatchState | `bumper_id: int, bumped_id: int` | Player bumped another |
| `time_sync_updated` | ServerTimeTracker | none | NTP offset/RTT updated |
| `game_session_started` | GameLiftManager | `game_session: GameSession` | GameLift session started |

---

## 15. Glossary

**player_id:** Globally unique sequential integer (1, 2, 3...) assigned by server to identify a player character in gameplay logic.

**peer_id:** Godot multiplayer API's identifier for a client machine (assigned by ENet). One peer can control multiple player_ids.

**local_player_index:** Zero-based index (0, 1, 2...) identifying which player within a peer (used for input device mapping in local multiplayer).

**session_id:** AWS GameLift authentication token (UUID string) authorizing a player to join a game session. Validated by server before assigning player_id.

**frame_index (server_frame_index):** Integer frame counter (incremented every 1/60 second) serving as canonical time for networked simulation.

**rollback:** Process of rewinding game state to a past frame, correcting it with authoritative server data, and re-simulating forward to the present.

**fast-forward:** Process of skipping ahead multiple frames when client falls behind server (e.g., after packet loss).

**packed_state:** Array representation of entity state (position, velocity, etc.) for efficient replication and rollback storage.

**authority:** Which peer (server or client) is responsible for a node's state. Server-authoritative nodes use server values as ground truth; client-authoritative nodes use client values.

**NTP (Network Time Protocol):** Algorithm for synchronizing clocks between machines, accounting for network latency. This project uses a simplified NTP-like approach.

**mismatch threshold:** Maximum allowed difference between predicted and authoritative state before triggering rollback. Used to filter out insignificant floating-point variations.

**client-side prediction:** Technique where clients immediately simulate their inputs locally before server validation, providing instant feedback despite network latency.

**server reconciliation:** Process where server corrects client's predicted state if it diverges from authoritative simulation.

**MultiplayerSynchronizer:** Godot node that automatically replicates configured properties from authority peer to other peers.

**MultiplayerSpawner:** Godot node that replicates instantiation/deletion of child nodes across all peers.

**ReconcilableNetworkedState:** Base class for all networked entities implementing three-phase frame processing, rollback buffering, and mismatch detection.

**three-phase processing:** Frame processing pattern: (1) _pre_network_process (restore from buffer), (2) _network_process (simulate), (3) _post_network_process (pack to buffer).

**FrameAuthority enum:** Tracks whether a buffered state is UNKNOWN (uninitialized), AUTHORITATIVE (from server), or PREDICTED (from client).

**RollbackBuffer:** Circular buffer storing ~90 frames (1.5 seconds) of state history for rollback reconciliation.

**CircularBuffer:** Fixed-capacity buffer that wraps around when full, overwriting oldest data. Used as base for RollbackBuffer.

**ArrayPool:** Memory optimization pattern that reuses Array instances to reduce garbage collection pressure.

**back-filling:** Algorithm to fill gaps in rollback buffer when non-sequential states arrive (e.g., frames 10 → 15 with 11-14 missing).

**pause-until-ready pattern:** Server starts paused and only unpauses when all expected players connect, ensuring synchronized game start.

**preview mode:** Local testing mode (enabled with `--preview` flag) that disables GameLift validation, allowing multi-instance testing on one machine.

---

