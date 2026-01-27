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

var _original_collision_layer := 0
var _original_collision_mask := 0

var _has_disabled_inter_player_collisions := false


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

	# Store original collision values for respawn.
	_original_collision_layer = collision_layer
	_original_collision_mask = collision_mask

	# Set up action sources for local mode (lobby).
	# In networked mode, this will be called again from
	# on_match_state_ready(), but _set_up_action_sources() guards against
	# duplicate setup.
	if not G.is_networked_level_active:
		_set_up_action_sources()


func _process(_delta: float) -> void:
	super._process(_delta)
	_update_match_end_collisions()


func _physics_process(_delta: float) -> void:
	super._physics_process(_delta)


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
		# Guard against duplicate setup (expected behavior).
		return

	var local_player_index: int
	var device_config: DeviceConfig

	if G.is_networked_level_active:
		# Networked mode: Get local_player_index from match state.
		var player_match_state := G.get_player_match_state(player_id)
		if not is_instance_valid(player_match_state):
			# Player state not replicated yet.
			return

		# Only set up action sources for local players.
		if G.network.is_server:
			return

		# Only set up action sources for local players.
		if player_match_state.peer_id != G.network.local_peer_id:
			# This player belongs to a different peer.
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
		"Set up action sources for player %d (local_index=%d, device=%s)" % [
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


func server_trigger_death() -> void:
	G.check_is_server()

	# Record death time (this is replicated and drives all derived state).
	state_from_server.last_died_time_usec = G.network.server_time_usec

	# Disable collision and hide.
	is_sprite_visible = false
	collision_layer = 0
	collision_mask = 0

	# Schedule respawn.
	G.time.set_timeout(
		server_execute_respawn,
		G.settings.player_respawn_cooldown_sec
	)

	# Schedule invincibility expiry.
	G.time.set_timeout(
		_server_clear_invincibility,
		G.settings.player_respawn_cooldown_sec + \
			G.settings.player_invincibility_duration_sec
	)


func server_execute_respawn() -> void:
	G.check_is_server()

	if not state_from_server.is_dead:
		return

	# Get level for spawn position.
	if not is_instance_valid(G.level):
		return

	# Re-enable and reposition.
	global_position = G.level._get_player_spawn_position()
	velocity = Vector2.ZERO
	is_sprite_visible = true
	collision_layer = _original_collision_layer
	collision_mask = _original_collision_mask
	_has_disabled_inter_player_collisions = false


func _server_clear_invincibility() -> void:
	G.check_is_server()

	# Clear death time to end invincibility period.
	if state_from_server.last_died_time_usec >= 0:
		state_from_server.last_died_time_usec = -1


func _update_match_end_collisions() -> void:
	if not is_instance_valid(G.match_state):
		return

	var should_disable_collisions := G.match_state.is_match_ended

	if should_disable_collisions and not _has_disabled_inter_player_collisions:
		# Disable inter-player collisions by removing player layer from mask.
		set_collision_mask_value(4, false) # Layer 4 = "player"
		_has_disabled_inter_player_collisions = true
	elif not should_disable_collisions and _has_disabled_inter_player_collisions:
		# Re-enable inter-player collisions.
		set_collision_mask_value(4, true)
		_has_disabled_inter_player_collisions = false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_instance_valid(input_from_client):
		warnings.append("input_from_client is not set")
	if not is_instance_valid(forwarded_input_from_server):
		warnings.append("forwarded_input_from_server is not set")
	return warnings
