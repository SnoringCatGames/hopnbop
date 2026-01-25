class_name LocalSession
extends RefCounted

var is_game_active := false
var is_game_loading := false

var latest_match_state := MatchState.new()

## Number of local players on this client.
var local_player_count: int:
	get:
		return device_configs.size()

## Composite player IDs for all local players ("peer_id:local_index").
## Populated after connection when peer_id is known.
var local_player_ids: Array[StringName] = []

## Device configurations for each local player.
## Array index corresponds to local_player_index.
var device_configs: Array[DeviceConfig] = []

## GameLift player session IDs from matchmaking (one per player).
## Used for connection validation when connecting to GameLift servers.
var player_session_ids: Array[StringName] = []

## Deprecated: Single player session ID (backward compatibility).
## Use player_session_ids instead for multi-player support.
var player_session_id: StringName:
	get:
		return player_session_ids[0] if player_session_ids.size() > 0 else ""
	set(value):
		player_session_ids = [value]


func _init() -> void:
	clear()


func clear() -> void:
	is_game_active = false
	is_game_loading = false


func copy_match_state() -> void:
	latest_match_state = G.game_panel.match_state.duplicate()
