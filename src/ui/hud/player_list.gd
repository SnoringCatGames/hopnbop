class_name PlayerList
extends HBoxContainer
## Horizontal container for all player displays.


# Dictionary<int, PlayerDisplay>
var _player_displays := {}

# Preload PlayerDisplay scene.
const PLAYER_DISPLAY_SCENE := preload("res://src/ui/hud/player_display.tscn")

const _MAX_PLAYER_LIST_SIZE := 8


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

	var current_player_ids: Array[int] = _get_current_player_ids()

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


func _get_current_player_ids() -> Array[int]:
	# Get current player IDs from match state.
	var current_player_ids: Array = G.match_state.players_by_id.keys()

	# Sort and filter the player IDs.
	# - The local player IDs should be listed first, sorted by
	#   local_player_index.
	# - If there are more than 8 players in the match, only the 4 other highest
	#   scoring players should be listed.
	var local_player_ids: Array[int] = G.level.players_by_id.keys()
	local_player_ids.sort_custom(func(a: int, b: int) -> bool:
		return (
			G.network.get_local_player_index_from_player_id(a) <
			G.network.get_local_player_index_from_player_id(b)
		)
	)
	for local_player_id in local_player_ids:
		current_player_ids.erase(local_player_id)

	if local_player_ids.size() + current_player_ids.size() > _MAX_PLAYER_LIST_SIZE:
		# Sort by score (highest first) and slice to fit remaining slots.
		# FIXME: Add support for getting the current score of a player
		#        (kills - deaths + a tiny bit for bumps).
		#current_player_ids.sort_custom(func(a: int, b: int) -> bool:
			#var state_a := G.get_player_match_state(a)
			#var state_b := G.get_player_match_state(b)
			#var score_a := state_a.score if state_a else 0
			#var score_b := state_b.score if state_b else 0
			#return score_a > score_b
		#)
		var max_remote_players := _MAX_PLAYER_LIST_SIZE - local_player_ids.size()
		current_player_ids = current_player_ids.slice(0, max_remote_players)

	local_player_ids.append_array(current_player_ids)
	current_player_ids = local_player_ids

	return current_player_ids


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
