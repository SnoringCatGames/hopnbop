@tool
class_name ReconcilableNetworkedState
extends MultiplayerSynchronizer
## Base class for all networked entities that require client-side prediction
## with server-mismatch reconciliation and rollback support.
##
## ReconcilableNetworkedState is the foundation of the networking system,
## providing automatic state replication, client prediction, mismatch detection,
## and rollback reconciliation for any game entity. Subclasses define which
## properties to sync and how to integrate with the scene hierarchy.
##
## Architecture:
## This class bridges three systems:
## 1. **Godot MultiplayerSynchronizer**: Handles low-level replication of
##    packed_state across network
## 2. **RollbackBuffer**: Stores historical states for time-travel during
##    rollback
## 3. **NetworkFrameDriver**: Coordinates frame-synchronous simulation and
##    rollback
##
## Server-authoritative vs client-authoritative:
## - **Server-authoritative** (default): Server is source of truth for entity
##   state (position, health, etc.)
## - **Client-authoritative**: Client is source of truth (used for player input)
##
## Typically used as a pair: one client-authoritative node for input, one
## server-authoritative node for all other state.
##
## Frame processing cycle (called by NetworkFrameDriver):
## 1. **_pre_network_process()**: Restore state from rollback buffer (frame N-1)
##    and sync to scene
## 2. **_network_process()**: Game logic executes (implemented by subclass)
## 3. **_post_network_process()**: Pack state from scene back to properties and
##    buffer
##
## Subclass requirements:
## - Define `_synced_properties_and_rollback_diff_thresholds` dictionary mapping
##   property names to mismatch thresholds
## - Implement `_get_default_values()` to return initial state
## - Implement `_sync_to_scene_state(previous_state)` to update scene from
##   networked properties
## - Implement `_sync_from_scene_state()` to update networked properties from
##   scene
## - Must be marked with @tool annotation
##
## Rollback reconciliation:
## When the server's authoritative state differs from client prediction beyond
## the configured threshold, a rollback is triggered:
## 1. State is restored to the mismatched frame
## 2. All frames from mismatch to present are re-simulated
## 3. Visual state smoothly interpolates (future: rollback visual interpolation)
##
## Thresholds (in _synced_properties_and_rollback_diff_thresholds):
## - Position: typically 1.0 pixel
## - Velocity: typically 10.0 pixels/sec
## - Boolean/String: exact match required (threshold N/A)
## - Numeric: absolute difference threshold
## - Vector2: distance_squared threshold
##
## Usage example:
## ```gdscript
## @tool
## class_name CharacterStateFromServer
## extends ReconcilableNetworkedState
##
## var position := Vector2.ZERO
## var velocity := Vector2.ZERO
##
## var _synced_properties_and_rollback_diff_thresholds := {
##     "position": 1.0,
##     "velocity": 10.0,
## }
##
## func _get_default_values() -> Array:
##     return [Vector2.ZERO, Vector2.ZERO]
##
## func _sync_to_scene_state(_previous_state: Array) -> void:
##     root.position = position
##     root.velocity = velocity
##
## func _sync_from_scene_state() -> void:
##     position = root.position
##     velocity = root.velocity
## ```

enum FrameAuthority {
    UNKNOWN,
    AUTHORITATIVE,
    PREDICTED,
}

signal received_network_state
signal network_processed

# FIXME: Test these rollback diff threshold defaults.
const DEFAULT_POSITION_DIFF_ROLLBACK_THRESHELD := 1.0
const DEFAULT_VELOCITY_DIFF_ROLLBACK_THRESHELD := 10.0

const _MULTIPLAYER_ID_PROPERTY_NAME := "multiplayer_id"

## The estimated server frame, when this state occurred.
var timestamp_index := 0

## This identifies whether this data originated from an authoritative source.
var frame_authority := FrameAuthority.UNKNOWN

## If true, the server is the authoritative source of data for this state.
##
## This likely should only be false for input from the client.
var is_server_authoritative: bool:
    get:
        return _get_is_server_authoritative()

var is_client_authoritative: bool:
    get:
        return not _get_is_server_authoritative()

## This should contain the values for all of the properties of this state
## instance, packed (somewhat) efficiently for syncing across the network.
var packed_state := []:
    set(value):
        packed_state = value

        if not _is_packing_state_locally:
            _handle_new_authoritative_state()

