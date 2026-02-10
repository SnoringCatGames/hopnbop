class_name PerfTrackerPanel
extends PanelContainer
## UI-only performance tracker panel that displays metrics from PerfTracker.
##
## This class handles UI rendering only. All tracking logic, calculations,
## and networking are handled by the PerfTracker class in NetworkMain.

# UI color-coding thresholds.
const _SLOW_NETWORK_RTT_THRESHOLD_SEC := 0.1 # 100ms
const _HIGH_JITTER_THRESHOLD_MS := 10.0
const _HIGH_INPUT_DELAY_THRESHOLD := 3
const _HIGH_PACKET_LOSS_THRESHOLD := 5.0 # 5%
const _LARGE_FASTFORWARD_THRESHOLD := 2
const _HIGH_FASTFORWARD_RATE_THRESHOLD := 0.2
const _SLOW_RENDER_FPS := 30
const _SLOW_PHYSICS_FPS := 50  # 60 FPS - 10
const _SLOW_NETWORK_FPS := 30

const _COLOR_FADE_DURATION_SEC := 0.5

# Color fade tweens.
var _color_tweens := {}


func _ready() -> void:
	pass

# --- Engine callbacks ---


func _process(_delta: float) -> void:
	if not G.settings.show_perf_tracker:
		return

	_update_render_fps_ui()
	_update_server_ui()
	_update_physics_fps_ui()
	_update_network_ping_ui()
	_update_rtt_jitter_ui()
	_update_packet_loss_ui()
	_update_input_delay_ui()
	_update_network_fps_ui()
	_update_rollback_metrics_ui()
	_update_fastforward_metrics_ui()


func _update_render_fps_ui() -> void:
	var current_fps := Netcode.perf_tracker.get_client_render_fps()
	var min_fps := Netcode.perf_tracker.get_min_render_fps()

	var min_text := "%.1f" % min_fps if min_fps != INF else "--"
	%ClientRenderFPS.text = "%.1f (%s)" % [current_fps, min_text]

	var is_slow := current_fps > 0.0 and current_fps < _SLOW_RENDER_FPS
	_update_label_color(%ClientRenderFPS, is_slow)


func _update_physics_fps_ui() -> void:
	var current_fps := Netcode.perf_tracker.get_client_physics_fps()
	var min_fps := Netcode.perf_tracker.get_min_physics_fps()

	var min_text := "%.1f" % min_fps if min_fps != INF else "--"
	%ClientPhysicsFPS.text = "%.1f (%s)" % [current_fps, min_text]

	var is_slow := current_fps > 0.0 and current_fps < _SLOW_PHYSICS_FPS
	_update_label_color(%ClientPhysicsFPS, is_slow)


func _update_network_fps_ui() -> void:
	var current_fps := Netcode.perf_tracker.get_client_network_fps()
	var min_fps := Netcode.perf_tracker.get_min_network_fps()

	var min_text := "%.1f" % min_fps if min_fps != INF else "--"
	%ClientNetworkFPS.text = "%.1f (%s)" % [current_fps, min_text]

	var is_slow := current_fps > 0.0 and current_fps < _SLOW_NETWORK_FPS
	_update_label_color(%ClientNetworkFPS, is_slow)


func _update_network_ping_ui() -> void:
	var current_ping := Netcode.perf_tracker.get_client_network_ping_ms()
	var max_ping := Netcode.perf_tracker.get_max_network_ping_ms()

	%ClientNetworkPing.text = "%.1f (%.1f)" % [current_ping, max_ping]

	var is_slow := current_ping > _SLOW_NETWORK_RTT_THRESHOLD_SEC * 1000.0
	_update_label_color(%ClientNetworkPing, is_slow)


func _update_rtt_jitter_ui() -> void:
	var current_jitter := (
		Netcode.perf_tracker.get_client_rtt_jitter_ms()
	)
	var max_jitter := (
		Netcode.perf_tracker.get_max_rtt_jitter_ms()
	)

	%ClientRttJitter.text = (
		"%.1f (%.1f)" % [current_jitter, max_jitter]
	)
	# Server doesn't have jitter (no self-ping).
	%ServerRttJitter.text = "N/A"

	var is_high := current_jitter > _HIGH_JITTER_THRESHOLD_MS
	_update_label_color(%ClientRttJitter, is_high)


func _update_packet_loss_ui() -> void:
	var current_loss := (
		Netcode.perf_tracker.get_client_packet_loss_pct()
	)
	var max_loss := (
		Netcode.perf_tracker.get_max_packet_loss_pct()
	)

	%ClientPacketLoss.text = (
		"%.0f%% (%.0f%%)" % [current_loss, max_loss]
	)
	# Server doesn't track packet loss (no self-ping).
	%ServerPacketLoss.text = "N/A"

	var is_high := current_loss >= _HIGH_PACKET_LOSS_THRESHOLD
	_update_label_color(%ClientPacketLoss, is_high)


func _update_input_delay_ui() -> void:
	var current_delay := (
		Netcode.perf_tracker.get_client_input_delay_frames()
	)
	var max_delay := (
		Netcode.perf_tracker.get_max_input_delay_frames()
	)

	%ClientInputDelay.text = "%d (%d)" % [
		current_delay, max_delay,
	]
	# Server doesn't have input delay.
	%ServerInputDelay.text = "N/A"

	var is_high := current_delay >= _HIGH_INPUT_DELAY_THRESHOLD
	_update_label_color(%ClientInputDelay, is_high)


func _update_rollback_metrics_ui() -> void:
	var rollbacks_per_sec := Netcode.perf_tracker.get_client_rollbacks_per_sec()
	var last_duration_ms := Netcode.perf_tracker.get_client_last_rollback_duration_ms()
	var last_frames := Netcode.perf_tracker.get_client_last_rollback_frames()
	var max_rollbacks := Netcode.perf_tracker.get_max_rollbacks_per_sec()
	var max_duration := Netcode.perf_tracker.get_max_last_rollback_duration_ms()
	var max_frames := Netcode.perf_tracker.get_max_last_rollback_frames()

	%ClientRollbacksPerSec.text = "%.1f (%.1f)" % [rollbacks_per_sec, max_rollbacks]
	%ClientLastRollbackDuration.text = "%.2f (%.2f)" % [last_duration_ms, max_duration]
	%ClientLastRollbackFrames.text = "%d (%d)" % [last_frames, max_frames]


func _update_fastforward_metrics_ui() -> void:
	var fastforwards_per_sec := Netcode.perf_tracker.get_client_fastforwards_per_sec()
	var last_duration_ms := Netcode.perf_tracker.get_client_last_fastforward_duration_ms()
	var last_frames := Netcode.perf_tracker.get_client_last_fastforward_frames()
	var max_fastforwards := Netcode.perf_tracker.get_max_fastforwards_per_sec()
	var max_duration := Netcode.perf_tracker.get_max_last_fastforward_duration_ms()
	var max_frames := Netcode.perf_tracker.get_max_last_fastforward_frames()

	%ClientFastforwardsPerSec.text = "%.1f (%.1f)" % [fastforwards_per_sec, max_fastforwards]
	%ClientLastFastforwardDuration.text = "%.2f (%.2f)" % [last_duration_ms, max_duration]
	%ClientLastFastforwardFrames.text = "%d (%d)" % [last_frames, max_frames]

	# Update colors based on thresholds.
	var is_large_fastforward := last_frames >= _LARGE_FASTFORWARD_THRESHOLD
	var is_high_rate := fastforwards_per_sec > _HIGH_FASTFORWARD_RATE_THRESHOLD

	_update_label_color(%ClientLastFastforwardFrames, is_large_fastforward)
	_update_label_color(%ClientFastforwardsPerSec, is_high_rate)

# --- Helper methods ---


func _update_label_color(label: Label, is_slow: bool) -> void:
	var label_path := label.get_path()

	if is_slow:
		if label_path in _color_tweens and _color_tweens[label_path]:
			_color_tweens[label_path].kill()
		label.add_theme_color_override("font_color", Color.RED)
	else:
		# Only start fade tween if we're currently red or have a red tween
		# running.
		var current_color := label.get_theme_color("font_color")
		var should_fade: bool = (
			current_color == Color.RED
			or (label_path in _color_tweens and _color_tweens[label_path])
		)

		if should_fade:
			if label_path in _color_tweens and _color_tweens[label_path]:
				_color_tweens[label_path].kill()
			var tween := create_tween()
			_color_tweens[label_path] = tween
			tween.tween_method(
				func(color: Color):
					label.add_theme_color_override("font_color", color),
				current_color,
				Color.WHITE,
				_COLOR_FADE_DURATION_SEC,
			)
		else:
			# Already white, just ensure no override
			label.remove_theme_color_override("font_color")


# --- Server UI update ---


func _update_server_ui() -> void:
	# Physics FPS
	var server_physics_fps := Netcode.perf_tracker.get_server_physics_fps()
	var server_min_physics_fps := Netcode.perf_tracker.get_server_min_physics_fps()
	var min_physics_text := "%.1f" % server_min_physics_fps if server_min_physics_fps != INF else "--"
	%ServerPhysicsFPS.text = "%.1f (%s)" % [server_physics_fps, min_physics_text]

	# Render FPS - N/A for headless servers
	%ServerRenderFPS.text = "N/A"

	# Network FPS
	var server_network_fps := Netcode.perf_tracker.get_server_network_fps()
	var server_min_network_fps := Netcode.perf_tracker.get_server_min_network_fps()
	var min_network_text := "%.1f" % server_min_network_fps if server_min_network_fps != INF else "--"
	%ServerNetworkFPS.text = "%.1f (%s)" % [server_network_fps, min_network_text]

	# Ping - N/A for server (no self-ping)
	%ServerNetworkPing.text = "N/A"

	# Rollback metrics
	var server_rollbacks_per_sec := Netcode.perf_tracker.get_server_rollbacks_per_sec()
	var server_max_rollbacks := Netcode.perf_tracker.get_server_max_rollbacks_per_sec()
	%ServerRollbacksPerSec.text = "%.1f (%.1f)" % [server_rollbacks_per_sec, server_max_rollbacks]

	var server_last_rollback_duration := Netcode.perf_tracker.get_server_last_rollback_duration_ms()
	var server_max_rollback_duration := Netcode.perf_tracker.get_server_max_last_rollback_duration_ms()
	%ServerLastRollbackDuration.text = "%.2f (%.2f)" % [server_last_rollback_duration, server_max_rollback_duration]

	var server_last_rollback_frames := Netcode.perf_tracker.get_server_last_rollback_frames()
	var server_max_rollback_frames := Netcode.perf_tracker.get_server_max_last_rollback_frames()
	%ServerLastRollbackFrames.text = "%d (%d)" % [server_last_rollback_frames, server_max_rollback_frames]

	# Fastforward metrics
	var server_fastforwards_per_sec := Netcode.perf_tracker.get_server_fastforwards_per_sec()
	var server_max_fastforwards := Netcode.perf_tracker.get_server_max_fastforwards_per_sec()
	%ServerFastforwardsPerSec.text = "%.1f (%.1f)" % [server_fastforwards_per_sec, server_max_fastforwards]

	var server_last_fastforward_duration := Netcode.perf_tracker.get_server_last_fastforward_duration_ms()
	var server_max_fastforward_duration := Netcode.perf_tracker.get_server_max_last_fastforward_duration_ms()
	%ServerLastFastforwardDuration.text = "%.2f (%.2f)" % [server_last_fastforward_duration, server_max_fastforward_duration]

	var server_last_fastforward_frames := Netcode.perf_tracker.get_server_last_fastforward_frames()
	var server_max_fastforward_frames := Netcode.perf_tracker.get_server_max_last_fastforward_frames()
	%ServerLastFastforwardFrames.text = "%d (%d)" % [server_last_fastforward_frames, server_max_fastforward_frames]
