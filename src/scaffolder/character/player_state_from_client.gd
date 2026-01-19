@tool
class_name PlayerStateFromClient
extends ReconcilableNetworkedState

# FIXME: Override configuration warnings to check this is set.
@export var player: Player

var state_from_server: CharacterStateFromServer:
    get:
        if is_instance_valid(_partner_state):
            return _partner_state as CharacterStateFromServer
        else:
            return null

## A bitmask representing which of the player's actions are active.
var actions := 0

## Timestamp of the last triggered jump, for network sync of instantaneous events.
var last_triggered_jump_time_usec := 0

var last_triggered_jump_frame_index: int:
    get:
        return G.network.frame_driver.get_frame_index_from_time(
            last_triggered_jump_time_usec,
        )
    set(value):
        last_triggered_jump_time_usec = \
        G.network.frame_driver.get_time_from_frame_index(value)

var _last_reconciled_jump_frame_index := -1

const _synced_properties_and_rollback_diff_thresholds := {
    actions = 0,
    last_triggered_jump_time_usec = 0,
}


func _get_default_values() -> Array:
    return [
        0,
        0,
    ]


func _exit_tree() -> void:
    if is_multiplayer_authority():
        G.network.local_authority_removed.emit(self)


func update_authority() -> void:
    var was_multiplayer_authority := is_multiplayer_authority()
    super.update_authority()
    if is_multiplayer_authority() and not was_multiplayer_authority:
        G.network.local_authority_added.emit(self)


func _network_process() -> void:
    # CharacterStateFromServer handles _network_process for itself and any
    # corresponding PlayerStateFromClient.
    pass


func _sync_to_scene_state(previous_state: Array) -> void:
    if not G.ensure_valid(player):
        return

    player.actions.bitmask = actions

    player.actions.previous_bitmask = previous_state[_property_name_to_pack_index.actions]

    player.last_triggered_jump_frame_index = last_triggered_jump_frame_index


func _sync_from_scene_state() -> void:
    if not G.ensure_valid(player):
        return

    actions = player.actions.bitmask
    last_triggered_jump_frame_index = player.last_triggered_jump_frame_index


func _handle_new_authoritative_state() -> void:
    super._handle_new_authoritative_state()
    _reconcile_jump_event()


func _reconcile_jump_event() -> void:
    var jump_frame := last_triggered_jump_frame_index

    # Skip if not a new jump event.
    if jump_frame <= _last_reconciled_jump_frame_index:
        return
    if last_triggered_jump_time_usec == 0:
        return

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
        var is_authoritative: int = (
            frame_state[frame_state.size() - 1] == FrameAuthority.AUTHORITATIVE
        )
        if is_authoritative:
            G.warning(
                "last_triggered_jump_time_usec corresponds to a frame that " +
                "is already recorded as authoritative and without jump " +
                "pressed: frame %d" % jump_frame,
                ScaffolderLog.CATEGORY_NETWORK_SYNC,
            )
            _last_reconciled_jump_frame_index = jump_frame
            return

        frame_state[actions_idx] = current_actions | jump_bit_mask
        _rollback_buffer.set_at(jump_frame, frame_state)

        # Ensure previous frame has no jump bit.
        _clear_jump_bit_in_frame(jump_frame - 1)

        G.network.frame_driver.queue_rollback(jump_frame)

    _last_reconciled_jump_frame_index = jump_frame


func _clear_jump_bit_in_frame(frame_index: int) -> void:
    if frame_index < 0 or not _rollback_buffer.has_at(frame_index):
        return

    var frame_state: Array = _rollback_buffer.get_at(frame_index)
    var actions_idx: int = _property_name_to_pack_index.actions
    var current_actions: int = frame_state[actions_idx]
    var jump_bit_mask := 1 << CharacterActionState.BIT_JUMP

    if (current_actions & jump_bit_mask) != 0:
        frame_state[actions_idx] = current_actions & ~jump_bit_mask
        _rollback_buffer.set_at(frame_index, frame_state)
