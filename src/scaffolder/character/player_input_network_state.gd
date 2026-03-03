@tool
class_name PlayerInputNetworkState
extends ReconcilableState
## Base class for player input synchronization (PlayerInputFromClient and
## ForwardedPlayerInputFromServer). Provides shared jump reconciliation logic.

## Client-authoritative interaction types.
enum ClientInteractionType {
	NONE,
	JUMP,
}

## A bitmask representing which of the player's actions are active.
var actions := 0

var _synced_properties_and_rollback_diff_thresholds := {
	actions = 0,
	last_interaction_type = 0,
	last_interaction_frame_index = 0,
	last_interaction_position = 0.001,
	last_interaction_velocity = 1.0,
}


func _get_default_values() -> Array:
	return [
		0, # actions
		ClientInteractionType.NONE, # last_interaction_type
		-1, # last_interaction_frame_index
		Vector2.ZERO, # last_interaction_position
		Vector2.ZERO, # last_interaction_velocity
	]


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	# With redundant input, the actions bitmask already carries
	# jump information via _process_redundant_inputs. Disable
	# mismatch detection for interaction properties to prevent
	# cascading rollbacks from redundant metadata.
	if Netcode.settings.redundant_input_frame_count > 0:
		var t := _synced_properties_and_rollback_diff_thresholds
		t.last_interaction_type = -1
		t.last_interaction_frame_index = -1
		t.last_interaction_position = -1
		t.last_interaction_velocity = -1


func _pre_network_process() -> void:
	super._pre_network_process()
	# Don't propagate AUTHORITATIVE authority from corrected
	# frames to subsequent frames. Non-authority input nodes use
	# AUTHORITATIVE only as a re-sim guard marker (to protect
	# redundant-input corrections from buffer overwrite), not as
	# a persistent authority flag. Without this, all frames after
	# a correction inherit AUTHORITATIVE and block future
	# _process_redundant_inputs corrections.
	if not is_multiplayer_authority():
		if frame_authority == FrameAuthority.AUTHORITATIVE:
			frame_authority = (
				FrameAuthority.SERVER_PREDICTED
				if Netcode.is_server
				else FrameAuthority.CLIENT_PREDICTED
			)


func _post_network_process() -> void:
	if (
		Netcode.frame_driver.is_resimulating
		and not is_multiplayer_authority()
	):
		# Non-authority during re-sim: _sync_from_scene_state is
		# a no-op (returns early or does nothing), so local
		# properties hold stale values from buffer[N-1].
		# Only pack for non-AUTHORITATIVE frames to preserve
		# corrections from the network or redundant input.
		if _rollback_buffer == null:
			return
		var frame_state: Array = (
			_rollback_buffer.get_at(frame_index)
		)
		if (
			frame_state == null
			or not _is_frame_authoritative(frame_state)
		):
			_pack_buffer_state_from_local_state()
		return
	super._post_network_process()


# -------------------- Redundant input transmission -------------------


func _pack_networked_state() -> void:
	var redundant_count: int = (
		Netcode.settings.redundant_input_frame_count
	)

	if redundant_count <= 0:
		# No redundant input. Use default packing.
		super._pack_networked_state()
		return

	var standard_size := _property_names_for_packing.size() + 2
	# Extra: 1 count header + 2 ints per redundant frame.
	var extra_size := 1 + redundant_count * 2
	var state := ArrayPool.acquire(standard_size + extra_size)

	# Pack standard properties (same logic as base class).
	var i := 0
	for property_name in _property_names_for_packing:
		state[i] = get(property_name)
		i += 1
	state[i] = frame_authority
	i += 1
	state[i] = frame_index
	i += 1

	# Pack redundant input history (most recent first).
	state[i] = redundant_count
	i += 1
	for j in redundant_count:
		var hist_frame := Netcode.server_frame_index - j - 1
		var hist_actions := 0
		if _rollback_buffer.has_at(hist_frame):
			var frame_state: Array = (
				_rollback_buffer.get_at(hist_frame)
			)
			hist_actions = _get_frame_property(
				frame_state, &"actions"
			)
		state[i] = hist_frame
		i += 1
		state[i] = hist_actions
		i += 1

	if Netcode.log.is_verbose:
		var authority_string: StringName = (
			FrameAuthority.keys()[frame_authority]
		)
		Netcode.log.verbose(
			"%s F:%d Packed input state (%s) "
			+"with %d redundant frames" % [
				name,
				Netcode.server_frame_index,
				authority_string,
				redundant_count,
			],
			NetworkLogger.CATEGORY_NETWORK_SYNC,
		)

	# Input nodes always use the authoritative channel.
	var channel: StringName = (
		NetworkConditionSimulator.CHANNEL_AUTHORITATIVE
	)
	if _should_use_network_simulator():
		Netcode.condition_simulator.queue_outgoing_state(
			self , state, channel
		)
	else:
		_assign_outgoing_state(state, channel)


