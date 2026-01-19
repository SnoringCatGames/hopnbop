class_name PerfTracker
extends PanelContainer

# TODO: Check how network process compares to physics process (both are
#       hopefully close to 60 FPS?).
# - If network is much slower, consider adjusting my rollback frame index
#   bucketing.

const _SLOW_NETWORK_RTT_THRESHOLD_SEC := 0.1 # 100ms

const _SLOW_RENDER_FPS := 30
const _SLOW_PHYSICS_FPS := ScaffolderTime.PHYSICS_FPS - 1
const _SLOW_NETWORK_FPS := 30

@export var sample_window_size := 60

@onready var _physics_deltas := CircularBuffer.new(sample_window_size)
@onready var _render_deltas := CircularBuffer.new(sample_window_size)
@onready var _network_deltas := CircularBuffer.new(sample_window_size)

var _last_network_update_time := -1.0


func _ready() -> void:
    visible = G.settings.show_perf_tracker

    if not G.settings.show_perf_tracker:
        return

    G.network.local_authority_added.connect(_on_local_authority_added)
    G.network.local_authority_removed.connect(_on_local_authority_removed)


func _on_local_authority_added(
        state_from_client: PlayerStateFromClient,
) -> void:
    # Wait a tick to ensure state_from_server is populated
    await get_tree().process_frame

    G.check_valid(state_from_client)
    G.check_valid(state_from_client.state_from_server)

    (
        state_from_client.state_from_server.received_network_state.connect(
            _character_state_from_server_updated,
        )
    )


func _on_local_authority_removed(
        _state_from_client: PlayerStateFromClient,
) -> void:
    # Do nothing.
    pass


func _process(delta: float) -> void:
    if not G.settings.show_perf_tracker:
        return

    _render_deltas.append(delta)
    var avg_fps := _calculate_average_fps(_render_deltas)
    %RenderFPS.text = "%.1f" % avg_fps

    if avg_fps > 0.0 and avg_fps < _SLOW_RENDER_FPS:
        (
            G.warning(
                "Slow render FPS: %.1f (threshold: %d)" % [avg_fps, _SLOW_RENDER_FPS],
                ScaffolderLog.CATEGORY_CORE_SYSTEMS,
            )
        )


func _physics_process(delta: float) -> void:
    if not G.settings.show_perf_tracker:
        return

    _physics_deltas.append(delta)
    var avg_fps := _calculate_average_fps(_physics_deltas)
    %PhysicsFPS.text = "%.1f" % avg_fps

    if avg_fps > 0.0 and avg_fps < _SLOW_PHYSICS_FPS:
        (
            G.warning(
                "Slow physics FPS: %.1f (threshold: %d)" % [avg_fps, _SLOW_PHYSICS_FPS],
                ScaffolderLog.CATEGORY_CORE_SYSTEMS,
            )
        )

    _update_network_ping()


func _update_network_ping() -> void:
    var rtt_msec := G.network.time.rtt_usec / 1_000.0
    %NetworkPing.text = "%.1f" % rtt_msec

    if rtt_msec > _SLOW_NETWORK_RTT_THRESHOLD_SEC * 1000.0:
        (
            G.warning(
                (
                    "Slow network RTT: %.1fms (threshold: %.0fms)"
                    % [rtt_msec, _SLOW_NETWORK_RTT_THRESHOLD_SEC * 1000.0]
                ),
                ScaffolderLog.CATEGORY_CORE_SYSTEMS,
            )
        )


func _character_state_from_server_updated() -> void:
    if not G.settings.show_perf_tracker:
        return

    var current_time := Time.get_ticks_msec() / 1000.0
    if _last_network_update_time >= 0.0:
        var delta := current_time - _last_network_update_time
        _network_deltas.append(delta)
        var avg_fps := _calculate_average_fps(_network_deltas)
        %NetworkFPS.text = "%.1f" % avg_fps

        if avg_fps > 0.0 and avg_fps < _SLOW_NETWORK_FPS:
            (
                G.warning(
                    "Slow network FPS: %.1f (threshold: %d)" % [avg_fps, _SLOW_NETWORK_FPS],
                    ScaffolderLog.CATEGORY_CORE_SYSTEMS,
                )
            )
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
