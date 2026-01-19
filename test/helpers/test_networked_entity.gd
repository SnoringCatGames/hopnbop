extends ReconcilableNetworkedState
## A simple test entity for integration testing networked state and rollback.
##
## This entity tracks position and velocity, which can be used to test
## rollback reconciliation logic.


var position := Vector2.ZERO
var velocity := Vector2.ZERO
var custom_data: int = 0

## Whether this entity has been reconciled.
var was_reconciled := false

## Number of times _network_process was called.
var network_process_count := 0

## Last frame index processed.
var last_processed_frame := -1


func _init() -> void:
    super._init()
    # Set up basic replication config.
    is_server_authoritative = true


func _pre_network_process(delta: float) -> void:
    # In a real implementation, this would sync state from rollback buffer.
    pass


func _network_process(delta: float) -> void:
    network_process_count += 1
    last_processed_frame = timestamp_index

    # Simple physics: position += velocity * delta.
    position += velocity * delta


func _post_network_process(delta: float) -> void:
    # Pack state for replication.
    _pack_state()


## Override to define what gets packed into network state.
func _get_packed_state() -> Array:
    return [
        position.x,
        position.y,
        velocity.x,
        velocity.y,
        custom_data,
        frame_authority,
    ]


## Override to apply packed state from network.
func _apply_packed_state(state: Array) -> void:
    if state.size() < 6:
        return

    position.x = state[0]
    position.y = state[1]
    velocity.x = state[2]
    velocity.y = state[3]
    custom_data = state[4]
    frame_authority = state[5]


## Override to detect mismatches for rollback.
func _has_state_mismatch(
    client_state: Array,
    server_state: Array
) -> bool:
    if client_state.size() < 6 or server_state.size() < 6:
        return false

    # Check position mismatch.
    var pos_diff := Vector2(
        abs(client_state[0] - server_state[0]),
        abs(client_state[1] - server_state[1])
    )
    if pos_diff.length() > 1.0:
        return true

    # Check velocity mismatch.
    var vel_diff := Vector2(
        abs(client_state[2] - server_state[2]),
        abs(client_state[3] - server_state[3])
    )
    if vel_diff.length() > 0.5:
        return true

    # Check custom data mismatch.
    if client_state[4] != server_state[4]:
        return true

    return false


## Called when reconciliation occurs.
func _on_reconciled() -> void:
    was_reconciled = true


## Reset test state.
func reset_test_state() -> void:
    was_reconciled = false
    network_process_count = 0
    last_processed_frame = -1


## Create a simple test entity with given initial values.
static func create_test_entity(
    initial_position := Vector2.ZERO,
    initial_velocity := Vector2.ZERO
) -> TestNetworkedEntity:
    var entity := TestNetworkedEntity.new()
    entity.position = initial_position
    entity.velocity = initial_velocity
    return entity
