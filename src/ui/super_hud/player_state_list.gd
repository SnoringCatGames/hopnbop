class_name PlayerStateList
extends PanelContainer

@export var player_state_panel_scene: PackedScene


func _enter_tree() -> void:
	if Netcode.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return


func _ready() -> void:
	if Netcode.is_server:
		return

	visibility_changed.connect(
		_on_visibility_changed)

	if visible:
		_initialize()


func _on_visibility_changed() -> void:
	if visible and %States.get_child_count() == 0:
		_initialize()


func _initialize() -> void:
	_rebuild_panels()
	if not (G.match_state.players_updated
			.is_connected(_rebuild_panels)):
		G.match_state.players_updated.connect(
			_rebuild_panels)
	if (
		is_instance_valid(G.game_panel)
		and not (G.game_panel
			.lobby_players_updated
			.is_connected(_rebuild_panels))
	):
		G.game_panel.lobby_players_updated.connect(
			_rebuild_panels
		)


func _rebuild_panels() -> void:
	for child in %States.get_children():
		child.queue_free()

	# Networked match path.
	if (
		not G.match_state.players_by_id
			.is_empty()
		and not G.client_session
			.local_player_ids.is_empty()
	):
		# Add local player states first.
		for player_id in (
				G.client_session.local_player_ids):
			if G.match_state.players_by_id.has(player_id):
				_add_player_state(player_id)

		# Add other players.
		for player_id in (
				G.match_state.players_by_id):
			if (player_id in G.client_session
					.local_player_ids):
				continue
			_add_player_state(player_id)
		return

	# Lobby fallback: use level's player list directly.
	if is_instance_valid(G.level):
		for player_id in G.level.players_by_id:
			_add_player_state(player_id)


func _add_player_state(player_id: int) -> void:
	var player_state_panel: PlayerStatePanel = (
		player_state_panel_scene.instantiate())
	player_state_panel.player_id = player_id
	%States.add_child(player_state_panel)
