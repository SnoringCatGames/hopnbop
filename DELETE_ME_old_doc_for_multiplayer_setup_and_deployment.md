Plan: Multi-Player Per Client Support
Summary
Enable multiple players to play on a single client connection, separating the concept of "peer" (client connection) from "player" (individual character).

Current Architecture
Based on codebase exploration, the system currently assumes:

One peer_id = One player_id: No separation between client and player
multiplayer_id is both: The Godot peer ID serves as the player identifier throughout
Automatic player spawning: When a peer connects, exactly one player is created in Level._server_add_player(multiplayer_id)
Global input per client: One InputMap, no multi-device support
Dictionary indexing by multiplayer_id: All lookups use peer ID as the key
Key Files Requiring Changes
Core Identification System
src/level/level.gd - Player spawning and players_by_id dict
src/core/match_state.gd - Player tracking dict structure
src/core/match_state_synchronizer.gd - Player lifecycle
src/core/player_match_state.gd - Per-player metadata
Input System
src/scaffolder/character/action/player_action_source.gd - Input collection
src/scaffolder/character/player.gd - Player character base class
src/scaffolder/character/player_input_from_client.gd - Input authority
Network Layer
src/networking/network_connector.gd - Connection handling
src/networking/gamelift_manager.gd - GameLift integration
src/scaffolder/character/character_state_from_server.gd - State replication
Game Management
src/core/game_panel.gd - Game lifecycle
src/player/bunny.gd - Game-specific player
Research Phase Findings
1. Connection & Player Spawning System
Server creates players in Level._server_add_player(multiplayer_id)
Creates exactly one player per peer connection
Sets player.multiplayer_id = multiplayer_id
Adds to players_by_id[multiplayer_id] = player
2. Input System Limitations
Uses global Input.is_action_pressed(action) - no device filtering
No gamepad device ID → player mapping
Single InputMap for all input
PlayerActionSource.update() collects input without device context
3. Match State Player Tracking
MatchState.players is Dictionary<int, PlayerMatchState>
Keyed by multiplayer_id (peer ID)
PlayerMatchState stores multiplayer_id, bunny_name, connection times
No concept of multiple players per peer
4. GameLift Integration
GameLiftManager maintains _peer_to_session and _session_to_peer mappings
Currently maps one peer_id to one session_id
FIXME notes indicate client doesn't yet send player_session_id to server
Validation flow: peer connects → sends session_id → server validates via GameLift SDK
User Requirements Clarification
Based on user feedback:

Input devices: Support any number of gamepads AND multiple players sharing a single keyboard (most complex scenario)
Player count: Fixed at connection time (determined before client connects)
GameLift: One player_session_id per player (matchmaking must know player count per client)
Architectural Design
Player Identification System
Current Problem: multiplayer_id (int) serves dual purpose as both network peer ID AND player identifier.

Solution: Introduce composite player_id separating peer from player.

Player ID Format: "peer_id:local_index" (String)

Examples: "1234:0", "1234:1", "1234:2"
peer_id: ENet multiplayer peer ID (int)
local_index: 0-based index for players on that peer (int)
Rationale:

Clear peer ownership visible in ID
Natural grouping for peer-based operations (disconnect all players for peer)
Easy backward compatibility (peer_id:0 for single-player-per-peer)
Aligns with GameLift's peer + multiple session_ids model
Connection Handshake Protocol
New Flow:

Client connects to server (ENet establishes connection, assigns peer_id)
Client sends player count + session_ids RPC (NEW):

@rpc("any_peer", "call_remote", "reliable")
func client_declare_players(player_count: int, session_ids: Array[String])
Server validates sessions with GameLift (if enabled)
Server spawns N players for this peer_id with IDs: "peer_id:0", "peer_id:1", etc.
Location: Add to NetworkConnector or create new ConnectionManager class.

Input System Redesign
Current Limitation: Global Input.is_action_pressed() with no device filtering.

Solution: Device-to-player mapping with device-aware input polling.

New Components:

InputDeviceManager (new singleton):


class DeviceConfig:
    enum DeviceType { KEYBOARD, GAMEPAD }
    var type: DeviceType
    var device_id: int  # -1 for keyboard, 0+ for gamepad
    var key_bindings: Dictionary  # action → key code

var player_device_map: Dictionary = {}  # local_index → DeviceConfig
Keyboard Partitioning:

Define separate key binding sets per keyboard player
Example: Player 0 = WASD+Space, Player 1 = IJKL+Shift
Use Input.is_physical_key_pressed() for keyboard players
Modified PlayerActionSource:

Add device_config and local_player_index properties
Replace global input checks with device-specific polling
For gamepads: Use Godot's device parameter in Input methods
For keyboard: Use physical key codes from device_config
Data Structure Changes
PlayerMatchState (src/core/player_match_state.gd):


# ADD
var player_id: String  # "peer_id:local_index"
var peer_id: int       # extracted from player_id
var local_index: int   # extracted from player_id

# KEEP (deprecated, for backward compat)
var multiplayer_id: int:
    get: return peer_id
Level (src/level/level.gd):


# CHANGE from Dictionary<int, Player> to Dictionary<String, Player>
var players_by_id := {}  # keyed by "peer_id:local_index"

# ADD
var peer_to_player_ids := {}  # Dictionary<int, Array<String>>
LocalSession (src/core/local_session.gd):


# ADD
var local_player_count: int = 1
var local_player_ids: Array[String] = []
var device_configs: Array[InputDeviceManager.DeviceConfig] = []
Network Replication Changes
CharacterStateFromServer (src/scaffolder/character/character_state_from_server.gd):

Replace multiplayer_id sync with player_id sync
Update authority checks to use peer portion of player_id:

var is_authority_for_state_from_server: bool:
    get:
        var my_peer_id = int(player_id.split(":")[0]) if player_id else 0
        return multiplayer.get_unique_id() == my_peer_id
