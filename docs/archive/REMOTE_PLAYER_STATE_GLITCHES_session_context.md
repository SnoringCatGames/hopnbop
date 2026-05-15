# Session Context: Remote Player Visual State Bug

## Date: 2026-03-28

## Problem Description

When viewing a remote player on a client in local preview mode (3 instances), the remote player's **position updates correctly in real-time**, but visual state is broken:

1. **Stuck facing direction**: Remote player faces one direction even when moving the other way
2. **Jump/walk jitter**: Remote player flickers between jump-rise/jump-fall and walk animations while walking on the ground
3. In the second test session, the remote player was **always in jump-fall animation** even though they were just walking back and forth on flat ground

## Root Cause Analysis

### Architecture Overview

The character visual state system has three layers:

1. **Network State Layer** (`CharacterStateFromServer`): Syncs position, velocity, and surfaces bitmask
2. **Game Logic Layer** (`Character`, `CharacterSurfaceState`, `CharacterActionState`): Derives visual state from synced data + local simulation
3. **Rendering Layer** (`CharacterAnimator`): Applies sprite flip and animations

### What Gets Replicated

`CharacterStateFromServer` syncs these properties via MultiplayerSynchronizer:
- `position` (Vector2)
- `velocity` (Vector2)
- `surfaces` (int bitmask encoding floor/wall/ceiling contact, facing direction, etc.)
- `last_interaction_type`, `last_interaction_frame_index`, `last_interaction_position`, `last_interaction_velocity`

The `surfaces` bitmask encodes (from `CharacterSurfaceState`):
- Bits 0-3: touching floor/ceiling/left wall/right wall
- Bits 4-7: attaching to floor/ceiling/left wall/right wall
- Bit 8: facing left
- Bit 9: is launched
- Bit 10: in water

### The Bug: Local Re-simulation Overwrites Server Surfaces

For remote players on the client, the processing flow per frame is:

1. **`_pre_network_process()`**: Loads buffer[N-1] via `_unpack_buffer_state()`, then `_sync_to_scene_state()` applies `character.surfaces.bitmask = surfaces` (from buffer)
2. **`_network_process()`**:
   - Applies forwarded input (from `ForwardedPlayerInputFromServer`, which may be stale/extrapolated)
   - Calls `character._apply_movement()` which runs `move_and_slide()` + `update_touches()` + `update_actions()` -- **THIS OVERWRITES `character.surfaces.bitmask`** with local physics results
   - Calls `character._process_movement_and_actions()` which reads the (now wrong) surfaces for animation/facing
3. **`_post_network_process()`**: `_sync_from_scene_state()` reads `surfaces = character.surfaces.bitmask` (the wrong local value), then `_pack_buffer_state_from_local_state()` stores it in the buffer

The locally re-simulated surfaces diverge from the server because:
- **Forwarded input is stale/extrapolated**: `_update_horizontal_direction()` doesn't update facing correctly
- **Local collision detection differs**: Local `move_and_slide()` + `update_touches()` can produce different `is_on_floor` results than the server, causing `surface_type` to oscillate between FLOOR and AIR

Position is unaffected because it's stored as a separate Vector2, not derived from the bitmask.

### The Buffer Contamination Cycle

The wrong surfaces bitmask gets stored in the rollback buffer via `_sync_from_scene_state()` + `_pack_buffer_state_from_local_state()`. Next frame, `_pre_network_process()` loads this wrong value from buffer[N-1]. The bad data compounds frame over frame, and even when server data arrives, re-simulation overwrites it.

## Fix Attempts

### Attempt 1: Restore `self.surfaces` after `_apply_movement()` (FAILED)

**Change**: In `_network_process()`, after `_apply_movement()` for remote players, restore `character.surfaces.bitmask = surfaces` (from `self.surfaces`).

**Why it failed**: `self.surfaces` is loaded from buffer[N-1] in `_pre_network_process()`. Buffer[N-1] was stored during frame N-1's `_pack_buffer_state_from_local_state()`, which already had the wrong locally-simulated surfaces. So restoring from `self.surfaces` just propagates the same bad data.

### Attempt 2: Track `_last_server_surfaces` independently (CURRENT, UNVERIFIED)

**Changes** (all in `character_state_from_server.gd`):

1. **Added `_last_server_surfaces` variable** (line ~102): Tracks most recent server-authoritative surfaces bitmask, independent of buffer lifecycle.

2. **Added `_update_last_server_surfaces()` method** (line ~172): Called after `super._pre_network_process()`. Checks:
   - First: buffer[current_frame] for AUTHORITATIVE or SERVER_PREDICTED data (catches fresh server data during rollback re-sim before `_pack_buffer_state_from_local_state()` overwrites it)
   - Fallback: buffer[N-1] data if its frame_authority is AUTHORITATIVE or SERVER_PREDICTED

3. **Modified restore in `_network_process()`** (line ~648): Uses `_last_server_surfaces` instead of `self.surfaces`.

**Confidence level: LOW**. Key uncertainties:
- With 50-92% perceived packet loss, the buffer may rarely have AUTHORITATIVE/SERVER_PREDICTED entries at the frames being checked
- `_last_server_surfaces` might stay at 0 (initial value) if server data doesn't reach the right buffer slots
- The "always jump-fall" symptom could have a different root cause entirely (e.g., forwarded input issues, or the animation selection logic itself)
- Haven't verified how frequently `_pack_buffer_state_from_network_state()` actually stores entries vs how quickly they get overwritten

