class_name PlayerList
extends HBoxContainer

## Horizontal container for all player displays.

# Dictionary<StringName, PlayerDisplay>
var _player_displays := {}

# Preload PlayerDisplay scene.
const PLAYER_DISPLAY_SCENE := preload("res://src/ui/hud/player_display.tscn")


func _ready() -> void:
	# Listen to match state updates.
	if is_instance_valid(G.match_state):
		G.match_state.players_updated.connect(_on_players_updated)
		_refresh_displays()


func _on_players_updated() -> void:
	_refresh_displays()


func _refresh_displays() -> void:
	if not is_instance_valid(G.match_state):
		return

	# Get current player IDs from match state.
	var current_player_ids: Array = G.match_state.players.keys()

	# Remove displays for players that no longer exist.
	var player_ids_to_remove: Array = []
	for player_id in _player_displays.keys():
		if not current_player_ids.has(player_id):
			player_ids_to_remove.append(player_id)

	for player_id in player_ids_to_remove:
		var display: PlayerDisplay = _player_displays[player_id]
		_player_displays.erase(player_id)
		display.queue_free()

	# Add displays for new players.
	for player_id in current_player_ids:
		if not _player_displays.has(player_id):
			var display: PlayerDisplay = PLAYER_DISPLAY_SCENE.instantiate()
			display.set_player_id(player_id)
			_player_displays[player_id] = display
			add_child(display)

	# Sort displays (local players first).
	_sort_displays()


func _sort_displays() -> void:
	# Get local peer ID.
	var local_peer_id := G.network.local_peer_id

	# Separate local and remote players.
	var local_displays: Array[PlayerDisplay] = []
	var remote_displays: Array[PlayerDisplay] = []

	for player_id in _player_displays.keys():
		var display: PlayerDisplay = _player_displays[player_id]
		var player_match_state := G.get_player_match_state(player_id)
		if player_match_state and player_match_state.peer_id == local_peer_id:
			local_displays.append(display)
		else:
			remote_displays.append(display)

	# Reorder children: local players first, then remote.
	for display in local_displays:
		move_child(display, 0)