func _handle_new_state_from_network(p_state: Array) -> void:
	var standard_size := _property_names_for_packing.size() + 2
	if p_state.size() > standard_size:
		_process_redundant_inputs(p_state, standard_size)
		# Trim to standard format before passing to parent.
		p_state = p_state.slice(0, standard_size)
	super._handle_new_state_from_network(p_state)


func _get_interaction_type_name(interaction_type: int) -> String:
	if interaction_type >= 0 and interaction_type < ClientInteractionType.size():
		return ClientInteractionType.keys()[interaction_type]
	return "UNKNOWN_%d" % interaction_type


func _has_non_rollbackable_interactions() -> bool:
	return true


func _is_interaction_rollbackable(interaction_type: int) -> bool:
	# Client interactions are rollbackable - effects recalculated during
	# rollback.
	match interaction_type:
		ClientInteractionType.NONE:
			return true
		ClientInteractionType.JUMP:
			return true
		_:
			Netcode.fatal("Unknown ClientInteractionType: %d" % interaction_type)
			return true


func _restore_indirect_interaction_state(_frame_state: Array) -> void:
	# Do nothing.
	pass


func _clear_jump_bit_in_frame_if_not_pressed(p_frame_index: int) -> void:
	if p_frame_index < 0 or not _rollback_buffer.has_at(p_frame_index):
		return

	var frame_state: Array = _rollback_buffer.get_at(p_frame_index)
	var current_actions: int = _get_frame_property(frame_state, &"actions")
	var jump_bit_mask: int = 1 << CharacterActionState.BIT_JUMP

	# Only clear if the frame is predicted (not authoritative).
	if (current_actions & jump_bit_mask) != 0 and _is_frame_predicted(frame_state):
		_set_frame_property(frame_state, &"actions", current_actions & ~jump_bit_mask)
		_rollback_buffer.set_at(p_frame_index, frame_state)


## Unified client interaction reconciliation (new system).
func _reconcile_client_interaction() -> void:
	# Skip if no interaction.
	if last_interaction_type == ClientInteractionType.NONE:
		return

	var interaction_frame := last_interaction_frame_index

	var should_process := _should_reconcile_interaction(
		interaction_frame,
		_last_reconciled_interaction_frame_index
	)

	# Verbose logging for reconciliation status.
	if Netcode.log.is_verbose:
		var type_name: StringName = ClientInteractionType.keys()[last_interaction_type]
		Netcode.verbose(
			"Reconciling %s: frame=%d, should_process=%s, buffer_has=%s (%s)" % [
				type_name,
				interaction_frame,
				should_process,
				_rollback_buffer.has_at(interaction_frame),
				name
			],
			NetworkLogger.CATEGORY_NETWORK_SYNC
		)

	# Always mark as reconciled to prevent retry loops.
	_last_reconciled_interaction_frame_index = interaction_frame

	if not should_process:
		return

	match last_interaction_type:
		ClientInteractionType.NONE:
			pass
		ClientInteractionType.JUMP:
			_reconcile_jump_interaction(interaction_frame)
		_:
			Netcode.fatal()