## Key Files

| File | Role |
|------|------|
| `src/scaffolder/character/character_state_from_server.gd` | Network state sync, movement re-simulation, the fix location |
| `src/scaffolder/character/character.gd` | `_apply_movement()`, `_process_movement_and_actions()`, `_process_animation()`, `_process_facing_direction()` |
| `src/scaffolder/character/character_surface_state.gd` | Surface bitmask, `update_touches()`, `update_actions()`, `_update_horizontal_direction()` |
| `src/scaffolder/character/forwarded_player_input_from_server.gd` | Forwarded/extrapolated input for remote players |
| `src/scaffolder/character/character_action_state.gd` | Action bitmask for input states |
| `src/scaffolder/character/character_animator.gd` | Sprite flip based on facing direction |
| `src/player/bunny.tscn` | MultiplayerSynchronizer replication config |
| `addons/rollback_netcode/core/reconcilable_state.gd` | Base class: buffer lifecycle, `_pre/_post_network_process`, `_pack_buffer_state_from_local_state` |

## Key Code Paths

### Animation Selection (`character.gd:608-647`)
```
_process_animation() -> match surfaces.surface_type:
    FLOOR: Walk or Rest (based on actions.pressed_left/right)
    AIR: JumpFall or JumpRise (based on velocity.y)
    WALL: ClimbUp/ClimbDown/RestOnWall
    CEILING: CrawlOnCeiling/RestOnCeiling
```

### Facing Direction (`character_surface_state.gd:601-613`)
```
_update_horizontal_direction():
    if attaching to wall: face toward wall
    elif pressed_face_right: face right
    elif pressed_face_left: face left
    elif pressed_right: face right
    elif pressed_left: face left
    (else: no change -- keeps previous direction)
```

### Remote Player Input Source (`character_state_from_server.gd:281-289`)
```
is_remote_player_on_client = not is_authority_for_state_from_server and not is_authority_for_input_from_client
if is_remote_player_on_client:
    input_source = forwarded_input_from_server  # server-predicted/extrapolated
else:
    input_source = input_from_client  # real local input
```

### Buffer Lifecycle (per frame)
```
_pre_network_process():
    _unpack_buffer_state(N-1)         # Load previous frame from buffer into self.properties
    _sync_to_scene_state()            # Apply to character scene nodes

_network_process():
    [input handling + movement simulation]

_post_network_process():
    _sync_from_scene_state()          # Read character scene state back into self.properties
    _pack_buffer_state_from_local_state()  # Store in buffer[N] (ALWAYS runs, even during resim)
```

### Server Data Arrival
```
MultiplayerSynchronizer -> authoritative_packed_state setter
    -> _handle_new_state_from_network()
        -> _pack_buffer_state_from_network_state()  # Store in buffer
        -> _unpack_networked_state()                 # Update local properties (if current/future frame)
        -> [may trigger rollback if mismatch detected]
```

## Suggested Next Steps

1. **Add debug logging** to verify whether `_last_server_surfaces` is actually getting updated with server data. Log:
   - `_last_server_surfaces` value and source (current frame buffer vs N-1 fallback vs unchanged)
   - `frame_authority` values seen in the buffer
   - `character.surfaces.bitmask` before and after restore
   - `surfaces.surface_type` used by `_process_animation()`

2. **Consider alternative approaches** if the buffer-based approach doesn't work:
   - Override `_unpack_networked_state()` in `CharacterStateFromServer` to capture server surfaces directly when network state arrives (bypasses buffer entirely)
   - Skip `_apply_movement()` entirely for remote players and just use server position directly (sacrifices smooth interpolation between server updates)
   - Don't run `update_touches()` / `update_actions()` inside `_apply_movement()` for remote players (would require refactoring `_apply_movement()`)

3. **Investigate the "always jump-fall" symptom more deeply**:
   - Is `_last_server_surfaces` staying at 0 (initial value = AIR)?
   - Are there frames where it gets updated but then reverts?
   - Is the server actually sending correct surfaces in the packed state?

## Test Logs

Two test sessions were run (logs in `DO_NOT_SUBMIT_desktop_client_logs.txt`):

### Session 1 (pre-fix)
- 3 players across 2 clients (C1 with 2 players, C2 with 1 player)
- C1 PERF: PING 22-60ms, LOSS 30-49%, RB/s 6-29
- C2 PERF: PING 22-31ms, LOSS 29-53%, RB/s 0.7-9.2, frequent fast-forwards
- Symptoms: stuck facing direction, jump-state jitter

### Session 2 (after attempt 1 fix)
- 4 players across 2 clients (C1 with 2 players, C2 with 2 players)
- C1 (peer 2056928929) PERF: PING 18-43ms, LOSS 29-80%, RB/s 0.5-15.3
- C2 (peer 1886840528) PERF: PING 29-124ms, LOSS 0-92%, frequent fast-forwards
- Symptoms: remote player ALWAYS in jump-fall animation while walking on ground
- Note: this is WORSE than session 1, consistent with the analysis that attempt 1 froze surfaces at the initial value (0 = AIR)
