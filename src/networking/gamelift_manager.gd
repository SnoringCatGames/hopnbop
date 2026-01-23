class_name GameLiftManager
extends Node
## Manages AWS GameLift Server SDK integration for production multiplayer.
##
## GameLiftManager handles the lifecycle of GameLift game sessions including:
## - SDK initialization (managed and Anywhere fleets)
## - Game session activation and termination
## - Player session validation and tracking
## - Health checks and process lifecycle callbacks
##
## This manager is only active when G.settings.use_gamelift is true. In preview
## mode (use_gamelift = false), all GameLift functionality is disabled and the
## game uses standard ENet networking.
##
## Usage:
## - Server: GameLift calls on_start_game_session → activate → wait for players
## - Clients: Connect via ENet → send player_session_id for validation
## - Both: Listen to all_players_connected signal when match is ready to start

# FIXME: Review this.

## Emitted when all expected players have connected and been validated.
signal all_players_connected()

## Emitted when GameLift sends a game session to this server process.
## Parameter is GameLiftGameSession when extension is loaded, null otherwise.
signal game_session_started(session)

## Emitted when a player session is successfully validated.
signal player_session_validated(peer_id: int, session_id: String)

var _gamelift = null # GameLiftServer when extension loaded
var _game_session = null # GameLiftGameSession when active
var _is_initialized := false
var _is_process_ready := false

# Maps peer_id <-> player_session_id (1:1)
var _peer_to_session: Dictionary = { } # int -> String
var _session_to_peer: Dictionary = { } # String -> int

# Pending connections awaiting validation
var _pending_peers: Array[int] = []

# Expected player count from matchmaking
var _expected_player_count: int = 0
var _validated_player_count: int = 0


func _ready() -> void:
    if not G.settings.use_gamelift:
        G.print(
            "[GameLift] Disabled via settings (use_gamelift = false)",
            ScaffolderLog.CATEGORY_CORE_SYSTEMS,
        )
        return

    if not G.network.is_server:
        G.print(
            "[GameLift] Client mode, skipping server SDK initialization",
            ScaffolderLog.CATEGORY_CORE_SYSTEMS,
        )
        return

    G.print(
        "[GameLift] Initializing (stub mode)",
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )
    G.log.log_system_ready("GameLiftManager")


## Returns true if GameLift is active and initialized.
func is_active() -> bool:
    return G.settings.use_gamelift and _is_initialized


## Returns true if the server process is ready to host sessions.
func is_process_ready() -> bool:
    return _is_process_ready


## Set the expected number of players for this game session.
func set_expected_player_count(count: int) -> void:
    _expected_player_count = count
    G.print(
        "[GameLift] Expected player count: %d" % count,
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )


## Validate a player session ID and map it to the peer_id.
func validate_player_session(peer_id: int, session_id: String) -> void:
    G.check_is_server("GameLiftManager.validate_player_session")

    if not is_active():
        # In preview mode, auto-accept without validation
        G.print(
            "[GameLift] Preview mode: Auto-accepting peer %d" % peer_id,
            ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
        )
        _on_validation_success(peer_id, session_id)
        return

    # TODO: Phase 4 - Implement actual GameLift validation
    G.warning(
        "[GameLift] Validation not yet implemented (Phase 4), auto-accepting",
        ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
    )
    _on_validation_success(peer_id, session_id)


func _on_validation_success(peer_id: int, session_id: String) -> void:
    _peer_to_session[peer_id] = session_id
    _session_to_peer[session_id] = peer_id
    _validated_player_count += 1

    G.print(
        "[GameLift] Player validated: peer=%d, session=%s (%d/%d)" % [
            peer_id,
            session_id,
            _validated_player_count,
            _expected_player_count,
        ],
        ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
    )

    player_session_validated.emit(peer_id, session_id)

    # Check if all matched players connected
    if _validated_player_count >= _expected_player_count:
        _on_all_players_ready()


func _on_all_players_ready() -> void:
    G.print(
        "[GameLift] All players connected, starting game",
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )

    # Unpause frame simulation
    G.network.frame_driver.set_paused(false)

    all_players_connected.emit()


## Get the player_session_id for a given peer_id.
func get_session_id_for_peer(peer_id: int) -> String:
    return _peer_to_session.get(peer_id, "")


## Get the peer_id for a given player_session_id.
func get_peer_id_for_session(session_id: String) -> int:
    return _session_to_peer.get(session_id, 0)


## Remove a player session when a player disconnects.
func remove_player_session(session_id: String) -> void:
    if not is_active():
        return

    # TODO: Phase 6 - Call GameLift SDK to remove player session
    G.print(
        (
            "[GameLift] Would remove player session: %s (not implemented)"
            % session_id
        ),
        ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
    )


## End the game session (called on server shutdown).
func end_game_session() -> void:
    if not is_active():
        return

    # TODO: Phase 6 - Update player session creation policy and cleanup
    G.print(
        "[GameLift] Would end game session (not implemented)",
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )


## Activate the game session after setup is complete.
func activate_game_session() -> void:
    if not is_active():
        return

    # TODO: Phase 2 - Call GameLift SDK to activate session
    G.print(
        "[GameLift] Would activate game session (not implemented)",
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )
