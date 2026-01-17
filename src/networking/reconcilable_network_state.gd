@tool
class_name ReconcilableNetworkedState
extends MultiplayerSynchronizer
## FIXME: [Rollback] Write extensive docs for this class.
##
## - In general, during rollback ReconcilableNetworkedState is responsible for updating the
##   state of all properties directly specified in its replication_config, but
##   also any state within the current scene that is derived from this state.
##


# FIXME: [Rollback] Add support here for maintaining the buffer.
# - Use G.settings.rollback_buffer_duration_sec
# - Use NetworkMain.TARGET_NETWORK_FPS
# - var buffer_size := ceili(G.settings.rollback_buffer_duration_sec * NetworkMain.TARGET_NETWORK_FPS)


# FIXME: [Pre-Rollback]: Add another super-hud debug display:
# - Show the current Physics process, Render process, and Network process FPS.
#   - Keep a running average over the latest 1 second (make that number
#     configurable).
#   - Keep a circular buffer for the start_times of the last 100 for each
#     (also configurable).
# - Toggleable in Settings.
# - Check how network process compares to physics process (both are hopefully
#   close to 60 FPS?).
#   - If network is much slower, consider adjusting my rollback frame index
#     bucketing.
# - Log warnings when any of these three FPS dimensions drops below some
#   threshold.
#   - Separate threshold for each.
# - And log a print message when they recover.


enum Authority {
    UNKNOWN,
    AUTHORITATIVE,
    PREDICTED,
}


signal network_processed


# FIXME: [Rollback] Test these rollback diff threshold defaults.
const DEFAULT_POSITION_DIFF_ROLLBACK_THRESHELD := 0.5
const DEFAULT_VELOCITY_DIFF_ROLLBACK_THRESHELD := 1.0
const DEFAULT_NORMAL_DIFF_ROLLBACK_THRESHELD := 0.05

const _MULTIPLAYER_ID_PROPERTY_NAME := "multiplayer_id"

## The estimated server time, in microseconds, when this state occurred.
var timestamp_usec := 0

## This identifies whether this data originated from an authoritative source.
var data_source := Authority.UNKNOWN

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
            _unpack_state()

var _is_packing_state_locally := false

var _property_names_for_packing: Array[String] = []

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
            set_multiplayer_authority(authority_id)

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


func _init() -> void:
    if Engine.is_editor_hint():
        return
    G.ensure(Utils.check_whether_sub_classes_are_tools(self),
        "Subclasses of ReconcilableNetworkedState must be marked with @tool")


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

    set_multiplayer_authority(authority_id)


func _network_process() -> void:
    network_processed.emit()


## This is called before _network_process is called on any nodes.
func _pre_network_process() -> void:
    _sync_to_scene_state()


## This is called after _network_process has been called on all relevant nodes.
func _post_network_process() -> void:
    if is_multiplayer_authority():
        _sync_from_scene_state()
    _record_rollback_frame()


## This will update the surrounding scene state to match the networked state.
func _sync_to_scene_state() -> void:
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


## Records the current state in the rollback buffer at the current simulated
## frame index.
##
## This does _not_ record state in the packed_state array for syncing across the
## network. That step is handled separately, after any rollback extrapolation
## simulations are finished.
func _record_rollback_frame() -> void:
    timestamp_usec = G.network.server_frame_time_usec

    var is_authoritative_source := \
        is_server_authoritative == G.network.is_server

    data_source = \
        Authority.AUTHORITATIVE if \
        is_authoritative_source else \
        Authority.PREDICTED

    # FIXME: [Rollback]: Record frame in buffer.
    # - Call pack_state() and record that array?

    # FIXME: [Rollback] Fill previous empty frames.
    # - Use G.network.server_frame_index
    # - Extrapolate from the last-filled frame in order to populate any empty
    #   frames preceding this frame.
    # - Unless there is no last-filled frame, in which case use default values.


func pack_state() -> void:
    var thresholds: Dictionary = \
        get("_synced_properties_and_rollback_diff_thresholds")
    G.check_valid(thresholds)
    var property_names := thresholds.keys()
    var state := []
    state.resize(property_names.size() + 1)
    state[0] = timestamp_usec
    var i := 1
    for property_name in property_names:
        state[i] = get(property_name)
        i += 1
    _is_packing_state_locally = true
    packed_state = state
    _is_packing_state_locally = false


func _unpack_state() -> void:
    if packed_state.is_empty():
        # This happens for the initial sync, when there is no state to send yet.
        return

    if not G.ensure(
            packed_state.size() == _property_names_for_packing.size() + 1):
        return

    timestamp_usec = packed_state[0]
    var i := 1
    for property_name in _property_names_for_packing:
        set(property_name, packed_state[i])
        i += 1


func _update_partner_state() -> void:
    if not is_node_ready():
        # Don't try parsing siblings until we're actually in the tree.
        return

    _partner_state = null

    # Collect all sibling ReconcilableNetworkedState.
    var sibling_states: Array[ReconcilableNetworkedState] = []
    for child in get_parent().get_children():
        if child is ReconcilableNetworkedState and child != self:
            sibling_states.push_back(child)

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
        warnings.push_back(
            "A _synced_properties_and_rollback_diff_thresholds property must be defined on subclasses of ReconcilableNetworkedState")
    elif not thresholds is Dictionary:
        warnings.push_back(
            "The _synced_properties_and_rollback_diff_thresholds property must be a Dictionary")
    else:
        # Check if _synced_properties_and_rollback_diff_thresholds matches the other properties.
        for property_name in thresholds.keys():
            if get(property_name) == null:
                warnings.push_back(
                    "Key %s in _synced_properties_and_rollback_diff_thresholds does not match any class property" % property_name)

    if root_path.is_empty():
        warnings.push_back("root_path must be defined")
    elif not is_instance_valid(root):
        warnings.push_back("root_path does not point to a valid node")
    elif not _partner_state_configuration_warning.is_empty():
        warnings.append(_partner_state_configuration_warning)

    return warnings
