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


func _init() -> void:
	clear()


func clear() -> void:
	is_game_active = false
	is_game_loading = false


func copy_match_state() -> void:
	latest_match_state = G.game_panel.match_state.duplicate()
