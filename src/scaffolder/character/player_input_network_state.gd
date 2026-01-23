@tool
class_name PlayerInputNetworkState
extends ReconcilableNetworkedState
## Base class for player input synchronization (PlayerInputFromClient and
## ForwardedPlayerInputFromServer). Provides shared jump reconciliation logic.

## A bitmask representing which of the player's actions are active.
var actions := 0

## Timestamp of the last triggered jump, for network sync of instantaneous
## events. Use -1 (invalid time) to indicate no jump has been triggered yet.
var last_triggered_jump_time_usec := -1

var last_triggered_jump_frame_index: int:
    get:
        return G.network.frame_driver.get_frame_index_from_time_usec(
            last_triggered_jump_time_usec,
        )
    set(value):
        last_triggered_jump_time_usec = \
        G.network.frame_driver.get_time_usec_from_frame_index(value)

var _last_reconciled_jump_frame_index := -1

const _synced_properties_and_rollback_diff_thresholds := {
    actions = 0,
    last_triggered_jump_time_usec = 0,
}


func _get_default_values() -> Array:
    return [
        0, # actions
        -1, # last_triggered_jump_time_usec (-1 = no jump yet)
    ]


func _handle_new_authoritative_state() -> void:
    super._handle_new_authoritative_state()
    _reconcile_jump_event()


func _reconcile_jump_event() -> void:
    var jump_frame := last_triggered_jump_frame_index

    # Skip if not a new jump event.
    if jump_frame <= _last_reconciled_jump_frame_index:
        return
    if last_triggered_jump_time_usec < 0:
        return

    # FIXME: Remove after testing.
    G.print(
        "F:%d Reconciling jump event from frame %d (%s)" % [
            G.network.server_frame_index,
            jump_frame,
            name,
        ],
        ScaffolderLog.CATEGORY_NETWORK_SYNC,
    )

    # Check if frame is too old.
    if G.network.frame_driver.is_frame_too_old_to_consider(jump_frame):
        G.warning(
            "Jump event too old to reconcile: frame %d" % jump_frame,
            ScaffolderLog.CATEGORY_NETWORK_SYNC,
        )
        _last_reconciled_jump_frame_index = jump_frame
        return

    # Check if frame exists in buffer.
    if not _rollback_buffer.has_at(jump_frame):
        _last_reconciled_jump_frame_index = jump_frame
        return

    var frame_state: Array = _rollback_buffer.get_at(jump_frame)

    # Set jump bit in this frame.
    var actions_idx: int = _property_name_to_pack_index.actions
    var current_actions: int = frame_state[actions_idx]
    var jump_bit_mask := 1 << CharacterActionState.BIT_JUMP
    var has_jump_bit := (current_actions & jump_bit_mask) != 0

    if not has_jump_bit:
        if frame_state[frame_state.size() - 1] == FrameAuthority.AUTHORITATIVE:
            G.warning(
                (
                    "last_triggered_jump_time_usec corresponds to a frame that " +
                    "is already recorded as authoritative and without jump " +
                    "pressed: frame %d"
                )
                % jump_frame,
                ScaffolderLog.CATEGORY_NETWORK_SYNC,
            )
            _last_reconciled_jump_frame_index = jump_frame
            return

        frame_state[actions_idx] = current_actions | jump_bit_mask
        _rollback_buffer.set_at(jump_frame, frame_state)

        # Only clear previous frame's jump bit if it wasn't already pressed.
        _clear_jump_bit_in_previous_frame_if_not_held(jump_frame - 1)

        # FIXME: Remove after testing.
        G.print(
            "F:%d Jump bit injected into frame %d, queuing rollback (%s)" % [
                G.network.server_frame_index,
                jump_frame,
                name,
            ],
            ScaffolderLog.CATEGORY_NETWORK_SYNC,
        )
        G.network.frame_driver.queue_rollback(jump_frame)

    _last_reconciled_jump_frame_index = jump_frame


func _clear_jump_bit_in_previous_frame_if_not_held(frame_index: int) -> void:
    if frame_index < 0 or not _rollback_buffer.has_at(frame_index):
        return

    var frame_state: Array = _rollback_buffer.get_at(frame_index)
    var actions_idx: int = _property_name_to_pack_index.actions
    var current_actions: int = frame_state[actions_idx]
    var jump_bit_mask: int = 1 << CharacterActionState.BIT_JUMP

    # Only clear if the frame is predicted (not authoritative).
    var is_predicted: bool = (
        frame_state[frame_state.size() - 1] == FrameAuthority.PREDICTED
    )
    if (current_actions & jump_bit_mask) != 0 and is_predicted:
        frame_state[actions_idx] = current_actions & ~jump_bit_mask
        _rollback_buffer.set_at(frame_index, frame_state)
