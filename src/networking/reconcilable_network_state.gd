@tool
class_name ReconcilableNetworkedState
extends MultiplayerSynchronizer
## FIXME: [Rollback] Write extensive docs for this class.
##
## - In general, during rollback ReconcilableNetworkedState is responsible for updating the
##   state of all properties directly specified in its replication_config, but
##   also any state within the current scene that is derived from this state.
##


enum FrameAuthority {
    UNKNOWN,
    AUTHORITATIVE,
    PREDICTED,
}


signal received_network_state
signal network_processed


# FIXME: [Rollback] Test these rollback diff threshold defaults.
const DEFAULT_POSITION_DIFF_ROLLBACK_THRESHELD := 0.5
const DEFAULT_VELOCITY_DIFF_ROLLBACK_THRESHELD := 1.0
const DEFAULT_NORMAL_DIFF_ROLLBACK_THRESHELD := 0.05

const _MULTIPLAYER_ID_PROPERTY_NAME := "multiplayer_id"

## The estimated server time, in microseconds, when this state occurred.
var timestamp_usec := 0

## This identifies whether this data originated from an authoritative source.
var frame_authority := FrameAuthority.UNKNOWN

## If true, the server is the authoritative source of data for this state.
##
## This likely should only be false for input from the client.
@export var is_server_authoritative := true:
    set(value):
        is_server_authoritative = value
        _update_partner_state()
        update_configuration_warnings()

var is_client_authoritative: bool:
    get: return not is_server_authoritative

## This should contain the values for all of the properties of this state
## instance, packed (somewhat) efficiently for syncing across the network.
var packed_state := []:
    set(value):
        packed_state = value
        if not _is_packing_state_locally:
            _unpack_networked_state()
            frame_authority = FrameAuthority.AUTHORITATIVE

var _is_packing_state_locally := false

var _property_names_for_packing: Array[String] = []
# Dictionary<String, int>
var _property_name_to_pack_index := {}

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
        return NetworkConnector.SERVER_ID if \
            is_server_authoritative else \
            multiplayer_id

## Server-authoritative ReconcilableNetworkedState and client-authoritative
## ReconcilableNetworkedState nodes are often used as a pair to send input state
## from a client machine to the server and to then send all other networked
## state from the server to all clients.
##
## In this scenario, _partner_state is the other node from this pair.
var _partner_state: ReconcilableNetworkedState

var _partner_state_configuration_warning := ""

var root: Node:
    get: return get_node_or_null(root_path)

# FIXME: [Rollback] Add support here for maintaining the buffer.
var _rollback_buffer: RollbackBuffer


func _init() -> void:
    if Engine.is_editor_hint():
        return

    G.ensure(Utils.check_whether_sub_classes_are_tools(self),
        "Subclasses of ReconcilableNetworkedState must be marked with @tool")

    _set_up_rollback_buffer()


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

    _parse_property_names()
    update_authority()


func _parse_property_names() -> void:
    _property_names_for_packing = \
        get("_synced_properties_and_rollback_diff_thresholds").keys()
    for i in range(_property_names_for_packing.size()):
        var property_name := _property_names_for_packing[i]
        _property_name_to_pack_index[property_name] = i


func update_authority() -> void:
    set_multiplayer_authority(authority_id)


func _network_process() -> void:
    network_processed.emit()


## This is called before _network_process is called on any nodes.
func _pre_network_process() -> void:
    timestamp_usec = G.network.server_frame_time_usec

    # FIXME: LEFT OFF HERE: ACTUALLY, ACTUALLY, ACTUALLY, ACTUALLY: ----------------
    # - NO! Update this to sync to the state from the _previous_ frame.
    #   - Implement _get_previous_frame_state()
    #     - Use G.network.frame_driver.server_frame_index
    #   - JUST ACCESSING get_previous is not sufficient! Need to backfill.
    # - After finishing hooking up all the parts, walk through each bit and
    #  double-check if we're setting and getting "latest" state from the buffer
    #  at the correct times (before and after the simulation). Like, should we
    #  actually access get_latest() instead of get_previous() from the buffer
    #  here?

    var frame_state: Array = _rollback_buffer.get_at(
        G.network.frame_driver.server_frame_index - 1)
    var previous_frame_state: Array = _rollback_buffer.get_at(
        G.network.frame_driver.server_frame_index - 2)
    _unpack_rollback_state(frame_state)
    _sync_to_scene_state(previous_frame_state)


## This is called after _network_process has been called on all relevant nodes.
func _post_network_process() -> void:
    _sync_from_scene_state()
    _record_rollback_frame()


func _get_default_values() -> Array:
    G.fatal(
        "Abstract ReconcilableNetworkState._get_default_values is not implemented")
    return []


## This will update the surrounding scene state to match the networked state.
func _sync_to_scene_state(previous_state: Array) -> void:
    G.fatal(
        "Abstract ReconcilableNetworkState._sync_to_scene_state is not implemented")


## This will update the networked state to match the surrounding scene state.
func _sync_from_scene_state() -> void:
    G.fatal(
        "Abstract ReconcilableNetworkState._sync_from_scene_state is not implemented")


func _update_replication_config() -> void:
    for property_path in replication_config.get_properties():
        replication_config.remove_property(property_path)

    var packed_state_path := "%s:packed_state" % root.get_path_to(self)
    replication_config.add_property(packed_state_path)


