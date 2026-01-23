class_name PerfTracker
extends PanelContainer

const _SLOW_NETWORK_RTT_THRESHOLD_SEC := 0.1 # 100ms
const _LARGE_FASTFORWARD_THRESHOLD := 2
const _HIGH_FASTFORWARD_RATE_THRESHOLD := 0.2

const _SLOW_RENDER_FPS := 30
const _SLOW_PHYSICS_FPS := ScaffolderTime.PHYSICS_FPS - 10
const _SLOW_NETWORK_FPS := 30

const _METRICS_LOG_INTERVAL_SEC := 5.0
const _WARNING_THROTTLE_SEC := 5.0
const _ROLLBACK_TRACKING_WINDOW_SEC := 60.0
const _FASTFORWARD_TRACKING_WINDOW_SEC := 60.0
const _MAX_MIN_TRACKING_WINDOW_SEC := 10.0
const _FPS_TRACKING_WINDOW_SEC := 1.0
const _COLOR_FADE_DURATION_SEC := 0.5

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
var _fastforward_count_in_window := 0
var _fastforward_window_start_time := 0.0
var _last_total_fastforwards := 0

# Current metric values (exposed via Performance monitors)
var _current_render_fps := 0.0
var _current_physics_fps := 0.0
var _current_network_fps := 0.0
var _current_network_ping_ms := 0.0
var _current_rollbacks_per_sec := 0.0
var _current_last_rollback_duration_ms := 0.0
var _current_last_rollback_frames := 0
var _current_fastforwards_per_sec := 0.0
var _current_last_fastforward_duration_ms := 0.0
var _current_last_fastforward_frames := 0

# Max/Min metric tracking (periodic window)
var _max_min_window_start_time := 0.0
var _min_render_fps_in_window := INF
var _min_physics_fps_in_window := INF
var _min_network_fps_in_window := INF
var _max_network_ping_in_window := 0.0
var _max_rollbacks_per_sec_in_window := 0.0
var _max_last_rollback_duration_in_window := 0.0
var _max_last_rollback_frames_in_window := 0
var _max_fastforwards_per_sec_in_window := 0.0
var _max_last_fastforward_duration_in_window := 0.0
var _max_last_fastforward_frames_in_window := 0

# Throttled warning functions
var _throttled_warn_render_fps: Callable
var _throttled_warn_physics_fps: Callable
var _throttled_warn_network_fps: Callable
var _throttled_warn_network_rtt: Callable
var _throttled_warn_large_fastforward: Callable
var _throttled_warn_high_fastforward_rate: Callable

# Color fade tweens
var _color_tweens := { }


func _ready() -> void:
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
    _throttled_warn_large_fastforward = G.time.throttle(
        _log_large_fastforward_warning,
        _WARNING_THROTTLE_SEC,
    )
    _throttled_warn_high_fastforward_rate = G.time.throttle(
        _log_high_fastforward_rate_warning,
        _WARNING_THROTTLE_SEC,
    )

    G.network.local_authority_added.connect(_on_local_authority_added)
    G.network.local_authority_removed.connect(_on_local_authority_removed)

    G.time.set_interval(
        _log_metrics_periodically,
        _METRICS_LOG_INTERVAL_SEC,
    )

    # Register custom performance monitors
    Performance.add_custom_monitor("networking/render_fps", func(): return _current_render_fps)
    Performance.add_custom_monitor("networking/physics_fps", func(): return _current_physics_fps)
    Performance.add_custom_monitor("networking/network_fps", func(): return _current_network_fps)
    Performance.add_custom_monitor("networking/network_ping_ms", func(): return _current_network_ping_ms)
    Performance.add_custom_monitor("networking/rollbacks_per_sec", func(): return _current_rollbacks_per_sec)
    Performance.add_custom_monitor("networking/last_rollback_duration_ms", func(): return _current_last_rollback_duration_ms)
    Performance.add_custom_monitor("networking/last_rollback_frames", func(): return _current_last_rollback_frames)
    Performance.add_custom_monitor("networking/fastforwards_per_sec", func(): return _current_fastforwards_per_sec)
    Performance.add_custom_monitor("networking/last_fastforward_duration_ms", func(): return _current_last_fastforward_duration_ms)
    Performance.add_custom_monitor("networking/last_fastforward_frames", func(): return _current_last_fastforward_frames)
    Performance.add_custom_monitor("networking/min_render_fps", func(): return _min_render_fps_in_window)
    Performance.add_custom_monitor("networking/min_physics_fps", func(): return _min_physics_fps_in_window)
    Performance.add_custom_monitor("networking/min_network_fps", func(): return _min_network_fps_in_window)
    Performance.add_custom_monitor("networking/max_network_ping_ms", func(): return _max_network_ping_in_window)
    Performance.add_custom_monitor("networking/max_rollbacks_per_sec", func(): return _max_rollbacks_per_sec_in_window)
    Performance.add_custom_monitor("networking/max_last_rollback_duration_ms", func(): return _max_last_rollback_duration_in_window)
    Performance.add_custom_monitor("networking/max_last_rollback_frames", func(): return _max_last_rollback_frames_in_window)
    Performance.add_custom_monitor("networking/max_fastforwards_per_sec", func(): return _max_fastforwards_per_sec_in_window)
    Performance.add_custom_monitor("networking/max_last_fastforward_duration_ms", func(): return _max_last_fastforward_duration_in_window)
    Performance.add_custom_monitor("networking/max_last_fastforward_frames", func(): return _max_last_fastforward_frames_in_window)

# --- Signal handlers ---


func _on_local_authority_added(
        input_from_client: PlayerInputFromClient,
) -> void:
    # Wait a tick to ensure state_from_server is populated
    await get_tree().process_frame

    G.check_valid(input_from_client)
    G.check_valid(input_from_client.state_from_server)

    input_from_client.state_from_server.received_network_state.connect(
        _character_state_from_server_updated,
    )


func _on_local_authority_removed(
        _input_from_client: PlayerInputFromClient,
) -> void:
    # Do nothing.
    pass

# --- Engine callbacks ---


func _process(_delta: float) -> void:
    if not G.settings.show_perf_tracker:
        return

    _calculate_render_fps()
    _check_and_reset_max_min_window()
    if _current_render_fps > 0.0:
        _min_render_fps_in_window = min(_min_render_fps_in_window, _current_render_fps)
    %RenderFPS.text = "%.1f" % _current_render_fps
    %MinRenderFPS.text = "%.1f" % _min_render_fps_in_window if _min_render_fps_in_window != INF else "--"

    var is_slow := _current_render_fps > 0.0 and _current_render_fps < _SLOW_RENDER_FPS
    _update_label_color(%RenderFPS, is_slow)
    if is_slow and G.game_panel.is_level_fully_loaded:
        _throttled_warn_render_fps.call(_current_render_fps)


func _physics_process(_delta: float) -> void:
    if not G.settings.show_perf_tracker:
        return

    _calculate_physics_fps()
    if _current_physics_fps > 0.0:
        _min_physics_fps_in_window = min(_min_physics_fps_in_window, _current_physics_fps)
    %PhysicsFPS.text = "%.1f" % _current_physics_fps
    %MinPhysicsFPS.text = "%.1f" % _min_physics_fps_in_window if _min_physics_fps_in_window != INF else "--"

    var is_slow := _current_physics_fps > 0.0 and _current_physics_fps < _SLOW_PHYSICS_FPS
    _update_label_color(%PhysicsFPS, is_slow)
    if is_slow and G.game_panel.is_level_fully_loaded:
        _throttled_warn_physics_fps.call(_current_physics_fps)

    _update_network_ping()
    _update_rollback_metrics()
    _update_fastforward_metrics()

# --- Network state callback ---


func _character_state_from_server_updated() -> void:
    if not G.settings.show_perf_tracker:
        return

    _calculate_network_fps()
    if _current_network_fps > 0.0:
        _min_network_fps_in_window = min(_min_network_fps_in_window, _current_network_fps)
    %NetworkFPS.text = "%.1f" % _current_network_fps
    %MinNetworkFPS.text = "%.1f" % _min_network_fps_in_window if _min_network_fps_in_window != INF else "--"

    var is_slow := _current_network_fps > 0.0 and _current_network_fps < _SLOW_NETWORK_FPS
    _update_label_color(%NetworkFPS, is_slow)
    if is_slow and G.game_panel.is_level_fully_loaded:
        _throttled_warn_network_fps.call(_current_network_fps)

# --- Update methods ---


func _update_network_ping() -> void:
    _calculate_network_ping()
    _max_network_ping_in_window = max(_max_network_ping_in_window, _current_network_ping_ms)
    %NetworkPing.text = "%.1f" % _current_network_ping_ms
    %MaxNetworkPing.text = "%.1f" % _max_network_ping_in_window

    var is_slow := _current_network_ping_ms > _SLOW_NETWORK_RTT_THRESHOLD_SEC * 1000.0
    _update_label_color(%NetworkPing, is_slow)
    if is_slow and G.game_panel.is_level_fully_loaded:
        _throttled_warn_network_rtt.call(_current_network_ping_ms)


