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
- ⏳ Multiplayer state synchronization (planned)
- ⏳ Rollback reconciliation flow (planned)
- ⏳ Character physics integration (planned)

### Priority Areas for Future Tests

1. **Networking Layer**
   - ReconcilableNetworkedState (requires extensive mocking)
   - NetworkFrameDriver (integration test)
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

## Resources

- [GUT Documentation](https://gut.readthedocs.io/en/latest/)
- [GUT GitHub](https://github.com/bitwes/Gut)
- [CLAUDE.md Testing Section](../CLAUDE.md#testing-with-gut)
