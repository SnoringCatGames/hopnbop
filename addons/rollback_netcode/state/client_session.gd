class_name LocalSession
extends RefCounted

var is_game_active := false
var is_game_loading := false

var latest_match_state := MatchState.new()
var latest_local_device_configs: Array[DeviceConfig] = []
var latest_local_player_ids: Array[int] = []

## Number of local players on this client.
var local_player_count: int:
	get:
		return local_device_configs.size()

## Device configurations for each local player.
## Array index corresponds to local_player_index.
var local_device_configs: Array[DeviceConfig] = []

## GameLift player session IDs from backend matchmaking.
## Array index corresponds to local_player_index.
var local_session_ids: Array[String] = []

var local_player_ids: Array[int] = []

## Client-generated player attributes to send to server during connection.
## Array index corresponds to local_player_index.
var local_player_attributes: Array[Dictionary] = []

## Message from server (e.g., shutdown notification) to display on game over
## screen.
var latest_server_message := ""


func _init() -> void:
	clear()


## Validates that session IDs are properly populated.
## Returns true if local_session_ids array matches player count and contains no empty
## strings.
func has_valid_local_session_ids() -> bool:
	if local_session_ids.size() != local_device_configs.size():
		return false
	for session_id in local_session_ids:
		if session_id.is_empty():
			return false
	return true


func clear() -> void:
	is_game_active = false
	is_game_loading = false
	local_session_ids.clear()
	local_device_configs.clear()
	local_player_ids.clear()
	local_player_attributes.clear()


func clear_latest_state() -> void:
	latest_match_state.clear()
	latest_local_device_configs.clear()
	latest_local_player_ids.clear()
	latest_server_message = ""


## Copy current state into latest_* properties.
## Consumers should call this with their current match_state.
func copy_latest_state(match_state: MatchState) -> void:
	latest_match_state = match_state.duplicate()
	latest_local_device_configs = local_device_configs.duplicate()
	latest_local_player_ids = local_player_ids.duplicate()