func _update_rollback_metrics() -> void:
    _calculate_rollback_metrics()
    _max_rollbacks_per_sec_in_window = max(_max_rollbacks_per_sec_in_window, _current_rollbacks_per_sec)
    _max_last_rollback_duration_in_window = max(_max_last_rollback_duration_in_window, _current_last_rollback_duration_ms)
    _max_last_rollback_frames_in_window = max(_max_last_rollback_frames_in_window, _current_last_rollback_frames)
    %RollbacksPerSec.text = "%.1f" % _current_rollbacks_per_sec
    %LastRollbackDuration.text = "%.2f" % _current_last_rollback_duration_ms
    %LastRollbackFrames.text = str(_current_last_rollback_frames)
    %MaxRollbacksPerSec.text = "%.1f" % _max_rollbacks_per_sec_in_window
    %MaxLastRollbackDuration.text = "%.2f" % _max_last_rollback_duration_in_window
    %MaxLastRollbackFrames.text = str(_max_last_rollback_frames_in_window)


func _update_fastforward_metrics() -> void:
    _calculate_fastforward_metrics()
    _max_fastforwards_per_sec_in_window = max(_max_fastforwards_per_sec_in_window, _current_fastforwards_per_sec)
    _max_last_fastforward_duration_in_window = max(_max_last_fastforward_duration_in_window, _current_last_fastforward_duration_ms)
    _max_last_fastforward_frames_in_window = max(_max_last_fastforward_frames_in_window, _current_last_fastforward_frames)
    %FastforwardsPerSec.text = "%.1f" % _current_fastforwards_per_sec
    %LastFastforwardDuration.text = "%.2f" % _current_last_fastforward_duration_ms
    %LastFastforwardFrames.text = str(_current_last_fastforward_frames)
    %MaxFastforwardsPerSec.text = "%.1f" % _max_fastforwards_per_sec_in_window
    %MaxLastFastforwardDuration.text = "%.2f" % _max_last_fastforward_duration_in_window
    %MaxLastFastforwardFrames.text = str(_max_last_fastforward_frames_in_window)

    # Update colors based on thresholds
    var is_large_fastforward := _current_last_fastforward_frames >= _LARGE_FASTFORWARD_THRESHOLD
    var is_high_rate := _current_fastforwards_per_sec > _HIGH_FASTFORWARD_RATE_THRESHOLD

    _update_label_color(%LastFastforwardFrames, is_large_fastforward)
    _update_label_color(%FastforwardsPerSec, is_high_rate)

    # Warn if we're fast-forwarding many frames at once
    if is_large_fastforward and G.game_panel.is_level_fully_loaded:
        _throttled_warn_large_fastforward.call(_current_last_fastforward_frames)

    # Warn if fast-forwards are happening too frequently
    if is_high_rate and G.game_panel.is_level_fully_loaded:
        _throttled_warn_high_fastforward_rate.call(_current_fastforwards_per_sec)

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
    var state := {
        "window_start_time": _rollback_window_start_time,
        "count_in_window": _rollback_count_in_window,
        "last_total": _last_total_rollbacks,
    }

    _current_rollbacks_per_sec = _calculate_events_per_sec(
        G.network.frame_driver.total_rollbacks,
        state,
        _ROLLBACK_TRACKING_WINDOW_SEC,
    )

    _rollback_window_start_time = state.window_start_time
    _rollback_count_in_window = state.count_in_window
    _last_total_rollbacks = state.last_total

    # Calculate last rollback metrics
    _current_last_rollback_duration_ms = (
        G.network.frame_driver.last_rollback_duration_usec / 1000.0
    )
    _current_last_rollback_frames = G.network.frame_driver.last_rollback_frame_count


func _calculate_fastforward_metrics() -> void:
    var state := {
        "window_start_time": _fastforward_window_start_time,
        "count_in_window": _fastforward_count_in_window,
        "last_total": _last_total_fastforwards,
    }

    _current_fastforwards_per_sec = _calculate_events_per_sec(
        G.network.frame_driver.total_fastforwards,
        state,
        _FASTFORWARD_TRACKING_WINDOW_SEC,
    )

    _fastforward_window_start_time = state.window_start_time
    _fastforward_count_in_window = state.count_in_window
    _last_total_fastforwards = state.last_total

    # Calculate last fastforward metrics
    _current_last_fastforward_duration_ms = (
        G.network.frame_driver.last_fastforward_duration_usec / 1000.0
    )
    _current_last_fastforward_frames = G.network.frame_driver.last_fastforward_frame_count


