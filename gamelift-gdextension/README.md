# GameLift GDExtension for Godot 4

# FIXME: Review this.

A GDExtension that wraps the AWS GameLift Server SDK 5.x, allowing you to integrate your Godot dedicated server with AWS GameLift for session-based multiplayer game hosting.

## Features

- Full GameLift Server SDK 5.x integration
- Support for both **Managed EC2** and **Anywhere** fleets
- Player session management (accept, remove, describe)
- Matchmaking backfill support
- TLS certificate access for secure connections
- Fleet role credentials for accessing other AWS services
- Signal-based callbacks for GDScript integration

## Requirements

- **Godot 4.2+** (GDExtension API)
- **godot-cpp** (C++ bindings for Godot)
- **AWS GameLift Server SDK 5.x** (C++ version)
- **OpenSSL 3.x**
- **SCons** (build system)
- **CMake 3.1+** (for building GameLift SDK)
- **C++17 compatible compiler**

## Directory Structure

```
gamelift-gdextension/
├── src/
│   ├── gamelift_server.h          # Main header with class definitions
│   ├── gamelift_server.cpp        # Implementation
│   └── register_types.cpp         # GDExtension registration
├── example/
│   └── gamelift_server_manager.gd # Example GDScript usage
├── bin/                           # Compiled libraries (created during build)
├── godot-cpp/                     # Godot C++ bindings (clone here)
├── gamelift-server-sdk/           # GameLift SDK (build here)
├── SConstruct                     # Build script
├── gamelift.gdextension           # Extension configuration
└── README.md                      # This file
```

## Build Instructions

### Step 1: Clone godot-cpp

```bash
cd gamelift-gdextension
git clone --recurse-submodules https://github.com/godotengine/godot-cpp.git
cd godot-cpp
git checkout godot-4.2-stable  # Match your Godot version
```

### Step 2: Build GameLift Server SDK