## Reconciles a jump interaction by injecting the jump input bit into the
## rollback buffer.
func _reconcile_jump_interaction(p_frame_index: int) -> void:
	var frame_state: Array = _rollback_buffer.get_at(p_frame_index)
	var current_actions: int = _get_frame_property(frame_state, &"actions")
	var jump_bit_mask := 1 << CharacterActionState.BIT_JUMP
	var has_jump_input := (current_actions & jump_bit_mask) != 0

	# Also check for UP bit if the setting allows UP to trigger jumps.
	if G.settings.does_up_also_trigger_jump:
		var up_bit_mask := 1 << CharacterActionState.BIT_UP
		has_jump_input = has_jump_input or ((current_actions & up_bit_mask) != 0)

	if not has_jump_input:
		if _is_frame_authoritative(frame_state):
			Netcode.warning(
				("last_interaction_frame_index"
					+ " corresponds to a frame "
					+ "that is already recorded"
					+ " as authoritative and"
					+ " without jump pressed:"
					+ " frame %d, actions=%s"
					+ " (%s)"
				) % [
					p_frame_index,
					_get_string_for_bitmask(current_actions),
					name,
				],
				NetworkLogger.CATEGORY_NETWORK_SYNC,
			)
			return

		# Inject jump bit using base class helper.
		_inject_action_bit_into_buffer(p_frame_index, jump_bit_mask)
		_clear_jump_bit_in_frame_if_not_pressed(p_frame_index - 1)

		if Netcode.log.is_verbose:
			Netcode.verbose(
				"Jump bit injected into frame %d via client interaction, queuing rollback (%s)" % [
					p_frame_index,
					name,
				],
				NetworkLogger.CATEGORY_NETWORK_SYNC,
			)


## Injects an action bit into the rollback buffer at the specified frame.
## Used for jump interactions to ensure jump input is recorded.
func _inject_action_bit_into_buffer(
	p_frame_index: int,
	bit_mask: int,
	_actions_index: int = -1 # Deprecated parameter, kept for compatibility.
) -> void:
	var frame_state: Array = _rollback_buffer.get_at(p_frame_index)
	var current_actions: int = _get_frame_property(frame_state, &"actions")
	_set_frame_property(frame_state, &"actions", current_actions | bit_mask)
	_rollback_buffer.set_at(p_frame_index, frame_state)
	Netcode.frame_driver.queue_rollback(
		p_frame_index,
		"action_bit inject on %s" % name
	)


## Extracts redundant input frames from extended packed state and
## fills gaps in the rollback buffer where input was predicted.
func _process_redundant_inputs(
	p_state: Array,
	standard_size: int,
) -> void:
	var redundant_count: int = p_state[standard_size]
	var offset := standard_size + 1
	for j in redundant_count:
		var hist_frame: int = p_state[offset + j * 2]
		var hist_actions: int = p_state[offset + j * 2 + 1]
		if not _rollback_buffer.has_at(hist_frame):
			continue
		var frame_state: Array = (
			_rollback_buffer.get_at(hist_frame)
		)
		if not _is_frame_predicted(frame_state):
			# Already have authoritative data.
			continue
		var current_actions: int = _get_frame_property(
			frame_state, &"actions"
		)
		if current_actions == hist_actions:
			# Extrapolation was correct, no correction needed.
			continue
		# Fill gap with actual input and trigger rollback.
		_set_frame_property(
			frame_state, &"actions", hist_actions
		)
		# Mark as authoritative so the re-sim buffer guard
		# preserves this correction (prevents overwrite by
		# stale buffer[N-1] values during rollback).
		_set_frame_authority(
			frame_state, FrameAuthority.AUTHORITATIVE
		)
		_rollback_buffer.set_at(hist_frame, frame_state)
		# Target one frame earlier so the character state at
		# hist_frame is re-simulated with the corrected input
		# (same rationale as the input mismatch fix in
		# _handle_new_state_from_network).
		Netcode.frame_driver.queue_rollback(
			hist_frame - 1,
			"redundant_input on %s" % name
		)
		if Netcode.log.is_verbose:
			Netcode.log.verbose(
				("Redundant input corrected frame %d "
				+"(was=%d, now=%d) (%s)") % [
					hist_frame,
					current_actions,
					hist_actions,
					name,
				],
				NetworkLogger.CATEGORY_NETWORK_SYNC,
			)
