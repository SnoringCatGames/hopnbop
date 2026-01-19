@tool
class_name CharacterStateFromServer
extends ReconcilableNetworkedState

@export var character: Character:
    set(value):
        character = value
        update_configuration_warnings()

var state_from_client: PlayerStateFromClient:
    get:
        if is_instance_valid(_partner_state):
            return _partner_state as PlayerStateFromClient
        else:
            return null

var is_authority_for_state_from_server: bool:
    get:
        return is_multiplayer_authority()

var is_authority_for_state_from_client: bool:
    get:
        return is_instance_valid(state_from_client) and state_from_client.is_multiplayer_authority()

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


func _ready() -> void:
    super._ready()
    update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
    var warnings := super._get_configuration_warnings()
    if not is_instance_valid(character):
        warnings.append("character is not set")
    return warnings


func _network_process() -> void:
    if not G.ensure_valid(character):
        return

    # Handle actions (from a client).
    if state_from_client._has_authoritative_state_for_current_frame():
        # We already recorded authoritative state for this frame, so we don't
        # want to overwrite it.
        state_from_client._unpack_buffer_state(timestamp_index)
    else:
        if is_authority_for_state_from_client:
            # This is the client that controls actions for this player.
            character._update_actions()
            state_from_client.frame_authority = FrameAuthority.AUTHORITATIVE
        else:
            # This machine only records actions that have been sent from the
            # authoritative client.
            state_from_client._unpack_buffer_state(timestamp_index - 1)
            state_from_client.frame_authority = FrameAuthority.PREDICTED

    # Handle scene state (from the server).
    if is_authority_for_state_from_server:
        # The server always processes each frame, and records the resulting
        # scene state as authoritative.
        character._network_process()
        frame_authority = FrameAuthority.AUTHORITATIVE
    else:
        if _has_authoritative_state_for_current_frame():
            # We already recorded authoritative state for this frame, so we
            # don't want to overwrite it.
            _unpack_buffer_state(timestamp_index)
        else:
            # Process the frame, and record the scene state as predicted.
            character._network_process()
            frame_authority = FrameAuthority.PREDICTED

    super._network_process()


func _sync_to_scene_state(previous_state: Array) -> void:
    if not G.ensure_valid(character):
        return

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
