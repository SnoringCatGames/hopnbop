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

const _synced_properties_and_rollback_diff_thresholds := {
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


func _handle_new_authoritative_state() -> void:
	super._handle_new_authoritative_state()
	_reconcile_client_interaction()


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
			G.fatal("Unknown ClientInteractionType: %d" % interaction_type)
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
		G.verbose(
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
			G.fatal()


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
			G.warning(
				(
					"F:%d last_interaction_frame_index corresponds to a frame " +
					"that is already recorded as authoritative and without jump " +
					"pressed: frame %d, actions=%s (%s)"
				) % [
					Netcode.server_frame_index,
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
			G.verbose(
				"F:%d Jump bit injected into frame %d via client interaction, queuing rollback (%s)" % [
					Netcode.server_frame_index,
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
	Netcode.frame_driver.queue_rollback(p_frame_index)