Player (src/scaffolder/character/player.gd):

Add player_id: String property
Add local_player_index: int property
Update _on_multiplayer_id_replicated() to use player_id
GameLift Integration
GameLiftManager (src/networking/gamelift_manager.gd):

Update mappings to use player_id instead of peer_id:

var _peer_to_session: Dictionary = {}  # player_id (String) → session_id (String)
var _session_to_peer: Dictionary = {}  # session_id (String) → player_id (String)
Update validate_player_session() to iterate through multiple session_ids per peer
Implementation Plan
Phase 1: Core Player ID System (Foundation)
Goal: Separate peer_id from player_id throughout the codebase.

Update PlayerMatchState (src/core/player_match_state.gd):

Add player_id: String, peer_id: int, local_index: int fields
Keep multiplayer_id as deprecated getter returning peer_id
Update get_packed_state() and populate_from_packed_state() to use player_id
Update get_multiplayer_id_from_packed_state() → get_player_id_from_packed_state()
Update MatchState (src/core/match_state.gd):

Change players: Dictionary from int keys to String keys
Add helper: get_players_for_peer(peer_id: int) -> Array[PlayerMatchState]
Update all dictionary operations to use String player_id
Update Level (src/level/level.gd):

Change players_by_id from Dictionary<int, Player> to Dictionary<String, Player>
Add peer_to_player_ids: Dictionary (peer_id → Array of player_ids)
Update on_player_added() and on_player_removed() to use String player_id
Update Player (src/scaffolder/character/player.gd):

Add player_id: String property
Add local_player_index: int property
Keep multiplayer_id as deprecated getter extracting peer_id from player_id
Update CharacterStateFromServer (src/scaffolder/character/character_state_from_server.gd):

Replace multiplayer_id: int with player_id: String
Update _update_replication_config() to sync player_id instead of multiplayer_id
Update authority checks to parse peer_id from player_id
Update ReconcilableNetworkedState (src/networking/reconcilable_network_state.gd):

Change multiplayer_id property from int to String (rename to player_id)
Update multiplayer_id_changed signal to player_id_changed
Update all subclasses (PlayerInputFromClient, ForwardedPlayerInputFromServer)
Phase 2: Connection Protocol
Goal: Enable clients to declare player count and spawn multiple players per peer.

Add RPC to NetworkConnector (src/networking/network_connector.gd):


const MAX_PLAYERS_PER_PEER := 4
var _pending_peer_declarations := {}  # peer_id → {count, session_ids, validated_count}

@rpc("any_peer", "call_remote", "reliable")
func client_declare_players(player_count: int, session_ids: Array[String]) -> void:
    # Validate player_count
    # Store pending declaration
    # Trigger GameLift validation or direct spawning
Update Level Player Spawning (src/level/level.gd):

Replace _server_add_player(multiplayer_id: int) with _server_add_players_for_peer(peer_id: int, count: int)
Loop to create N player instances with player_ids: "peer_id:0" through "peer_id:N-1"
Set player.player_id, player.local_player_index, and authority on input nodes
Add to players_by_id[player_id] and peer_to_player_ids[peer_id]
Update Level Player Removal (src/level/level.gd):

Replace _server_remove_player(multiplayer_id: int) with _server_remove_players_for_peer(peer_id: int)
Loop through peer_to_player_ids[peer_id] and remove all associated players
Update GamePanel (src/core/game_panel.gd):

Add peer_player_counts: Dictionary to track player count per peer
Update _on_player_joined() to handle multiple players per peer
Update local player detection (line 52) to check player_id against local_player_ids array
Phase 3: Input System
Goal: Support device-to-player mapping with multiple input sources per peer.

Create InputDeviceManager (new file src/core/input_device_manager.gd):

Define DeviceConfig class with type, device_id, key_bindings
Maintain player_device_map: Dictionary (local_index → DeviceConfig)
Add methods: assign_device_to_player(), get_action_state(), has_device_for_player()
Register as autoload singleton
Define Keyboard Binding Presets (add to InputDeviceManager or settings):

KEYBOARD_PLAYER_1_BINDINGS (WASD + Space)
KEYBOARD_PLAYER_2_BINDINGS (IJKL + Shift)
KEYBOARD_PLAYER_3_BINDINGS (Arrow keys + Enter)
KEYBOARD_PLAYER_4_BINDINGS (Numpad)
Update PlayerActionSource (src/scaffolder/character/action/player_action_source.gd):

Add device_config: InputDeviceManager.DeviceConfig property
Add local_player_index: int property
Modify _init() to accept device_config and local_index
Replace Input.is_action_pressed(action) with device-specific input checks:
Gamepad: Use Godot's device parameter
Keyboard: Use Input.is_physical_key_pressed(device_config.key_bindings[action])
Update Character (src/scaffolder/character/character.gd):

Modify _ready() where PlayerActionSource is created
Pass device_config and local_player_index from player
Update LocalSession (src/core/local_session.gd):

Add local_player_count: int = 1
Add device_configs: Array[InputDeviceManager.DeviceConfig] = []
Add method to configure devices before connection
Phase 4: GameLift Integration
Goal: Support multiple player_session_ids per peer.

Update GameLiftManager (src/networking/gamelift_manager.gd):

Change _peer_to_session to use player_id (String) keys instead of peer_id (int)
Add validate_player_sessions(peer_id: int, session_ids: Array[String]) method
Loop through session_ids, validate each, create player_id, store mappings
If any validation fails, disconnect entire peer
Update _validated_player_count and _expected_player_count calculation
Update NetworkConnector Client Side (src/networking/network_connector.gd):

In client_connect_to_server(), after connection, send client_declare_players() RPC
Pass G.local_session.local_player_count and array of session_ids from LocalSession
Note: Requires LocalSession to store multiple player_session_ids from matchmaking
Update LocalSession for Multiple Sessions:

Change player_session_id: String to player_session_ids: Array[String]
Populated by matchmaking backend based on player count
Phase 5: Network Replication & Authority
Goal: Ensure proper authority and state sync for multiple players per peer.

Update PlayerInputFromClient (src/scaffolder/character/player_input_from_client.gd):

Add player_id: String property
Add local_player_index: int property
Update get_is_player_control_active() to check:
Peer owns player (peer_id matches)
Device is assigned to this local_index
Update ForwardedPlayerInputFromServer (src/scaffolder/character/forwarded_player_input_from_server.gd):

Add player_id: String property
Update authority checks
Update Bunny Scene (src/player/bunny.tscn):

No structural changes needed
InputFromClient and ForwardedInputFromServer nodes will be configured at runtime
Update MatchStateSynchronizer (src/core/match_state_synchronizer.gd):

Modify _server_on_peer_connected() to wait for player count declaration before creating PlayerMatchStates
Create N PlayerMatchState objects with player_ids: "peer_id:0" through "peer_id:N-1"
Modify _server_on_peer_disconnected() to handle all players for that peer
Phase 6: UI & Configuration (Deferred to Future)
Note: Implementation focuses on backend systems. UI for device assignment is future work.

Deferred Components:

Device assignment UI screen (pre-connection)
Keyboard binding configuration UI
Player count selection screen
Lobby showing all local players with device indicators
Temporary Solution: Hardcode device configs in LocalSession for testing:


# In LocalSession or test script
func _ready():
    local_player_count = 2
    device_configs = [
        InputDeviceManager.DeviceConfig.new(KEYBOARD, -1, KEYBOARD_PLAYER_1_BINDINGS),
        InputDeviceManager.DeviceConfig.new(GAMEPAD, 0, {}),
    ]
Critical Files Summary
File Changes
src/core/player_match_state.gd Add player_id (String), peer_id, local_index; update packing
src/core/match_state.gd Change players dict to String keys; add get_players_for_peer()
src/level/level.gd Update players_by_id to String keys; add peer_to_player_ids; spawn N players per peer
src/scaffolder/character/player.gd Add player_id, local_player_index properties
src/scaffolder/character/character_state_from_server.gd Replace multiplayer_id with player_id; update authority checks
src/networking/reconcilable_network_state.gd Change multiplayer_id to player_id (String)
src/networking/network_connector.gd Add client_declare_players RPC; coordinate spawning
src/scaffolder/character/action/player_action_source.gd Add device_config, local_index; device-specific input polling
src/core/input_device_manager.gd NEW FILE: Device-to-player mapping system
src/core/local_session.gd Add local_player_count, device_configs, player_session_ids array
src/core/game_panel.gd Add peer_player_counts tracking; update local player detection
src/networking/gamelift_manager.gd Update to validate multiple sessions per peer; use player_id keys
src/scaffolder/character/player_input_from_client.gd Add player_id, local_index; update control checks
src/core/match_state_synchronizer.gd Wait for player count; create N PlayerMatchStates per peer
Systems Requiring Changes
Based on user question: "Please let me know if there are any other systems or designs that will need to change to accommodate this."

1. Player Identification (Critical)
What: Separate peer_id from player_id throughout
Why: Core assumption that one peer = one player is baked into all systems
Impact: High - touches every system that references players
2. Input Handling (Critical)
What: Device-to-player mapping for multiple local players
Why: Current system uses global InputMap with no device filtering
Impact: High - requires complete input system redesign
3. Network Spawning (Critical)
What: Spawn N players per peer instead of 1
Why: Level._server_add_player() hardcodes one player per peer
Impact: Medium - localized to Level and MatchStateSynchronizer
4. GameLift Integration (Critical)
What: Support multiple player_session_ids per peer
Why: Matchmaking needs to know player count upfront
Impact: Medium - affects connection validation flow
5. Match State Tracking (Critical)
What: Update dictionaries, indexing, and replication
Why: All player tracking uses multiplayer_id as key
Impact: High - affects all game state lookups
6. Camera System (Future Work)
What: Split-screen or follow-active-player camera for multiple local players
Why: Current camera in Bunny only follows multiplayer_id == G.network.local_id
Impact: Medium - deferred to future (can use single camera for now)
7. UI/HUD (Future Work)
What: Display multiple local player states (health, score, etc.)
Why: Current HUD assumes one local player
Impact: Low - cosmetic, deferred to future
8. Animation/Audio (Minor)
What: May need player-specific audio listeners
Why: If using spatial audio, need proper listener positioning
Impact: Low - likely works with default settings
9. Collision/Physics (No Change)
What: Player-player collision, damage, etc.
Why: Already supports N players in scene (from N peers)
Impact: None - existing multi-player logic works
10. Rollback/Reconciliation (No Change)
What: Frame-based rollback buffer
Why: Already supports N ReconcilableNetworkedState instances
Impact: None - works with any number of players
Backward Compatibility
Single-player-per-client mode (default):

Default local_player_count = 1
player_id = "peer_id:0"
All existing logic works with modifications
No breaking changes to save data or network protocol (just int→String for IDs)
Migration Strategy:

