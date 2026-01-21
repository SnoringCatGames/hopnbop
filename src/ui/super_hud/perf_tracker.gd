class_name PerfTracker
extends PanelContainer

const _SLOW_NETWORK_RTT_THRESHOLD_SEC := 0.1 # 100ms

const _SLOW_RENDER_FPS := 30
const _SLOW_PHYSICS_FPS := ScaffolderTime.PHYSICS_FPS - 1
const _SLOW_NETWORK_FPS := 30

const _WARNING_THROTTLE_SEC := 5.0
const _ROLLBACK_TRACKING_WINDOW_SEC := 60.0
const _FPS_TRACKING_WINDOW_SEC := 1.0

# Tracking window state
var _render_frame_count := 0
var _render_window_start_time := 0.0
var _physics_frame_count := 0
var _physics_window_start_time := 0.0
var _network_frame_count := 0
var _network_window_start_time := 0.0
var _rollback_count_in_window := 0
var _rollback_window_start_time := 0.0
var _last_total_rollbacks := 0

# Current metric values (exposed via Performance monitors)
var _current_render_fps := 0.0
var _current_physics_fps := 0.0
var _current_network_fps := 0.0
var _current_network_ping_ms := 0.0
var _current_rollbacks_per_sec := 0.0
var _current_last_rollback_duration_ms := 0.0
var _current_last_rollback_frames := 0

# Throttled warning functions
var _throttled_warn_render_fps: Callable
var _throttled_warn_physics_fps: Callable
var _throttled_warn_network_fps: Callable
var _throttled_warn_network_rtt: Callable


func _ready() -> void:
    visible = G.settings.show_perf_tracker

    if not G.settings.show_perf_tracker:
        return

    _throttled_warn_render_fps = G.time.throttle(
        _log_render_fps_warning,
        _WARNING_THROTTLE_SEC,
    )
    _throttled_warn_physics_fps = G.time.throttle(
        _log_physics_fps_warning,
        _WARNING_THROTTLE_SEC,
    )
    _throttled_warn_network_fps = G.time.throttle(
        _log_network_fps_warning,
        _WARNING_THROTTLE_SEC,
    )
    _throttled_warn_network_rtt = G.time.throttle(
        _log_network_rtt_warning,
        _WARNING_THROTTLE_SEC,
    )

    G.network.local_authority_added.connect(_on_local_authority_added)
    G.network.local_authority_removed.connect(_on_local_authority_removed)

    # Register custom performance monitors
    Performance.add_custom_monitor("networking/render_fps", func(): return _current_render_fps)
    Performance.add_custom_monitor("networking/physics_fps", func(): return _current_physics_fps)
    Performance.add_custom_monitor("networking/network_fps", func(): return _current_network_fps)
    Performance.add_custom_monitor("networking/network_ping_ms", func(): return _current_network_ping_ms)
    Performance.add_custom_monitor("networking/rollbacks_per_sec", func(): return _current_rollbacks_per_sec)
    Performance.add_custom_monitor("networking/last_rollback_duration_ms", func(): return _current_last_rollback_duration_ms)
    Performance.add_custom_monitor("networking/last_rollback_frames", func(): return _current_last_rollback_frames)

# --- Signal handlers ---


func _on_local_authority_added(
        state_from_client: PlayerInputFromClient,
) -> void:
    # Wait a tick to ensure state_from_server is populated
    await get_tree().process_frame

    G.check_valid(state_from_client)
    G.check_valid(state_from_client.state_from_server)

    state_from_client.state_from_server.received_network_state.connect(
        _character_state_from_server_updated,
    )


func _on_local_authority_removed(
        _state_from_client: PlayerInputFromClient,
) -> void:
    # Do nothing.
    pass

# --- Engine callbacks ---


func _process(_delta: float) -> void:
    if not G.settings.show_perf_tracker:
        return

    _calculate_render_fps()
    %RenderFPS.text = "%.1f" % _current_render_fps

    if (
        G.game_panel.is_level_fully_loaded
        and _current_render_fps > 0.0
        and _current_render_fps < _SLOW_RENDER_FPS
    ):
        _throttled_warn_render_fps.call(_current_render_fps)


func _physics_process(_delta: float) -> void:
    if not G.settings.show_perf_tracker:
        return

    _calculate_physics_fps()
    %PhysicsFPS.text = "%.1f" % _current_physics_fps

    if (
        G.game_panel.is_level_fully_loaded
        and _current_physics_fps > 0.0
        and _current_physics_fps < _SLOW_PHYSICS_FPS
    ):
        _throttled_warn_physics_fps.call(_current_physics_fps)

    _update_network_ping()
    _update_rollback_metrics()

# --- Network state callback ---


func _character_state_from_server_updated() -> void:
    if not G.settings.show_perf_tracker:
        return

    _calculate_network_fps()
    %NetworkFPS.text = "%.1f" % _current_network_fps

    if (
        G.game_panel.is_level_fully_loaded
        and _current_network_fps > 0.0
        and _current_network_fps < _SLOW_NETWORK_FPS
    ):
        _throttled_warn_network_fps.call(_current_network_fps)

# --- Update methods ---


