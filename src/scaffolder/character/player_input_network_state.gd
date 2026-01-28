@tool
class_name PlayerInputNetworkState
extends ReconcilableNetworkedState
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
	last_interaction_time_usec = 0,
	last_interaction_position = 0.001,
	last_interaction_direction = 0.001,
}


func _get_default_values() -> Array:
	return [
		0, # actions
		ClientInteractionType.NONE, # last_interaction_type
		-1, # last_interaction_time_usec
		Vector2.ZERO, # last_interaction_position
		Vector2.ZERO, # last_interaction_direction
	]


func _handle_new_authoritative_state() -> void:
	super._handle_new_authoritative_state()
	_reconcile_client_interaction()


func _clear_jump_bit_in_frame_if_not_pressed(frame_index: int) -> void:
	if frame_index < 0 or not _rollback_buffer.has_at(frame_index):
		return

	var frame_state: Array = _rollback_buffer.get_at(frame_index)
	var actions_index: int = _property_name_to_pack_index.actions
	var current_actions: int = frame_state[actions_index]
	var jump_bit_mask: int = 1 << CharacterActionState.BIT_JUMP

	# Only clear if the frame is predicted (not authoritative).
	var is_predicted: bool = (
		frame_state[frame_state.size() - 1] == FrameAuthority.PREDICTED
	)
	if (current_actions & jump_bit_mask) != 0 and is_predicted:
		frame_state[actions_index] = current_actions & ~jump_bit_mask
		_rollback_buffer.set_at(frame_index, frame_state)


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
func _reconcile_jump_interaction(frame_index: int) -> void:
	var frame_state: Array = _rollback_buffer.get_at(frame_index)
	var actions_index: int = _property_name_to_pack_index.actions
	var current_actions: int = frame_state[actions_index]
	var jump_bit_mask := 1 << CharacterActionState.BIT_JUMP
	var has_jump_input := (current_actions & jump_bit_mask) != 0

	# Also check for UP bit if the setting allows UP to trigger jumps.
	if G.settings.does_up_also_trigger_jump:
		var up_bit_mask := 1 << CharacterActionState.BIT_UP
		has_jump_input = has_jump_input or ((current_actions & up_bit_mask) != 0)

	if not has_jump_input:
		var stored_authority: int = frame_state[frame_state.size() - 1]
		if stored_authority == FrameAuthority.AUTHORITATIVE:
			G.warning(
				(
					"F:%d last_interaction_time_usec corresponds to a frame " +
					"that is already recorded as authoritative and without jump " +
					"pressed: frame %d, actions=%s (%s)"
				) % [
					G.network.server_frame_index,
					frame_index,
					_get_string_for_bitmask(current_actions),
					name,
				],
				ScaffolderLog.CATEGORY_NETWORK_SYNC,
			)
			return

		# Inject jump bit using base class helper.
		_inject_action_bit_into_buffer(frame_index, jump_bit_mask, actions_index)
		_clear_jump_bit_in_frame_if_not_pressed(frame_index - 1)

		if G.is_verbose:
			G.print(
				"F:%d Jump bit injected into frame %d via client interaction, queuing rollback (%s)" % [
					G.network.server_frame_index,
					frame_index,
					name,
				],
				ScaffolderLog.CATEGORY_NETWORK_SYNC,
				ScaffolderLog.Verbosity.VERBOSE,
			)
