class_name FrameSynchronizer
extends Node
## Synchronizes frame indices between server and clients using NTP-like
## protocol.
##
## Uses a ping/pong mechanism to simultaneously measure round-trip time (RTT)
## and sync frame indices. The server includes its current frame index in the
## pong response, eliminating the need for separate frame broadcasts.
##
## Combined NTP + Frame Sync Protocol:
## 1. Client sends ping with client timestamp (t1) every second.
## 2. Server receives ping at t2, immediately sends pong with:
##    - t1 (client send time)
##    - t2 (server receive time)
##    - t3 (server send time)
##    - current_frame (server's frame index at t3)
## 3. Client receives pong at t4.
## 4. Client calculates RTT = (t4 - t1) - (t3 - t2).
## 5. Client estimates frames elapsed during transmission from t3 to t4.
## 6. Client estimates current server frame and corrects drift if needed.

const DRIFT_THRESHOLD_FRAMES := 1 # Correct if +/- 1 frame off.
const PING_INTERVAL_SEC := 3.0 # Ping server every 3 seconds.
const RTT_SMOOTHING_FACTOR := 0.2 # Exponential moving average weight.
const _MAX_RTT_SAMPLES := 10 # Jitter window size.
# Minimum time between consecutive hard resets. Prevents a
# feedback loop where repeated resets discard valid state
# before it can stabilize.
const _HARD_RESET_COOLDOWN_USEC := 3_000_000 # 3 seconds.

# Network timing derived from FrameDriver config.
var target_network_time_step_sec: float:
	get:
		return (
			Netcode.frame_driver.target_network_time_step_sec if
			Netcode.frame_driver else
			1.0 / 60.0
		)

var _time_since_last_ping_sec := 0.0
var _last_hard_reset_usec := 0

# RTT tracking (in microseconds).
var _smoothed_rtt_usec := 0
var _is_rtt_initialized := false
var _raw_rtt_samples: Array[int] = []

## Returns the smoothed round-trip time in microseconds.
var rtt_usec: float:
	get:
		return _smoothed_rtt_usec

## Returns RTT jitter as mean absolute deviation from smoothed RTT
## (in microseconds).
var rtt_jitter_usec: float:
	get:
		if _raw_rtt_samples.is_empty():
			return 0.0
		var total_deviation := 0.0
		for sample in _raw_rtt_samples:
			total_deviation += absf(
				sample - _smoothed_rtt_usec
			)
		return total_deviation / _raw_rtt_samples.size()

## Current adaptive input delay in frames, based on smoothed RTT.
## Only updated on clients; always 0 on server.
var input_delay_frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	# Only clients send pings. Server responds with pongs containing frame
	# index.
	if Netcode.is_client and Netcode.connector.is_connected_to_server:
		_client_process(delta)


func _client_process(delta: float) -> void:
	_time_since_last_ping_sec += delta
	if _time_since_last_ping_sec >= PING_INTERVAL_SEC:
		_time_since_last_ping_sec = 0.0
		_client_send_ping()


# -------------------------------- NTP Ping/Pong -------------------------------


func _client_send_ping() -> void:
	Netcode.check_is_client()

	var t1 := Time.get_ticks_usec()
	_server_rpc_ping.rpc_id(1, t1)


@rpc("any_peer", "call_remote", "unreliable", NetworkConnector.RPC_CHANNEL_CLOCK_SYNC)
func _server_rpc_ping(client_t1: int) -> void:
	Netcode.check_is_server()

	var t2 := Time.get_ticks_usec() # Server receive time.
	var sender_id := multiplayer.get_remote_sender_id()

	# Immediately respond with pong, including current frame index.
	var t3 := Time.get_ticks_usec() # Server send time.
	var current_frame := Netcode.frame_driver.server_frame_index
	_client_rpc_pong.rpc_id(sender_id, client_t1, t2, t3, current_frame)


@rpc("authority", "call_remote", "unreliable", NetworkConnector.RPC_CHANNEL_CLOCK_SYNC)
func _client_rpc_pong(
		client_t1: int,
		server_t2: int,
		server_t3: int,
		server_frame_at_t3: int,
) -> void:
	Netcode.check_is_client()

	var t4 := Time.get_ticks_usec() # Client receive time.

	# Calculate RTT: (t4 - t1) - (t3 - t2).
	var rtt_usec := (t4 - client_t1) - (server_t3 - server_t2)

	# Track raw RTT samples for jitter calculation.
	_raw_rtt_samples.append(rtt_usec)
	if _raw_rtt_samples.size() > _MAX_RTT_SAMPLES:
		_raw_rtt_samples.remove_at(0)

	# Smooth RTT using exponential moving average.
	if _is_rtt_initialized:
		_smoothed_rtt_usec = roundi(
			RTT_SMOOTHING_FACTOR * rtt_usec +
			(1.0 - RTT_SMOOTHING_FACTOR) * _smoothed_rtt_usec
		)
	else:
		_smoothed_rtt_usec = rtt_usec
		_is_rtt_initialized = true

	# Update adaptive input delay.
	_update_input_delay()

	# Estimate one-way delay as half RTT. Cannot use (t4 - server_t3) because
	# client and server clocks are not synchronized. Mixing clock domains
	# produces incorrect values that cause progressive frame drift.
	var one_way_delay_usec := _smoothed_rtt_usec / 2
	var frames_during_transmission := roundi(
		float(one_way_delay_usec) /
		(target_network_time_step_sec * 1_000_000.0)
	)

	# Estimate current server frame index.
	var estimated_current_server_frame := (
		server_frame_at_t3 + frames_during_transmission
	)

	var local_frame := Netcode.frame_driver.server_frame_index
	var drift := estimated_current_server_frame - local_frame

	# Correct drift if outside threshold.
	if abs(drift) <= DRIFT_THRESHOLD_FRAMES:
		# Within acceptable range, no correction needed.
		return

	if drift > 0:
		# Client is behind - use existing fast-forward logic.
		Netcode.frame_driver.fast_forward(estimated_current_server_frame)
		if Netcode.log.is_verbose:
			Netcode.log.verbose(
				"Client behind by %d frames, fast-forwarding to %d" % [
					drift,
					estimated_current_server_frame,
				],
				NetworkLogger.CATEGORY_NETWORK_SYNC
			)
	else:
		# Client is ahead - hard reset. This can happen when the server
		# runs slower than clients due to performance issues. We need
		# to:
		# 1. Set a grace period so incoming states aren't rejected
		# 2. Reinitialize rollback buffers to clear stale predictions
		# 3. Reset the frame index
		var now := Time.get_ticks_usec()
		if now - _last_hard_reset_usec < _HARD_RESET_COOLDOWN_USEC:
			return
		_last_hard_reset_usec = now
		Netcode.log.warning(
			("Client ahead of server by %d frames! "
			+"Hard reset from %d to %d") % [
				abs(drift),
				local_frame,
				estimated_current_server_frame,
			],
			NetworkLogger.CATEGORY_NETWORK_SYNC
		)
		# Trigger grace period to prevent rejecting valid server
		# states.
		Netcode.frame_driver._frame_reset_time_usec = now
		# Reinitialize rollback buffers to clear stale predicted
		# data.
		Netcode.frame_driver.reinitialize_buffers_for_hard_reset(
			estimated_current_server_frame
		)
		# Reset the frame index.
		Netcode.frame_driver.server_frame_index = (
			estimated_current_server_frame
		)


func _update_input_delay() -> void:
	if not Netcode.settings.is_adaptive_input_delay_enabled:
		input_delay_frames = 0
		return

	var max_delay: int = Netcode.settings.max_input_delay_frames
	if max_delay <= 0:
		input_delay_frames = 0
		return

	# Target delay = one-way latency in frames.
	var time_step_usec := (
		target_network_time_step_sec * 1_000_000.0
	)
	var target := ceili(
		float(_smoothed_rtt_usec / 2) / time_step_usec
	)
	target = clampi(target, 0, max_delay)

	# Ramp by at most +/-1 per pong to avoid jarring transitions.
	if target > input_delay_frames:
		input_delay_frames = mini(
			input_delay_frames + 1, target
		)
	elif target < input_delay_frames:
		input_delay_frames = maxi(
			input_delay_frames - 1, target
		)