var _is_packing_state_locally := false

var _property_names_for_packing: Array[String] = []
# Dictionary<String, int>
var _property_name_to_pack_index := { }

## Which machine this state is associated with.
##
## - This is used for making sure the right NetworkedNodes actually have
##   authority for triggering the replication.
## - This is the machine that would be given authority to client input.
## - This should be assigned by the server machine when spawning new networked
##   nodes.
## - An ID of 1 represents the server.
var multiplayer_id := 1:
    set(value):
        if value != multiplayer_id:
            multiplayer_id = value
            update_authority()

            # Assign multiplayer_id on the partner InputFromClient.
            if is_server_authoritative and is_instance_valid(_partner_state):
                _partner_state.multiplayer_id = multiplayer_id

var authority_id: int:
    get:
        return NetworkConnector.SERVER_ID if is_server_authoritative else multiplayer_id

## Server-authoritative ReconcilableNetworkedState and client-authoritative
## ReconcilableNetworkedState nodes are often used as a pair to send input state
## from a client machine to the server and to then send all other networked
## state from the server to all clients.
##
## In this scenario, _partner_state is the other node from this pair.
var _partner_state: ReconcilableNetworkedState

var _partner_state_configuration_warning := ""

var root: Node:
    get:
        return get_node_or_null(root_path)

var _rollback_buffer: RollbackBuffer


func _init() -> void:
    if Engine.is_editor_hint():
        return

    G.ensure(
        Utils.check_whether_sub_classes_are_tools(self),
        "Subclasses of ReconcilableNetworkedState must be marked with @tool",
    )


func _enter_tree() -> void:
    if Engine.is_editor_hint():
        return
    G.network.frame_driver.add_networked_state(self)


func _exit_tree() -> void:
    if Engine.is_editor_hint():
        return
    G.network.frame_driver.remove_networked_state(self)


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

    _update_replication_config()
    _update_partner_state()
    update_configuration_warnings()

    if Engine.is_editor_hint():
        return

    if _rollback_buffer == null:
        _set_up_rollback_buffer()

    _parse_property_names()
    update_authority()


func _parse_property_names() -> void:
    _property_names_for_packing.assign(
        get("_synced_properties_and_rollback_diff_thresholds").keys(),
    )
    for i in range(_property_names_for_packing.size()):
        var property_name := _property_names_for_packing[i]
        _property_name_to_pack_index[property_name] = i


func update_authority() -> void:
    set_multiplayer_authority(authority_id)


func _handle_new_authoritative_state() -> void:
    if packed_state.is_empty():
        # Ignore any initial empty state.
        return

    var state_time_usec: int = packed_state[packed_state.size() - 1]
    var state_frame_index := G.network.frame_driver.get_frame_index_from_time_usec(state_time_usec)

    if G.network.frame_driver.is_frame_too_old_to_consider(state_frame_index):
        G.warning(
            "Received networked state that is too old to reconcile - " +
            "DISCARDING: state frame: %d, state time: %d, local frame: %d, " +
            "local time: %d, oldest acceptable: %d"
            % [
                state_frame_index,
                state_time_usec,
                G.network.server_frame_index,
                G.network.server_frame_time_usec,
                G.network.frame_driver.oldest_rollbackable_frame_index,
            ],
            ScaffolderLog.CATEGORY_NETWORK_SYNC,
        )
        return

    var should_trigger_fast_forward := G.network.server_frame_index < state_frame_index - 1
    var should_unpack_state := state_frame_index >= G.network.server_frame_index
    var should_check_for_prediction_mismatch := (
        state_frame_index < G.network.server_frame_index
        and _rollback_buffer.has_at(state_frame_index)
    )

    if should_check_for_prediction_mismatch:
        if _check_is_client_prediction_mismatch(packed_state, state_frame_index):
            var buffer_state: Array = _rollback_buffer.get_at(state_frame_index)
            G.print(
                "Client-prediction state mismatch: networked state: %s, local state: %s"
                % [
                    get_string_for_packed_state(packed_state),
                    get_string_for_packed_state(buffer_state),
                ],
                ScaffolderLog.CATEGORY_NETWORK_SYNC,
            )

            G.network.frame_driver.queue_rollback(state_frame_index)

    # Record rollback buffer frame.
    _pack_buffer_state_from_network_state(packed_state)

    if should_unpack_state:
        # Record local class properties.
        _unpack_networked_state()
        frame_authority = FrameAuthority.AUTHORITATIVE

    received_network_state.emit()

    # If we have skipped frames, we need to force the entire system to
    # fast-forward.
    if should_trigger_fast_forward:
        if G.network.is_server:
            G.warning(
                "Ignoring future state from client",
                ScaffolderLog.CATEGORY_NETWORK_SYNC,
            )
        else:
            G.warning(
                "Fast-forwarding due to future state from server",
                ScaffolderLog.CATEGORY_NETWORK_SYNC,
            )

            # Adjust the time tracker's clock offset to account for the drift.
            # This prevents the NTP averaging from reverting the fast-forward by
            # also adjusting all NTP samples. The force_clock_offset method
            # updates both the current offset and all historical samples to
            # maintain consistency.
            var frames_behind := state_frame_index - 1 - G.network.server_frame_index
            var time_delta_usec := floori(
                frames_behind
                * G.network.frame_driver.TARGET_NETWORK_TIME_STEP_USEC,
            )
            G.network.time.force_clock_offset(time_delta_usec)

            G.network.frame_driver.fast_forward(state_frame_index - 1)


