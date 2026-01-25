class_name LocalSession
extends RefCounted

var is_game_active := false
var is_game_loading := false

var latest_match_state := MatchState.new()

## Number of local players on this client.
var local_player_count: int:
	get:
		return device_configs.size()

## Device configurations for each local player.
## Array index corresponds to local_player_index.
var device_configs: Array[DeviceConfig] = []

## GameLift player session IDs from backend matchmaking.
## Array index corresponds to local_player_index.
var session_ids: Array[String] = []


func _init() -> void:
	clear()


## Validates that session IDs are properly populated.
## Returns true if session_ids array matches player count and contains no empty
## strings.
func has_valid_session_ids() -> bool:
	if session_ids.size() != device_configs.size():
		return false
	for session_id in session_ids:
		if session_id.is_empty():
			return false
	return true


func clear() -> void:
	is_game_active = false
	is_game_loading = false
	session_ids.clear()
	device_configs.clear()


func copy_match_state() -> void:
	latest_match_state = G.game_panel.match_state.duplicate()
