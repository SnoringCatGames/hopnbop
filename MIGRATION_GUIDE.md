# Jump 'n Thump → Rollback Netcode Plugin Migration Guide

## Overview

This guide documents the migration of Jump 'n Thump from the embedded networking code to the reusable rollback netcode plugin.

## Phase 1: Adapter Classes (COMPLETE)

Created three adapter classes in `src/adapters/`:

1. **GNetworkConfig** - Bridges `G.settings` → `NetworkConfig`
2. **GNetworkLogger** - Bridges `ScaffolderLog` → `NetworkLogger`
3. **GNetworkTime** - Bridges `ScaffolderTime` → `NetworkTime`

## Phase 2: G Singleton Update (IN PROGRESS)

### Changes to `src/core/global.gd`:

**Before:**
```gdscript
var network := NetworkMain.new()
```

**After:**
```gdscript
# Create adapters.
var _network_config_adapter: GNetworkConfig
var _network_logger_adapter: GNetworkLogger
var _network_time_adapter: GNetworkTime

# NetworkOrchestrator (replaces NetworkMain).
var network: NetworkOrchestrator

func _enter_tree() -> void:
	# ... existing code ...
	
	# Initialize adapters.
	_network_config_adapter = GNetworkConfig.new(settings)
	_network_logger_adapter = GNetworkLogger.new(log)
	_network_time_adapter = GNetworkTime.new(time)
	
	# Initialize NetworkOrchestrator with adapters.
	network = NetworkOrchestrator.new(
		_network_config_adapter,
		_network_logger_adapter,
		_network_time_adapter
	)
	network.name = "Network"
	add_child(network)
```

## Phase 3: Global Find/Replace (PENDING)

Replace all references to old NetworkMain properties with NetworkOrchestrator:

| Old Pattern | New Pattern | Count |
|-------------|-------------|-------|
| `G.network.frame_driver` | `G.network.frame_driver` | No change |
| `G.network.connector` | `G.network.connector` | No change |
| `G.network.frame_sync` | `G.network.frame_sync` | No change |
| `G.network.perf_tracker` | `G.network.perf_tracker` | No change |

Most properties remain the same! The NetworkOrchestrator API is designed to be compatible.

## Phase 4: State Management Extensions (PENDING)

### Extend MatchManager
Create `src/core/jump_n_thump_match_state.gd`:
```gdscript
class_name JumpNThumpMatchState
extends MatchManager

signal player_killed(killer: PlayerMatchState, killee: PlayerMatchState)
signal players_bumped(a: PlayerMatchState, b: PlayerMatchState)

const _KILL_SCORE := 100
const _DEATH_PENALTY := 90
const _BUMP_SCORE := 5

var kills: PackedInt32Array = []
var bumps: PackedInt32Array = []

# ... implement game-specific logic ...
```

### Extend ClientSession
Update `src/core/local_session.gd` to extend `ClientSession` instead of being standalone.

### Extend PlayerState  
Update `src/core/player_match_state.gd` to extend `PlayerState` from plugin.

## Phase 5: Delete Old Networking (PENDING)

After validation, delete obsolete files:
- `src/networking/network_main.gd`
- `src/networking/network_frame_driver.gd`
- `src/networking/network_connector.gd`
- `src/networking/frame_index_synchronizer.gd`
- `src/networking/reconcilable_network_state.gd`
- ... (keep GameLift files in modules/)

## Phase 6: Testing (PENDING)

1. Run all 90+ unit tests
2. Test 3-player preview mode
3. Verify multiplayer gameplay
4. Performance validation

## Status

- [x] Phase 1: Adapter Classes
- [ ] Phase 2: G Singleton Update
- [ ] Phase 3: Find/Replace
- [ ] Phase 4: State Management
- [ ] Phase 5: Delete Old Files
- [ ] Phase 6: Testing
