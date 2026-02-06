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

	visibility_changed.connect(_on_visibility_changed)

	if visible:
		_initialize()


func _on_visibility_changed() -> void:
	if visible and %States.get_child_count() == 0:
		_initialize()


func _initialize() -> void:
	_on_players_updated()
	if not G.match_state.players_updated.is_connected(_on_players_updated):
		G.match_state.players_updated.connect(_on_players_updated)


func _on_players_updated() -> void:
	for child in %States.get_children():
		child.queue_free()

	if G.match_state.players_by_id.is_empty():
		# No player state to show.
		return

	if G.client_session.local_player_ids.is_empty():
		# Local player IDs not yet assigned.
		return

	# Add local player states first.
	for player_id in G.client_session.local_player_ids:
		if G.match_state.players_by_id.has(player_id):
			_add_player_state(player_id)

	# Add other players.
	for player_id in G.match_state.players_by_id:
		if player_id in G.client_session.local_player_ids:
			# Already added this local player.
			continue
		_add_player_state(player_id)


func _add_player_state(player_id: int) -> void:
	var player_state_panel: PlayerStatePanel = player_state_panel_scene.instantiate()
	player_state_panel.player_id = player_id
	%States.add_child(player_state_panel)