func _network_process() -> void:
    network_processed.emit()


## This is called before _network_process is called on any nodes.
func _pre_network_process() -> void:
    timestamp_index = G.network.server_frame_index
    frame_authority = FrameAuthority.UNKNOWN

    # FIXME: LEFT OFF HERE: What happens during the first calls to _pre_network_process?
    G.check(
        _rollback_buffer.get_latest_index() >= timestamp_index - 2,
        "Rollback buffer does not have state for the expected frame index",
    )

    # We're about to simulate frame N. Start by loading frame N-1's final state
    # as our starting point, and provide frame N-2 as "previous" for just_*
    # comparisons (e.g., just_pressed, just_touched).
    _unpack_buffer_state(timestamp_index - 1)

    var previous_frame_state: Array = _rollback_buffer.get_at(timestamp_index - 2)
    _sync_to_scene_state(previous_frame_state)


## This is called after _network_process has been called on all relevant nodes.
func _post_network_process() -> void:
    _sync_from_scene_state()
    if is_multiplayer_authority():
        _pack_networked_state()
    _pack_buffer_state_from_local_state()


func _get_is_server_authoritative() -> bool:
    G.fatal(
        "Abstract ReconcilableNetworkState._get_is_server_authoritative is not implemented",
    )
    return true


func _get_default_values() -> Array:
    G.fatal(
        "Abstract ReconcilableNetworkState._get_default_values is not implemented",
    )
    return []


## This will update the surrounding scene state to match the networked state.
func _sync_to_scene_state(_previous_state: Array) -> void:
    G.fatal(
        "Abstract ReconcilableNetworkState._sync_to_scene_state is not implemented",
    )


## This will update the networked state to match the surrounding scene state.
func _sync_from_scene_state() -> void:
    G.fatal(
        "Abstract ReconcilableNetworkState._sync_from_scene_state is not implemented",
    )


func _update_replication_config() -> void:
    for property_path in replication_config.get_properties():
        replication_config.remove_property(property_path)

    var packed_state_path := "%s:packed_state" % root.get_path_to(self)
    replication_config.add_property(packed_state_path)


func _set_up_rollback_buffer() -> void:
    var default_values := _get_default_values().duplicate()
    default_values.append(FrameAuthority.PREDICTED)

    _rollback_buffer = (
        RollbackBuffer.new(
            G.network.frame_driver.rollback_buffer_size,
            G.network.frame_driver.server_frame_index,
            default_values,
        )
    )


func _has_authoritative_state_for_current_frame() -> bool:
    if not _rollback_buffer.has_at(G.network.server_frame_index):
        return false
    var frame_data: Array = _rollback_buffer.get_at(G.network.server_frame_index)
    return frame_data[frame_data.size() - 1] == FrameAuthority.AUTHORITATIVE


func _pack_networked_state() -> void:
    var state := ArrayPool.acquire(_property_names_for_packing.size() + 1)

    var i := 0
    for property_name in _property_names_for_packing:
        state[i] = get(property_name)
        i += 1
    # We send time values across the network, but we store indices.
    state[i] = G.network.frame_driver.get_time_usec_from_frame_index(timestamp_index)
    _is_packing_state_locally = true

    if not packed_state.is_empty():
        ArrayPool.release(packed_state)

    packed_state = state
    _is_packing_state_locally = false