func _update_network_ping() -> void:
    _calculate_network_ping()
    %NetworkPing.text = "%.1f" % _current_network_ping_ms

    if (
        G.game_panel.is_level_fully_loaded
        and _current_network_ping_ms > _SLOW_NETWORK_RTT_THRESHOLD_SEC * 1000.0
    ):
        _throttled_warn_network_rtt.call(_current_network_ping_ms)


func _update_rollback_metrics() -> void:
    _calculate_rollback_metrics()
    %RollbacksPerSec.text = "%.1f" % _current_rollbacks_per_sec
    %LastRollbackDuration.text = "%.2f" % _current_last_rollback_duration_ms
    %LastRollbackFrames.text = str(_current_last_rollback_frames)

# --- Metric calculation helpers ---


func _calculate_render_fps() -> void:
    var current_time: float = Time.get_ticks_msec() / 1000.0

    # Initialize window on first call
    if _render_window_start_time == 0.0:
        _render_window_start_time = current_time

    _render_frame_count += 1

    # Calculate FPS over the tracking window
    var window_duration: float = current_time - _render_window_start_time
    if window_duration > 0.0:
        _current_render_fps = _render_frame_count / window_duration
    else:
        _current_render_fps = 0.0

    # Reset window after full duration
    if window_duration >= _FPS_TRACKING_WINDOW_SEC:
        _render_frame_count = 0
        _render_window_start_time = current_time


func _calculate_physics_fps() -> void:
    var current_time: float = Time.get_ticks_msec() / 1000.0

    # Initialize window on first call
    if _physics_window_start_time == 0.0:
        _physics_window_start_time = current_time

    _physics_frame_count += 1

    # Calculate FPS over the tracking window
    var window_duration: float = current_time - _physics_window_start_time
    if window_duration > 0.0:
        _current_physics_fps = _physics_frame_count / window_duration
    else:
        _current_physics_fps = 0.0

    # Reset window after full duration
    if window_duration >= _FPS_TRACKING_WINDOW_SEC:
        _physics_frame_count = 0
        _physics_window_start_time = current_time


func _calculate_network_fps() -> void:
    var current_time: float = Time.get_ticks_msec() / 1000.0

    # Initialize window on first call
    if _network_window_start_time == 0.0:
        _network_window_start_time = current_time

    _network_frame_count += 1

    # Calculate FPS over the tracking window
    var window_duration: float = current_time - _network_window_start_time
    if window_duration > 0.0:
        _current_network_fps = _network_frame_count / window_duration
    else:
        _current_network_fps = 0.0

    # Reset window after full duration
    if window_duration >= _FPS_TRACKING_WINDOW_SEC:
        _network_frame_count = 0
        _network_window_start_time = current_time


func _calculate_network_ping() -> void:
    _current_network_ping_ms = G.network.time.rtt_usec / 1_000.0


func _calculate_rollback_metrics() -> void:
    var current_total: int = G.network.frame_driver.total_rollbacks
    var current_time: float = Time.get_ticks_msec() / 1000.0

    # Initialize window on first call
    if _rollback_window_start_time == 0.0:
        _rollback_window_start_time = current_time
        _last_total_rollbacks = current_total

    # Update rollback count in current window
    var new_rollbacks: int = current_total - _last_total_rollbacks
    _rollback_count_in_window += new_rollbacks
    _last_total_rollbacks = current_total

    # Calculate rollbacks per second over the tracking window
    var window_duration: float = current_time - _rollback_window_start_time
    if window_duration > 0.0:
        _current_rollbacks_per_sec = _rollback_count_in_window / window_duration
    else:
        _current_rollbacks_per_sec = 0.0

    # Reset window after full duration
    if window_duration >= _ROLLBACK_TRACKING_WINDOW_SEC:
        _rollback_count_in_window = 0
        _rollback_window_start_time = current_time

    # Calculate last rollback metrics
    _current_last_rollback_duration_ms = (
        G.network.frame_driver.last_rollback_duration_usec / 1000.0
    )
    _current_last_rollback_frames = G.network.frame_driver.last_rollback_frame_count

# --- Warning log methods ---


func _log_render_fps_warning(avg_fps: float) -> void:
    G.warning(
        "SLOW RENDER FPS: %.1f (THRESHOLD: %d)"
        % [avg_fps, _SLOW_RENDER_FPS],
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )


func _log_physics_fps_warning(avg_fps: float) -> void:
    G.warning(
        "SLOW PHYSICS FPS: %.1f (THRESHOLD: %d)"
        % [avg_fps, _SLOW_PHYSICS_FPS],
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )


func _log_network_fps_warning(avg_fps: float) -> void:
    G.warning(
        "SLOW NETWORK FPS: %.1f (THRESHOLD: %d)"
        % [avg_fps, _SLOW_NETWORK_FPS],
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )


func _log_network_rtt_warning(rtt_msec: float) -> void:
    G.warning(
        "SLOW NETWORK RTT: %.1fMS (THRESHOLD: %.0fMS)"
        % [rtt_msec, _SLOW_NETWORK_RTT_THRESHOLD_SEC * 1000.0],
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )
