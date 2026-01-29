@tool
class_name CharacterStateFromServer
extends ReconcilableNetworkedState

## Server-authoritative interaction types (server controls timing).
enum ServerInteractionType {
	NONE,
	SPAWN,
	BUMP,
	KILL,
	DIE,
}

@export var character: Character:
	set(value):
		character = value
		update_configuration_warnings()

var is_authority_for_state_from_server: bool:
	get:
		return is_multiplayer_authority()

var is_authority_for_input_from_client: bool:
	get:
		return is_instance_valid(input_from_client) and input_from_client.is_multiplayer_authority()

var position := Vector2.ZERO
var velocity := Vector2.ZERO
## A bitmask representing the player's surface state.
var surfaces := 0

var is_dead: bool:
	get:
		if last_interaction_type != ServerInteractionType.DIE or \
			last_interaction_frame_index < 0:
			return false
		var respawn_frame: int = last_interaction_frame_index + \
			int(G.settings.player_respawn_cooldown_sec * 60)
		return G.network.server_frame_index < respawn_frame

var is_invincible: bool:
	get:
		if last_interaction_type != ServerInteractionType.DIE or \
			last_interaction_frame_index < 0:
			return false
		var invincibility_end_frame: int = last_interaction_frame_index + \
			int((G.settings.player_respawn_cooldown_sec + \
				G.settings.player_invincibility_duration_sec) * 60)
		return G.network.server_frame_index < invincibility_end_frame

const _synced_properties_and_rollback_diff_thresholds := {
	position = DEFAULT_POSITION_DIFF_ROLLBACK_THRESHOLD,
	velocity = DEFAULT_VELOCITY_DIFF_ROLLBACK_THRESHOLD,
	surfaces = 0,
	last_interaction_type = 0,
	last_interaction_frame_index = 0,
	last_interaction_position = 0.01,
	last_interaction_direction = 0.01,
}


func _get_default_values() -> Array:
	return [
		Vector2.ZERO, # position
		Vector2.ZERO, # velocity
		0, # surfaces
		ServerInteractionType.NONE, # last_interaction_type
		-1, # last_interaction_frame_index
		Vector2.ZERO, # last_interaction_position
		Vector2.ZERO, # last_interaction_direction
	]


func _get_is_server_authoritative() -> bool:
	return true


func _should_accept_predicted_states() -> bool:
	# Accept PREDICTED server states on clients to stay synced with
	# server's predicted trajectory. This reduces snap-back when
	# AUTHORITATIVE states arrive, since the client's prediction is
	# already close to the server's. Remote clients especially need this
	# since they only see forwarded input.
	return G.network.is_client


func _ready() -> void:
	super._ready()
	update_configuration_warnings()
	if Engine.is_editor_hint():
		return
	record_initial_state()


func _update_replication_config() -> void:
	super._update_replication_config()

	# Also sync the player_id, so the client can know which player has
	# authority.
	var player_id_path := "%s:player_id" % root.get_path_to(self)
	if not replication_config.has_property(player_id_path):
		replication_config.add_property(player_id_path)
		replication_config.property_set_replication_mode(
			player_id_path,
			SceneReplicationConfig.ReplicationMode.REPLICATION_MODE_ON_CHANGE,
		)
		replication_config.property_set_spawn(player_id_path, true)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := super._get_configuration_warnings()
	if not is_instance_valid(character):
		warnings.append("character is not set")
	return warnings


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if not G.ensure_valid(character):
		return

	# Only handle local mode here; networked mode uses _network_process().
	if G.is_networked_level_active:
		return

	# Local mode: Update character directly without networking.
	_process_local_mode()


func _process_local_mode() -> void:
	# Collect input from local player.
	character._collect_actions()

	# Apply movement (includes surfaces.update_touches()).
	character._apply_movement()

	# Process animations, sounds, etc.
	character._process_movement_and_actions()

	# Sync state (for consistency with networked path).
	_sync_from_scene_state()

	# Update previous state for next frame's just_* checks.
	character.actions.previous_bitmask = character.actions.bitmask
	character.surfaces.previous_bitmask = character.surfaces.bitmask


func _network_process() -> void:
	if not G.ensure_valid(character):
		return

	# Reconcile server interactions.
	_reconcile_server_interaction()

	# Determine which input source to use.
	# - Server and owning client: use PlayerInputFromClient (client-authoritative)
	# - Remote clients viewing other players: use ForwardedPlayerInputFromServer (server-authoritative)
	var is_remote_player_on_client := (
		not is_authority_for_state_from_server and
		not is_authority_for_input_from_client
	)
	var input_source: ReconcilableNetworkedState
	if is_remote_player_on_client:
		input_source = forwarded_input_from_server
	else:
		input_source = input_from_client

	if not G.ensure_valid(input_source):
		if G.is_verbose:
			G.print(
				"F:%d input_source is null! (is_remote=%s, has_forwarded=%s, has_input=%s)" % [
					G.network.server_frame_index,
					is_remote_player_on_client,
					forwarded_input_from_server != null,
					input_from_client != null,
				],
				ScaffolderLog.CATEGORY_NETWORK_SYNC,
			)
		return

	# Handle actions (from a client).
	var has_auth_input := input_source._has_authoritative_state_for_current_frame()

	# Check if we should use predicted input at current frame. Only use it if
	# we don't have fresher authoritative input at the previous frame to
	# extrapolate from. This prevents using stale predictions during rollback
	# re-simulation (e.g., when authoritative actions=0 arrives at frame N, we
	# should extrapolate from N to get N+1, not use old predicted actions=1 at
	# N+1).
	var should_use_predicted_input := false
	if (
		input_source is ForwardedPlayerInputFromServer and
		input_source._rollback_buffer.has_at(timestamp_index)
	):
		# Check if previous frame has authoritative input source data.
		var prev_frame_is_auth := false
		if input_source._rollback_buffer.has_at(timestamp_index - 1):
			var prev_frame_state: Array = input_source._rollback_buffer.get_at(
				timestamp_index - 1
			)
			if prev_frame_state != null:
				prev_frame_is_auth = input_source._is_frame_authoritative(prev_frame_state)

		# Only use predicted input if previous frame doesn't have authoritative
		# data to extrapolate from.
		should_use_predicted_input = not prev_frame_is_auth

	if has_auth_input or should_use_predicted_input:
		# Use received input from buffer (either authoritative from
		# PlayerInputFromClient, or predicted from ForwardedPlayerInputFromServer).
		input_source._unpack_buffer_state(timestamp_index)
		# Copy input from source to character.
		_apply_input_to_character(input_source)
		# Update surface attachment state based on the input we just loaded.
		character.surfaces.update_actions()
		if G.is_verbose:
			var authority_str := "PREDICTED" if should_use_predicted_input else "AUTHORITATIVE"
			G.print(
				"F:%d Using %s input (actions=%d)" % [
					G.network.server_frame_index,
					authority_str,
					character.actions.bitmask,
				],
				ScaffolderLog.CATEGORY_NETWORK_SYNC,
				ScaffolderLog.Verbosity.VERBOSE,
			)
	else:
		if is_authority_for_input_from_client:
			# This client controls input - capture it now as authoritative.
			# _collect_actions() will call surfaces.update_actions() internally.
			character._collect_actions()
			input_from_client.frame_authority = FrameAuthority.AUTHORITATIVE
		else:
			# No new input yet - extrapolate from previous frame's input.
			# This is intentional: predicted input uses the last known state
			# (N-1) to simulate frame N, while authoritative input that arrives
			# later will be at frame N.
			input_source._unpack_buffer_state(timestamp_index - 1)
			# Copy input from source to character.
			_apply_input_to_character(input_source)
			input_source.frame_authority = FrameAuthority.PREDICTED
			# Update surface attachment state based on the input we just loaded.
			character.surfaces.update_actions()
			if G.is_verbose:
				G.print(
					"F:%d Extrapolating input from prev frame (actions=%d)" % [
						G.network.server_frame_index,
						character.actions.bitmask,
					],
					ScaffolderLog.CATEGORY_NETWORK_SYNC,
				)

	# Forward input from PlayerInputFromClient to
	# ForwardedPlayerInputFromServer.
	if (
		is_authority_for_state_from_server and
		is_instance_valid(forwarded_input_from_server) and
		is_instance_valid(input_from_client)
	):
		forwarded_input_from_server.actions = input_from_client.actions
		forwarded_input_from_server.last_interaction_type = (
			input_from_client.last_interaction_type
		)
		forwarded_input_from_server.last_interaction_frame_index = (
			input_from_client.last_interaction_frame_index
		)
		forwarded_input_from_server.last_interaction_position = (
			input_from_client.last_interaction_position
		)
		forwarded_input_from_server.last_interaction_direction = (
			input_from_client.last_interaction_direction
		)
		forwarded_input_from_server.frame_authority = (
			input_from_client.frame_authority
		)
		if G.is_verbose and input_from_client.actions != 0:
			G.print(
				"F:%d Forwarding input to remote clients (actions=%d)" % [
					G.network.server_frame_index,
					forwarded_input_from_server.actions,
				],
				ScaffolderLog.CATEGORY_NETWORK_SYNC,
			)

	# Handle scene state (from the server).
	if is_authority_for_state_from_server:
		# The server processes movement. Mark as authoritative only if we have
		# authoritative input, otherwise mark as predicted to avoid overriding
		# client predictions with server extrapolations.
		character._apply_movement()
		frame_authority = input_from_client.frame_authority
	else:
		# Client: always re-simulate movement based on current input.
		# Don't unpack authoritative state from buffer, because it may be
		# stale if ForwardedPlayerInputFromServer reconciled input (e.g., jump)
		# after the server computed this state. Re-simulation ensures the
		# character's position matches the reconciled input.
		var pos_before := character.position
		var vel_before := character.velocity
		character._apply_movement()
		frame_authority = FrameAuthority.PREDICTED
		if G.is_verbose and (
			character.position.distance_to(pos_before) > 0.1 or
			character.velocity.distance_to(vel_before) > 0.1
		):
			G.print(
				("F:%d Remote simulation: pos %s->%s, vel %s->%s, " +
				"actions=%d") % [
					G.network.server_frame_index,
					pos_before,
					character.position,
					vel_before,
					character.velocity,
					character.actions.bitmask,
				],
				ScaffolderLog.CATEGORY_NETWORK_SYNC,
			)

	character._process_movement_and_actions()

	super._network_process()


func _sync_to_scene_state(previous_state: Array) -> void:
	if not G.ensure_valid(character):
		return

	if G.is_verbose and not is_authority_for_state_from_server:
		var pos_before := character.position
		var will_change := position.distance_to(pos_before) > 0.1
		if will_change:
			G.print(
				"F:%d _sync_to_scene_state: char pos %s->%s (rollback)" % [
					G.network.server_frame_index,
					pos_before,
					position,
				],
				ScaffolderLog.CATEGORY_NETWORK_SYNC,
			)

	character.position = position
	character.velocity = velocity
	character.surfaces.bitmask = surfaces

	character.previous_position = previous_state[_property_name_to_pack_index.position]
	character.previous_velocity = previous_state[_property_name_to_pack_index.velocity]
	character.surfaces.previous_bitmask = previous_state[_property_name_to_pack_index.surfaces]


func _sync_from_scene_state() -> void:
	if not G.ensure_valid(character):
		return

	position = character.position
	velocity = character.velocity
	surfaces = character.surfaces.bitmask


func _apply_input_to_character(input_source: ReconcilableNetworkedState) -> void:
	# Copy input from PlayerInputFromClient or ForwardedPlayerInputFromServer
	# to the character.
	if input_source is PlayerInputNetworkState:
		var input := input_source as PlayerInputNetworkState
		character.actions.bitmask = input.actions
		match input.last_interaction_type:
			PlayerInputNetworkState.ClientInteractionType.NONE:
				pass
			PlayerInputNetworkState.ClientInteractionType.JUMP:
				character.last_triggered_jump_frame_index = input.last_interaction_frame_index
			_:
				G.fatal()


## Unified server interaction reconciliation.
func _reconcile_server_interaction() -> void:
	# Skip if no interaction.
	if last_interaction_type == ServerInteractionType.NONE:
		return

	var interaction_frame := last_interaction_frame_index

	var should_process := _should_reconcile_interaction(
		interaction_frame,
		_last_reconciled_interaction_frame_index
	)

	# Always mark as reconciled to prevent retry loops.
	_last_reconciled_interaction_frame_index = interaction_frame

	if not should_process:
		return

	match last_interaction_type:
		ServerInteractionType.NONE:
			pass
		ServerInteractionType.BUMP:
			_reconcile_bump_interaction(interaction_frame)
		ServerInteractionType.KILL:
			_reconcile_kill_interaction(interaction_frame)
		ServerInteractionType.DIE:
			_reconcile_die_interaction(interaction_frame)
		ServerInteractionType.SPAWN:
			_reconcile_spawn_interaction(interaction_frame)
		_:
			G.fatal()


