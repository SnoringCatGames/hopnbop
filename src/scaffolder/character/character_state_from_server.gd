@tool
class_name CharacterStateFromServer
extends ReconcilableNetworkedState

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
    var has_predicted_forwarded_input := (
        input_source is ForwardedPlayerInputFromServer and
        input_source._rollback_buffer.has_at(timestamp_index)
    )

    if has_auth_input or has_predicted_forwarded_input:
        # Use received input from buffer (either authoritative from
        # PlayerInputFromClient, or predicted from ForwardedPlayerInputFromServer).
        input_source._unpack_buffer_state(timestamp_index)
        # Copy input from source to character.
        _apply_input_to_character(input_source)
        # Update surface attachment state based on the input we just loaded.
        character.surfaces.update_actions()
        if G.is_verbose:
            var authority_str := "PREDICTED" if has_predicted_forwarded_input else "AUTHORITATIVE"
            G.print(
                "F:%d Using %s input (actions=%d)" % [
                    G.network.server_frame_index,
                    authority_str,
                    character.actions.bitmask,
                ],
                ScaffolderLog.CATEGORY_NETWORK_SYNC,
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
        forwarded_input_from_server.last_triggered_jump_time_usec = input_from_client.last_triggered_jump_time_usec
        forwarded_input_from_server.frame_authority = input_from_client.frame_authority
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
                (
                    "F:%d Remote simulation: pos %s->%s, vel %s->%s, " +
                    "actions=%d"
                )
                % [
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
    if input_source is PlayerInputFromClient:
        var input := input_source as PlayerInputFromClient
        character.actions.bitmask = input.actions
        character.last_triggered_jump_frame_index = input.last_triggered_jump_frame_index
    elif input_source is ForwardedPlayerInputFromServer:
        var input := input_source as ForwardedPlayerInputFromServer
        character.actions.bitmask = input.actions
        character.last_triggered_jump_frame_index = input.last_triggered_jump_frame_index
