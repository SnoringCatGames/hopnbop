---
paths:
  - "test/**"
  - "addons/gut/**"
---

# Testing lore (GUT)

The full GUT reference, moved verbatim from CLAUDE.md by H34
(2026-10-13). CLAUDE.md keeps how to run the suite and the
engine-lockstep rule.

Tests are organized in `res://test/` with separate directories for
unit and integration tests.

**GUT is version-matched to the engine — keep them in lockstep.**
GUT ships a release per Godot minor (9.5.0 → 4.5, 9.6.0 → 4.6,
9.7.x → 4.7), and a mismatch does not fail loudly. On 4.7.1 with
GUT 9.5.0, `gut_loader.gd`'s `_static_init` dies assigning a Nil
`ProjectSettings.get(...)` to a typed bool, GUT reports "Nothing
was run", **and still exits 0** — so `pr-validate`'s per-file loop
goes green having executed zero tests. Vendored at `addons/gut/`
(not a submodule); currently **9.7.1** for Godot 4.7.2. When you
bump the engine, bump GUT in the same change and confirm a real
test count, not just a zero exit code.

After swapping the addon, delete `.godot/global_script_class_cache.cfg`
and re-import. A stale cache surfaces as `Parse Error: Identifier
"GutConstants" not declared` — see `docs/web-parse-errors.md` for
the same failure class.

## Test file structure

- Files must start with `test_` prefix (e.g. `test_rollback_buffer.gd`)
- Extend `GutTest` base class
- Use `func test_*()` naming for test methods
- No `.gutconfig.json` exists in this repo; CI and local runs pass
  flags explicitly on the command line.

## Common assertions

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

## Test lifecycle methods

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

## Test doubles (mocking)

**Creating doubles:**
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

**Stubbing methods:**
```gdscript
# Return a specific value
stub(instance, 'method_name').to_return(42)

# Call original implementation
stub(instance, 'method_name').to_call_super()

# Stub with parameters
stub(instance, 'method_name').param_count(2).to_return(value)
```

**Spies (verifying calls):**
```gdscript
# Check if method was called
assert_called(instance, 'method_name')
assert_not_called(instance, 'method_name')

# Check call count
assert_call_count(instance, 'method_name', 3)

# Check parameters
assert_called_with(instance, 'method_name', [arg1, arg2])
```

**Important notes:**
- Inner classes need `register_inner_classes(ClassName)` before doubling
- Doubles are freed automatically after each test
- Don't create doubles in `before_all()` - use `before_each()`
- Use `partial_double()` to keep some original functionality

## Parameterized tests

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

**Named parameters (more readable):**
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

## Inner test classes

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

## Async testing

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

## Scene testing

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

## Common patterns for this project

**Testing networking code:**
```gdscript
# Mock NetworkMain
var MockNetworkMain = double(NetworkMain)
stub(MockNetworkMain, 'is_server').to_return(true)
stub(MockNetworkMain, 'get_current_tick').to_return(100)

# Mock multiplayer API
var MockMultiplayer = double(MultiplayerAPI)
stub(MockMultiplayer, 'get_unique_id').to_return(1)
```

**Testing rollback logic:**
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

**Testing character actions:**
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

## Running tests

**Editor:**
- Open GUT panel (bottom dock)
- Select test file or directory
- Click "Run All" or specific test

**Command line:**
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

## Best practices

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

## Common pitfalls

- **Forgetting to extend GutTest** - Tests won't be discovered
- **Missing `test_` prefix** - Method won't run as a test
- **Creating doubles in before_all()** - Use before_each() instead
- **Not registering inner classes** - Call `register_inner_classes()`
  first
- **Assuming execution order** - Tests can run in any order
- **Testing implementation details** - Test behavior, not internals
- **Integration tests in unit test dir** - Keep them separated

## Project-specific testing notes

**Running tests successfully:**
- Run specific test files rather than directories for reliability:
  ```bash
  godot --headless -s --path . addons/gut/gut_cmdln.gd \
	-gtest=res://test/unit/core/test_match_state_get_player_score.gd -gexit
  ```
  (The old example here pointed at
  `res://test/unit/scaffolder/test_circular_buffer.gd`, which moved
  into the `rollback_netcode` submodule when the netcode was
  extracted. A `-gtest=` path that doesn't exist reports "Could not
  find script" and still exits 0.)
- Directory-based runs (`-gdir=res://test/unit`) sometimes fail to
  discover tests
- Always use `-gexit` flag for CI/CD to get proper exit codes
- **Don't await GUT's `wait_seconds`.** The scene tree is paused
  during GUT runs here, so GUT's awaiter never ticks and the test
  hangs until the process is killed. Await
  `get_tree().create_timer(sec).timeout`, which runs while
  paused, or `get_tree().process_frame` instead.

**Critical test setup patterns:**
- **ArrayPool management is mandatory** - Every test that uses ArrayPool
  (directly or indirectly through CircularBuffer/RollbackBuffer) MUST call
  `ArrayPool.clear_all_pools()` in both `before_each()` and `after_each()`
- **Type hints for Arrays** - GDScript tests require explicit type hints
  when retrieving arrays:
  ```gdscript
  var state: Array = buffer.get_at(5)  # Correct
  var state = buffer.get_at(5)         # May fail type checking
  ```

**Testing networking components:**
- The `G` singleton (Global) is auto-loaded and initializes networking
  subsystems
- Tests run with full autoload context - NetworkMain, NetworkFrameDriver,
  etc. are active
- Frame-based simulation uses `NetworkFrameDriver.TARGET_NETWORK_TIME_STEP_SEC`
  (1/60 = 0.01666... seconds)
- Use `ReconcilableNetworkedState.FrameAuthority` enum values (UNKNOWN=0,
  AUTHORITATIVE=1, PREDICTED=2)

**Accessing internal state:**
- Avoid accessing private members like `buffer._data[i]` in tests when
  possible
- Use public API methods (`get_at()`, `set_at()`) for better encapsulation
- If internal access is necessary, understand it couples tests to
  implementation

**Known test failures:**
- A few tests check array instance equality which fails due to GDScript's
  array semantics
- Some tests access RollbackBuffer internal state for validation - these
  may break if implementation changes
- Type coercion in assertions: use explicit types to avoid GDScript type
  inference issues
- `test_party_matchmaking_context.gd` fails 7/11 under a full
  `-gdir=res://test/unit -ginclude_subdirs` run but passes alone:
  state bleed from earlier scripts, not a product bug (H35).

**Test coverage:**
- Unit tests: CircularBuffer (47 tests), ArrayPool (13 tests),
  RollbackBuffer (20 tests), ServerTimeTracker (12 tests)
- Integration tests: Rollback flow (10 tests), state synchronization
  (10+ tests), frame timing (14+ tests)
- Total: 90+ tests covering core networking infrastructure
