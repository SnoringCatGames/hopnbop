class_name PlayerList
extends BoxContainer
## Horizontal container for all player displays.


# Dictionary<int, PlayerDisplay>
var _player_displays := {}

# Dictionary<String user_id, PlayerDisplay> — display-only nameplates
# for remote party members shown in the lobby (they have no local
# spawned player).
var _party_member_displays := {}

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
	# Refresh the remote-party-member nameplates when party
	# membership changes (join / leave / kick / leader transfer).
	if is_instance_valid(G.party_manager):
		G.party_manager.party_updated.connect(
			_on_party_updated)
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

	_update_party_member_displays()


func _on_party_updated(_party_data: Dictionary) -> void:
	_update_party_member_displays()


## Show display-only nameplates for the OTHER active party members
## (remote accounts) while in the lobby, so a party sees each other
## before the match. In a match those members are real match players
## and already appear via the normal path. Self (covered by the local
## player displays) and pending invitees are excluded.
func _update_party_member_displays() -> void:
	var wanted := {}
	if (G.is_lobby_active
			and is_instance_valid(G.party_manager)
			and G.party_manager.is_in_party()):
		var self_id: String = Platform.token_store.player_id
		for m in G.party_manager.current_party.get("members", []):
			if not (m is Dictionary):
				continue
			var uid: String = m.get("user_id", "")
			if uid.is_empty() or uid == self_id:
				continue
			if m.get("role", "") == "invited":
				continue
			wanted[uid] = m

	# Drop displays for members no longer present.
	for uid in _party_member_displays.keys():
		if not wanted.has(uid):
			_party_member_displays[uid].queue_free()
			_party_member_displays.erase(uid)

	# Add / refresh.
	for uid in wanted:
		var display: PlayerDisplay
		if _party_member_displays.has(uid):
			display = _party_member_displays[uid]
		else:
			display = _player_display_scene.instantiate()
			_party_member_displays[uid] = display
			add_child(display)
		display.set_party_member(wanted[uid])


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