Download the SDK from the [GameLift GitHub repository](https://github.com/amazon-gamelift/amazon-gamelift-servers-cpp-server-sdk):

```bash
# Clone the SDK
git clone https://github.com/amazon-gamelift/amazon-gamelift-servers-cpp-server-sdk.git gamelift-server-sdk
cd gamelift-server-sdk

# Install OpenSSL first (if not already installed)
# Ubuntu/Debian:
sudo apt-get install libssl-dev

# Build the SDK
mkdir cmake-build && cd cmake-build
cmake -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGAMELIFT_USE_STD=1 \
    -S .. -B .
make -j$(nproc)

# The built library will be in cmake-build/
```

### Step 3: Build the GDExtension

```bash
cd gamelift-gdextension

# Set environment variables (adjust paths as needed)
export GODOT_CPP_PATH=./godot-cpp
export GAMELIFT_SDK_PATH=./gamelift-server-sdk/cmake-build
export OPENSSL_PATH=/usr

# Build for Linux release (for GameLift deployment)
scons platform=linux target=template_release

# Build for Linux debug (for local testing)
scons platform=linux target=template_debug
```

### Step 4: Install in Your Godot Project

1. Create the addon directory in your project:
   ```bash
   mkdir -p your_project/addons/gamelift/bin
   ```

2. Copy the built files:
   ```bash
   cp gamelift.gdextension your_project/addons/gamelift/
   cp bin/*.so your_project/addons/gamelift/bin/
   ```

3. Copy required shared libraries:
   ```bash
   # From GameLift SDK build
   cp gamelift-server-sdk/cmake-build/libaws-cpp-sdk-gamelift-server.so your_project/addons/gamelift/bin/
   
   # OpenSSL libraries (check your system paths)
   cp /usr/lib/x86_64-linux-gnu/libssl.so.3 your_project/addons/gamelift/bin/
   cp /usr/lib/x86_64-linux-gnu/libcrypto.so.3 your_project/addons/gamelift/bin/
   ```

4. Enable the extension in Godot (it should auto-detect from the .gdextension file)

## Usage in GDScript

### Basic Server Setup

```gdscript
extends Node

var gamelift: GameLiftServer

func _ready():
    if not OS.has_feature("dedicated_server"):
        return
    
    gamelift = GameLiftServer.new()
    add_child(gamelift)
    
    # Connect signals
    gamelift.game_session_started.connect(_on_game_session_started)
    gamelift.process_terminate_requested.connect(_on_terminate)
    
    # Initialize SDK (for managed EC2 fleet)
    var result = gamelift.init_sdk()
    if not result.is_success():
        push_error("Failed to init GameLift: " + result.get_error_message())
        return
    
    # Tell GameLift we're ready
    result = gamelift.process_ready(7777, ["logs/server.log"])
    if result.is_success():
        print("Server ready on port 7777")

func _on_game_session_started(session: GameLiftGameSession):
    print("Game session started: " + session.game_session_id)
    
    # Set up your game based on session properties
    var props = session.game_properties
    
    # Activate the session when ready
    gamelift.activate_game_session()

func _on_terminate():
    print("Shutdown requested")
    gamelift.process_ending()
    gamelift.destroy()
    get_tree().quit()
```

### Player Session Validation

```gdscript
# When a player connects with their player_session_id
func validate_player(player_session_id: String) -> bool:
    var result = gamelift.accept_player_session(player_session_id)
    return result.is_success()

# When a player disconnects
func player_disconnected(player_session_id: String):
    gamelift.remove_player_session(player_session_id)
```

### For Anywhere Fleets (Local Development)

```gdscript
# Initialize with Anywhere fleet parameters
var result = gamelift.init_sdk_anywhere(
    "wss://us-west-2.api.amazongamelift.com",
    auth_token,
    fleet_id,
    host_id,
    process_id
)
```

## API Reference

### GameLiftServer

The main class for GameLift integration.

#### Methods

| Method | Description |
|--------|-------------|
| `init_sdk()` | Initialize for managed EC2 fleet |
| `init_sdk_anywhere(websocket_url, auth_token, fleet_id, host_id, process_id)` | Initialize for Anywhere fleet |
| `process_ready(port, log_paths)` | Signal ready to receive game sessions |
| `process_ending()` | Signal that the process is terminating |
| `activate_game_session()` | Activate the current game session |
| `accept_player_session(player_session_id)` | Validate a player connection |
| `remove_player_session(player_session_id)` | Remove a disconnected player |
| `describe_player_sessions(...)` | Get player session information |
| `get_game_session_id()` | Get current game session ID |
| `get_termination_time()` | Get scheduled termination time |
| `update_player_session_creation_policy(policy)` | Allow/deny new players |
| `start_match_backfill(...)` | Start matchmaking backfill |
| `stop_match_backfill(...)` | Stop matchmaking backfill |
| `get_sdk_version()` | Get SDK version string |
| `is_initialized()` | Check if SDK is initialized |
| `is_process_ready()` | Check if ProcessReady was called |
| `get_current_game_session()` | Get current GameLiftGameSession |
| `get_compute_certificate()` | Get TLS certificate info |
| `get_fleet_role_credentials(role_arn)` | Get AWS credentials |
| `destroy()` | Clean up SDK resources |

#### Signals

| Signal | Parameters | Description |
|--------|------------|-------------|
| `game_session_started` | `(session: GameLiftGameSession)` | New game session assigned |
| `game_session_updated` | `(session, backfill_ticket_id, update_reason)` | Session updated (e.g., backfill) |
| `process_terminate_requested` | None | GameLift wants to shut down |
| `health_check_requested` | None | Health check (every ~60s) |

#### Enums

```gdscript
GameLiftServer.PlayerSessionCreationPolicy.ACCEPT_ALL
GameLiftServer.PlayerSessionCreationPolicy.DENY_ALL

GameLiftServer.PlayerSessionStatus.PLAYER_SESSION_RESERVED
GameLiftServer.PlayerSessionStatus.PLAYER_SESSION_ACTIVE
GameLiftServer.PlayerSessionStatus.PLAYER_SESSION_COMPLETED
GameLiftServer.PlayerSessionStatus.PLAYER_SESSION_TIMEDOUT
```

### GameLiftGameSession

Properties for game session information:

- `game_session_id: String`
- `name: String`
- `fleet_id: String`
- `ip_address: String`
- `port: int`
- `maximum_player_session_count: int`
- `current_player_session_count: int`
- `game_session_data: String`
- `matchmaker_data: String`
- `dns_name: String`
- `game_properties: Dictionary`

### GameLiftPlayerSession

Properties for player session information:

- `player_session_id: String`
- `player_id: String`
- `game_session_id: String`
- `fleet_id: String`
- `ip_address: String`
- `dns_name: String`
- `port: int`
- `player_data: String`
- `status: int`
- `creation_time: int`
- `termination_time: int`

### GameLiftOutcome

Result object returned by most operations:

- `is_success() -> bool`
- `get_error_message() -> String`
- `get_error_type() -> int`

## Deployment to GameLift

### 1. Export Your Server

Export your Godot project as a Linux dedicated server build.

### 2. Package the Build

```bash
# Create build directory
mkdir -p my-server-build

# Copy your exported server
cp -r your_export/* my-server-build/

# Copy the GDExtension and dependencies
cp -r addons/gamelift my-server-build/addons/

# Ensure libraries are in the right place or set LD_LIBRARY_PATH
```

### 3. Create install.sh (Optional)

```bash
#!/bin/bash
# install.sh - Run any setup needed before the server starts

# Make sure the server executable is runnable
chmod +x /local/game/your_server.x86_64

# Set library path if needed
export LD_LIBRARY_PATH=/local/game/addons/gamelift/bin:$LD_LIBRARY_PATH
```

### 4. Upload to GameLift

```bash
aws gamelift upload-build \
    --name "My Godot Game Server v1.0" \
    --build-version "1.0.0" \
    --build-root ./my-server-build \
    --operating-system AMAZON_LINUX_2023 \
    --server-sdk-version 5.2.0 \
    --region us-west-2
```

### 5. Create Fleet

Create a fleet using the AWS Console or CLI, specifying:
- Launch path: `/local/game/your_server.x86_64`
- Launch parameters: `--server --headless`
- Port: Your server port (e.g., 7777)

## Troubleshooting

### SDK Initialization Fails

- Ensure you're running on a GameLift instance or have correct Anywhere parameters
- Check that all shared libraries are accessible (use `ldd` to verify)
- Verify the server SDK version matches what you specified when creating the build

### ProcessReady Fails

- Make sure `init_sdk()` succeeded first
- Verify the port isn't already in use
- Check log paths are writable

### Player Sessions Not Accepting

- Ensure `activate_game_session()` was called after receiving `game_session_started`
- Verify the player_session_id is valid and from GameLift

### Missing Libraries

```bash
# Check what libraries are needed
ldd your_project/addons/gamelift/bin/libgamelift.linux.template_release.x86_64.so

# Common issues:
# - libssl.so.3 not found: Copy from system or install OpenSSL 3
# - libaws-cpp-sdk-gamelift-server.so not found: Copy from SDK build
```

## License

This GDExtension wrapper is provided under the MIT license. 

The AWS GameLift Server SDK is subject to the AWS Customer Agreement and AWS Service Terms.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.
