class_name MatchEndCountdown
extends Label
## Displays match time remaining in M:SS format.


const _TIMER_HIDE_AFTER_ZERO_DELAY_SEC := 0.3
const _TIMER_TIME_REMAINING_BLINK_THRESHOLD_DELAY_SEC := 10.0
const _PULSE_SECONDS := [30, 20, 10, 5, 4, 3, 2, 1]
const _PULSE_SCALE := 1.3
const _PULSE_DURATION := 0.15

var _last_second := -1
var _original_scale := Vector2.ONE
var _is_animating_zero := false


func _ready() -> void:
	if Netcode.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	# Store original scale.
	_original_scale = scale

	# Set pivot to center for scaling animations.
	await get_tree().process_frame
	pivot_offset = size / 2.0


func _process(_delta: float) -> void:
	_update_display()


func _update_display() -> void:
	if not is_instance_valid(G.match_state):
		visible = false
		return

	if G.match_state.match_start_frame_index < 0:
		visible = false
		return

	# Don't show until match-start countdown ends.
	var countdown_end := Netcode.frame_driver.match_start_countdown_end_frame_index
	if countdown_end > 0 and Netcode.server_frame_index < countdown_end:
		visible = false
		return

	# Calculate remaining time from when countdown ended (can be negative after
	# expiry).
	var match_start_after_countdown := (
		countdown_end if countdown_end > 0 else
		G.match_state.match_start_frame_index
	)
	var elapsed_frames := (
		Netcode.server_frame_index -
		match_start_after_countdown
	)
	var elapsed_sec := (
		elapsed_frames /
		Netcode.frame_driver.target_network_fps
	)
	var remaining_sec := (
		(G.match_state.match_duration_usec / 1_000_000.0) -
		elapsed_sec
	)

	# Hide after timer reaches zero.
	if remaining_sec < -_TIMER_HIDE_AFTER_ZERO_DELAY_SEC:
		visible = false
		return

	visible = true

	# Clamp to 0 for display.
	remaining_sec = max(0.0, remaining_sec)

	var current_second := int(remaining_sec)

	# Trigger pulse animation when second changes.
	if current_second != _last_second:
		var previous_second := _last_second
		_last_second = current_second

		# Pulse at specific seconds.
		if current_second in _PULSE_SECONDS:
			_animate_pulse()

		# Fade out and scale up when hitting zero.
		if previous_second == 1 and current_second == 0:
			_is_animating_zero = true
			_animate_zero_transition()

	# Blink red at a half-second interval when 10 seconds or less remain.
	# Skip blinking during zero transition animation.
	if not _is_animating_zero:
		if remaining_sec <= _TIMER_TIME_REMAINING_BLINK_THRESHOLD_DELAY_SEC:
			modulate = (
				Color.WHITE if
				int(remaining_sec * 2) % 2 == 0 else
				Color.RED
			)
		else:
			modulate = Color.WHITE

	# Format as M:SS.
	@warning_ignore("integer_division")
	var minutes := int(remaining_sec) / 60
	var seconds := int(remaining_sec) % 60

	text = "%d:%02d" % [minutes, seconds]


func _animate_pulse() -> void:
	# Kill any existing scale tweens.
	var tween := create_tween()
	tween.set_parallel(false)

	# Pulse out.
	tween.tween_property(
		self,
		"scale",
		_original_scale * _PULSE_SCALE,
		_PULSE_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Pulse back in.
	tween.tween_property(
		self,
		"scale",
		_original_scale,
		_PULSE_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _animate_zero_transition() -> void:
	# Stop blinking and set to white before animating.
	modulate = Color.WHITE

	var tween := create_tween()
	tween.set_parallel(true)

	# Size increase with ease-out.
	tween.tween_property(
		self,
		"scale",
		_original_scale * 1.5,
		0.5
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Fade-out with ease-in.
	tween.tween_property(
		self,
		"modulate:a",
		0.0,
		0.5
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Hide the label after animation completes to prevent snap-back.
	tween.tween_callback(func(): visible = false)
