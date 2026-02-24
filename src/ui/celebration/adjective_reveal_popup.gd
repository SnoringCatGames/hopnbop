class_name AdjectiveRevealPopup
extends Control
## Animated popup that reveals a player's new dynamic
## adjective over their PlayerDisplay panel. Features
## scale overshoot, elastic settle, rotation wobble,
## and fade in/out. Auto-frees on completion.


const _INITIAL_SCALE := 0.1
const _OVERSHOOT_SCALE := 2.2
const _TARGET_SCALE := 1.0
const _GROW_DURATION := 0.15
const _SETTLE_DURATION := 0.5
const _FADE_IN_DURATION := 0.1
const _HOLD_DURATION := 1.8
const _FADE_OUT_DURATION := 0.4
const _WOBBLE_AMPLITUDE_DEG := 8.0
const _WOBBLE_FREQUENCY := 3.0
const _WOBBLE_DURATION := 0.6


var _label: Label


func reveal(
	adjective: String,
	label_color: Color,
	outline_color: Color,
) -> void:
	top_level = true
	mouse_filter = MOUSE_FILTER_IGNORE

	_label = Label.new()
	_label.text = adjective
	_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	# Style.
	_label.add_theme_font_size_override(
		"font_size", 20)
	_label.add_theme_color_override(
		"font_color", label_color)
	_label.add_theme_color_override(
		"font_outline_color", outline_color)
	_label.add_theme_constant_override(
		"outline_size", 3)

	add_child(_label)

	# Initial state.
	_label.scale = Vector2.ONE * _INITIAL_SCALE
	_label.modulate.a = 0.0
	_label.rotation = 0.0

	# Defer pivot setup until layout is resolved.
	_setup_pivot.call_deferred()

	# Animate.
	_animate()


func _setup_pivot() -> void:
	_label.pivot_offset = _label.size / 2.0
	_label.position = -_label.size / 2.0


func _animate() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_pause_mode(
		Tween.TWEEN_PAUSE_PROCESS)

	# Fade in.
	tween.tween_property(
		_label, "modulate:a", 1.0,
		_FADE_IN_DURATION,
	).set_ease(
		Tween.EASE_OUT
	).set_trans(
		Tween.TRANS_QUAD
	)

	# Scale: quick grow to overshoot.
	tween.tween_property(
		_label, "scale",
		Vector2.ONE * _OVERSHOOT_SCALE,
		_GROW_DURATION,
	).set_ease(
		Tween.EASE_OUT
	).set_trans(
		Tween.TRANS_QUAD
	)

	# Scale: elastic settle back to target.
	tween.tween_property(
		_label, "scale",
		Vector2.ONE * _TARGET_SCALE,
		_SETTLE_DURATION,
	).set_ease(
		Tween.EASE_OUT
	).set_trans(
		Tween.TRANS_ELASTIC
	).set_delay(_GROW_DURATION)

	# Wobble rotation.
	var wobble_tween := create_tween()
	wobble_tween.set_pause_mode(
		Tween.TWEEN_PAUSE_PROCESS)
	var angle := deg_to_rad(
		_WOBBLE_AMPLITUDE_DEG)
	var period := 1.0 / _WOBBLE_FREQUENCY
	var wobble_count := int(
		_WOBBLE_DURATION / period)
	for i in range(wobble_count):
		var target_angle := (
			angle if i % 2 == 0 else -angle
		)
		wobble_tween.tween_property(
			_label, "rotation",
			target_angle, period / 2.0,
		).set_ease(
			Tween.EASE_IN_OUT
		).set_trans(
			Tween.TRANS_SINE
		)
	wobble_tween.tween_property(
		_label, "rotation", 0.0, period / 2.0,
	).set_ease(
		Tween.EASE_OUT
	).set_trans(
		Tween.TRANS_SINE
	)

	# Fade out after hold.
	var total_delay := (
		_GROW_DURATION + _SETTLE_DURATION
		+ _HOLD_DURATION
	)
	tween.tween_property(
		_label, "modulate:a", 0.0,
		_FADE_OUT_DURATION,
	).set_ease(
		Tween.EASE_IN
	).set_trans(
		Tween.TRANS_QUAD
	).set_delay(total_delay)

	# Cleanup.
	var total_duration := (
		total_delay + _FADE_OUT_DURATION
	)
	tween.tween_callback(queue_free).set_delay(
		total_duration)
