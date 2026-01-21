@tool
class_name CharacterStateFromServer
extends ReconcilableNetworkedState

@export var character: Character:
    set(value):
        character = value
        update_configuration_warnings()

var state_from_client: PlayerInputFromClient:
    get:
        if is_instance_valid(_partner_state):
            return _partner_state as PlayerInputFromClient
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


func _get_is_server_authoritative() -> bool:
    return true


func _ready() -> void:
    super._ready()
    update_configuration_warnings()


func _update_replication_config() -> void:
    super._update_replication_config()

    # Also sync the multiplayer_id, so the client can know which player has
    # authority.
    var multiplayer_id_path := "%s:multiplayer_id" % root.get_path_to(self)
    replication_config.add_property(multiplayer_id_path)
    replication_config.property_set_replication_mode(
        multiplayer_id_path,
        SceneReplicationConfig.ReplicationMode.REPLICATION_MODE_ON_CHANGE,
    )
    replication_config.property_set_spawn(multiplayer_id_path, true)


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
        # Authoritative input already received for this frame - use it.
        # This happens when the client has sent input that arrived and was
        # unpacked into the buffer during _handle_new_authoritative_state.
        state_from_client._unpack_buffer_state(timestamp_index)
        # Update surface attachment state based on the input we just loaded.
        character.surfaces.update_actions()
    else:
        if is_authority_for_state_from_client:
            # This client controls input - capture it now as authoritative.
            # _collect_actions() will call surfaces.update_actions() internally.
            character._collect_actions()
            state_from_client.frame_authority = FrameAuthority.AUTHORITATIVE
        else:
            # No new input yet - extrapolate from previous frame's input.
            # This is intentional: predicted input uses the last known state
            # (N-1) to simulate frame N, while authoritative input that arrives
            # later will be at frame N.
            state_from_client._unpack_buffer_state(timestamp_index - 1)
            state_from_client.frame_authority = FrameAuthority.PREDICTED
            # Update surface attachment state based on the input we just loaded.
            character.surfaces.update_actions()

    # Handle scene state (from the server).
    if is_authority_for_state_from_server:
        # The server always processes each frame, and records the resulting
        # scene state as authoritative.
        character._apply_movement()
        frame_authority = FrameAuthority.AUTHORITATIVE
    else:
        if _has_authoritative_state_for_current_frame():
            # We already recorded authoritative state for this frame, so we
            # don't want to overwrite it.
            _unpack_buffer_state(timestamp_index)
        else:
            # Process the frame, and record the scene state as predicted.
            character._apply_movement()
            frame_authority = FrameAuthority.PREDICTED

    character._process_movement_and_actions()

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
