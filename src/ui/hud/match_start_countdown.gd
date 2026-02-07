class_name MatchStartCountdown
extends Control
## Displays the match start countdown with animated transitions.
## Dynamically shows countdown numbers based on configured duration
## (e.g., 4, 3, 2, 1, GO for a 4-second countdown).
## Uses frame-based timing synchronized to server_frame_index.
## UI-only component - game state (pause/unpause) is handled by FrameDriver.


const SCALE_SHRINK_DURATION_SEC := 0.3
const GO_DURATION_SEC := 1.0
const INITIAL_SCALE := 2.0
const FINAL_SCALE := 1.0
const GO_FINAL_SCALE := 2.0


@onready var _label: Label = $Label


var _tween: Tween
var _is_active := false
var _current_step_index := -1


func _ready() -> void:
	if Netcode.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	# Must run while game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Initially hidden.
	visible = false


func start_countdown() -> void:
	if _is_active:
		return

	_is_active = true
	_current_step_index = -1
	visible = true


func _process(_delta: float) -> void:
	if not _is_active:
		return

	var countdown_end := Netcode.frame_driver.match_start_countdown_end_frame_index
	var countdown_sec := Netcode.settings.match_start_countdown_sec
	var numeric_step_count := ceili(countdown_sec)

	@warning_ignore("integer_division")
	var frames_per_numeric_step := countdown_end / numeric_step_count

	var frame := Netcode.server_frame_index

	# Determine current step.
	var next_step_index: int
	if frame < countdown_end:
		@warning_ignore("integer_division")
		next_step_index = mini(
			frame / frames_per_numeric_step,
			numeric_step_count - 1)
	else:
		# Show "GO" when countdown ends (frame 240).
		next_step_index = numeric_step_count

	if next_step_index != _current_step_index:
		_current_step_index = next_step_index
		_update_display()

	if frame >= countdown_end:
		_finish_countdown()


func _update_display() -> void:
	var countdown_sec := Netcode.settings.match_start_countdown_sec
	var numeric_step_count := ceili(countdown_sec)

	if _current_step_index < numeric_step_count:
		var number := numeric_step_count - _current_step_index
		_show_number(str(number))
	else:
		_show_go()


func _finish_countdown() -> void:
	_is_active = false


func _show_number(number_text: String) -> void:
	_label.text = number_text
	# Recalculate pivot after text change.
	_label.pivot_offset = _label.size / 2
	_label.scale = Vector2.ONE * INITIAL_SCALE
	_label.modulate.a = 1.0

	# Cancel any previous tween.
	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(
		_label, "scale",
		Vector2.ONE * FINAL_SCALE,
		SCALE_SHRINK_DURATION_SEC
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _show_go() -> void:
	_label.text = "GO!"
	# Recalculate pivot after text change.
	_label.pivot_offset = _label.size / 2
	_label.scale = Vector2.ONE * FINAL_SCALE
	_label.modulate.a = 1.0

	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_parallel(true)

	# Expand scale.
	_tween.tween_property(
		_label, "scale",
		Vector2.ONE * GO_FINAL_SCALE,
		GO_DURATION_SEC
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Fade out.
	_tween.tween_property(
		_label, "modulate:a",
		0.0,
		GO_DURATION_SEC
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Hide the UI after animation completes.
	_tween.finished.connect(func(): visible = false, CONNECT_ONE_SHOT)
