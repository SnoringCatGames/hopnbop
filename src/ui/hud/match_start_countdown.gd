class_name MatchStartCountdown
extends Control
## Displays the match start countdown (3, 2, 1, GO) with animated transitions.
## Uses frame-based timing synchronized to server_frame_index.
## UI-only component - game state (pause/unpause) is handled by FrameDriver.


const NUM_COUNTDOWN_STEPS := 4  # "3", "2", "1", "GO".
const SCALE_SHRINK_DURATION_SEC := 0.3
const GO_DURATION_SEC := 1.0
const INITIAL_SCALE := 2.0
const FINAL_SCALE := 1.0
const GO_FINAL_SCALE := 2.0


@onready var _label: Label = $Label


var _tween: Tween
var _is_active := false
var _current_step := -1  # 0="3", 1="2", 2="1", 3="GO".


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
	_current_step = -1
	visible = true


func _process(_delta: float) -> void:
	if not _is_active:
		return

	var countdown_end := Netcode.frame_driver.countdown_end_frame_index
	@warning_ignore("integer_division")
	var frames_per_step := countdown_end / NUM_COUNTDOWN_STEPS

	var frame := Netcode.server_frame_index
	@warning_ignore("integer_division")
	var new_step := mini(frame / frames_per_step, NUM_COUNTDOWN_STEPS - 1)

	if new_step != _current_step:
		_current_step = new_step
		_update_display()

	if frame >= countdown_end:
		_finish_countdown()


func _update_display() -> void:
	match _current_step:
		0:
			_show_number("3")
		1:
			_show_number("2")
		2:
			_show_number("1")
		3:
			_show_go()


func _finish_countdown() -> void:
	_is_active = false
	visible = false


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
