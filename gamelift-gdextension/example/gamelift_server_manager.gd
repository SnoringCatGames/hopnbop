extends Node
## GameLift Server Integration Example
##
## This script demonstrates how to integrate your Godot dedicated server
## with AWS GameLift using the GameLift GDExtension.
##
## Add this script to your server's main scene or autoload it.

# Configuration
@export var server_port: int = 7777
@export var log_paths: PackedStringArray = ["logs/server.log"]

# For Anywhere fleets (local development), set these via command line or environment
var anywhere_websocket_url: String = ""
var anywhere_auth_token: String = ""
var anywhere_fleet_id: String = ""
var anywhere_host_id: String = ""
var anywhere_process_id: String = ""

# Reference to the GameLift server instance
var gamelift: GameLiftServer

# Track connected players by their player_session_id
var connected_players: Dictionary = { }


func _ready() -> void:
    # Only run GameLift integration on dedicated server builds
    if not is_dedicated_server():
        print("Not running as dedicated server, skipping GameLift initialization")
        return

    # Parse command line arguments for Anywhere fleet configuration
    parse_command_line_args()

    # Create and configure GameLift server
    gamelift = GameLiftServer.new()
    add_child(gamelift)

    # Connect to GameLift signals
    gamelift.game_session_started.connect(_on_game_session_started)
    gamelift.game_session_updated.connect(_on_game_session_updated)
    gamelift.process_terminate_requested.connect(_on_process_terminate_requested)
    gamelift.health_check_requested.connect(_on_health_check)

    # Initialize the SDK
    initialize_gamelift()


func is_dedicated_server() -> bool:
    # Check if running as dedicated server
    # You can also use OS.has_feature("dedicated_server") in Godot 4.x
    return OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_args()


func parse_command_line_args() -> void:
    var args = OS.get_cmdline_args()

    for i in range(args.size()):
        var arg = args[i]

        if arg == "--port" and i + 1 < args.size():
            server_port = int(args[i + 1])
        elif arg == "--gamelift-websocket" and i + 1 < args.size():
            anywhere_websocket_url = args[i + 1]
        elif arg == "--gamelift-auth-token" and i + 1 < args.size():
            anywhere_auth_token = args[i + 1]
        elif arg == "--gamelift-fleet-id" and i + 1 < args.size():
            anywhere_fleet_id = args[i + 1]
        elif arg == "--gamelift-host-id" and i + 1 < args.size():
            anywhere_host_id = args[i + 1]
        elif arg == "--gamelift-process-id" and i + 1 < args.size():
            anywhere_process_id = args[i + 1]

    # Also check environment variables (useful for containerized deployments)
    if anywhere_websocket_url.is_empty():
        anywhere_websocket_url = OS.get_environment("GAMELIFT_WEBSOCKET_URL")
    if anywhere_auth_token.is_empty():
        anywhere_auth_token = OS.get_environment("GAMELIFT_AUTH_TOKEN")
    if anywhere_fleet_id.is_empty():
        anywhere_fleet_id = OS.get_environment("GAMELIFT_FLEET_ID")
    if anywhere_host_id.is_empty():
        anywhere_host_id = OS.get_environment("GAMELIFT_HOST_ID")
    if anywhere_process_id.is_empty():
        anywhere_process_id = OS.get_environment("GAMELIFT_PROCESS_ID")


func initialize_gamelift() -> void:
    var outcome: GameLiftOutcome

    # Check if this is an Anywhere fleet (has WebSocket URL) or managed EC2
    if not anywhere_websocket_url.is_empty():
        print("[Server] Initializing GameLift SDK for Anywhere fleet...")
        outcome = gamelift.init_sdk_anywhere(
            anywhere_websocket_url,
            anywhere_auth_token,
            anywhere_fleet_id,
            anywhere_host_id,
            anywhere_process_id,
        )
    else:
        print("[Server] Initializing GameLift SDK for managed EC2 fleet...")
        outcome = gamelift.init_sdk()

    if not outcome.is_success():
        push_error("[Server] Failed to initialize GameLift SDK: " + outcome.get_error_message())
        get_tree().quit(1)
        return

    print("[Server] GameLift SDK version: " + gamelift.get_sdk_version())

    # Signal that we're ready to receive game sessions
    print("[Server] Calling ProcessReady on port %d..." % server_port)
    outcome = gamelift.process_ready(server_port, log_paths)

    if not outcome.is_success():
        push_error("[Server] ProcessReady failed: " + outcome.get_error_message())
        get_tree().quit(1)
        return

    print("[Server] Server is ready and waiting for game sessions!")