func _unpack_networked_state() -> void:
    # Empty packed_state is expected and normal during initial sync. When a
    # ReconcilableNetworkedState is first created, MultiplayerSynchronizer may
    # trigger a sync before we've packed any state.
    if packed_state.is_empty():
        return

    if not (
        G.ensure(
            packed_state.size() == _property_names_for_packing.size() + 1,
        )
    ):
        return

    var i := 0
    for property_name in _property_names_for_packing:
        set(property_name, packed_state[i])
        i += 1
    # We send time values across the network, but we store indices.
    var timestamp_usec: int = packed_state[i]
    timestamp_index = G.network.frame_driver.get_frame_index_from_time_usec(timestamp_usec)


func _pack_buffer_state_from_local_state() -> void:
    var state := ArrayPool.acquire(_property_names_for_packing.size() + 1)

    var i := 0
    for property_name in _property_names_for_packing:
        state[i] = get(property_name)
        i += 1
    state[i] = frame_authority

    # Note: state is now owned by the rollback buffer, don't release it here.
    _record_buffer_frame(timestamp_index, state)


## Records the current state in the rollback buffer at the current simulated
## frame index.
##
## This does _not_ record state in the packed_state array for syncing across the
## network.
func _pack_buffer_state_from_network_state(packed_network_state: Array) -> void:
    var state_time_usec: int = packed_network_state[packed_network_state.size() - 1]
    var frame_index := G.network.frame_driver.get_frame_index_from_time_usec(state_time_usec)

    # For the rollback buffer, we want to record the same state that we
    # replicate across the network, except, we don't need the timestamp and we
    # do need the frame_authority.
    var rollback_frame_state := ArrayPool.acquire(packed_network_state.size())

    for i in range(packed_network_state.size() - 1):
        rollback_frame_state[i] = packed_network_state[i]
    rollback_frame_state[rollback_frame_state.size() - 1] = FrameAuthority.AUTHORITATIVE

    # Note: rollback_frame_state is now owned by the rollback buffer, don't
    #       release it here.
    _record_buffer_frame(frame_index, rollback_frame_state)


func _record_buffer_frame(frame_index: int, frame_state: Array) -> void:
    # TODO: When updating frame buffer state later, reference the preexisting
    #       frame array, rather than instantiating a new one.

    _rollback_buffer.backfill_to_with_last_state(frame_index - 1)

    _rollback_buffer.set_at(frame_index, frame_state)


func _unpack_buffer_state(frame_index: int) -> void:
    var frame_state: Array = _rollback_buffer.get_at(frame_index)

    var i := 0
    for property_name in _property_names_for_packing:
        set(property_name, frame_state[i])
        i += 1
    frame_authority = frame_state[i]


func _check_is_client_prediction_mismatch(
        networked_state: Array,
        frame_index: int,
) -> bool:
    var buffer_data: Array = _rollback_buffer.get_at(frame_index)
    var thresholds: Dictionary = get("_synced_properties_and_rollback_diff_thresholds")

    for property_name in thresholds:
        var threshold = thresholds[property_name]
        var pack_index: int = _property_name_to_pack_index[property_name]
        var networked_value = networked_state[pack_index]
        var buffer_value = buffer_data[pack_index]
        if _check_do_values_mismatch(buffer_value, networked_value, threshold):
            return true

    return false


func _check_do_values_mismatch(
        buffer_value: Variant,
        networked_value: Variant,
        threshold: Variant,
) -> bool:
    match typeof(buffer_value):
        TYPE_BOOL, TYPE_STRING:
            return buffer_value != networked_value
        TYPE_INT, TYPE_FLOAT:
            if threshold == 0:
                # Threshold of 0 means exact match required
                return buffer_value != networked_value
            else:
                return abs(buffer_value - networked_value) >= threshold
        TYPE_VECTOR2, TYPE_VECTOR2I:
            if threshold == 0:
                # Threshold of 0 means exact match required
                return buffer_value != networked_value
            else:
                return buffer_value.distance_squared_to(networked_value) >= threshold * threshold
        _:
            G.fatal(
                "Type not yet supported for client-prediction mismatch threshold calculations: %s"
                % type_string(buffer_value),
            )
            return true


