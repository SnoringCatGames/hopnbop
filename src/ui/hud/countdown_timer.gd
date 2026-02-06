class_name CountdownTimer
extends Label
## Displays match time remaining in M:SS format.


const _TIMER_HIDE_AFTER_ZERO_DELAY_SEC := 0.3
const _TIMER_TIME_REMAINING_BLINK_THRESHOLD_DELAY_SEC := 30.0


func _ready() -> void:
	if Netcode.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	# Configure label appearance.
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vertical_alignment = VERTICAL_ALIGNMENT_TOP


func _process(_delta: float) -> void:
	_update_display()


func _update_display() -> void:
	if not is_instance_valid(G.match_state):
		visible = false
		return

	if G.match_state.match_start_frame_index < 0:
		visible = false
		return

	# Calculate remaining time (can be negative after expiry).
	var elapsed_frames := (
		Netcode.server_frame_index -
		G.match_state.match_start_frame_index
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

	# Blink red at a half-second interval when less than 30 seconds remain.
	if remaining_sec < _TIMER_TIME_REMAINING_BLINK_THRESHOLD_DELAY_SEC:
		modulate = (
			Color.RED if
			int(remaining_sec * 2) % 2 == 0 else
			Color.WHITE
		)
	else:
		modulate = Color.WHITE

	# Format as M:SS.
	var minutes := int(remaining_sec) / 60
	var seconds := int(remaining_sec) % 60

	text = "%d:%02d" % [minutes, seconds]
