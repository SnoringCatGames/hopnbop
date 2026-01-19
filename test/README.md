# Jump 'n Thump Test Suite

This directory contains unit and integration tests for the Jump 'n Thump
multiplayer game, using the GUT (Godot Unit Test) framework.

## Directory Structure

```
test/
├── unit/                    # Fast, isolated unit tests
│   ├── networking/         # Networking logic tests
│   ├── scaffolder/         # Utility and framework tests
│   ├── character/          # Character system tests
│   └── core/               # Core game state tests
├── integration/            # Slower, multi-component tests
│   ├── gameplay/           # Full gameplay scenarios
│   └── multiplayer/        # Networked multiplayer tests
└── helpers/                # Test helper classes and utilities
```

## Running Tests

### In Godot Editor

1. Open the project in Godot Editor
2. Open the GUT panel (bottom dock)
3. Select the test directory or specific test file
4. Click "Run All" or select a specific test to run
5. View results in the panel output

### Command Line

Run all tests:
```bash
godot --headless -s --path . addons/gut/gut_cmdln.gd -gexit
```

Run only unit tests:
```bash
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gdir=res://test/unit -gexit
```

Run only integration tests:
```bash
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gdir=res://test/integration -gexit
```

Run specific integration test suite:
```bash
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gtest=res://test/integration/multiplayer/test_rollback_flow.gd \
  -gexit
```

Run specific test file:
```bash
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gtest=res://test/unit/scaffolder/test_circular_buffer.gd -gexit
```

Export results to JUnit XML:
```bash
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gexit -gjunit_xml_file=test_results.xml
```

### Exit Codes

- `0` = All tests passed
- `1` = One or more tests failed

## Writing Tests

### Test File Naming

- Test files must start with `test_` prefix
- Example: `test_circular_buffer.gd`

### Basic Test Structure

```gdscript
extends GutTest

func before_each():
    # Setup code that runs before each test
    pass

func after_each():
    # Cleanup code that runs after each test
    pass

func test_something_happens():
    # Arrange
    var buffer = CircularBuffer.new(5)

    # Act
    buffer.append("value")

    # Assert
    assert_eq(buffer.size(), 1)
```

### Inner Test Classes

Organize related tests with shared setup:

```gdscript
extends GutTest

class TestWhenEmpty:
    extends GutTest

    var buffer: CircularBuffer

    func before_each():
        buffer = CircularBuffer.new(5)

    func test_size_is_zero():
        assert_eq(buffer.size(), 0)
```

## Test Coverage

### Current Coverage

**Unit Tests:**
- ✅ CircularBuffer - Comprehensive coverage of all methods
- ✅ ArrayPool - Pool management and reuse logic
- ✅ RollbackBuffer - Frame storage and backfill logic
- ✅ ServerTimeTracker - Time offset calculation and sample management

**Integration Tests:**
- ✅ Rollback Flow - Frame simulation, wraparound, large gaps, ArrayPool
  efficiency
- ✅ State Synchronization - Client prediction, server reconciliation,
  out-of-order packets, multi-client scenarios
- ✅ Frame Synchronization - Time/frame conversion, latency scenarios,
  frame skip detection

### Integration Test Details

**test_rollback_flow.gd** - Tests rollback buffer behavior during gameplay
- Frame simulation without rollback (30+ frames)
- Backfilling missing frames during packet loss
- Detecting mismatches and triggering rollback
- Re-simulating frames after rollback point
- Buffer wraparound with 50+ frame sequences
- Applying server corrections to old frames
- ArrayPool efficiency during frame updates
- Large gap backfill triggering buffer reinitialization
- Negative index handling (-1, -2)

**test_state_synchronization.gd** - Tests multiplayer sync patterns
- Client prediction ahead of server
- Server corrections updating client prediction
- Late packet arrival handling
- Ignoring extremely old packets (beyond buffer)
- Multiple clients with different latencies
- State divergence detection (position, velocity)
- Client catch-up to server
- Burst of updates in quick succession

**test_frame_synchronization.gd** - Tests timing and frame alignment
- Time-to-frame and frame-to-time conversion
- Client/server frame alignment
- Clock offset handling (server ahead/behind)
- Low latency scenarios (20ms RTT, ~1 frame)
- High latency scenarios (200ms RTT, ~6 frames)
- Variable latency jitter (out-of-order packets)
- Frame skip detection
- Backfilling skipped frames
- Buffer size sufficiency for latency (1.5s = 90 frames)
- Extreme latency handling (500ms RTT)
- Packet loss extending effective latency

### Priority Areas for Future Tests

1. **Networking Layer**
   - ReconcilableNetworkedState (requires extensive mocking)
   - NetworkFrameDriver (full system integration test)
   - NetworkConnector (integration test)

2. **Character System**
   - Character action handlers
   - CharacterActionState state machine
   - Surface detection logic

3. **Game State**
   - Match state synchronization
   - Player state management

## Continuous Integration

Tests run automatically on GitHub Actions for:
- Pushes to `main` and `develop` branches
- All pull requests to `main`

See `.github/workflows/test.yml` for the CI configuration.

## Debugging Failed Tests

### Verbose Output

Run tests with verbose logging:
```bash
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gdir=res://test/unit -glog=2 -gexit
```

### Running Single Test

Isolate a failing test:
```bash
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gtest=res://test/unit/scaffolder/test_circular_buffer.gd \
  -gunit_test_name=test_append_overwrites_oldest -gexit
```

### Common Issues

1. **ArrayPool interference**: Make sure to call `ArrayPool.clear_all_pools()`
   in `before_each()` and `after_each()` for tests that use it.

2. **Node cleanup**: Use `add_child_autofree()` when adding nodes to the
   scene tree in tests.

3. **Test order dependency**: Tests should be independent and not rely on
   execution order.

4. **Directory discovery issues**: If tests aren't running with `-gdir`,
   try running specific test files with `-gtest` instead.

5. **Type hints required**: GDScript tests need explicit type hints for
   arrays:
   ```gdscript
   var state: Array = buffer.get_at(5)  # Correct
   var state = buffer.get_at(5)         # May cause issues
   ```

6. **Autoloads active during tests**: The `G` singleton and networking
   subsystems are fully initialized when tests run.

## Resources

- [GUT Documentation](https://gut.readthedocs.io/en/latest/)
- [GUT GitHub](https://github.com/bitwes/Gut)
- [CLAUDE.md Testing Section](../CLAUDE.md#testing-with-gut)
