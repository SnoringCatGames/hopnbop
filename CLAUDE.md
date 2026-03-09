# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hop 'n Bop is a multiplayer action game built with Godot 4.5. It implements client-side prediction with rollback reconciliation for networked gameplay.

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
- **NetworkFrameDriver** - Core frame simulation at 60 FPS. Increments
  `server_frame_index` directly on each physics tick for deterministic frame
  progression. Manages rollback buffer and reconciliation.
- **ReconcilableNetworkedState** - Base class for all networked entities;
  implements client prediction + server authoritative reconciliation
- **ServerTimeTracker** - NTP-like clock sync between client and server. Server
  frame timing is based on physics ticks, with periodic wall-clock re-sync for
  accurate logging.
- **NetworkConnector** - ENet peer management (default port 4433)

**Frame Processing Flow:**
1. `_pre_network_process()` - Sync scene state from rollback buffer
2. `_network_process()` - Game logic executes (frame-synchronous)
3. `_post_network_process()` - Pack state for replication

All networked entities must extend ReconcilableNetworkedState and participate in this cycle.

### Game State (src/core/)

- **MatchState/MatchStateSynchronizer** - Replicated match data (players, kills, bumps)
- **PlayerState** - Per-player metadata (name, connection status)
- **GamePanel** - Game lifecycle orchestrator, handles level spawning
- **ClientSession** - Per-client session state

#### Signal Architecture

**MatchState is the single source of truth for all match events:**
- Low-level state change signals: `players_updated`, `kills_updated`, `bumps_updated`
- High-level game event signals: `player_joined`, `player_left`, `player_killed`, `players_bumped`
- MatchStateSynchronizer acts as a replication coordinator that triggers these signals
- All external code should connect to `G.match_state` signals for match events

#### Local Mode (Offline/Local-Only)

The game supports an offline local-only mode where the same
process acts as both server and client. The process stays
`is_server = false` (so client UI continues working) but sets
`Netcode.is_local_mode = true`. The property
`Netcode.runs_server_logic` (`is_server or is_local_mode`)
replaces `is_server` checks where server-side game logic must
also run locally.

**Local Mode RPC Pattern:** When adding server-to-client RPCs
(`call_remote`), also add a direct local call gated by
`Netcode.is_local_mode`. RPCs with `call_remote` do not reach
the local process in offline mode.

```gdscript
_client_rpc_foo.rpc(args)
if Netcode.is_local_mode:
    _client_rpc_foo(args)
```

This pattern keeps `@rpc` annotations unchanged and makes the
local-mode path explicit. Not all RPCs need this treatment.
Only server-to-client RPCs where the client needs to receive
the call (e.g., match ended, unpause, stats). Server-side
functions that already apply state locally before sending the
RPC (e.g., snail crush/respawn) do not need it.

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

