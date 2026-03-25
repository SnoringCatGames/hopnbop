class_name PlayerList
extends BoxContainer
## Horizontal container for all player displays.


# Dictionary<int, PlayerDisplay>
var _player_displays := {}

@export var _player_display_scene: PackedScene

const _MAX_PLAYER_LIST_SIZE := 8


func _ready() -> void:
	if Netcode.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	# Wait a frame, so we know GamePanel is rendered.
	await get_tree().process_frame

	# Listen to match state updates.
	G.match_state.players_updated.connect(_update_displays)
	G.game_panel.lobby_players_updated.connect(
		_update_displays)
	_update_displays()


func _update_displays() -> void:
	var current_player_ids: Array[int] = _get_current_player_ids()

	# Remove displays for players that no longer exist.
	var player_ids_to_remove: Array = []
	for player_id in _player_displays.keys():
		if not current_player_ids.has(player_id):
			player_ids_to_remove.append(player_id)

	for player_id in player_ids_to_remove:
		var display: PlayerDisplay = (
			_player_displays[player_id])
		_player_displays.erase(player_id)
		display.queue_free()

	# Add displays for new players.
	for player_id in current_player_ids:
		if not _player_displays.has(player_id):
			var display: PlayerDisplay = (
				_player_display_scene.instantiate())
			display.set_player_id(player_id)
			_player_displays[player_id] = display
			add_child(display)


func _get_current_player_ids() -> Array[int]:
	if (not is_instance_valid(G.match_state)
			or not is_instance_valid(G.level)):
		return []

	if G.is_lobby_active:
		return _get_current_player_ids_from_lobby()
	elif G.is_networked_level_active:
		return _get_current_player_ids_from_match_level()
	else:
		return []


func _get_current_player_ids_from_lobby(
) -> Array[int]:
	var lobby := G.level as LobbyLevel
	return lobby.get_registered_player_ids()


func _get_current_player_ids_from_match_level(
) -> Array[int]:
	var all_player_ids: Array = (
		G.match_state.players_by_id.keys())
	var local_player_ids: Array[int] = (
		G.client_session.local_player_ids)

	# Separate remote players by checking
	# ownership directly.
	var remote_player_ids: Array[int] = []
	for player_id in all_player_ids:
		if not local_player_ids.has(player_id):
			remote_player_ids.append(player_id)

	# If there are more than 8 players in the
	# match, only local players will be listed.
	if (local_player_ids.size()
			+ all_player_ids.size()
			> _MAX_PLAYER_LIST_SIZE):
		# TODO: Add support for also showing
		#       the top-N other players in the
		#       match.
		#var max_remote_players := (
		#	_MAX_PLAYER_LIST_SIZE
		#	- local_player_ids.size())
		all_player_ids = local_player_ids

	# List local players first.
	var sorted_ids := local_player_ids.duplicate()
	sorted_ids.append_array(remote_player_ids)

	return sorted_ids