func _update_partner_state() -> void:
    if not is_node_ready():
        # Don't try parsing siblings until we're actually in the tree.
        return

    _partner_state = null

    # Collect all sibling ReconcilableNetworkedState.
    var sibling_states: Array[ReconcilableNetworkedState] = []
    for child in get_parent().get_children():
        if child is ReconcilableNetworkedState and child != self:
            sibling_states.append(child)

    # Record the sibling, and validate the node configuration.
    if sibling_states.size() == 1:
        if sibling_states[0].is_server_authoritative != is_server_authoritative:
            _partner_state = sibling_states[0]
        elif is_server_authoritative:
            _partner_state_configuration_warning = "You should consolidate sibling server-authoritative ReconcilableNetworkedState nodes (or should one be client-authoritative?)"
        else:
            _partner_state_configuration_warning = "There should only be one client-authoritative ReconcilableNetworkedState node here (should one be server-authoritative?)"
    elif sibling_states.size() > 1:
        _partner_state_configuration_warning = "There should be no more than 2 ReconcilableNetworkedState nodes in a given place--one server-authoritative and one client-authoritative"
    elif is_client_authoritative:
        _partner_state_configuration_warning = "A client-authoritative ReconcilableNetworkedState node must be accompanied by a server-authoritative ReconcilableNetworkedState sibling node"

    # Get the multiplayer_id from the parter StateFromServer node.
    if is_instance_valid(_partner_state):
        var state_from_server: ReconcilableNetworkedState = (
            self if is_server_authoritative else _partner_state
        )
        if is_client_authoritative and is_instance_valid(state_from_server):
            multiplayer_id = state_from_server.multiplayer_id

    if not Engine.is_editor_hint() and not _partner_state_configuration_warning.is_empty():
        # Log and assert in game runtime environments.
        G.error(
            "ReconcilableNetworkedState is misconfigured: %s"
            % _partner_state_configuration_warning,
            ScaffolderLog.CATEGORY_CORE_SYSTEMS,
        )

    # Also refresh sibling ReconcilableNetworkedState warnings.
    if is_instance_valid(_partner_state):
        _partner_state.update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
    var warnings: PackedStringArray = []

    var thresholds = get("_synced_properties_and_rollback_diff_thresholds")

    if thresholds == null:
        warnings.append(
            "A _synced_properties_and_rollback_diff_thresholds property must be defined on subclasses of ReconcilableNetworkedState",
        )
    elif not thresholds is Dictionary:
        warnings.append(
            "The _synced_properties_and_rollback_diff_thresholds property must be a Dictionary",
        )
    else:
        # Check if _synced_properties_and_rollback_diff_thresholds matches the other properties.
        for property_name in thresholds.keys():
            if get(property_name) == null:
                warnings.append(
                    "Key %s in _synced_properties_and_rollback_diff_thresholds does not match any class property"
                    % property_name,
                )

    if root_path.is_empty():
        warnings.append("root_path must be defined")
    elif not is_instance_valid(root):
        warnings.append("root_path does not point to a valid node")
    elif not _partner_state_configuration_warning.is_empty():
        warnings.append(_partner_state_configuration_warning)

    return warnings


func get_string_for_packed_state(state: Array) -> String:
    var tokens: Array[String] = []
    tokens.resize(state.size())
    var i := 0
    for value in state:
        tokens[i] = _get_string_for_value(value, i == state.size() - 1)
        i += 1

    return "[%s]" % ",".join(tokens)


func _get_string_for_value(value, is_final_value := false) -> String:
    match typeof(value):
        TYPE_BOOL, TYPE_STRING:
            return str(value)
        TYPE_INT:
            # By default, we display int values as bitmasks.
            if is_final_value:
                return str(value)
            return _get_string_for_bitmask(value)
        TYPE_FLOAT:
            return "%.1f" % value
        TYPE_VECTOR2, TYPE_VECTOR2I:
            return Utils.get_vector_string(value, 1)
        _:
            G.fatal(
                "Type not yet supported for rollback buffer: %s" % type_string(value),
            )
            return ""


func _get_string_for_bitmask(value: int) -> String:
    return String.num_int64(value, 2).lpad(8, "0")
