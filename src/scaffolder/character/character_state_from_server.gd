@tool
class_name CharacterStateFromServer
extends ReconcilableState

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
		return (
			is_instance_valid(input_from_client) and
			input_from_client.is_multiplayer_authority()
		)

var position := Vector2.ZERO
var velocity := Vector2.ZERO
## A bitmask representing the player's surface state.
var surfaces := 0

# -------------------------------------
# FIXME: REMOVE
# Diagnostic tracking for visibility bug.
var _last_applied_collidability_frame := -1
var _last_applied_collidability_value := true
var _collidability_apply_count := 0
# -------------------------------------

var is_dead: bool:
	get:
		# Player is dead only while DIE interaction is active (before SPAWN).
		if last_interaction_type != ServerInteractionType.DIE or \
			last_interaction_frame_index < 0:
			return false
		var respawn_frame: int = last_interaction_frame_index + \
			int(G.settings.player_respawn_cooldown_sec * 60)
		return Netcode.server_frame_index < respawn_frame

var is_invincible: bool:
	get:
		# Player is invincible after SPAWN for the invincibility duration.
		if last_interaction_type != ServerInteractionType.SPAWN or \
			last_interaction_frame_index < 0:
			return false
		var invincibility_end_frame: int = last_interaction_frame_index + \
			int(G.settings.player_invincibility_duration_sec * 60)
		return Netcode.server_frame_index < invincibility_end_frame

const _synced_properties_and_rollback_diff_thresholds := {
	position = DEFAULT_POSITION_DIFF_ROLLBACK_THRESHOLD,
	velocity = DEFAULT_VELOCITY_DIFF_ROLLBACK_THRESHOLD,
	surfaces = 0,
	last_interaction_type = 0,
	last_interaction_frame_index = 0,
	last_interaction_position = 0.01,
	last_interaction_velocity = 10.0,
}


func _get_default_values() -> Array:
	return [
		Vector2.ZERO, # position
		Vector2.ZERO, # velocity
		0, # surfaces
		ServerInteractionType.NONE, # last_interaction_type
		-1, # last_interaction_frame_index
		Vector2.ZERO, # last_interaction_position
		Vector2.ZERO, # last_interaction_velocity
	]


func _get_is_server_authoritative() -> bool:
	return true


func _should_accept_predicted_states() -> bool:
	# Accept SERVER_PREDICTED states only for remote players (not the owning
	# client). The owning client has authoritative input and runs its own
	# prediction, so accepting server extrapolations would overwrite the
	# client's more-accurate predicted state and cause jitter.
	return Netcode.is_client and not is_authority_for_input_from_client


func _uses_split_packed_state() -> bool:
	return true


func _should_create_debug_buffer() -> bool:
	return true


func _get_interaction_type_name(interaction_type: int) -> String:
	if interaction_type >= 0 and interaction_type < ServerInteractionType.size():
		return ServerInteractionType.keys()[interaction_type]
	return "UNKNOWN_%d" % interaction_type


func _has_non_rollbackable_interactions() -> bool:
	return true


func _is_interaction_rollbackable(interaction_type: int) -> bool:
	# Server interactions are non-rollbackable - server's first impression is
	# final.
	match interaction_type:
		ServerInteractionType.NONE:
			return true # No interaction, doesn't matter.
		ServerInteractionType.SPAWN, \
		ServerInteractionType.BUMP, \
		ServerInteractionType.KILL, \
		ServerInteractionType.DIE:
			return false # Non-rollbackable.
		_:
			Netcode.fatal("Unknown ServerInteractionType: %d" % interaction_type)
			return false


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
	var player_id_path := "%s:player_id" % root.get_path_to(self )
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

	if not Netcode.ensure_valid(character):
		return

	# Only handle local mode here; networked mode uses _network_process().
	if G.is_networked_level_active:
		return

	# Local mode: Update character directly without networking.
	_process_local_mode()


