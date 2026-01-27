@tool
class_name Player
extends Character


@export var input_from_client: PlayerInputFromClient:
	set(value):
		input_from_client = value
		update_configuration_warnings()

@export var forwarded_input_from_server: ForwardedPlayerInputFromServer:
	set(value):
		forwarded_input_from_server = value
		update_configuration_warnings()

var player_id: int:
	set(value):
		state_from_server.player_id = value
	get:
		return state_from_server.player_id


func _enter_tree() -> void:
	super._enter_tree()
	if Engine.is_editor_hint():
		return
	if G.network.is_client:
		# On clients, wait for player_id to be replicated before adding
		# to level's players_by_id dictionary.
		state_from_server.player_id_changed.connect(
			_client_on_player_id_replicated,
			CONNECT_ONE_SHOT,
		)
	else:
		# Server sets player_id before adding to tree, so add immediately.
		G.level.register_player(self)


func _client_on_player_id_replicated(new_player_id: int) -> void:
	G.print(
		"Player._client_on_player_id_replicated: new_player_id=%d" %
			new_player_id,
		ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
		ScaffolderLog.Verbosity.VERBOSE,
	)

	player_id = new_player_id
	G.level.register_player(self)

	# Now that the player is registered, call on_match_state_ready.
	# This triggers action source setup for networked mode.
	if G.is_networked_level_active:
		var player_match_state := G.get_player_match_state(player_id)
		if is_instance_valid(player_match_state):
			on_match_state_ready(player_match_state)


func _exit_tree() -> void:
	super._exit_tree()
	if Engine.is_editor_hint():
		return
	if is_instance_valid(G.level):
		G.level.deregister_player(self)


func _ready() -> void:
	super._ready()

	update_configuration_warnings()

	if Engine.is_editor_hint():
		return

	# Set up action sources for local mode (lobby).
	# In networked mode, this will be called again from
	# on_match_state_ready(), but _set_up_action_sources() guards against
	# duplicate setup.
	if not G.is_networked_level_active:
		_set_up_action_sources()


## Called by the server after spawning to initialize player_id and update
## authority on all networked child nodes. Must be called after add_child()
## so that all child nodes are ready and sibling references are established.
func server_initialize_player_id(p_player_id: int) -> void:
	# Set the player_id, which propagates to state_from_server and then
	# to input_from_client and forwarded_input_from_server.
	player_id = p_player_id
	update_authority()


func update_authority() -> void:
	# Now that player_id is set, update authority on all network nodes.
	# This ensures they calculate the correct peer_id from player_id.
	if is_instance_valid(state_from_server):
		state_from_server.update_authority()
	if is_instance_valid(input_from_client):
		input_from_client.update_authority()
	if is_instance_valid(forwarded_input_from_server):
		forwarded_input_from_server.update_authority()


func on_match_state_ready(_player_match_state: PlayerMatchState) -> void:
	G.print(
		"Player.on_match_state_ready called for player_id=%d" % player_id,
		ScaffolderLog.CATEGORY_PLAYER_ACTIONS,
	)
	_set_up_action_sources()


func _set_up_action_sources() -> void:
	if not _action_sources.is_empty():
		G.warning(
			"Player._set_up_action_sources: Already set up (player_id=%d)" % player_id,
			ScaffolderLog.CATEGORY_PLAYER_ACTIONS,
		)
		return

	var local_player_index: int
	var device_config: DeviceConfig

	if G.is_networked_level_active:
		# Networked mode: Get local_player_index from match state.
		var player_match_state := G.get_player_match_state(player_id)
		if not is_instance_valid(player_match_state):
			# Player state not replicated yet.
			G.warning(
				"Player._set_up_action_sources: Match state not ready (player_id=%d)" % player_id,
				ScaffolderLog.CATEGORY_PLAYER_ACTIONS,
			)
			return

		# Only set up action sources for local players.
		if G.network.is_server:
			return

		# Only set up action sources for local players.
		if player_match_state.peer_id != G.network.local_peer_id:
			# This player belongs to a different peer.
			G.warning(
				("Player._set_up_action_sources: Not local client " +
				"(player_id=%d, peer_id=%d, local_peer_id=%d)") % [
					player_id,
					player_match_state.peer_id,
					G.network.local_peer_id
				],
				ScaffolderLog.CATEGORY_PLAYER_ACTIONS,
			)
			return

		local_player_index = player_match_state.local_player_index
	else:
		# Local mode (lobby): Player IDs are negative (-1, -2, -3, etc.).
		# Convert to local_player_index: -1 -> 0, -2 -> 1, -3 -> 2, etc.
		local_player_index = - (player_id + 1)

	device_config = G.input_device_manager.get_device_for_player(
		local_player_index)
	if not G.ensure(is_instance_valid(device_config),
			"DeviceConfig not registered for player"):
		return

	var player_action_source := PlayerActionSource.new(
		self,
		true,
		device_config)
	_action_sources.append(player_action_source)

	G.print(
		"Set up action sources for player %d (local_idx=%d, device=%s)" % [
			player_id,
			local_player_index,
			device_config.name,
		],
		ScaffolderLog.CATEGORY_PLAYER_ACTIONS,
	)


func _process_movement_and_actions() -> void:
	super._process_movement_and_actions()


func get_is_player_control_active() -> bool:
	# In local mode (lobby), players always have control.
	if not G.is_networked_level_active:
		return true

	# In networked mode, check multiplayer authority.
	return (
		is_instance_valid(input_from_client) and
		input_from_client.is_multiplayer_authority()
	)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_instance_valid(input_from_client):
		warnings.append("input_from_client is not set")
	if not is_instance_valid(forwarded_input_from_server):
		warnings.append("forwarded_input_from_server is not set")
	return warnings