Follow the
[Godot GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
with the project-specific additions below.

### Formatting

- **Indentation:** Tabs (4-space width), enforced by
  `.editorconfig`.
- **Line length:** 80 characters maximum.
- **Blank lines:** Two blank lines between functions/methods.
- **Line wrapping:** Prefer parentheses over backslashes for
  line continuation. Conversely, unwrap lines onto a single
  line when they fit within the 80-character limit.
- **Operator placement:** When wrapping expressions across
  multiple lines, place operators at the start of the next
  line, not the end of the previous line.
- **Trailing commas:** Include trailing commas in multi-line
  function calls, arrays, and dictionaries.

```gdscript
# Correct: parens for wrapping, operator at start of line.
var is_valid := (
	is_instance_valid(node)
	and node.is_inside_tree()
	and not node.is_queued_for_deletion()
)

# Correct: trailing comma in multi-line call.
some_function(
	first_arg,
	second_arg,
)

# Wrong: backslash continuation.
var is_valid := is_instance_valid(node) \
	and node.is_inside_tree()

# Wrong: operator at end of line.
var is_valid := (
	is_instance_valid(node) and
	node.is_inside_tree()
)
```

### Naming Conventions

- **Classes/enums:** `PascalCase`
- **Functions/variables:** `snake_case`
- **Constants:** `UPPER_SNAKE_CASE`
- **Private members:** Prefix with underscore (`_my_var`,
  `_my_method`)
- **Signals:** Past tense (`player_died`, `match_started`)
- **Booleans:** Prefix with `is_`, `can_`, `has_`
- **No prefixes:** Avoid prefixes in variable names (e.g.,
  use `speed` not `player_speed` when already inside a player
  class). The underscore prefix for private members is the
  exception.

### Type Annotations

- Use `:=` for inferred types on variable declarations.
- Always specify return types on functions.
- Use explicit type hints for `@export` vars and function
  parameters.

```gdscript
var speed := 10.0
const _MAX_SPEED := 200.0
@export var jump_height: float = 64.0

func get_speed() -> float:
	return speed
```

### Negation

- Prefer `not` over `!` for boolean negation.
- Do use `!=` for inequality comparisons.

```gdscript
# Correct.
if not is_alive:
	return
if count != 0:
	process()

# Wrong.
if !is_alive:
	return
```

### Comments and Prose

- End all comments with a period.
- Use `##` for doc comments (Godot documentation comments),
  `#` for regular comments.
- Never use em dashes, en dashes, or hyphens as grammatical
  em dashes. Use a period and start a new sentence instead.
- Wrap comments at 80 characters, matching the code line
  limit.

```gdscript
## Advances the snail by the given number of
## network frames. Each frame applies a fixed
## movement step.
func _simulate_frames(count: int) -> void:

# Wrong: em dash in comment.
# The snail moves forward — unless blocked.

# Correct: period and new sentence.
# The snail moves forward. It stops when blocked.
```

### File Structure

Follow the Godot-recommended ordering within each script:

1. `@tool`
2. `class_name`
3. `extends`
4. Doc comment (`##`)
5. `signal` declarations
6. `enum` declarations
7. `const` declarations
8. `@export` variables
9. Public variables
10. Private variables (`_`-prefixed)
11. `@onready` variables
12. `_init()`, `_enter_tree()`, `_exit_tree()`, `_ready()`
13. `_process()`, `_physics_process()`
14. Other virtual/callback methods
15. Public methods
16. Private methods

### Constants Over Inline Values

Use file-level `const` declarations instead of hard-coding
static values inline in functions. Private constants use
underscore prefix.

```gdscript
# Correct: file-level constant.
const _RESPAWN_DELAY_FRAMES := 30

func _respawn() -> void:
	timer = _RESPAWN_DELAY_FRAMES

# Wrong: magic number inline.
func _respawn() -> void:
	timer = 30
```

### Scene Templates Over Scripts

Prefer configuring state in `.tscn` scene files rather than
in scripts:

- **Animations:** Configure `AnimatedSprite2D.sprite_frames`
  animations in the scene editor, not in code.
- **Resource references:** Use `@export` vars and assign
  resources in the scene inspector rather than hard-coding
  `preload()` paths in scripts.
- **Node references:** Use `%NodeName` unique-name syntax in
  scenes when referencing sibling/child nodes.

```gdscript
# Preferred: export var assigned in scene inspector.
@export var death_effect: PackedScene

# Acceptable when scene assignment is impractical.
const _DEATH_EFFECT := preload(
	"res://src/effects/death_effect.tscn"
)
```

### Direct Access Over Local Copies

Do not assign local or class-level variable copies of
autoload properties (`G`, `Netcode`) or unique-name nodes
(`%`). Access them directly where needed.

```gdscript
# Correct: access autoload properties directly.
if G.match_state.is_match_active:
	Netcode.server_frame_index += 1

# Wrong: local copy of autoload property.
var match_state := G.match_state
if match_state.is_match_active:
	pass

# Correct: access unique-name node directly.
%AnimatedSprite2D.play("idle")

# Wrong: local or class-level copy.
@onready var sprite := %AnimatedSprite2D
```

### Performance

- Prefer `distance_squared_to()` over `distance_to()` when
  feasible, to avoid unnecessary `sqrt` calculations.

### GDScript Formatter

The GDScript formatter addon is installed
(`addons/gdscript_formatter`). Format code before committing.

## Testing with GUT

This project uses GUT (Godot Unit Test) 9.x for testing. Tests are organized
in `res://test/` with separate directories for unit and integration tests.

### Test File Structure

- Files must start with `test_` prefix (e.g., `test_rollback_buffer.gd`)
- Extend `GutTest` base class
- Use `func test_*()` naming for test methods
- Configuration in `res://.gutconfig.json`

### Common Assertions

```gdscript
# Equality
assert_eq(actual, expected, "optional message")
assert_ne(actual, expected)

# Null checks
assert_null(value)
assert_not_null(value)

# Boolean
assert_true(condition, "message")
assert_false(condition)

# Numeric comparisons
assert_gt(value, threshold)  # greater than
assert_lt(value, threshold)  # less than
assert_almost_eq(actual, expected, tolerance)

# Godot types
assert_almost_eq(vector1, vector2, tolerance)
assert_has(array_or_dict, value)
assert_does_not_have(array_or_dict, value)

# Signals
watch_signals(object)
assert_signal_emitted(object, "signal_name")
assert_signal_not_emitted(object, "signal_name")
```

### Test Lifecycle Methods

```gdscript
extends GutTest

# Run once before any tests in this script
func before_all():
	pass

# Run before each test
func before_each():
	pass

# Run after each test
func after_each():
	pass

# Run once after all tests
func after_all():
	pass
```

### Test Doubles (Mocking)

**Creating Doubles:**
```gdscript
# Double a script
var MyClass = preload("res://src/my_class.gd")
var DoubledClass = double(MyClass)
var instance = DoubledClass.new()

# Double a scene
var MyScene = load("res://scenes/my_scene.tscn")
var DoubledScene = double(MyScene)
var instance = DoubledScene.instantiate()
```

**Stubbing Methods:**
```gdscript
# Return a specific value
stub(instance, 'method_name').to_return(42)

# Call original implementation
stub(instance, 'method_name').to_call_super()

# Stub with parameters
stub(instance, 'method_name').param_count(2).to_return(value)
```

**Spies (Verifying Calls):**
```gdscript
# Check if method was called
assert_called(instance, 'method_name')
assert_not_called(instance, 'method_name')

# Check call count
assert_call_count(instance, 'method_name', 3)

# Check parameters
assert_called_with(instance, 'method_name', [arg1, arg2])
```

**Important Notes:**
- Inner classes need `register_inner_classes(ClassName)` before doubling
- Doubles are freed automatically after each test
- Don't create doubles in `before_all()` - use `before_each()`
- Use `partial_double()` to keep some original functionality

### Parameterized Tests

Run the same test with different inputs:

```gdscript
var test_cases = [
    [0, 0],        # input, expected
    [5, 25],
    [-3, 9],
]

func test_square(params=use_parameters(test_cases)):
    var input = params[0]
    var expected = params[1]
    assert_eq(square(input), expected)
```

**Named Parameters (more readable):**
```gdscript
var test_cases = ParameterFactory.named_parameters(
	['input', 'expected'],
    [
        [0, 0],
        [5, 25],
    ]
)

func test_square(p=use_parameters(test_cases)):
    assert_eq(square(p.input), p.expected)
```

### Inner Test Classes

Organize related tests with shared setup:

```gdscript
extends GutTest

class TestWhenEmpty:
    extends GutTest

    var buffer

    func before_each():
        buffer = Buffer.new()

    func test_size_is_zero():
        assert_eq(buffer.size(), 0)

    func test_pop_returns_null():
        assert_null(buffer.pop())

class TestWhenFull:
    extends GutTest

    var buffer

    func before_each():
        buffer = Buffer.new(capacity=3)
        buffer.push(1)
        buffer.push(2)
        buffer.push(3)

    func test_size_is_capacity():
        assert_eq(buffer.size(), 3)
```

### Async Testing

For testing signals and coroutines:

```gdscript
func test_async_operation():
    var obj = MyClass.new()
    add_child_autofree(obj)

    watch_signals(obj)
    obj.start_async_operation()

    # Wait for signal
    await wait_for_signal(obj.completed, 2.0)  # 2 second timeout

    assert_signal_emitted(obj, "completed")

func test_with_frames():
    var obj = MyClass.new()
    add_child_autofree(obj)

    obj.start()

    # Wait for next frame
    await wait_frames(1)

    assert_true(obj.is_running)
```

### Scene Testing

```gdscript
func test_scene_interaction():
    var scene = load(
        "res://test/fixtures/test_scene.tscn"
    ).instantiate()
    add_child_autofree(scene)

    # Scene is now in tree and can be tested
    var button = scene.get_node("Button")
    button.pressed.emit()

    # Cleanup happens automatically via autofree
```

### Common Patterns for This Project

**Testing Networking Code:**
```gdscript
# Mock NetworkMain
var MockNetworkMain = double(NetworkMain)
stub(MockNetworkMain, 'is_server').to_return(true)
stub(MockNetworkMain, 'get_current_tick').to_return(100)

# Mock multiplayer API
var MockMultiplayer = double(MultiplayerAPI)
stub(MockMultiplayer, 'get_unique_id').to_return(1)
```

**Testing Rollback Logic:**
```gdscript
# Create fixture states
var state_frame_10 = {"x": 100, "y": 200}
var state_frame_20 = {"x": 150, "y": 250}

buffer.store_state(10, state_frame_10)
buffer.store_state(20, state_frame_20)

# Test rollback
var retrieved = buffer.get_state(10)
assert_eq(retrieved.x, state_frame_10.x)
```

**Testing Character Actions:**
```gdscript
# Create test character with mocked dependencies
var character = partial_double(Character)
character.velocity = Vector2.ZERO
character.surface_state = create_floor_surface_state()

# Test action handler
var action = FloorWalkAction.new()
action.process(character, delta, instructions)

assert_gt(character.velocity.x, 0, "Should move right")
```

### Running Tests

**Editor:**
- Open GUT panel (bottom dock)
- Select test file or directory
- Click "Run All" or specific test

**Command Line:**
```bash
# Run all tests
godot --headless -s --path . addons/gut/gut_cmdln.gd -gexit

# Run unit tests only
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gdir=res://test/unit -gexit

# Run specific test
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gtest=res://test/unit/networking/test_rollback_buffer.gd -gexit

# Export results
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gexit -gjunit_xml_file=results.xml
```

**Exit codes:** 0 = success, 1 = failures

### Best Practices

1. **One concept per test** - Test one behavior in each test method
2. **Descriptive names** -
   `test_rollback_triggers_on_mismatch_above_threshold` not
   `test_rollback`
3. **AAA pattern** - Arrange (setup), Act (execute), Assert (verify)
4. **Use fixtures** - Create reusable test data in `before_each`
5. **Mock external dependencies** - Don't rely on file I/O, network, etc.
6. **Test edge cases** - Empty, null, boundary values, error conditions
7. **Keep tests fast** - Unit tests should run in milliseconds
8. **Deterministic tests** - No randomness, no timing dependencies
   (in unit tests)
9. **Clean up** - Use `add_child_autofree()` for nodes, GUT handles
   the rest

### Common Pitfalls

- **Forgetting to extend GutTest** - Tests won't be discovered
- **Missing `test_` prefix** - Method won't run as a test
- **Creating doubles in before_all()** - Use before_each() instead
- **Not registering inner classes** - Call `register_inner_classes()`
  first
- **Assuming execution order** - Tests can run in any order
- **Testing implementation details** - Test behavior, not internals
- **Integration tests in unit test dir** - Keep them separated

### Project-Specific Testing Notes

**Running Tests Successfully:**
- Run specific test files rather than directories for reliability:
  ```bash
  godot --headless -s --path . addons/gut/gut_cmdln.gd \
	-gtest=res://test/unit/scaffolder/test_circular_buffer.gd -gexit
  ```
- Directory-based runs (`-gdir=res://test/unit`) sometimes fail to
  discover tests
- Always use `-gexit` flag for CI/CD to get proper exit codes

**Critical Test Setup Patterns:**
- **ArrayPool management is mandatory** - Every test that uses ArrayPool
  (directly or indirectly through CircularBuffer/RollbackBuffer) MUST call
  `ArrayPool.clear_all_pools()` in both `before_each()` and `after_each()`
- **Type hints for Arrays** - GDScript tests require explicit type hints
  when retrieving arrays:
  ```gdscript
  var state: Array = buffer.get_at(5)  # Correct
  var state = buffer.get_at(5)         # May fail type checking
  ```

**Testing Networking Components:**
- The `G` singleton (Global) is auto-loaded and initializes networking
  subsystems
- Tests run with full autoload context - NetworkMain, NetworkFrameDriver,
  etc. are active
- Frame-based simulation uses `NetworkFrameDriver.TARGET_NETWORK_TIME_STEP_SEC`
  (1/60 = 0.01666... seconds)
- Use `ReconcilableNetworkedState.FrameAuthority` enum values (UNKNOWN=0,
  AUTHORITATIVE=1, PREDICTED=2)

**Accessing Internal State:**
- Avoid accessing private members like `buffer._data[i]` in tests when
  possible
- Use public API methods (`get_at()`, `set_at()`) for better encapsulation
- If internal access is necessary, understand it couples tests to
  implementation

**Known Test Failures:**
- A few tests check array instance equality which fails due to GDScript's
  array semantics
- Some tests access RollbackBuffer internal state for validation - these
  may break if implementation changes
- Type coercion in assertions: use explicit types to avoid GDScript type
  inference issues

**Test Coverage:**
- Unit tests: CircularBuffer (47 tests), ArrayPool (13 tests),
  RollbackBuffer (20 tests), ServerTimeTracker (12 tests)
- Integration tests: Rollback flow (10 tests), state synchronization
  (10+ tests), frame timing (14+ tests)
- Total: 90+ tests covering core networking infrastructure

## References

Networking concepts and patterns:
- [Gabriel Gambetta's Client-Side Prediction and Server Reconciliation](https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html) - Definitive explanation of prediction/reconciliation
- [Godot High-Level Multiplayer Docs](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html) - Official Godot networking documentation
- [Godot Scene Replication (4.0)](https://godotengine.org/article/multiplayer-in-godot-4-0-scene-replication/) - MultiplayerSynchronizer/Spawner introduction

Godot networking addons (for reference, not used in this project):
- [Netfox](https://forum.godotengine.org/t/netfox-addons-for-online-multiplayer-games/36066) - Client-side prediction and server reconciliation addon
- [MonkeNet](https://github.com/grazianobolla/godot-monke-net) - C# addon with prediction, interpolation, lag compensation