func _calculate_events_per_sec(
        current_total: int,
        state: Dictionary,
        tracking_window_sec: float,
) -> float:
    var current_time: float = Time.get_ticks_msec() / 1000.0

    # Initialize window on first call
    if state.window_start_time == 0.0:
        state.window_start_time = current_time
        state.last_total = current_total

    # Update event count in current window
    var new_events: int = current_total - state.last_total
    state.count_in_window += new_events
    state.last_total = current_total

    # Calculate events per second over the tracking window
    var window_duration: float = current_time - state.window_start_time
    var events_per_sec: float
    if window_duration > 0.0:
        events_per_sec = state.count_in_window / window_duration
    else:
        events_per_sec = 0.0

    # Reset window after full duration
    if window_duration >= tracking_window_sec:
        state.count_in_window = 0
        state.window_start_time = current_time

    return events_per_sec


func _check_and_reset_max_min_window() -> void:
    var current_time := Time.get_ticks_msec() / 1000.0

    if _max_min_window_start_time == 0.0:
        _max_min_window_start_time = current_time

    var window_duration := current_time - _max_min_window_start_time
    if window_duration >= _MAX_MIN_TRACKING_WINDOW_SEC:
        _min_render_fps_in_window = INF
        _min_physics_fps_in_window = INF
        _min_network_fps_in_window = INF
        _max_network_ping_in_window = 0.0
        _max_rollbacks_per_sec_in_window = 0.0
        _max_last_rollback_duration_in_window = 0.0
        _max_last_rollback_frames_in_window = 0
        _max_fastforwards_per_sec_in_window = 0.0
        _max_last_fastforward_duration_in_window = 0.0
        _max_last_fastforward_frames_in_window = 0
        _max_min_window_start_time = current_time


func _update_label_color(label: Label, is_slow: bool) -> void:
    var label_path := label.get_path()

    if is_slow:
        if label_path in _color_tweens and _color_tweens[label_path]:
            _color_tweens[label_path].kill()
        label.add_theme_color_override("font_color", Color.RED)
    else:
        # Only start fade tween if we're currently red or have a red tween running
        var current_color := label.get_theme_color("font_color")
        var should_fade: bool = current_color == Color.RED or (label_path in _color_tweens and _color_tweens[label_path])

        if should_fade:
            if label_path in _color_tweens and _color_tweens[label_path]:
                _color_tweens[label_path].kill()
            var tween := create_tween()
            _color_tweens[label_path] = tween
            tween.tween_method(
                func(color: Color): label.add_theme_color_override("font_color", color),
                current_color,
                Color.WHITE,
                _COLOR_FADE_DURATION_SEC,
            )
        else:
            # Already white, just ensure no override
            label.remove_theme_color_override("font_color")


func _log_metrics_periodically() -> void:
    if not G.settings.show_perf_tracker:
        return

    G.print(
        "PERF: FPS[P:%.1f R:%.1f N:%.1f] PING:%.1fms RB[/s:%.1f last:%.2fms/%df] FF[/s:%.1f last:%.2fms/%df]" % [
            _current_physics_fps,
            _current_render_fps,
            _current_network_fps,
            _current_network_ping_ms,
            _current_rollbacks_per_sec,
            _current_last_rollback_duration_ms,
            _current_last_rollback_frames,
            _current_fastforwards_per_sec,
            _current_last_fastforward_duration_ms,
            _current_last_fastforward_frames,
        ],
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )

# --- Warning log methods ---


func _log_render_fps_warning(avg_fps: float) -> void:
    G.warning(
        "Slow render FPS: %.1f (threshold: %d)"
        % [avg_fps, _SLOW_RENDER_FPS],
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )


func _log_physics_fps_warning(avg_fps: float) -> void:
    G.warning(
        "Slow physics FPS: %.1f (threshold: %d)"
        % [avg_fps, _SLOW_PHYSICS_FPS],
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )


func _log_network_fps_warning(avg_fps: float) -> void:
    G.warning(
        "Slow network FPS: %.1f (threshold: %d)"
        % [avg_fps, _SLOW_NETWORK_FPS],
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )


func _log_network_rtt_warning(rtt_msec: float) -> void:
    G.warning(
        "Slow network RTT: %.1fms (threshold: %.0fms)"
        % [rtt_msec, _SLOW_NETWORK_RTT_THRESHOLD_SEC * 1000.0],
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )


func _log_large_fastforward_warning(frame_count: int) -> void:
    G.warning(
        "Large fast-forward: %d frames (threshold: %d)"
        % [frame_count, _LARGE_FASTFORWARD_THRESHOLD],
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )


func _log_high_fastforward_rate_warning(rate: float) -> void:
    G.warning(
        "High fast-forward rate: %.2f/sec (threshold: %.1f)"
        % [rate, _HIGH_FASTFORWARD_RATE_THRESHOLD],
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )
