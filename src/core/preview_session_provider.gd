class_name PreviewSessionProvider
extends SessionProvider
## Preview/local testing session provider (no validation).
##
## Used for local multi-instance testing without GameLift backend.
## Generates debug session IDs and auto-accepts all connections.

## Stand-in session id: preview client number, then local player index.
const _DEBUG_SESSION_ID_FORMAT := "DEBUG_SESSION_C%d_%d"

var logger: NetworkLogger
var config: Dictionary

var _expected_player_count: int = 0
var _validated_player_count: int = 0
var _selected_level_id: StringName = ""
var _player_to_profile_image_url: Dictionary = {}


func _init(p_logger: NetworkLogger, p_config: Dictionary = {}) -> void:
	logger = p_logger
	config = p_config


func is_active() -> bool:
	return false # Not using real backend


func client_request_session_ids(
	player_count: int,
	session_prefs: Dictionary = {},
) -> void:
	var debug_session_ids := make_debug_session_ids(
		_get_instance_number(),
		player_count,
	)

	var server_ip: String = config.get("server_ip", "127.0.0.1")
	var server_port: int = config.get("server_port", 4433)

	# Select level locally based on preferences.
	_selected_level_id = \
		_select_level_locally(session_prefs)

	logger.print(
		"Preview mode: Generated %d debug session ID(s), level: %s" % [
			player_count,
			_selected_level_id if not _selected_level_id.is_empty() else "(default)"
		],
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Defer to next frame for consistent async behavior.
	await Engine.get_main_loop().process_frame

	session_ids_received.emit(
		debug_session_ids,
		server_ip,
		server_port,
		String(_selected_level_id),
		"",
	)


func server_validate_player_sessions(
	_peer_id: int,
	_session_ids: Array,
	_backend_player_id: String = "",
) -> Dictionary:
	return {"accepted": true, "backend_player_ids": []}


func server_commit_player_sessions(
	peer_id: int,
	player_ids: Array[int],
	_session_ids: Array,
	_backend_player_ids: Array,
	profile_image_url: String = "",
	_auth_display_name: String = "",
) -> void:
	logger.print(
		"Preview mode: Auto-accepting %d player(s) for peer %d" % [
			player_ids.size(),
			peer_id
		],
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Store profile image URL for all players.
	if not profile_image_url.is_empty():
		for player_id in player_ids:
			_player_to_profile_image_url[
				player_id] = profile_image_url

	# Auto-accept all sessions without validation.
	for player_id in player_ids:
		player_session_validated.emit(player_id, "")
		_validated_player_count += 1

	# Check if all expected players have connected.
	if _expected_player_count > 0 and \
			_validated_player_count >= _expected_player_count:
		logger.print(
			"Preview mode: All %d players connected" % _expected_player_count,
			NetworkLogger.CATEGORY_CONNECTIONS
		)
		all_players_connected.emit()


func server_set_expected_player_count(count: int) -> void:
	_expected_player_count = count
	_validated_player_count = 0 # Reset counter
	logger.print(
		"Preview mode: Expected player count set to %d" % count,
		NetworkLogger.CATEGORY_CONNECTIONS
	)


func server_get_selected_level_id() -> StringName:
	return _selected_level_id


func get_profile_image_url_map() -> Dictionary:
	return _player_to_profile_image_url


## Returns one stand-in session id per local player. The ids must be
## unique across every client in the match. NetworkConnector maps
## session_id to player_id so that a reconnecting client keeps its
## slot, so two clients sending the same id end up sharing one
## player_id and the second client never gets a bunny. Keying the id
## by the instance number keeps clients apart while staying stable
## across a reconnect of the same client.
static func make_debug_session_ids(
	instance_number: int,
	player_count: int,
) -> Array[String]:
	var session_ids: Array[String] = []
	for local_player_index in range(player_count):
		session_ids.append(
			_DEBUG_SESSION_ID_FORMAT % [instance_number, local_player_index])
	return session_ids


## The --client=N instance number. Falls back to the process id so a
## client launched without --client still mints ids no other client
## shares.
func _get_instance_number() -> int:
	if Netcode.preview_client_number > 0:
		return Netcode.preview_client_number
	return OS.get_process_id()


## Select a level locally based on client preferences.
## In preview mode, this uses simple logic:
## 1. Use preferred level if specified
## 2. Use first level from inclusion list
## 3. Fall back to default level
func _select_level_locally(prefs: Dictionary) -> StringName:
	# Check for preferred level.
	var preferred: String = prefs.get("preferred", "")
	if not preferred.is_empty():
		return StringName(preferred)

	# Check inclusion list.
	var inclusion: Array = prefs.get("inclusion", [])
	if not inclusion.is_empty():
		return StringName(str(inclusion[0]))

	# Return default level ID (will be resolved by GamePanel).
	return ""
