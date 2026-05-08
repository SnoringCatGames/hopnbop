class_name LocalOnlySessionProvider
extends SessionProvider
## Session provider for offline local-only mode.
##
## Used when the client falls back to local play
## (matchmaking timeout with 2+ players) or when the
## user explicitly enables offline mode. Generates
## debug session IDs and auto-accepts all connections.


var _expected_player_count: int = 0
var _validated_player_count: int = 0
var _selected_level_id: StringName = ""
var _player_to_profile_image_url: Dictionary = {}
var _player_to_display_name: Dictionary = {}


func is_active() -> bool:
	return false


func client_request_session_ids(
	player_count: int,
	session_prefs: Dictionary = {},
) -> void:
	var debug_session_ids: Array[String] = []
	for i in range(player_count):
		debug_session_ids.append(
			"LOCAL_SESSION_%d" % i)

	_selected_level_id = (
		_select_level_locally(session_prefs))

	Netcode.print(
		"Local mode: Generated %d session ID(s),"
		+ " level: %s" % [
			player_count,
			_selected_level_id
			if not _selected_level_id.is_empty()
			else "(default)"],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	# Defer to next frame for consistent async
	# behavior.
	await Engine.get_main_loop().process_frame

	session_ids_received.emit(
		debug_session_ids,
		"",
		0,
		String(_selected_level_id),
		"",
	)


func server_validate_player_sessions(
	peer_id: int,
	player_ids: Array[int],
	_session_ids: Array,
	_backend_player_id: String = "",
	profile_image_url: String = "",
	auth_display_name: String = "",
) -> void:
	Netcode.print(
		"Local mode: Auto-accepting"
		+ " %d player(s) for peer %d" % [
			player_ids.size(), peer_id],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	if not profile_image_url.is_empty():
		for player_id in player_ids:
			_player_to_profile_image_url[
				player_id] = profile_image_url

	if not auth_display_name.is_empty():
		for player_id in player_ids:
			_player_to_display_name[
				player_id] = auth_display_name

	for player_id in player_ids:
		player_session_validated.emit(
			player_id, "")
		_validated_player_count += 1

	if (_expected_player_count > 0
			and _validated_player_count
				>= _expected_player_count):
		Netcode.print(
			"Local mode: All %d players"
			+ " connected"
			% _expected_player_count,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		all_players_connected.emit()


func server_set_expected_player_count(
	count: int,
) -> void:
	_expected_player_count = count
	_validated_player_count = 0
	Netcode.print(
		"Local mode: Expected player count"
		+ " set to %d" % count,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


func server_get_selected_level_id() -> StringName:
	return _selected_level_id


func get_profile_image_url_map() -> Dictionary:
	return _player_to_profile_image_url


func get_display_name_map() -> Dictionary:
	return _player_to_display_name


## Select a level locally based on client
## preferences.
func _select_level_locally(
	prefs: Dictionary,
) -> StringName:
	var preferred: String = prefs.get(
		"preferred", "")
	if not preferred.is_empty():
		return StringName(preferred)

	var inclusion: Array = prefs.get(
		"inclusion", [])
	if not inclusion.is_empty():
		return StringName(str(inclusion[0]))

	return ""
