class_name CountdownTimer
extends Label
## Displays match time remaining in M:SS format.


func _ready() -> void:
	if G.network.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	# Configure label appearance.
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vertical_alignment = VERTICAL_ALIGNMENT_TOP


func _process(_delta: float) -> void:
	_update_display()


func _update_display() -> void:
	# Don't show the countdown if the match hasn't started or has finished.
	visible = (
		is_instance_valid(G.match_state) and
		G.match_state.match_start_time_usec >= 0
	)

	var remaining_sec := G.match_state.match_time_remaining_sec

	# Blink red at a half-second intervalwhen less than 30 seconds remain.
	if remaining_sec < 30.0:
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
