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
## server_ip: String - Server IP address (used for ENet/native UDP)
## server_port: int - Server port (TCP for WS/WebRTC, UDP for ENet)
## selected_level_id: String - Level ID selected by server/backend (may be empty)
## signaling_url: String - Pre-built wss:// URL for WebRTC/WS signaling
##     when the backend fronts the deploy with a stable proxy (see
##     snoringcat-platform's signaling-proxy). Empty when the backend
##     wants the client to construct the URL from server_ip/_port.
signal session_ids_received(
	session_ids: Array,
	server_ip: String,
	server_port: int,
	selected_level_id: String,
	signaling_url: String,
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

## Emitted during matchmaking to report progress.
## phase: String - Current phase
##     (e.g., "searching", "placing").
## elapsed_sec: float - Seconds since matchmaking
##     started.
## estimated_total_sec: float - Estimated total wait
##     time. Negative if unknown.
signal matchmaking_progress_updated(
	phase: String,
	elapsed_sec: float,
	estimated_total_sec: float,
)

## Emitted when the hosting service requests process termination.
## seconds_remaining: float - Approximate seconds until forced
## termination. Zero if unknown.
signal shutdown_requested(seconds_remaining: float)


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


## SERVER: Vet session IDs for a connecting peer before the
## connector assigns player ids (H41). Returns a Dictionary:
## "accepted" (bool) and "backend_player_ids" (Array of String,
## one derived backend id per session id; empty when the provider
## cannot derive them and the declared id stands). A provider
## that implements server_commit_player_sessions gets this gate;
## the connector disconnects a rejected peer without assigning,
## sending, or announcing any player id.
func server_validate_player_sessions(
	peer_id: int,
	session_ids: Array,
	backend_player_id: String = "",
) -> Dictionary:
	push_error("SessionProvider.server_validate_player_sessions not implemented")
	return {"accepted": false, "backend_player_ids": []}


## SERVER: Record sessions that passed validation, once the
## connector has assigned player ids. backend_player_ids carries
## the per-player ids derived during validation (may be empty).
func server_commit_player_sessions(
	peer_id: int,
	player_ids: Array[int],
	session_ids: Array,
	backend_player_ids: Array,
	profile_image_url: String = "",
	_auth_display_name: String = "",
) -> void:
	push_error("SessionProvider.server_commit_player_sessions not implemented")


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