# =============================================================================
# GameLift Signal Handlers
# =============================================================================


func _on_game_session_started(game_session: GameLiftGameSession) -> void:
    print("[Server] Game session started!")
    print("  Session ID: " + game_session.game_session_id)
    print("  Name: " + game_session.name)
    print("  Max Players: %d" % game_session.maximum_player_session_count)
    print("  Game Properties: " + str(game_session.game_properties))

    # Parse matchmaker data if using FlexMatch
    if not game_session.matchmaker_data.is_empty():
        print("  Matchmaker Data: " + game_session.matchmaker_data)
        var matchmaker_data = JSON.parse_string(game_session.matchmaker_data)
        if matchmaker_data:
            setup_match_from_matchmaker_data(matchmaker_data)

    # TODO: Set up your game world/match here based on game_session properties
    # For example: load the correct map, configure game rules, etc.
    setup_game_world(game_session)

    # Tell GameLift we're ready to accept players
    var outcome = gamelift.activate_game_session()
    if outcome.is_success():
        print("[Server] Game session activated, ready for players!")
    else:
        push_error("[Server] Failed to activate game session: " + outcome.get_error_message())


func _on_game_session_updated(game_session: GameLiftGameSession, backfill_ticket_id: String, update_reason: int) -> void:
    print("[Server] Game session updated")
    print("  Backfill Ticket ID: " + backfill_ticket_id)
    print("  Update Reason: %d" % update_reason)

    # Handle backfill - new players may be joining via matchmaking
    if not backfill_ticket_id.is_empty():
        handle_backfill_update(game_session, backfill_ticket_id)


func _on_process_terminate_requested() -> void:
    print("[Server] GameLift requested process termination")

    # Get termination time if available
    var termination_time = gamelift.get_termination_time()
    if termination_time > 0:
        print("[Server] Termination scheduled for: %d" % termination_time)

    # Gracefully shut down
    # 1. Stop accepting new players
    gamelift.update_player_session_creation_policy(GameLiftServer.DENY_ALL)

    # 2. Notify connected players
    notify_players_of_shutdown()

    # 3. Save any game state if needed
    save_game_state()

    # 4. Signal process ending to GameLift
    var outcome = gamelift.process_ending()
    if not outcome.is_success():
        push_error("[Server] ProcessEnding failed: " + outcome.get_error_message())

    # 5. Clean up and exit
    gamelift.destroy()
    get_tree().quit(0)


func _on_health_check() -> void:
    # GameLift calls this every ~60 seconds
    # Return true (healthy) by default in the callback
    # You can add custom health check logic here
    print("[Server] Health check - OK")

# =============================================================================
# Player Session Management
# =============================================================================


## Call this when a player connects to your server
## The player should provide their player_session_id (received from matchmaking/backend)
func on_player_connecting(peer_id: int, player_session_id: String) -> bool:
    print("[Server] Player connecting with session: " + player_session_id)

    # Validate the player session with GameLift
    var outcome = gamelift.accept_player_session(player_session_id)

    if outcome.is_success():
        print("[Server] Player session accepted: " + player_session_id)
        connected_players[peer_id] = player_session_id
        return true
    else:
        push_warning("[Server] Failed to accept player session: " + outcome.get_error_message())
        # Reject the connection
        return false


## Call this when a player disconnects from your server
func on_player_disconnected(peer_id: int) -> void:
    if peer_id in connected_players:
        var player_session_id = connected_players[peer_id]
        print("[Server] Player disconnected: " + player_session_id)

        # Notify GameLift that the player has left
        var outcome = gamelift.remove_player_session(player_session_id)
        if not outcome.is_success():
            push_warning("[Server] Failed to remove player session: " + outcome.get_error_message())

        connected_players.erase(peer_id)

    # Check if we should start backfill
    check_and_start_backfill()