func _set_up_rollback_buffer() -> void:
    var default_values := _get_default_values().duplicate()
    default_values.append(FrameAuthority.PREDICTED)
    _rollback_buffer = RollbackBuffer.new(
        G.network.frame_driver.rollback_buffer_size,
        G.network.frame_driver.server_frame_index,
        default_values)


## Records the current state in the rollback buffer at the current simulated
## frame index.
##
## This does _not_ record state in the packed_state array for syncing across the
## network. That step is handled separately, after any rollback extrapolation
## simulations are finished.
func _record_rollback_frame() -> void:
    # FIXME: LEFT OFF HERE: ACTUALLY, ACTUALLY, ACTUALLY: Check this...
    pass

    _pack_networked_state()

    # For the rollback buffer, we want to record the same state that we
    # replicate across the network, except, we don't need the timestamp and we
    # do need the frame_authority.
    var rollback_frame_state := packed_state.duplicate()
    rollback_frame_state[rollback_frame_state.size() - 1] = frame_authority

    # FIXME: LEFT OFF HERE: ACTUALLY: When updating frame buffer state later,
    #   reference the preexisting frame array, rather than instantiating a new
    #   one.

    # FIXME: LEFT OFF HERE: ACTUALLY: When updating buffer frame with just-synced
    #        packed_state from the server, make sure we backfill as needed there
    #        too.

    _rollback_buffer.backfill_to_with_last_state(
        G.network.frame_driver.server_frame_index)

    _rollback_buffer.set_at(
        G.network.frame_driver.server_frame_index,
        rollback_frame_state)


func _has_authoritative_state_for_current_frame() -> bool:
    if not _rollback_buffer.has_at(G.network.frame_driver.server_frame_index):
        return false
    var frame_data: Array = _rollback_buffer.get_at(
        G.network.frame_driver.server_frame_index)
    # FIXME: LEFT OFF HERE: ACTUALLY: Change the index that I check for this.
    return frame_data[1] == FrameAuthority.AUTHORITATIVE


func _pack_networked_state() -> void:
    var state := []
    state.resize(_property_names_for_packing.size() + 1)
    var i := 0
    for property_name in _property_names_for_packing:
        state[i] = get(property_name)
        i += 1
    state[i] = timestamp_usec
    _is_packing_state_locally = true
    packed_state = state
    _is_packing_state_locally = false


func _unpack_networked_state() -> void:
    if packed_state.is_empty():
        # This happens for the initial sync, when there is no state to send yet.
        return

    if not G.ensure(
            packed_state.size() == _property_names_for_packing.size() + 1):
        return

    var i := 0
    for property_name in _property_names_for_packing:
        set(property_name, packed_state[i])
        i += 1
    timestamp_usec = packed_state[i]

    received_network_state.emit()


func _unpack_rollback_state(frame_state: Array) -> void:
    var i := 0
    for property_name in _property_names_for_packing:
        set(property_name, frame_state[i])
        i += 1
    frame_authority = packed_state[i]


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
            _partner_state_configuration_warning = \
                "You should consolidate sibling server-authoritative ReconcilableNetworkedState nodes (or should one be client-authoritative?)"
        else:
            _partner_state_configuration_warning = \
                "There should only be one client-authoritative ReconcilableNetworkedState node here (should one be server-authoritative?)"
    elif sibling_states.size() > 1:
        _partner_state_configuration_warning = \
            "There should be no more than 2 ReconcilableNetworkedState nodes in a given place--one server-authoritative and one client-authoritative"
    elif is_client_authoritative:
        _partner_state_configuration_warning = \
            "A client-authoritative ReconcilableNetworkedState node must be accompanied by a server-authoritative ReconcilableNetworkedState sibling node"

    # Get the multiplayer_id from the parter StateFromServer node.
    if is_instance_valid(_partner_state):
        var state_from_server: ReconcilableNetworkedState = \
            self if is_server_authoritative else _partner_state
        if is_client_authoritative and is_instance_valid(state_from_server):
            multiplayer_id = state_from_server.multiplayer_id

    if not Engine.is_editor_hint() and \
            not _partner_state_configuration_warning.is_empty():
        # Log and assert in game runtime environments.
        G.error("ReconcilableNetworkedState is misconfigured: %s" %
            _partner_state_configuration_warning,
            ScaffolderLog.CATEGORY_CORE_SYSTEMS)

    # Also refresh sibling ReconcilableNetworkedState warnings.
    if is_instance_valid(_partner_state):
        _partner_state.update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
    var warnings: PackedStringArray = []

    var thresholds = get("_synced_properties_and_rollback_diff_thresholds")

    if thresholds == null:
        warnings.append(
            "A _synced_properties_and_rollback_diff_thresholds property must be defined on subclasses of ReconcilableNetworkedState")
    elif not thresholds is Dictionary:
        warnings.append(
            "The _synced_properties_and_rollback_diff_thresholds property must be a Dictionary")
    else:
        # Check if _synced_properties_and_rollback_diff_thresholds matches the other properties.
        for property_name in thresholds.keys():
            if get(property_name) == null:
                warnings.append(
                    "Key %s in _synced_properties_and_rollback_diff_thresholds does not match any class property" % property_name)

    if root_path.is_empty():
        warnings.append("root_path must be defined")
    elif not is_instance_valid(root):
        warnings.append("root_path does not point to a valid node")
    elif not _partner_state_configuration_warning.is_empty():
        warnings.append(_partner_state_configuration_warning)

    return warnings
