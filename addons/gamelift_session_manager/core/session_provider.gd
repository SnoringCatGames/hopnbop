class_name SessionProvider
extends Node
## Abstract interface for session management providers.
##
## SessionProvider defines the contract between networking code and session
## validation systems (GameLift, Playfab, Steam, custom backends, etc.).
##
## Implementations handle:
## - Client: Request session IDs from matchmaking backend
## - Server: Validate session IDs against authority service
## - Both: Signal when sessions are ready or validation completes
##
## The plugin uses duck typing via Callables, so this class documents the
## expected interface but doesn't need to be extended.

## Emitted when client successfully retrieves session IDs from backend.
## session_ids: Array[String] - Session identifiers for local players
## server_ip: String - Server IP address to connect to
## server_port: int - Server port number
## selected_level_id: String - Level ID selected by server/backend (may be empty)
signal session_ids_received(
	session_ids: Array,
	server_ip: String,
	server_port: int,
	selected_level_id: String
)

## Emitted when session ID request fails.
## error_message: String - Human-readable error description
signal session_request_failed(error_message: String)

## Emitted when server validates a player session.
## player_id: int - Game-assigned player ID
## session_id: String - Backend session identifier
signal player_session_validated(player_id: int, session_id: String)

## Emitted when all expected players have connected and validated.
signal all_players_connected()

## Emitted when server receives the selected level from game session.
## level_id: String - The level ID to spawn
signal level_selected(level_id: String)


## CLIENT: Request session IDs for local players.
## player_count: int - Number of local players
## (split-screen/couch co-op).
## session_prefs: Dictionary - Session
## preferences (level, critters, cheats).
func client_request_session_ids(
	player_count: int,
	session_prefs: Dictionary = {},
) -> void:
	push_error("SessionProvider.client_request_session_ids not implemented")


## SERVER: Validate session IDs for a connecting peer.
## peer_id: int - Network peer identifier
## player_ids: Array[int] - Game-assigned player IDs
## session_ids: Array[String] - Backend session identifiers to validate
func server_validate_player_sessions(
	peer_id: int,
	player_ids: Array[int],
	session_ids: Array
) -> void:
	push_error("SessionProvider.server_validate_player_sessions not implemented")


## SERVER: Set expected total player count for this match.
## count: int - Total players across all peers
func server_set_expected_player_count(count: int) -> void:
	push_error("SessionProvider.server_set_expected_player_count not implemented")


## Returns true if session provider is active (not preview mode).
func is_active() -> bool:
	return false


## Called when provider should clean up (disconnect, etc.).
func cleanup() -> void:
	pass


## SERVER: Get the selected level ID for this game session.
## Returns empty string if no level has been selected yet.
func server_get_selected_level_id() -> StringName:
	return ""