## Get information about current player sessions
func get_active_player_sessions() -> Array:
    var game_session_id = gamelift.get_game_session_id()
    if game_session_id.is_empty():
        return []

    return gamelift.describe_player_sessions(
        game_session_id, # game_session_id
        "", # player_id (empty = all players)
        "", # player_session_id (empty = all sessions)
        "ACTIVE", # status filter
        100, # limit
    )

# =============================================================================
# Matchmaking Backfill
# =============================================================================


## Start a backfill request to find more players
func check_and_start_backfill() -> void:
    var current_session = gamelift.get_current_game_session()
    if current_session == null:
        return

    var current_players = connected_players.size()
    var max_players = current_session.maximum_player_session_count

    # Only backfill if we have room and minimum players
    if current_players >= max_players or current_players == 0:
        return

    print("[Server] Starting matchmaking backfill...")

    # Build player list for backfill
    var players: Array = []
    for peer_id in connected_players:
        var player_session_id = connected_players[peer_id]
        # You'd want to include actual player attributes here
        players.append(
            {
                "player_id": player_session_id,
                "team": "default",
                "attributes": { },
                "latency_ms": { },
            },
        )

    # Generate a unique ticket ID
    var ticket_id = "backfill-" + str(Time.get_unix_time_from_system())

    # You need to provide your matchmaking configuration ARN
    var matchmaking_config_arn = "arn:aws:gamelift:us-west-2:123456789012:matchmakingconfiguration/MyMatchmaker"

    var outcome = gamelift.start_match_backfill(ticket_id, matchmaking_config_arn, players)
    if outcome.is_success():
        print("[Server] Backfill request started: " + ticket_id)
    else:
        push_warning("[Server] Backfill request failed: " + outcome.get_error_message())


func handle_backfill_update(game_session: GameLiftGameSession, backfill_ticket_id: String) -> void:
    # New players have been matched via backfill
    # They will connect with their player session IDs
    print("[Server] Backfill completed: " + backfill_ticket_id)

    # Parse matchmaker data for new player info
    if not game_session.matchmaker_data.is_empty():
        var matchmaker_data = JSON.parse_string(game_session.matchmaker_data)
        if matchmaker_data and matchmaker_data.has("teams"):
            for team in matchmaker_data["teams"]:
                for player in team.get("players", []):
                    print("[Server] Backfill player: " + str(player.get("playerId", "unknown")))

# =============================================================================
# Game Setup Helpers
# =============================================================================


func setup_game_world(game_session: GameLiftGameSession) -> void:
    # Example: Load map based on game properties
    var props = game_session.game_properties

    if props.has("map"):
        var map_name = props["map"]
        print("[Server] Loading map: " + map_name)
        # load_map(map_name)

    if props.has("game_mode"):
        var mode = props["game_mode"]
        print("[Server] Setting game mode: " + mode)
        # set_game_mode(mode)


func setup_match_from_matchmaker_data(matchmaker_data: Dictionary) -> void:
    # FlexMatch provides detailed player and team information
    if matchmaker_data.has("teams"):
        for team in matchmaker_data["teams"]:
            var team_name = team.get("name", "unknown")
            print("[Server] Team: " + team_name)

            for player in team.get("players", []):
                var player_id = player.get("playerId", "unknown")
                var attributes = player.get("attributes", { })
                print("[Server]   Player: %s, Attributes: %s" % [player_id, str(attributes)])


func notify_players_of_shutdown() -> void:
    # Send shutdown notification to all connected players
    # This depends on your networking implementation
    print("[Server] Notifying %d players of shutdown..." % connected_players.size())
    # For example with high-level multiplayer:
    # rpc("server_shutting_down")


func save_game_state() -> void:
    # Save any persistent game state
    # This could be to DynamoDB, S3, or local files
    print("[Server] Saving game state...")


func _exit_tree() -> void:
    # Clean up on exit
    if gamelift and gamelift.is_initialized():
        gamelift.process_ending()
        gamelift.destroy()
