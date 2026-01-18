@tool
class_name CharacterStateFromServer
extends ReconcilableNetworkedState


# FIXME: Override configuration warnings to check this is set.
@export var character: Character

var _state_from_client: PlayerStateFromClient:
    get:
        if is_instance_valid(_partner_state):
            return _partner_state as PlayerStateFromClient
        else:
            return null

var is_authority_for_state_from_server: bool:
    get: return is_multiplayer_authority()

var is_authority_for_state_from_client: bool:
    get: return is_instance_valid(_state_from_client) and \
        _state_from_client.is_multiplayer_authority()

var position := Vector2.ZERO
var velocity := Vector2.ZERO
## A bitmask representing the player's surface state.
var surfaces := 0

const _synced_properties_and_rollback_diff_thresholds := {
    position = DEFAULT_POSITION_DIFF_ROLLBACK_THRESHELD,
    velocity = DEFAULT_VELOCITY_DIFF_ROLLBACK_THRESHELD,
    surfaces = 0,
}


func _get_default_values() -> Array:
    return [
        Vector2.ZERO,
        Vector2.ZERO,
        0,
    ]


func _network_process() -> void:
    if not G.ensure_valid(character):
        return

    # FIXME: LEFT OFF HERE: ACTUALLY: Set this.
    frame_authority = \
        FrameAuthority.AUTHORITATIVE if \
        is_multiplayer_authority() else \
        FrameAuthority.PREDICTED

    # Handle actions (from a client).
    if _state_from_client._has_authoritative_state_for_current_frame():
        # We already recorded authoritative state for this frame, so we don't
        # want to overwrite it.
        pass
    else:
        if is_authority_for_state_from_client:
            # This is the client that controls actions for this player.
            character._update_actions()
            # FIXME: LEFT OFF HERE: Mark frame as authoritative.
        else:
            # This machine only records actions that have been sent from the
            # authoritative client.
            # FIXME: LEFT OFF HERE: Copy state from previous frame (check if
            #        there _is_ a previous frame first).
            # - Mark frame as predicted.
            # - Make sure the code path for marking frames as authoritative when
            #   coming from the server is set up.
            pass

    # Handle scene state (from the server).
    if is_authority_for_state_from_server:
        # The server always processes each frame, and records the resulting
        # scene state as authoritative.
        character._network_process()
        # FIXME: LEFT OFF HERE: Mark frame as authoritative.
    else:
        if _has_authoritative_state_for_current_frame():
            # We already recorded authoritative state for this frame, so we
            # don't want to overwrite it.
            pass
        else:
            # Process the frame, and record the scene state as predicted.
            character._network_process()
            # FIXME: LEFT OFF HERE: Mark frame as predicted.

    super._network_process()


func _sync_to_scene_state(previous_state: Array) -> void:
    if not G.ensure_valid(character):
        return

    character.position = position
    character.velocity = velocity
    character.surfaces.bitmask = surfaces

    character.previous_position = \
        previous_state[_property_name_to_pack_index.position]
    character.previous_velocity = \
        previous_state[_property_name_to_pack_index.velocity]
    character.surfaces.previous_bitmask = \
        previous_state[_property_name_to_pack_index.surfaces]


func _sync_from_scene_state() -> void:
    if not G.ensure_valid(character):
        return

    position = character.position
    velocity = character.velocity
    surfaces = character.surfaces.bitmask
