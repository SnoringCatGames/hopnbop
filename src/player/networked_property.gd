class_name NetworkedProperty
extends Node


const _RESET_LOCAL_VALUE_DELAY := 0.2

enum NetworkedDataType {
    UNKNOWN,
    BOOL,
    INT,
    VECTOR2
}

var data_type := NetworkedDataType.UNKNOWN

var has_authority := false

var authoritative_value
# Estimated server time, in microseconds, since the server engine started.
var authoritative_timestamp: int

var local_value
# Estimated server time, in microseconds, since the server engine started.
var local_timestamp: int

var _timer: Timer

# In order to guarantee atomic transactions when syncing networked values and
# timestamps, we bundle the value and the timestamp together into a single variant.
var timestamped_value:
    set(value): _update_authoritative_timestamped_value(value)
    get: return _get_authoritative_timestamped_value()


func _init(p_data_type: NetworkedDataType) -> void:
    data_type = p_data_type


func _ready() -> void:
    _timer = Timer.new()
    _timer.autostart = false
    _timer.one_shot = true
    _timer.wait_time = _RESET_LOCAL_VALUE_DELAY
    _timer.timeout.connect(_reset_local_state)
    add_child(_timer)


# In order to guarantee atomic transactions when syncing networked values and
# timestamps, we bundle the value and the timestamp together into a single variant.
func _get_authoritative_timestamped_value() -> Variant:
    match data_type:
        NetworkedDataType.BOOL, \
        NetworkedDataType.INT:
            return Vector2i(authoritative_value, authoritative_timestamp)
        NetworkedDataType.VECTOR2:
            return Vector3(authoritative_value.x, authoritative_value.y, authoritative_timestamp)
        _:
            G.log.error("NetworkedProperty._get_authoritative_timestamped_value")
            return null


func _update_authoritative_timestamped_value(p_timestamped_value) -> void:
    match data_type:
        NetworkedDataType.BOOL:
            var bundle: Vector2i = p_timestamped_value
            authoritative_value = bundle.x as bool
            authoritative_timestamp = bundle.y
        NetworkedDataType.INT:
            var bundle: Vector2i = p_timestamped_value
            authoritative_value = bundle.x
            authoritative_timestamp = bundle.y
        NetworkedDataType.VECTOR2:
            var bundle: Vector3 = p_timestamped_value
            authoritative_value = Vector2(bundle.x, bundle.y)
            authoritative_timestamp = bundle.z as int
        _:
            G.log.error("NetworkedProperty._update_authoritative_timestamped_value")
            return
    
    # FIXME: LEFT OFF HERE: ACTUALLY: Implement rollback. -------------
    # - THINK THROUGH HOW TO TEST THIS!!! Automatically and/or with print statements and/or by hand.
    #   - And list the different aspects that should be verified.
    # - Add a circular buffer to track up to N frames of networked state.
    # - Whenever new server data arrives:
    #   - Discard frames older than the server data timestamp.
    #   - Apply the server data to the corresponding recorded frame in the buffer.
    #   - Extrapolate: Iteratively simulate each frame after that, recorded in the buffer, until reaching the current time.
    #   - 
    # - What's this look like on the server side, for applying client actions?
    # - GO THROUGH AND REFACTOR CHARACTER AND SURFACE_STATE TO ACCOUNT FOR THIS NEW ROLL_BACK APPROACH.
    # - Ensure that all significant gameplay events are triggered as RPCs from the server.
    #if authoritative_timestamp > local_timestamp:
    local_value = authoritative_value
    local_timestamp = authoritative_timestamp
    _timer.stop()


func update_local_value(value) -> void:
    local_value = value
    local_timestamp = G.server_time_tracker.get_server_time()
    
    if has_authority:
        authoritative_value = local_value
        authoritative_timestamp = local_timestamp
        _timer.stop()
    else:
        if local_timestamp < authoritative_timestamp:
            _reset_local_state()
            _timer.stop()
        else:
            _timer.start()


func _reset_local_state() -> void:
    local_value = authoritative_value
    local_timestamp = authoritative_timestamp
