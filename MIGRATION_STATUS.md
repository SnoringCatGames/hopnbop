# Jump 'n Thump Migration Status

# FIXME: REMOVE

## ✅ Completed

1. **Plugin Development** (Weeks 1-8)
   - All core components refactored
   - State management abstractions created
   - Performance utilities implemented
   - Complete documentation (README, QUICKSTART, ARCHITECTURE, API_REFERENCE)
   - Working example (simple_game)

2. **Adapter Classes Created** (`src/adapters/`)
   - GNetworkConfig - Bridges G.settings → NetworkConfig
   - GNetworkLogger - Bridges ScaffolderLog → NetworkLogger
   - GNetworkTime - Bridges ScaffolderTime → NetworkTime

3. **G Singleton Updated** (`src/core/global.gd`)
   - Replaced NetworkMain with NetworkOrchestrator
   - Initialize adapters in `_enter_tree()`

4. **Configuration**
   - Added `includes_verbose_logs` to NetworkConfig
   - Added `is_verbose` flag to NetworkLogger
   - Enabled rollback_netcode plugin in project.godot

5. **File Cleanup**
   - Renamed `src/networking` → `src/networking_OLD` (temporarily)
   - Replaced `NetworkFrameDriver` → `FrameDriver` globally

## 🔧 In Progress - Critical Compilation Errors

### Error Category 1: Missing `class_name` in Adapters
**Files:** `src/adapters/*.gd`
**Fix Needed:** Add `class_name` declarations so Godot can find them globally

### Error Category 2: Old Class References
**Pattern:** `ReconcilableNetworkedState` → `ReconcilableState`
**Files Affected:**
- src/scaffolder/character/character_state_from_server.gd
- src/player/player_annotations.gd
- Many other files

### Error Category 3: Old Networking Classes
**Pattern:** Files trying to extend classes that no longer exist
- `PlayerInputNetworkState` - needs replacement
- `NetworkConnector` - exists in plugin but not found (might need preload)
- `RollbackBuffer` - exists in plugin but not found (might need preload)

### Error Category 4: Character System Dependencies
**Issue:** Character system (Player, CharacterStateFromServer, etc.) depends on old networking
**Files Affected:**
- src/scaffolder/character/*.gd
- src/player/*.gd

## 📋 Remaining Tasks

### Immediate (Critical Path)
1. Add `class_name` to adapter classes
2. Global find/replace: `ReconcilableNetworkedState` → `ReconcilableState`
3. Fix `PlayerInputNetworkState` references
4. Fix `CharacterStateFromServer` to extend `ReconcilableState`

### Post-Compilation (Integration)
5. Extend MatchManager for JumpNThumpMatchState
6. Extend ClientSession for LocalSession
7. Extend PlayerState for BunnyPlayerState
8. Delete/archive old networking files permanently

### Final (Testing)
9. Run full test suite (90+ tests)
10. Test 3-player preview mode
11. Verify multiplayer gameplay

## 🎯 Next Action

**Recommended:** Fix compilation errors in order:
1. Add `class_name` to adapters (quick fix)
2. Update class references globally (find/replace)
3. Fix character system dependencies (most complex)
4. Run tests iteratively to identify remaining issues

**Estimated Remaining Work:** 2-4 hours of systematic fixes + testing
