@tool
class_name NetworkedState
extends MultiplayerSynchronizer


# FIXME: LEFT OFF HERE: Replace the old MultiplayerReconciler with this.
# - Move logic from there to here.
# - Add a function here, and call it from player, for record_frame.
# - Add support here for maintaining the buffer.
#   - Use G.settings.rollback_buffer_duration_sec
#   - Use NetworkingMain.TARGET_NETWORK_FPS
#   - var buffer_size := ceili(G.settings.rollback_buffer_duration_sec * NetworkingMain.TARGET_NETWORK_FPS)


# FIXME: LEFT OFF HERE: Add another super-hud debug display:
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


# FIXME: [Rollback] Test these rollback diff threshold defaults.
const DEFAULT_POSITION_DIFF_ROLLBACK_THRESHELD := 0.5
const DEFAULT_VELOCITY_DIFF_ROLLBACK_THRESHELD := 1.0
const DEFAULT_NORMAL_DIFF_ROLLBACK_THRESHELD := 0.05

## The estimated server time, in microseconds, when this state occurred.
var timestamp_usec := 0

## This identifies whether this data originated from an authoritative source.
var data_source := Authority.UNKNOWN

## If true, the server is the authoritative source of data for this state.
## 
## This likely should only be false for input from the client.
@export var is_server_authoritative := true

## This should contain the values for all of the properties of this state
## instance, packed (somewhat) efficiently for syncing across the network.
var packed_state := []:
    set(value):
        packed_state = value
        if not _is_packing_state_locally:
            _unpack_state()

var _is_packing_state_locally := false

# Dictionary<String, bool>
static var _excluded_property_names_for_packing := {}

var _property_names_for_packing: Array[String] = []

var root: Node:
    get: return get_node_or_null(root_path)


static func set_up_static_state() -> void:
    var dummy := NetworkedState.new()
    var names := Utils.get_script_property_names(dummy.get_script())
    _excluded_property_names_for_packing = Utils.array_to_set(names)
    # We also require child classes to include this propert, but we don't want
    # to network it.
    _excluded_property_names_for_packing._property_diff_rollback_thresholds = true


func _init() -> void:
    G.ensure(Utils.check_whether_sub_classes_are_tools(self),
        "Subclasses of NetworkedState must be marked with @tool.")
    _property_names_for_packing = Utils.get_script_property_names(
        get_script(),
        _excluded_property_names_for_packing)


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _update_replication_config()
    update_configuration_warnings()


func _update_replication_config() -> void:
    for property_path in replication_config.get_properties():
        replication_config.remove_property(property_path)
    
    var packed_state_path := "%s:packed_state" % root.get_path_to(self)
    replication_config.add_property(packed_state_path)


# FIXME: LEFT OFF HERE: Call this.
func record_frame() -> void:
    if G.ensure(data_source != Authority.AUTHORITATIVE,
            "State is already authoritative, and cannot be overwritten."):
        return
    
    timestamp_usec = G.network.server_canonical_frame_time_usec
    
    var is_authoritative_source := \
        is_server_authoritative == G.network.is_server
    
    data_source = \
        Authority.AUTHORITATIVE if \
        is_authoritative_source else \
        Authority.PREDICTED
    
    _pack_state()
    
    # FIXME: [Rollback] Fill previous empty frames.
    # - Use G.network.get_server_frame_index(timestamp_usec)
    # - Extrapolate from the last-filled frame in order to populate any empty
    #   frames preceding this frame.
    # - Unless there is no last-filled frame, in which case use default values.


func _pack_state() -> void:
    var state := []
    state.resize(_property_names_for_packing.size() + 1)
    state[0] = timestamp_usec
    var i := 1
    for property_name in _property_names_for_packing:
        state[i] = get(property_name)
        i += 1
    _is_packing_state_locally = true
    packed_state = state
    _is_packing_state_locally = false


func _unpack_state() -> void:
    if packed_state.is_empty():
        # This happens for the initial sync, when there is no state to send yet.
        return
        
    if not G.ensure(packed_state.size() == _property_names_for_packing.size() + 1):
        return

    timestamp_usec = packed_state[0]
    var i := 1
    for property_name in _property_names_for_packing:
        set(property_name, packed_state[i])
        i += 1


func _get_configuration_warnings() -> PackedStringArray:
    var warnings: PackedStringArray = []
    
    var _property_diff_rollback_thresholds = get("_property_diff_rollback_thresholds")
    
    if _property_diff_rollback_thresholds == null:
        warnings.push_back(
            "A _property_diff_rollback_thresholds property must be defined on subclasses of NetworkedState.")
    elif not _property_diff_rollback_thresholds is Dictionary:
        warnings.push_back(
            "The _property_diff_rollback_thresholds property must be a Dictionary.")
    else:
        # Check if _property_diff_rollback_thresholds matches the other properties.
        var properties_match := true
        if _property_diff_rollback_thresholds.size() != _property_names_for_packing.size():
            properties_match = false
        else:
            for property_name in _property_names_for_packing:
                if not _property_diff_rollback_thresholds.has(property_name):
                    properties_match = false
                    break
        if not properties_match:
            warnings.push_back(
                "The keys in _property_diff_rollback_thresholds must match the other properties defined on the subclass.")
    
    return warnings