func _process_local_mode() -> void:
	# Save current bitmask before _collect_actions() clears it.
	# _collect_actions() calls actions.clear() which zeros both
	# bitmask and previous_bitmask, losing the frame-to-frame
	# transition needed by just_pressed_* onset detection. The
	# networked path restores this from the input buffer; in
	# local mode we save/restore it manually.
	var previous_actions_bitmask := character.actions.bitmask

	# Collect input from local player.
	character._collect_actions()

	# Restore previous frame's bitmask for onset detection.
	character.actions.previous_bitmask = previous_actions_bitmask

	# Apply movement (includes surfaces.update_touches()).
	character._apply_movement()

	# Process animations, sounds, etc.
	character._process_movement_and_actions()
	character._process_client_effects()

	# Sync state (for consistency with networked path).
	_sync_from_scene_state()

	character.surfaces.previous_bitmask = character.surfaces.bitmask


func _network_process() -> void:
	if not Netcode.ensure_valid(character):
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
	var input_source: ReconcilableState
	if is_remote_player_on_client:
		input_source = forwarded_input_from_server
	else:
		input_source = input_from_client

	if not Netcode.ensure_valid(input_source):
		if Netcode.log.is_verbose:
			Netcode.verbose(
				"F:%d input_source is null! (is_remote=%s, has_forwarded=%s, has_input=%s)" % [
					Netcode.server_frame_index,
					is_remote_player_on_client,
					forwarded_input_from_server != null,
					input_from_client != null,
				],
				NetworkLogger.CATEGORY_NETWORK_SYNC,
			)
		return

	# Handle actions (from a client).
	var has_authoritative_input := input_source._has_authoritative_state_for_current_frame()

	# Check if we should use predicted input at current frame. Only use it if
	# we don't have fresher authoritative input at the previous frame to
	# extrapolate from. This prevents using stale predictions during rollback
	# re-simulation (e.g., when authoritative actions=0 arrives at frame N, we
	# should extrapolate from N to get N+1, not use old predicted actions=1 at
	# N+1).
	var should_use_predicted_input := false
	if (
		input_source is ForwardedPlayerInputFromServer and
		input_source._rollback_buffer.has_at(frame_index)
	):
		# Check if previous frame has authoritative input source data.
		var previous_frame_index_is_auth := false
		if input_source._rollback_buffer.has_at(frame_index - 1):
			var previous_frame_index_state: Array = input_source._rollback_buffer.get_at(
				frame_index - 1
			)
			if previous_frame_index_state != null:
				previous_frame_index_is_auth = input_source._is_frame_authoritative(previous_frame_index_state)

		# Only use predicted input if previous frame doesn't have authoritative
		# data to extrapolate from.
		should_use_predicted_input = not previous_frame_index_is_auth

	# Calculate input delay upfront (only relevant for local authority).
	var input_delay: int = 0
	if is_authority_for_input_from_client:
		input_delay = (
			Netcode.frame_sync.input_delay_frames
			if Netcode.frame_sync != null
			else 0
		)

	# Save previous bitmask before any input loading (needed when no delay).
	var previous_bitmask_before_input := character.actions.bitmask

	if has_authoritative_input or should_use_predicted_input:
		# ROLLBACK PATH: Use received input from buffer.
		# For local authority with delay, the buffer already contains
		# delayed input -- no delay transformation needed.
		input_source._unpack_buffer_state(frame_index)
		_apply_input_to_character(input_source)

		# Restore previous_bitmask from the previous frame's input
		# buffer so just_triggered_jump fires only on the onset
		# frame, matching forward-sim behavior. Without this, the
		# rollback path would have just_triggered_jump = true on
		# every held frame (previous_bitmask = 0 from
		# _apply_input_to_character), causing server/client
		# divergence in AirJumpAction.
		if input_source._rollback_buffer.has_at(
			frame_index - 1
		):
			var prev_input_state: Array = (
				input_source._rollback_buffer.get_at(
					frame_index - 1
				)
			)
			if prev_input_state != null:
				character.actions.previous_bitmask = (
					input_source._get_frame_property(
						prev_input_state, &"actions"
					)
				)

		character.surfaces.update_actions()
		if Netcode.log.is_verbose:
			var authority_str := (
				"PREDICTED"
				if should_use_predicted_input
				else "AUTHORITATIVE"
			)
			Netcode.verbose(
				"F:%d Using %s input (actions=%d)" % [
					Netcode.server_frame_index,
					authority_str,
					character.actions.bitmask,
				],
				NetworkLogger.CATEGORY_NETWORK_SYNC,
			)
	else:
		if is_authority_for_input_from_client:
			# FORWARD SIM: Capture fresh raw input.
			# _collect_actions() calls surfaces.update_actions().
			character._collect_actions()
			input_from_client.frame_authority = (
				ReconcilableState.FrameAuthority.AUTHORITATIVE
			)

			if input_delay > 0:
				# Apply delay transformation: store raw input in
				# delay buffer and replace with delayed input for
				# local simulation. _sync_from_scene_state will
				# read the delayed value from player.actions.bitmask
				# so server and client agree on timing.
				var delay_buf := (
					input_from_client.input_delay_buffer
				)
				var raw_input := character.actions.bitmask
				delay_buf.store(frame_index, raw_input)
				var delayed := delay_buf.get_delayed(
					frame_index, input_delay
				)
				var prev_delayed := delay_buf.get_delayed(
					frame_index - 1, input_delay
				)
				character.actions.bitmask = delayed
				character.actions.previous_bitmask = prev_delayed

				# Reset and re-detect jump trigger on delayed input.
				character.last_triggered_jump_frame_index = -1
				if character.actions.just_triggered_jump:
					character.last_triggered_jump_frame_index = (
						Netcode.server_frame_index
					)

				# Re-update surface state for delayed input.
				character.surfaces.update_actions()
			else:
				# No input delay - use previous bitmask from last
				# frame.
				character.actions.previous_bitmask = (
					previous_bitmask_before_input
				)

				# Reset and re-detect jump trigger with correct
				# previous_bitmask (same as delay path above).
				character.last_triggered_jump_frame_index = -1
				if character.actions.just_triggered_jump:
					character.last_triggered_jump_frame_index = (
						Netcode.server_frame_index
					)

				# Re-update surface state with correct
				# previous_bitmask.
				character.surfaces.update_actions()

				if Netcode.log.is_verbose:
					if character.actions.just_triggered_jump:
						Netcode.verbose(
							"F:%d Jump onset detected "
							+ "(no-delay path, "
							+ "surface=%s) (%s)" % [
								Netcode.server_frame_index,
								SurfaceType.get_string(
									character.surfaces
										.surface_type
								),
								name,
							],
							NetworkLogger
								.CATEGORY_NETWORK_SYNC,
						)
		else:
			# No new input yet - extrapolate from previous frame's
			# input. Predicted input uses the last known state (N-1)
			# to simulate frame N.
			input_source._unpack_buffer_state(frame_index - 1)
			_apply_input_to_character(input_source)
			# Set previous_bitmask = current bitmask so no actions
			# are detected as "just pressed" during extrapolation.
			character.actions.previous_bitmask = (
				character.actions.bitmask
			)
			input_source.frame_authority = (
				ReconcilableState.FrameAuthority.SERVER_PREDICTED
			)
			character.surfaces.update_actions()
			if Netcode.log.is_verbose:
				Netcode.verbose(
					"F:%d Extrapolating input from prev frame "
					+ "(actions=%d)" % [
						Netcode.server_frame_index,
						character.actions.bitmask,
					],
					NetworkLogger.CATEGORY_NETWORK_SYNC,
				)

	# On the server, set frame authority to indicate whether this
	# frame's character state is based on authoritative input or
	# extrapolation. Without this, frame_authority stays UNKNOWN
	# (set in _pre_network_process), which bypasses the client's
	# SERVER_PREDICTED filter. The client then overwrites its
	# correct local prediction buffer with the server's
	# extrapolated state, causing jump rubberbanding.
	if is_authority_for_state_from_server:
		frame_authority = (
			FrameAuthority.AUTHORITATIVE
			if has_authoritative_input
			else FrameAuthority.SERVER_PREDICTED
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
		forwarded_input_from_server.last_interaction_velocity = (
			input_from_client.last_interaction_velocity
		)
		forwarded_input_from_server.frame_authority = (
			input_from_client.frame_authority
		)
		if Netcode.log.is_verbose and input_from_client.actions != 0:
			Netcode.verbose(
				"F:%d Forwarding input to remote clients (actions=%d)" % [
					Netcode.server_frame_index,
					forwarded_input_from_server.actions,
				],
				NetworkLogger.CATEGORY_NETWORK_SYNC,
			)

	# Skip movement processing if player is dead.
	if not is_dead:
		# Handle scene state (from the server).
		if is_authority_for_state_from_server:
			# The server processes movement. Mark as authoritative only if we have
			# authoritative input, otherwise mark as SERVER_PREDICTED to avoid
			# overriding client predictions with server extrapolations.
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
			frame_authority = ReconcilableState.FrameAuthority.CLIENT_PREDICTED
			if Netcode.log.is_verbose and (
				character.position.distance_to(pos_before) > 0.1 or
				character.velocity.distance_to(vel_before) > 0.1
			):
				Netcode.print(
					("F:%d Remote simulation: pos %s->%s, vel %s->%s, " +
					"actions=%d") % [
						Netcode.server_frame_index,
						pos_before,
						character.position,
						vel_before,
						character.velocity,
						character.actions.bitmask,
					],
					NetworkLogger.CATEGORY_NETWORK_SYNC,
				)

		character._process_movement_and_actions()

	# Process client-side effects (sounds, particles) regardless of
	# death state. This must be outside the is_dead guard so that
	# death effects (die sound, gore particles) fire on the frame
	# the interaction is first detected.
	# Skip during re-simulation: effects (sounds, particles) are
	# real-time-only. Re-sim can cross DIE/SPAWN boundaries
	# repeatedly, causing _last_processed_interaction_start_time
	# to reset and re-trigger effects on every rollback.
	if not Netcode.frame_driver.is_resimulating:
		character._process_client_effects()

	# Ensure visibility/collision state is correct based on current interaction.
	# This is critical to prevent players from staying invisible after respawn.
	_ensure_interaction_state_applied()

	super._network_process()


func _sync_to_scene_state(previous_state: Array) -> void:
	if not Netcode.ensure_valid(character):
		return

	character.position = position
	character.velocity = velocity
	character.surfaces.bitmask = surfaces

	character.previous_position = previous_state[_property_name_to_pack_index.position]
	character.previous_velocity = previous_state[_property_name_to_pack_index.velocity]
	character.surfaces.previous_bitmask = previous_state[_property_name_to_pack_index.surfaces]


func _restore_indirect_interaction_state(frame_state: Array) -> void:
	if not Netcode.ensure_valid(character):
		return

	# Extract interaction type from frame state.
	var interaction_type: int = _get_frame_property(
		frame_state,
		&"last_interaction_type"
	)

	# Apply collidability based on interaction type.
	_apply_interaction_collidability(interaction_type)


## Ensures the current interaction state is properly applied to character
## visibility and collision. Called every frame to maintain correct state.
func _ensure_interaction_state_applied() -> void:
	if not Netcode.ensure_valid(character):
		return

	# Use current interaction type to determine collidability.
	_apply_interaction_collidability(last_interaction_type)


## Helper to apply collidability based on interaction type.
func _apply_interaction_collidability(interaction_type: int) -> void:
	# Determine collidability based on interaction type.
	var is_collidable: bool
	match interaction_type:
		ServerInteractionType.DIE:
			is_collidable = false # Dead - no collision.
		ServerInteractionType.SPAWN, \
		ServerInteractionType.NONE, \
		ServerInteractionType.BUMP, \
		ServerInteractionType.KILL:
			is_collidable = true # Alive - has collision.
		_:
			Netcode.fatal("Unknown ServerInteractionType: %d" % interaction_type)
			is_collidable = true

	# -------------------------------------
	# FIXME: REMOVE
	# Track diagnostic info for visibility bug detection.
	var current_frame := Netcode.server_frame_index
	var collidability_changed := (_last_applied_collidability_value != is_collidable)
	_last_applied_collidability_frame = current_frame
	_last_applied_collidability_value = is_collidable
	_collidability_apply_count += 1

	# Log when collidability changes, especially for SPAWN.
	if collidability_changed and Netcode.log.is_verbose:
		Netcode.verbose(
			"F:%d Player collidability changed: %s -> %s (interaction=%s)" % [
				current_frame,
				not is_collidable,
				is_collidable,
				ServerInteractionType.keys()[interaction_type],
			],
			NetworkLogger.CATEGORY_GAME_STATE,
		)
	# -------------------------------------

	# Delegate to character-specific collision handling.
	character.set_is_collidable(is_collidable)


## Gets the bounce velocity from the rollback buffer at the current frame.
## Returns the bounce velocity if the current frame has a KILL or BUMP
## interaction, or null if no bounce should be applied.
##
## This checks the buffer directly rather than using unpacked properties,
## because _pre_network_process() unpacks the PREVIOUS frame's state.
## During rollback re-simulation, we need to check if the CURRENT frame
## (being simulated) has a bounce interaction.
func get_current_frame_bounce_velocity():
	if _rollback_buffer == null:
		return null

	var current_frame := Netcode.server_frame_index
	if not _rollback_buffer.has_at(current_frame):
		return null

	var frame_state: Array = _rollback_buffer.get_at(current_frame)
	if frame_state == null:
		return null

	var interaction_frame: int = _get_frame_property(
		frame_state,
		&"last_interaction_frame_index"
	)

	# Only apply bounce on the exact frame the interaction occurred.
	if interaction_frame != current_frame:
		return null

	var interaction_type: int = _get_frame_property(
		frame_state,
		&"last_interaction_type"
	)

	# Only KILL and BUMP interactions have bounce velocities.
	if (
		interaction_type != ServerInteractionType.KILL and
		interaction_type != ServerInteractionType.BUMP
	):
		return null

	return _get_frame_property(frame_state, &"last_interaction_velocity")


func _sync_from_scene_state() -> void:
	if not Netcode.ensure_valid(character):
		return

	position = character.position
	velocity = character.velocity
	surfaces = character.surfaces.bitmask

	# NOTE: Interaction properties (last_interaction_type,
	# last_interaction_frame_index, last_interaction_position,
	# last_interaction_velocity) are NOT synced from scene state. They are
	# only set via record_interaction() and persist across frames until
	# explicitly changed by another interaction.
	#
	# IMPORTANT: DIE and SPAWN interactions are persistent states that must
	# remain active across multiple frames:
	# - DIE: Persists from death until respawn (checked by is_dead property)
	# - SPAWN: Persists for invincibility duration (checked by is_invincible)
	# - BUMP/KILL: One-frame events for applying physics impulses
	#
	# These properties are automatically packed into the rollback buffer and
	# replicated over the network in _pack_buffer_state_from_local_state().


func _post_network_process() -> void:
	super._post_network_process()
	# On the server, confirm the previous frame as authoritative
	# (input typically arrives 1 tick late). This sends the character
	# state for frame_index-1 to clients on the authoritative channel.
	# Skip during re-sim: running with re-sim frame indices interferes
	# with frame advancement.
	if not Netcode.frame_driver.is_resimulating:
		_try_send_confirmed_authoritative_state()


## Checks if the input for a recently processed frame became authoritative.
## If so, upgrades the character state authority and packs it for network
## sending. This ensures clients receive AUTHORITATIVE confirmations even
## when the server correctly predicts input (no rollback).
func _try_send_confirmed_authoritative_state() -> void:
	if not is_authority_for_state_from_server:
		return
	if not is_instance_valid(input_from_client):
		return
	if _rollback_buffer == null:
		return

	# Check the previous frame. Input typically arrives 1 tick after the
	# frame was processed.
	var previous_frame_index := frame_index - 1
	if previous_frame_index < 0:
		return
	if not _rollback_buffer.has_at(previous_frame_index):
		return
	if not input_from_client._rollback_buffer.has_at(previous_frame_index):
		return

	# Check if input for the previous frame is authoritative.
	var input_state: Array = \
		input_from_client._rollback_buffer.get_at(previous_frame_index)
	if not input_from_client._is_frame_authoritative(input_state):
		return

	# Always upgrade and send, even if already AUTHORITATIVE from
	# rollback re-simulation. Without this, _try_send skips frames
	# that were marked AUTHORITATIVE during server rollback, causing
	# the sent frame to stall for many ticks. The client then
	# receives the same stale AUTHORITATIVE state repeatedly,
	# triggering cascading rollbacks (especially during jumps where
	# position diverges).
	var char_state: Array = _rollback_buffer.get_at(previous_frame_index)
	if not _is_frame_authoritative(char_state):
		_set_frame_authority(char_state, FrameAuthority.AUTHORITATIVE)
		_rollback_buffer.set_at(previous_frame_index, char_state)

	# Pack this authoritative state for network sending.
	# Build a packed state array from the buffer entry.
	var prop_count := _property_names_for_packing.size()
	var state := ArrayPool.acquire(prop_count + 2)
	for i in range(prop_count):
		state[i] = _get_frame_property(char_state, \
			_property_names_for_packing[i])
	state[prop_count] = FrameAuthority.AUTHORITATIVE
	state[prop_count + 1] = previous_frame_index

	_is_packing_state_locally = true
	if not authoritative_packed_state.is_empty():
		ArrayPool.release(authoritative_packed_state)
	authoritative_packed_state = state
	_is_packing_state_locally = false

	if Netcode.log.is_verbose:
		Netcode.log.verbose(
			"%s F:%d Confirmed authoritative state for frame %d" %
			[name, Netcode.server_frame_index, previous_frame_index],
			NetworkLogger.CATEGORY_NETWORK_SYNC)


func _apply_input_to_character(input_source: ReconcilableState) -> void:
	# Copy input from PlayerInputFromClient or ForwardedPlayerInputFromServer
	# to the character.
	if input_source is PlayerInputNetworkState:
		var input := input_source as PlayerInputNetworkState
		# Default previous_bitmask to 0. Callers override this:
		# - Rollback path: reads from input buffer (frame N-1).
		# - Extrapolation path: sets to current bitmask.
		# - Forward sim path: sets from delay buffer or scene.
		character.actions.previous_bitmask = 0
		character.actions.bitmask = input.actions
		match input.last_interaction_type:
			PlayerInputNetworkState.ClientInteractionType.NONE:
				pass
			PlayerInputNetworkState.ClientInteractionType.JUMP:
				character.last_triggered_jump_frame_index = input.last_interaction_frame_index
			_:
				Netcode.fatal()


## Unified server interaction reconciliation.
func _reconcile_server_interaction() -> void:
	# Check the current frame's buffer for interactions to reconcile.
	# We can't use self.last_interaction_* because _unpack_buffer_state(N-1)
	# has already overwritten them with the previous frame's values.
	var current_frame := Netcode.server_frame_index
	if not _rollback_buffer.has_at(current_frame):
		return

	var frame_state: Array = _rollback_buffer.get_at(current_frame)
	if frame_state == null:
		return

	var buffer_interaction_type: int = _get_frame_property(
		frame_state,
		&"last_interaction_type"
	)
	var buffer_interaction_frame: int = _get_frame_property(
		frame_state,
		&"last_interaction_frame_index"
	)

	# Skip if no interaction at current frame.
	if buffer_interaction_type == ServerInteractionType.NONE:
		return

	# Update local interaction properties from current frame's buffer.
	# This is critical for rollback re-simulation: _pre_network_process()
	# unpacked frame N-1, so is_dead would return false without this update.
	# Interaction properties are safe to restore from buffer because they are
	# set by explicit injection (record_interaction), not by simulation.
	last_interaction_type = buffer_interaction_type
	last_interaction_frame_index = buffer_interaction_frame
	last_interaction_position = _get_frame_property(
		frame_state, &"last_interaction_position")
	last_interaction_velocity = _get_frame_property(
		frame_state, &"last_interaction_velocity")

	# Only reconcile if this is the onset frame (interaction_frame == current_frame).
	if buffer_interaction_frame != current_frame:
		return

	# For DIE and SPAWN onset, restore authoritative position/velocity from
	# buffer. This is only safe on the onset frame where the buffer has
	# injected authoritative data. On non-onset frames, the buffer may have
	# stale data from a previous simulation that hasn't been re-simulated yet
	# during rollback, which would overwrite correctly re-simulated positions.
	if buffer_interaction_type == ServerInteractionType.DIE or \
		buffer_interaction_type == ServerInteractionType.SPAWN:
		position = _get_frame_property(frame_state, &"position")
		velocity = _get_frame_property(frame_state, &"velocity")
		if Netcode.ensure_valid(character):
			character.position = position
			character.velocity = velocity

	var should_process := _should_reconcile_interaction(
		current_frame,
		_last_reconciled_interaction_frame_index
	)

	# Verbose logging for reconciliation status.
	if Netcode.log.is_verbose:
		var type_name: StringName = ServerInteractionType.keys()[buffer_interaction_type]
		Netcode.verbose(
			"Reconciling %s: frame=%d, should_process=%s (%s)" % [
				type_name,
				current_frame,
				should_process,
				name
			],
			NetworkLogger.CATEGORY_NETWORK_SYNC
		)

	# Always mark as reconciled to prevent retry loops.
	_last_reconciled_interaction_frame_index = current_frame

	if not should_process:
		return

	match buffer_interaction_type:
		ServerInteractionType.NONE:
			pass
		ServerInteractionType.BUMP:
			_reconcile_bump_interaction(current_frame)
		ServerInteractionType.KILL:
			_reconcile_kill_interaction(current_frame)
		ServerInteractionType.DIE:
			_reconcile_die_interaction(current_frame)
		ServerInteractionType.SPAWN:
			_reconcile_spawn_interaction(current_frame)
		_:
			Netcode.fatal()


## Reconciles a bump interaction by queuing rollback.
## The bounce velocity is applied during re-simulation by bunny.gd via
## get_current_frame_bounce_velocity() + force_launch().
func _reconcile_bump_interaction(p_frame_index: int) -> void:
	Netcode.frame_driver.queue_rollback(
		p_frame_index, "bump on %s" % name)

	if Netcode.log.is_verbose:
		Netcode.verbose(
			"F:%d Bump interaction at frame %d, queuing rollback (%s)" % [
				Netcode.server_frame_index,
				p_frame_index,
				name,
			],
			NetworkLogger.CATEGORY_NETWORK_SYNC,
		)


## Reconciles a kill interaction by queuing rollback.
## The bounce velocity is applied during re-simulation by bunny.gd via
## get_current_frame_bounce_velocity() + force_launch().
func _reconcile_kill_interaction(p_frame_index: int) -> void:
	Netcode.frame_driver.queue_rollback(
		p_frame_index, "kill on %s" % name)

	if Netcode.log.is_verbose:
		Netcode.verbose(
			"F:%d Kill interaction at frame %d, queuing rollback (%s)" % [
				Netcode.server_frame_index,
				p_frame_index,
				name,
			],
			NetworkLogger.CATEGORY_NETWORK_SYNC,
		)


## Sets all interaction properties on a frame state. Used by buffer
## modification functions to ensure interaction data persists through rollback.
func _set_frame_interaction_properties(
	frame_state: Array,
	interaction_type: int,
	interaction_frame_index: int,
	interaction_position: Vector2,
	interaction_velocity: Vector2
) -> void:
	_set_frame_property(frame_state, &"last_interaction_type", interaction_type)
	_set_frame_property(frame_state, &"last_interaction_frame_index", interaction_frame_index)
	_set_frame_property(frame_state, &"last_interaction_position", interaction_position)
	_set_frame_property(frame_state, &"last_interaction_velocity", interaction_velocity)


## Reconciles a die interaction by queuing rollback.
## Visibility/collision state is applied during re-simulation via
## _ensure_interaction_state_applied().
func _reconcile_die_interaction(p_frame_index: int) -> void:
	Netcode.frame_driver.queue_rollback(
		p_frame_index, "die on %s" % name)

	if Netcode.log.is_verbose:
		Netcode.verbose(
			"F:%d Die interaction at frame %d, queuing rollback (%s)" % [
				Netcode.server_frame_index,
				p_frame_index,
				name,
			],
			NetworkLogger.CATEGORY_NETWORK_SYNC,
		)


## Reconciles a spawn interaction by queuing rollback.
## Position/visibility state is applied during re-simulation. The server state
## already contains the correct spawn position.
func _reconcile_spawn_interaction(p_frame_index: int) -> void:
	Netcode.frame_driver.queue_rollback(
		p_frame_index, "spawn on %s" % name)

	if Netcode.log.is_verbose:
		Netcode.verbose(
			"F:%d Spawn interaction at frame %d, queuing rollback (%s)" % [
				Netcode.server_frame_index,
				p_frame_index,
				name,
			],
			NetworkLogger.CATEGORY_NETWORK_SYNC,
		)


## Records an interaction and automatically injects it into the rollback buffer.
##
## Override of base class method. This ensures server-side interactions are
## immediately injected into the buffer at the current frame to protect against
## rollback clearing them before _post_network_process() can pack them.
##
## For DIE interactions, use record_death_interaction() instead to also set
## position and velocity.
func record_interaction(
	interaction_type: int,
	p_frame_index: int,
	p_position: Vector2,
	p_velocity: Vector2
) -> void:
	# Inject into buffer FIRST before setting local properties.
	# This prevents rollback from clearing the interaction before
	# _post_network_process() can pack it.
	_inject_authoritative_state_into_buffer(
		p_frame_index,
		p_position,
		p_velocity,
		interaction_type,
		p_frame_index,
		p_position,
		p_velocity
	)

	# Then call base class to set local properties.
	super.record_interaction(interaction_type, p_frame_index, p_position, p_velocity)


## Records a DIE interaction with separate spawn and death positions.
##
## For death, the character is immediately moved to the spawn position (while
## hidden), but the interaction position records where death occurred (for
## visual effects like particles). This method handles both correctly.
func record_death_interaction(
	p_frame_index: int,
	spawn_position: Vector2,
	death_position: Vector2
) -> void:
	# Inject authoritative state with:
	# - position/velocity = spawn position + zero velocity (where character IS)
	# - interaction position = death position (where interaction HAPPENED)
	_inject_authoritative_state_into_buffer(
		p_frame_index,
		spawn_position,
		Vector2.ZERO,
		ServerInteractionType.DIE,
		p_frame_index,
		death_position,
		Vector2.ZERO
	)

	# Update local properties to match.
	position = spawn_position
	velocity = Vector2.ZERO

	# Set interaction properties on the local state.
	last_interaction_type = ServerInteractionType.DIE
	last_interaction_frame_index = p_frame_index
	last_interaction_position = death_position
	last_interaction_velocity = Vector2.ZERO


## Sets position, velocity, and interaction properties in the rollback buffer
## at the specified frame. Marks the frame as AUTHORITATIVE.
##
## Used for lag-compensated position injection and death/spawn state. This
## function explicitly sets all physics and interaction properties in the
## buffer to prevent them from being overwritten with stale values.
func _inject_authoritative_state_into_buffer(
	p_frame_index: int,
	new_position: Vector2,
	new_velocity: Vector2,
	interaction_type: int,
	interaction_frame_index: int,
	interaction_position: Vector2,
	interaction_velocity: Vector2
) -> void:
	var frame_state: Array = _rollback_buffer.get_at(p_frame_index)
	_set_frame_property(frame_state, &"position", new_position)
	_set_frame_property(frame_state, &"velocity", new_velocity)

	# Set interaction properties explicitly.
	# This ensures the buffer has the correct interaction data, preventing
	# _post_network_process() from overwriting with stale values.
	_set_frame_interaction_properties(
		frame_state,
		interaction_type,
		interaction_frame_index,
		interaction_position,
		interaction_velocity
	)

	# Mark as authoritative so clients accept this state without prediction.
	_set_frame_authority(frame_state, FrameAuthority.AUTHORITATIVE)

	_rollback_buffer.set_at(p_frame_index, frame_state)
	Netcode.frame_driver.queue_rollback(
		p_frame_index,
		"inject_authoritative on %s" % name
	)
