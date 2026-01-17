class_name PerfTracker
extends PanelContainer


# FIMXE: LEFT OFF HERE: ACTUALLY, ACTUALLY: FPS visualization.
# - Toggleable in Settings.
# - Check how network process compares to physics process (both are hopefully
#   close to 60 FPS?).
#   - If network is much slower, consider adjusting my rollback frame index
#     bucketing.
# - Log warnings when any of these three FPS dimensions drops below some
#   threshold.
#   - Separate threshold for each.
# - And log a print message when they recover.


@export var sample_window_size := 60

@onready var _physics_deltas := CircularBuffer.new(sample_window_size)
@onready var _render_deltas := CircularBuffer.new(sample_window_size)
@onready var _network_deltas := CircularBuffer.new(sample_window_size)

var _last_network_update_time := -1.0


func _ready() -> void:
    G.network.local_authority_added.connect(_on_local_authority_added)
    G.network.local_authority_removed.connect(_on_local_authority_removed)


func _on_local_authority_added(state_from_client: PlayerStateFromClient) -> void:
    # Wait a tick to ensure _state_from_server is populated
    await get_tree().process_frame

    G.check_valid(state_from_client)
    G.check_valid(state_from_client._state_from_server)

    state_from_client._state_from_server.received_network_state.connect(
        _character_state_from_server_updated)


func _on_local_authority_removed(_state_from_client: PlayerStateFromClient) -> void:
    # Do nothing.
    pass


func _process(delta: float) -> void:
    _render_deltas.append(delta)
    var avg_fps := _calculate_average_fps(_render_deltas)
    %RenderFPS.text = "%.1f" % avg_fps


func _physics_process(delta: float) -> void:
    _physics_deltas.append(delta)
    var avg_fps := _calculate_average_fps(_physics_deltas)
    %PhysicsFPS.text = "%.1f" % avg_fps


func _character_state_from_server_updated() -> void:
    var current_time := Time.get_ticks_msec() / 1000.0
    if _last_network_update_time >= 0.0:
        var delta := current_time - _last_network_update_time
        _network_deltas.append(delta)
        var avg_fps := _calculate_average_fps(_network_deltas)
        %NetworkFPS.text = "%.1f" % avg_fps
    _last_network_update_time = current_time


func _calculate_average_fps(deltas: CircularBuffer) -> float:
    if deltas.is_empty():
        return 0.0
    var total_delta := 0.0
    var count := deltas.size()
    for delta in deltas.to_array():
        total_delta += delta
    if total_delta <= 0.0:
        return 0.0
    return count / total_delta