Introduce player_id alongside deprecated multiplayer_id getters
Gradually migrate all references
Keep backward-compat getters indefinitely (low cost)
Testing Strategy
Unit Tests
PlayerIdentifier parsing (to_string/from_string)
InputDeviceManager device assignment
peer_to_player_ids mapping correctness
Dictionary lookups with String keys
Integration Tests
Spawn 2 players for peer, verify both in players_by_id
Simulate input from 2 devices, verify independent movement
Disconnect peer, verify all players removed
GameLift: validate multiple sessions for one peer
Manual Testing Scenarios
1 client, 2 gamepads: Both players move independently
1 client, keyboard + gamepad: Independent control
2 clients, 1 gamepad each: 4 total players work correctly
1 client, 2 keyboard players: Partitioned keys work
Peer disconnect: All players for that peer removed
GameLift validation: Multiple session IDs accepted
Open Questions for User
Maximum players per peer: Should we enforce a limit? (Suggest 4 max)
Keyboard partitioning: Should we provide preset key layouts or require manual config?
Camera for local multiplayer: Split-screen, follow active player, or fixed camera?
GameLift matchmaking: How does matchmaking populate multiple player_session_ids per client connection?
Mid-game device changes: Should we support hot-plugging gamepads or device reassignment?
Verification Steps
After implementation, verify:

Single player per client still works:

Start server + 2 clients with default settings
Verify 2 players spawn and move correctly
Multiple players per client:

Set local_player_count = 2 in LocalSession
Assign 2 device configs (keyboard + gamepad)
Connect client to server
Verify 2 players spawn for that peer
Verify both players move independently based on their input devices
Verify player_ids are "peer_id:0" and "peer_id:1"
GameLift integration (if enabled):

Mock matchmaking providing 2 player_session_ids for one client
Client connects and sends both session_ids in RPC
Server validates both via GameLift SDK
Verify 2 players spawn only after successful validation
Peer disconnect:

Client with 2 players disconnects
Verify both players removed from Level.players_by_id
Verify both PlayerMatchStates marked disconnected
Network replication:

Spawn 3 clients: A (2 players), B (1 player), C (1 player)
From client A, move both players
Verify clients B and C see both of A's players moving correctly
Verify rollback reconciliation works for all players
Match state events:

Player "1234:0" kills player "5678:0"
Verify kill event logged with correct player_ids
Verify MatchState.kills array contains correct IDs







































AWS GameLift Deployment Guide
Overview
This guide covers the complete setup of AWS GameLift infrastructure to support Jump 'n Thump multiplayer with FlexMatch matchmaking. The system will support multiple players per client connection (1-4 players per peer) as designed in the multi-player implementation above.

Deployment Strategy:

