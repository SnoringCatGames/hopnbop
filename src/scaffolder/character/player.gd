@tool
class_name Player
extends Character


const _PLAYER_COLLISION_LAYER := 4

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

# Store original collision layers for all Area2D children
# (BodyArea, FootArea, HeadArea).
var _original_area_collision_layers := {}
var _original_area_collision_masks := {}


func _enter_tree() -> void:
	super._enter_tree()
	if Engine.is_editor_hint():
		return
	if Netcode.is_client:
		# On clients, wait for player_id to be replicated before adding
		# to level's players_by_id dictionary.
		state_from_server.player_id_changed.connect(
			_client_on_player_id_replicated,
			CONNECT_ONE_SHOT,
		)
	else:
		# Server sets player_id before adding to tree, so add immediately.
		G.level.register_player(self )


func _client_on_player_id_replicated(new_player_id: int) -> void:
	Netcode.verbose(
		"Player._client_on_player_id_replicated: new_player_id=%d"
			% new_player_id,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	player_id = new_player_id
	G.level.register_player(self )

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
		G.level.deregister_player(self )


func _ready() -> void:
	super._ready()

	update_configuration_warnings()

	if Engine.is_editor_hint():
		return

	# Store original collision values for respawn.
	_original_collision_layer = collision_layer
	_original_collision_mask = collision_mask

	# Store all Area2D collision values (BodyArea, FootArea, HeadArea).
	for area_name in ["%BodyArea", "%FootArea", "%HeadArea"]:
		var area := get_node_or_null(area_name)
		if is_instance_valid(area) and area is Area2D:
			_original_area_collision_layers[area_name] = area.collision_layer
			_original_area_collision_masks[area_name] = area.collision_mask

	# Connect to match end signal.
	if is_instance_valid(G.match_state):
		G.match_state.match_ended.connect(_on_match_ended)

	# Set up action sources for local mode (lobby).
	# In networked mode, this will be called again from
	# on_match_state_ready(), but _set_up_action_sources() guards against
	# duplicate setup.
	if not G.is_networked_level_active:
		_set_up_action_sources()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	super._process(_delta)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	super._physics_process(_delta)


## Called by the server after spawning to initialize player_id and update
## authority on all networked child nodes. Must be called after add_child()
## so that all child nodes are ready and sibling references are established.
func server_initialize_player_id(p_player_id: int) -> void:
	# Set the player_id, which propagates to state_from_server and then
	# to input_from_client and forwarded_input_from_server.
	player_id = p_player_id
	update_authority()

	# If match state was created before this player node
	# was spawned (typical on the server, where
	# MatchStateSynchronizer processes before NetworkedLevel
	# in the peer_players_declared signal chain), notify
	# the player so subclasses can update appearance.
	var player_match_state = (
		G.get_player_match_state(player_id)
	)
	if player_match_state != null:
		on_match_state_ready(player_match_state)

	# Record a SPAWN interaction with authoritative position. This ensures
	# clients receive the correct spawn position before the first frame
	# processes, preventing a visual glitch during match-start countdown
	# where the player appears at the scene default position.
	state_from_server.record_interaction(
		CharacterStateFromServer.ServerInteractionType.SPAWN,
		Netcode.server_frame_index,
		global_position,
		Vector2.ZERO
	)


func update_authority() -> void:
	# Now that player_id is set, update authority on all network nodes.
	# This ensures they calculate the correct peer_id from player_id.
	if is_instance_valid(state_from_server):
		state_from_server.update_authority()
	if is_instance_valid(input_from_client):
		input_from_client.update_authority()
	if is_instance_valid(forwarded_input_from_server):
		forwarded_input_from_server.update_authority()


func on_match_state_ready(_player_match_state: PlayerState) -> void:
	Netcode.print(
		"Player.on_match_state_ready called for player_id=%d" % player_id,
		NetworkLogger.CATEGORY_PLAYER_ACTIONS,
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
		if Netcode.is_server:
			return

		# Only set up action sources for local players.
		if player_match_state.peer_id != Netcode.local_peer_id:
			# This player belongs to a different peer.
			return

		local_player_index = player_match_state.local_player_index
	else:
		# Local mode (lobby): Player IDs are negative (-1, -2, -3, etc.).
		# Convert to local_player_index: -1 -> 0, -2 -> 1, -3 -> 2, etc.
		local_player_index = - (player_id + 1)

	device_config = G.input_device_manager.get_device_for_player(
		local_player_index)
	if not Netcode.ensure(is_instance_valid(device_config),
			"DeviceConfig not registered for player"):
		return

	var player_action_source := PlayerActionSource.new(
		self ,
		true,
		device_config)
	_action_sources.append(player_action_source)

	Netcode.print(
		"Set up action sources for player %d (local_index=%d, device=%s)" % [
			player_id,
			local_player_index,
			device_config.name,
		],
		NetworkLogger.CATEGORY_PLAYER_ACTIONS,
	)


func _process_movement_and_actions() -> void:
	super._process_movement_and_actions()


func get_is_player_control_active() -> bool:
	if G.is_ui_interaction_mode_enabled:
		return false

	# In local mode (lobby), players always have
	# control unless this player has the settings
	# UI open.
	if not G.is_networked_level_active:
		return not (
			G.is_settings_ui_shown
			and G.settings_ui_player == self
		)

	# In networked mode, check multiplayer authority.
	return (
		is_instance_valid(input_from_client)
		and input_from_client.is_multiplayer_authority()
	)


func server_trigger_death() -> void:
	Netcode.check_is_server()

	Netcode.verbose(
		"Player %d triggered death, scheduling respawn in %s sec" % [
			player_id,
			G.settings.player_respawn_cooldown_sec,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	# Pre-calculate respawn position before recording death.
	var death_position := global_position
	var spawn_position := death_position
	if is_instance_valid(G.level):
		spawn_position = G.level._get_player_spawn_position()

	# Record DIE interaction with authoritative state:
	# - Position/velocity set to spawn position (where character moves to)
	# - Interaction position set to death position (for visual effects)
	# This prevents a one-frame visual glitch at respawn time where the player
	# would appear at their death position before being moved to spawn.
	state_from_server.record_death_interaction(
		Netcode.server_frame_index,
		spawn_position,
		death_position
	)

	# Move character to spawn position immediately (while hidden).
	global_position = spawn_position
	velocity = Vector2.ZERO

	# Disable collision and hide.
	is_sprite_visible = false
	collision_layer = 0
	collision_mask = 0

	# Disable all Area2D collisions (BodyArea, FootArea, HeadArea).
	for area_name in _original_area_collision_layers:
		var area := get_node_or_null(area_name)
		if is_instance_valid(area) and area is Area2D:
			area.collision_layer = 0
			area.collision_mask = 0

	Netcode.verbose(
		"Player %d moved to respawn position %s (hidden)" % [
			player_id,
			spawn_position,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	# Schedule respawn.
	Netcode.time.set_timeout(
		server_execute_respawn,
		G.settings.player_respawn_cooldown_sec
	)


func server_execute_respawn() -> void:
	Netcode.check_is_server()

	Netcode.verbose(
		"Player %d respawn timer fired, interaction_type=%d (DIE=%d)" % [
			player_id,
			state_from_server.last_interaction_type,
			CharacterStateFromServer.ServerInteractionType.DIE,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	# Only respawn if player is in DIE state (not already respawned).
	if (state_from_server.last_interaction_type
			!= CharacterStateFromServer
				.ServerInteractionType.DIE):
		Netcode.print(
			"Player %d respawn aborted - not in DIE state" % [
				player_id,
			],
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return

	# Use current position as spawn position (set during death).
	var spawn_position := global_position

	# Record SPAWN interaction (marks frame as authoritative).
	state_from_server.record_interaction(
		CharacterStateFromServer.ServerInteractionType.SPAWN,
		Netcode.server_frame_index,
		spawn_position,
		Vector2.ZERO
	)

	# Re-enable visibility and collision.
	is_sprite_visible = true
	collision_layer = _original_collision_layer
	collision_mask = _original_collision_mask

	# Re-enable all Area2D collisions (BodyArea, FootArea, HeadArea).
	for area_name in _original_area_collision_layers:
		var area := get_node_or_null(area_name)
		if is_instance_valid(area) and area is Area2D:
			area.collision_layer = _original_area_collision_layers[area_name]
			area.collision_mask = _original_area_collision_masks[area_name]

	Netcode.verbose(
		"Player %d respawned at %s" % [
			player_id,
			spawn_position,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)


func set_is_collidable(is_collidable: bool) -> void:
	if is_collidable:
		# Player is alive - show and enable collision.
		if not animator.visible:
			animator.visible = true
		if collision_layer == 0:
			collision_layer = _original_collision_layer
			collision_mask = _original_collision_mask
			# Also restore Area2D children collision.
			for area_name in _original_area_collision_layers:
				var area := get_node_or_null(area_name)
				if is_instance_valid(area) and area is Area2D:
					area.collision_layer = _original_area_collision_layers[area_name]
					area.collision_mask = _original_area_collision_masks[area_name]
	else:
		# Player is dead - hide and disable collision.
		animator.visible = false
		collision_layer = 0
		collision_mask = 0
		# Also disable Area2D children collision.
		for area_name in _original_area_collision_layers:
			var area := get_node_or_null(area_name)
			if is_instance_valid(area) and area is Area2D:
				area.collision_layer = 0
				area.collision_mask = 0


func _on_match_ended() -> void:
	# Disable inter-player collisions by removing player layer from mask.
	set_collision_mask_value(_PLAYER_COLLISION_LAYER, false)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_instance_valid(input_from_client):
		warnings.append("input_from_client is not set")
	if not is_instance_valid(forwarded_input_from_server):
		warnings.append("forwarded_input_from_server is not set")
	return warnings