## Reconciles a bump interaction by injecting velocity delta into rollback
## buffer.
func _reconcile_bump_interaction(frame_index: int) -> void:
	var bounce_velocity := _calculate_bounce_velocity(
		last_interaction_direction,
		character.movement_settings.bump_bounce_base_speed,
		character.movement_settings.bump_bounce_vertical_boost
	)
	_inject_velocity_delta_into_buffer(frame_index, bounce_velocity)

	if G.is_verbose:
		G.print(
			"F:%d Bump velocity injected via server interaction into frame %d, queuing rollback (%s)" % [
				G.network.server_frame_index,
				frame_index,
				name,
			],
			ScaffolderLog.CATEGORY_NETWORK_SYNC,
			ScaffolderLog.Verbosity.VERBOSE,
		)


## Reconciles a kill interaction by injecting kill bounce velocity into
## rollback buffer.
func _reconcile_kill_interaction(frame_index: int) -> void:
	var bounce_velocity := _calculate_bounce_velocity(
		last_interaction_direction,
		character.movement_settings.kill_bounce_base_speed,
		character.movement_settings.kill_bounce_vertical_boost
	)
	_inject_velocity_delta_into_buffer(frame_index, bounce_velocity)

	if G.is_verbose:
		G.print(
			"F:%d Kill velocity injected into frame %d, queuing rollback (%s)" % [
				G.network.server_frame_index,
				frame_index,
				name,
			],
			ScaffolderLog.CATEGORY_NETWORK_SYNC,
			ScaffolderLog.Verbosity.VERBOSE,
		)


## Reconciles a die interaction by stopping movement in rollback buffer.
func _reconcile_die_interaction(frame_index: int) -> void:
	var frame_state: Array = _rollback_buffer.get_at(frame_index)
	_set_frame_property(frame_state, &"velocity", Vector2.ZERO)
	_rollback_buffer.set_at(frame_index, frame_state)
	G.network.frame_driver.queue_rollback(frame_index)

	if G.is_verbose:
		G.print(
			"F:%d Die interaction reconciled at frame %d, queuing rollback (%s)" % [
				G.network.server_frame_index,
				frame_index,
				name,
			],
			ScaffolderLog.CATEGORY_NETWORK_SYNC,
			ScaffolderLog.Verbosity.VERBOSE,
		)


## Reconciles a spawn interaction by teleporting to spawn position in rollback
## buffer.
func _reconcile_spawn_interaction(frame_index: int) -> void:
	var frame_state: Array = _rollback_buffer.get_at(frame_index)
	_set_frame_property(frame_state, &"position", last_interaction_position)
	_set_frame_property(frame_state, &"velocity", Vector2.ZERO)
	_rollback_buffer.set_at(frame_index, frame_state)
	G.network.frame_driver.queue_rollback(frame_index)

	if G.is_verbose:
		G.print(
			"F:%d Spawn interaction reconciled at frame %d, position=%s, queuing rollback (%s)" % [
				G.network.server_frame_index,
				frame_index,
				last_interaction_position,
				name,
			],
			ScaffolderLog.CATEGORY_NETWORK_SYNC,
			ScaffolderLog.Verbosity.VERBOSE,
		)


## Calculates bounce velocity from direction and movement settings.
func _calculate_bounce_velocity(
	direction: Vector2,
	base_speed: float,
	vertical_boost: float
) -> Vector2:
	var base_bounce := direction * base_speed
	var upward_boost := Vector2(0, vertical_boost)
	return base_bounce + upward_boost


## Injects a velocity delta into the rollback buffer at the specified frame.
## Used for bumps and kills to apply collision bounce.
func _inject_velocity_delta_into_buffer(
	frame_index: int,
	velocity_delta: Vector2
) -> void:
	var frame_state: Array = _rollback_buffer.get_at(frame_index)
	var stored_velocity: Vector2 = _get_frame_property(frame_state, &"velocity")
	_set_frame_property(frame_state, &"velocity", stored_velocity + velocity_delta)
	_rollback_buffer.set_at(frame_index, frame_state)
	G.network.frame_driver.queue_rollback(frame_index)


## Sets the position in the rollback buffer at the specified frame.
## Used for spawn interactions to teleport the player.
func _inject_position_into_buffer(
	frame_index: int,
	new_position: Vector2
) -> void:
	var frame_state: Array = _rollback_buffer.get_at(frame_index)
	_set_frame_property(frame_state, &"position", new_position)
	_rollback_buffer.set_at(frame_index, frame_state)
	G.network.frame_driver.queue_rollback(frame_index)