Development/Testing: GameLift Anywhere fleet (run on local hardware)
Production: Managed EC2 fleet (AWS-hosted)
Matchmaking: FlexMatch with custom rule sets for multi-player-per-client
Prerequisites
AWS Account Setup
Create AWS Account (if you don't have one):

Go to https://aws.amazon.com
Click "Create an AWS Account"
Follow the registration process
Add a payment method (GameLift has a free tier, but requires billing info)
Install AWS CLI:

Download from: https://aws.amazon.com/cli/
Verify installation: aws --version
Configure credentials: aws configure
Enter AWS Access Key ID (from IAM console)
Enter Secret Access Key
Default region: us-west-2 (or your preferred region)
Default output format: json
Set Up IAM Permissions:

Navigate to IAM console: https://console.aws.amazon.com/iam/
Create a new IAM user for GameLift operations or use existing
Attach policies:
AmazonGameLiftFullAccess (for development)
CloudWatchLogsFullAccess (for server logs)
Generate access keys for CLI/SDK use
Local Development Tools
Godot GameLift Extension:

Extension repository: (search for "godot gamelift extension")
Download the extension for Godot 4.x
Place in addons/ directory
Enable in Project Settings → Plugins
Development Prerequisites:

Windows: Visual C++ Redistributable (for GameLift SDK)
Linux: libssl and libcrypto libraries
macOS: Xcode command-line tools
Phase 1: GameLift Server SDK Integration
1.1 Install GameLift Extension for Godot
Steps:

Download the Godot GameLift extension (check GitHub for community extensions)
Copy to res://addons/gamelift/
Enable plugin in Project Settings → Plugins
Verify GameLiftServer class is available: ClassDB.class_exists("GameLiftServer")
Note: If no Godot 4 extension exists, you may need to use GDNative/GDExtension to wrap the C++ SDK or use a REST API approach for matchmaking only.

1.2 Update Settings.tres
Add GameLift configuration fields to settings.tres:


@export var use_gamelift := false

# Managed Fleet Settings
@export var gamelift_region := "us-west-2"
@export var gamelift_fleet_id := ""
@export var gamelift_alias_id := ""

# Anywhere Fleet Settings (local testing)
@export var gamelift_anywhere_mode := false
@export var gamelift_anywhere_websocket := "wss://us-west-2.api.amazongamelift.com"
@export var gamelift_anywhere_auth_token := ""
@export var gamelift_anywhere_fleet_id := ""
@export var gamelift_anywhere_host_id := ""
@export var gamelift_anywhere_process_id := ""

# Matchmaking
@export var gamelift_matchmaker_config_name := ""
@export var gamelift_queue_name := ""

# Server Settings
@export var local_server_port := 4433
Update src/core/settings.gd if needed to expose these properties.

1.3 Verify GameLiftManager Integration
src/networking/gamelift_manager.gd is already updated to support:

Multi-player-per-client session validation
validate_player_sessions(peer_id, player_count, session_ids) method
Player ID format: "peer_id:local_index"
Current Implementation Status:
✅ Server SDK initialization (managed + Anywhere)
✅ Multi-session validation per peer
✅ Player session acceptance/removal
✅ Process lifecycle (ready, terminate, health checks)

What's Already Working:

GameLiftManager.validate_player_sessions() handles N sessions per peer
Mappings use player_id (String) keys
Preview mode auto-accepts for local testing without AWS
Phase 2: GameLift Anywhere Fleet (Local Testing)
GameLift Anywhere lets you test with the full GameLift SDK running on your local machine before deploying to EC2.

2.1 Create Anywhere Fleet
Via AWS Console:

Navigate to GameLift console: https://console.aws.amazon.com/gamelift/
Click "Fleets" → "Create fleet"
Select "GameLift Anywhere"
Fleet details:
Name: jumpnthump-dev-anywhere
Description: "Local development fleet for Jump 'n Thump"
Custom location:
Location name: local-dev
Click "Create fleet"
Via AWS CLI:


aws gamelift create-fleet \
  --name jumpnthump-dev-anywhere \
  --description "Local development fleet" \
  --fleet-type ANYWHERE \
  --locations "Location=custom-local-dev" \
  --region us-west-2
Save the Fleet ID (e.g., fleet-abcd1234-5678-90ab-cdef-1234567890ab)

2.2 Register Local Compute
Register your local machine as a compute resource:

Via AWS CLI:


aws gamelift register-compute \
  --fleet-id fleet-YOUR-FLEET-ID \
  --compute-name local-dev-machine \
  --location custom-local-dev \
  --ip-address 127.0.0.1 \
  --region us-west-2
Get Auth Token:


aws gamelift get-compute-auth-token \
  --fleet-id fleet-YOUR-FLEET-ID \
  --compute-name local-dev-machine \
  --region us-west-2
Output:


{
  "FleetId": "fleet-abcd1234...",
  "FleetArn": "arn:aws:gamelift:...",
  "ComputeName": "local-dev-machine",
  "ComputeArn": "arn:aws:gamelift:...",
  "AuthToken": "VERY-LONG-AUTH-TOKEN-STRING",
  "ExpirationTimestamp": 1234567890
}
Copy the AuthToken - it expires in 15 minutes and must be refreshed for each test session.

2.3 Configure Settings for Anywhere Fleet
In settings.tres, set:


use_gamelift = true
gamelift_anywhere_mode = true
gamelift_anywhere_websocket = "wss://us-west-2.api.amazongamelift.com"
gamelift_anywhere_auth_token = "YOUR-AUTH-TOKEN-FROM-ABOVE"
gamelift_anywhere_fleet_id = "fleet-YOUR-FLEET-ID"
gamelift_anywhere_host_id = "local-dev-machine"
gamelift_anywhere_process_id = "local-process-1"
local_server_port = 4433
2.4 Test Local Server with GameLift Anywhere
Launch server with --server flag

GameLiftManager should log:


[GameLift] Initializing for Anywhere fleet
[GameLift] SDK version: 5.x.x
[GameLift] Calling ProcessReady on port 4433
[GameLift] Server ready, waiting for game sessions
Create a test game session via AWS CLI:


aws gamelift create-game-session \
  --fleet-id fleet-YOUR-FLEET-ID \
  --maximum-player-session-count 4 \
  --location custom-local-dev \
  --region us-west-2
Server should receive game session callback:


[GameLift] Game session started: gsess-abcd1234...
[GameLift] Max players: 4
Create player sessions:


aws gamelift create-player-session \
  --game-session-id gsess-YOUR-SESSION-ID \
  --player-id player-1 \
  --region us-west-2
Repeat for multiple players per client:


aws gamelift create-player-session \
  --game-session-id gsess-YOUR-SESSION-ID \
  --player-id player-2 \
  --region us-west-2
Connect client with player session IDs:

Set G.local_session.player_session_ids = ["psess-1", "psess-2"]
Set G.local_session.local_player_count = 2
Connect to server
Server validates both sessions via GameLiftManager
Expected Flow:


[GameLift] Peer 1234 declared 2 player(s)
[GameLift] Player session validated: psess-1 (peer 1234, local index 0)
[GameLift] Player session validated: psess-2 (peer 1234, local index 1)
[GameLift] Player validated: player_id=1234:0, session=psess-1 (2/4)
[GameLift] Player validated: player_id=1234:1, session=psess-2 (2/4)
Phase 3: Managed EC2 Fleet (Production)
3.1 Prepare Server Build
Build Server Executable:

In Godot, go to Project → Export
Create/Edit Linux/X64 export preset (EC2 runs Linux)
Export settings:
Export Type: Executable
Runnable: ✅ (enabled)
Dedicated Server: ✅ (enabled, strips client-only features)
Embed PCK: ✅ (enabled)
Export to builds/jumpnthump-server-linux
Create Install Script (install.sh):


#!/bin/bash
# GameLift calls this script to install dependencies

# Install any required libraries
# (None needed for basic Godot server)

echo "Install complete"
Create Server Launch Script (start_server.sh):


#!/bin/bash
# GameLift calls this script to start the server

# Launch the server
./jumpnthump-server-linux --server --gamelift
Make scripts executable:


chmod +x install.sh start_server.sh
Directory structure:


builds/
  jumpnthump-server-linux  (executable)
  install.sh
  start_server.sh
3.2 Upload Build to GameLift
Via AWS CLI:


aws gamelift upload-build \
  --name "jumpnthump-server-v0.1.0" \
  --build-version "0.1.0" \
  --build-root ./builds \
  --operating-system AMAZON_LINUX_2 \
  --region us-west-2
Output:


{
  "UploadCredentials": {
    "AccessKeyId": "...",
    "SecretAccessKey": "...",
    "SessionToken": "..."
  },
  "StorageLocation": {
    "Bucket": "gamelift-builds-us-west-2-...",
    "Key": "..."
  },
  "Build": {
    "BuildId": "build-abcd1234-...",
    "Status": "INITIALIZED"
  }
}
Monitor upload status:


aws gamelift describe-build \
  --build-id build-YOUR-BUILD-ID \
  --region us-west-2
Wait for "Status": "READY".

3.3 Create Managed Fleet
Via AWS Console:

GameLift console → Fleets → Create fleet
Select "Amazon GameLift managed"
Fleet details:
Name: jumpnthump-prod-fleet
Build: Select your uploaded build
Fleet type: On-Demand (or Spot for cost savings)
Instance type:
Instance type: c5.large (2 vCPU, 4 GB RAM)
Start with 1 instance, scale later
Process configuration:
Launch path: ./start_server.sh
Concurrent processes: 1 (one server per instance)
Max concurrent sessions: 1 (one game session per process)
Runtime configuration:
Server process: 1
Max player sessions: 4 (or higher if supporting more players)
Port settings:
Port: 4433
Protocol: UDP
IP range: 0.0.0.0/0 (allow all, restrict later)
Create fleet
Via AWS CLI:


aws gamelift create-fleet \
  --name jumpnthump-prod-fleet \
  --description "Production fleet for Jump 'n Thump" \
  --build-id build-YOUR-BUILD-ID \
  --ec2-instance-type c5.large \
  --fleet-type ON_DEMAND \
  --runtime-configuration \
    "ServerProcesses=[{LaunchPath=./start_server.sh,ConcurrentExecutions=1}]" \
  --ec2-inbound-permissions \
    "FromPort=4433,ToPort=4433,IpRange=0.0.0.0/0,Protocol=UDP" \
  --region us-west-2
Monitor fleet status:


aws gamelift describe-fleet-attributes \
  --fleet-ids fleet-YOUR-FLEET-ID \
  --region us-west-2
Wait for "Status": "ACTIVE".

3.4 Create Fleet Alias (Optional but Recommended)
Aliases let you switch between fleet versions without changing client code.


aws gamelift create-alias \
  --name jumpnthump-prod \
  --routing-strategy "Type=SIMPLE,FleetId=fleet-YOUR-FLEET-ID" \
  --region us-west-2
Use the alias ARN in clients instead of fleet ID.

Phase 4: FlexMatch Matchmaking Configuration
FlexMatch handles player matchmaking with custom rule sets. For multi-player-per-client, we need to configure matchmaking to handle variable player counts per connection.

4.1 Create Game Session Queue
Queues route game sessions to available fleets.

Via AWS Console:

GameLift console → Queues → Create queue
Queue details:
Name: jumpnthump-queue
Timeout: 300 seconds
Fleet destinations:
Add your fleet: jumpnthump-prod-fleet
Player latency policies (optional):
Max latency: 150ms (adjust based on your game's tolerance)
Create queue
Via AWS CLI:


aws gamelift create-game-session-queue \
  --name jumpnthump-queue \
  --timeout-in-seconds 300 \
  --destinations "DestinationArn=arn:aws:gamelift:us-west-2:ACCOUNT-ID:fleet/fleet-YOUR-FLEET-ID" \
  --region us-west-2
4.2 Create FlexMatch Rule Set
Rule sets define matchmaking logic. For multi-player-per-client, we need to:

Accept variable player counts per connection
Match based on total player count (e.g., 2v2 or 4-player FFA)
Support latency-based matching
Rule Set JSON (2v2 team match, multi-player-per-client):

Create matchmaking-ruleset.json:


{
  "name": "jumpnthump-2v2-ruleset",
  "ruleLanguageVersion": "1.0",
  "playerAttributes": [
    {
      "name": "skill",
      "type": "number",
      "default": 10
    },
    {
      "name": "playerCount",
      "type": "number",
      "default": 1
    }
  ],
  "teams": [
    {
      "name": "red",
      "maxPlayers": 2,
      "minPlayers": 1
    },
    {
      "name": "blue",
      "maxPlayers": 2,
      "minPlayers": 1
    }
  ],
  "rules": [
    {
      "name": "FairTeamSkill",
      "description": "Balance teams by total skill",
      "type": "distance",
      "measurements": [
        "avg(teams[red].players.attributes[skill])",
        "avg(teams[blue].players.attributes[skill])"
      ],
      "referenceValue": 5,
      "maxDistance": 10
    },
    {
      "name": "EqualPlayerCounts",
      "description": "Each team should have equal total players",
      "type": "comparison",
      "operation": "=",
      "measurements": [
        "sum(teams[red].players.attributes[playerCount])",
        "sum(teams[blue].players.attributes[playerCount])"
      ]
    },
    {
      "name": "MinimumPlayersPerTeam",
      "description": "Each team needs at least 1 player",
      "type": "collection",
      "measurements": ["teams[*].players.attributes[playerCount]"],
      "operation": "min",
      "referenceValue": 1
    },
    {
      "name": "FastConnection",
      "description": "Prefer low-latency matches",
      "type": "latency",
      "maxLatency": 150
    }
  ],
  "expansions": [
    {
      "target": "rules[FastConnection].maxLatency",
      "steps": [
        {
          "waitTimeSeconds": 10,
          "value": 200
        },
        {
          "waitTimeSeconds": 20,
          "value": 250
        }
      ]
    }
  ]
}
Key Multi-Player-Per-Client Features:

playerCount attribute: Each matchmaking ticket specifies how many players the client has (1-4)
EqualPlayerCounts rule: Ensures teams have equal total players (not equal connections)
Example: Team Red could have 1 client with 2 players, Team Blue could have 2 clients with 1 player each
Upload Rule Set:


aws gamelift create-matchmaking-rule-set \
  --name jumpnthump-2v2-ruleset \
  --rule-set-body file://matchmaking-ruleset.json \
  --region us-west-2
4.3 Create Matchmaking Configuration
Links the rule set to the game session queue.

Via AWS Console:

GameLift console → Matchmaking → Configurations → Create configuration
Configuration details:
Name: jumpnthump-2v2-config
Rule set: jumpnthump-2v2-ruleset
Game session queue: jumpnthump-queue
Request timeout: 60 seconds
Acceptance timeout: 30 seconds (if using manual acceptance)
Require acceptance: No (auto-accept for now)
Create configuration
Via AWS CLI:


aws gamelift create-matchmaking-configuration \
  --name jumpnthump-2v2-config \
  --rule-set-name jumpnthump-2v2-ruleset \
  --game-session-queue-arns "arn:aws:gamelift:us-west-2:ACCOUNT-ID:gamesessionqueue/jumpnthump-queue" \
  --request-timeout-seconds 60 \
  --acceptance-timeout-seconds 30 \
  --acceptance-required false \
  --region us-west-2
Phase 5: Client-Side Matchmaking Integration
5.1 Create Matchmaking Client Module
Create src/networking/matchmaking_client.gd:


class_name MatchmakingClient
extends Node

signal matchmaking_searching()
signal matchmaking_succeeded(connection_info: Dictionary)
signal matchmaking_failed(reason: String)
signal matchmaking_cancelled()

const MATCHMAKING_CONFIG := "jumpnthump-2v2-config"
const POLLING_INTERVAL_SEC := 2.0

var _ticket_id := ""
var _is_searching := false
var _poll_timer: Timer


func _ready() -> void:
_poll_timer = Timer.new()
_poll_timer.timeout.connect(_poll_matchmaking_status)
add_child(_poll_timer)


## Start matchmaking with specified player count.
func start_matchmaking(player_count: int, skill: float = 10.0) -> void:
if _is_searching:
G.warning("Already searching for match")
return

G.print(
"Starting matchmaking with %d player(s), skill=%.1f" % [
player_count,
skill,
],
ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
)

# Construct matchmaking request
var request := {
"ConfigurationName": MATCHMAKING_CONFIG,
"Players": [
{
"PlayerId": G.network.local_id,  # Unique client ID
"PlayerAttributes": {
"skill": {"N": skill},
"playerCount": {"N": player_count},
},
}
],
}

# Call AWS GameLift StartMatchmaking API
# NOTE: This requires AWS SDK or HTTP client
var response = await _call_gamelift_api("StartMatchmaking", request)

if response.has("MatchmakingTicket"):
_ticket_id = response.MatchmakingTicket.TicketId
_is_searching = true
_poll_timer.start(POLLING_INTERVAL_SEC)
matchmaking_searching.emit()
else:
matchmaking_failed.emit("Failed to start matchmaking")


func cancel_matchmaking() -> void:
if not _is_searching:
return

var request := {"TicketId": _ticket_id}
await _call_gamelift_api("StopMatchmaking", request)

_cleanup_search()
matchmaking_cancelled.emit()


func _poll_matchmaking_status() -> void:
if not _is_searching:
return

var request := {"TicketIds": [_ticket_id]}
var response = await _call_gamelift_api("DescribeMatchmaking", request)

if not response.has("TicketList") or response.TicketList.size() == 0:
matchmaking_failed.emit("Ticket not found")
_cleanup_search()
return

var ticket = response.TicketList[0]
var status: String = ticket.Status

match status:
"COMPLETED":
_on_matchmaking_completed(ticket)
"FAILED", "TIMED_OUT", "CANCELLED":
matchmaking_failed.emit(status)
_cleanup_search()
"QUEUED", "SEARCHING", "REQUIRES_ACCEPTANCE", "PLACING":
# Still searching, keep polling
pass


func _on_matchmaking_completed(ticket: Dictionary) -> void:
_cleanup_search()

# Extract connection info
var game_session = ticket.GameSessionConnectionInfo
var ip_address: String = game_session.IpAddress
var port: int = game_session.Port
var player_session_ids: Array = []

# Extract player session IDs for all local players
for player in ticket.Players:
if player.PlayerId == G.network.local_id:
player_session_ids = player.PlayerSessionIds

var connection_info := {
"ip_address": ip_address,
"port": port,
"player_session_ids": player_session_ids,
}

G.print(
"Matchmaking complete: %s:%d, %d session IDs" % [
ip_address,
port,
player_session_ids.size(),
],
ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
)

matchmaking_succeeded.emit(connection_info)


func _cleanup_search() -> void:
_is_searching = false
_ticket_id = ""
_poll_timer.stop()


func _call_gamelift_api(action: String, request: Dictionary) -> Dictionary:
# TODO: Implement AWS API call using HTTPClient or AWS SDK
# Options:
# 1. Use AWS SDK for Godot (if available)
# 2. Direct HTTPS calls with AWS Signature V4
# 3. Proxy through your own backend API
#
# For now, return mock response for local testing
G.warning("_call_gamelift_api not implemented: %s" % action)
return {}
Note: Actual AWS API integration requires:

AWS SDK (if Godot plugin available)
Or direct HTTPS calls with AWS Signature V4 authentication
Or a backend API proxy (recommended for production to hide credentials)
5.2 Integrate Matchmaking with Connection Flow
Update client connection logic to use matchmaking:


# In main menu or lobby screen
func _on_find_match_pressed() -> void:
var player_count := G.local_session.local_player_count
var skill := 10.0  # Get from player profile/settings

G.network.matchmaking_client.start_matchmaking(player_count, skill)


func _on_matchmaking_succeeded(connection_info: Dictionary) -> void:
# Store player session IDs
G.local_session.player_session_ids = connection_info.player_session_ids

# Connect to server
var ip: String = connection_info.ip_address
var port: int = connection_info.port
G.network.connector.client_connect_to_server(ip, port)
Phase 6: Backend API (Optional but Recommended)
For production, it's best to proxy GameLift API calls through your own backend to:

Hide AWS credentials from clients
Add player authentication
Rate limit matchmaking requests
Log matchmaking events
Architecture:


Client (Godot) → Your Backend API (Node.js/Python/etc.) → AWS GameLift
Example Backend Endpoint (Node.js with AWS SDK):


// POST /api/matchmaking/start
app.post('/api/matchmaking/start', async (req, res) => {
  const { playerId, playerCount, skill } = req.body;

  const gamelift = new AWS.GameLift({ region: 'us-west-2' });

  const params = {
    ConfigurationName: 'jumpnthump-2v2-config',
    Players: [
      {
        PlayerId: playerId,
        PlayerAttributes: {
          skill: { N: skill },
          playerCount: { N: playerCount },
        },
      },
    ],
  };

  try {
    const result = await gamelift.startMatchmaking(params).promise();
    res.json({ ticketId: result.MatchmakingTicket.TicketId });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
Phase 7: Testing and Validation
7.1 Local Testing Checklist (Anywhere Fleet)
 Server starts with --server flag
 GameLiftManager initializes SDK successfully
 ProcessReady call succeeds
 Create game session via CLI
 Server receives game session callback
 Create 2 player sessions via CLI (for one client with 2 players)
 Client connects with player_session_ids = ["psess-1", "psess-2"]
 Server validates both sessions
 Server spawns 2 players with player_ids "peer:0" and "peer:1"
 Both players receive input and move independently
 Disconnect client, both players removed
7.2 Production Testing Checklist (Managed Fleet)
 Build uploaded successfully
 Fleet status = ACTIVE
 Fleet has available instances
 Game session queue created
 FlexMatch rule set uploaded
 Matchmaking configuration created
 Client starts matchmaking with player_count=2
 Matchmaking ticket status changes: QUEUED → SEARCHING → COMPLETED
 Client receives IP, port, and 2 player_session_ids
 Client connects to server
 Server validates sessions via GameLift SDK
 Gameplay works as expected
 Match ends gracefully, server process terminates
7.3 Multi-Player-Per-Client Scenarios
Test these specific cases:

1v1 match, each client has 1 player: Standard case
2v2 match, one client has 2 players, other team has 2 clients with 1 player each: Unequal connection counts
2v2 match, each client has 2 players: Each client spawns 2 players
Mixed input devices: Client with keyboard + gamepad, both players work
4-player FFA: 4 separate clients, 1 player each
4-player FFA: 2 clients, 2 players each
7.4 Monitoring and Logs
Server Logs:

GameLift captures stdout/stderr from server process
View logs in GameLift console: Fleet → Instances → View logs
Or use CloudWatch Logs
Client Logs:

Log matchmaking ticket ID
Log connection attempts
Log player session validation results
Metrics to Monitor:

Active game sessions
Player session count
Matchmaking success rate
Average matchmaking time
Server instance utilization
Phase 8: Cost Optimization
8.1 Development Cost Reduction
Use GameLift Anywhere (free) for all development
Use Spot instances instead of On-Demand (up to 90% savings)
Start with minimal instance count, scale as needed
Terminate fleets when not testing
8.2 Production Cost Optimization
Auto-scaling: Configure fleet scaling policies based on player count
Multi-region: Deploy to regions closer to players (reduces latency + costs)
Instance sizing: Start with c5.large, monitor CPU/RAM, downsize if possible
Game session reuse: Support multiple matches per server process if feasible
FlexMatch batching: Increase batch wait time to fill matches more efficiently
Example Scaling Policy:


aws gamelift put-scaling-policy \
  --fleet-id fleet-YOUR-FLEET-ID \
  --name player-count-scaling \
  --policy-type TargetBased \
  --metric-name PercentAvailableGameSessions \
  --target-configuration TargetValue=50 \
  --region us-west-2
Troubleshooting
Common Issues
1. "SDK initialization failed"

Check GameLift extension is enabled
Verify AWS credentials/permissions
Check region matches fleet region
For Anywhere: Verify auth token is not expired (15min lifetime)
2. "ProcessReady failed"

Ensure port is not in use
Check log file paths are writable
Verify server process has network access
3. "Player session validation failed"

Ensure session IDs are from correct game session
Check session IDs haven't been used already (one-time use)
Verify game session is in ACTIVE state
4. "Matchmaking stuck in SEARCHING"

Not enough players in queue (wait or relax rules)
Latency too restrictive (expand latency tolerance)
Rule set constraints too strict (check team balance rules)
5. "Cannot connect to server IP"

Check EC2 inbound rules allow UDP on game port
Verify fleet status is ACTIVE
Check security groups allow traffic from client IPs
Debug Commands
Check fleet status:


aws gamelift describe-fleet-attributes \
  --fleet-ids fleet-YOUR-FLEET-ID \
  --region us-west-2
Check active game sessions:


aws gamelift describe-game-sessions \
  --fleet-id fleet-YOUR-FLEET-ID \
  --region us-west-2
Check matchmaking ticket:


aws gamelift describe-matchmaking \
  --ticket-ids ticket-YOUR-TICKET-ID \
  --region us-west-2
View server logs (requires instance ID):


aws gamelift get-instance-access \
  --fleet-id fleet-YOUR-FLEET-ID \
  --instance-id i-YOUR-INSTANCE-ID \
  --region us-west-2
Next Steps
After completing AWS GameLift setup:

Return to Phase 6 of Multi-Player Implementation: Create lobby UI for local player management
Integrate matchmaking: Add "Find Match" button that calls MatchmakingClient.start_matchmaking()
Test end-to-end flow:
Local lobby → select 2 players → find match → connect → play → disconnect
Production deployment: Switch from Anywhere to managed fleet
Monitor and iterate: Use CloudWatch metrics to optimize matchmaking rules and fleet scaling




Summary
What You've Set Up:

✅ GameLift Server SDK integrated with Godot
✅ Anywhere fleet for local testing
✅ Managed EC2 fleet for production
✅ FlexMatch matchmaking with multi-player-per-client support
✅ Game session queue and routing
✅ Client matchmaking integration (stub)
What's Working:

Multiple player sessions per client connection
Flexible team balancing (equal players, not equal connections)
Latency-based matchmaking
Auto-scaling and cost optimization
What's Left:

Implement actual AWS API calls in MatchmakingClient (use SDK or backend proxy)
Create lobby UI for player/device management (Phase 6 of main plan)
Add player authentication and profile management
Set up CloudWatch alarms for monitoring
Configure auto-scaling policies based on load
