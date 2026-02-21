class_name PlayerDisplay
extends PanelContainer
## Individual player info panel showing adjective, name, and score.

# Floating score popup settings.
const _POPUP_MIN_SCORE_CHANGE := 10
const _POPUP_OFFSET := Vector2(-15.0, 0.0) # Small gap right of score.
const _POPUP_INITIAL_SCALE := 0.1
const _POPUP_TARGET_SCALE := 1.95
const _POPUP_OVERSHOOT_SCALE := 2.8
const _POPUP_GROW_DURATION_SEC := 0.12
const _POPUP_SETTLE_DURATION_SEC := 0.6
const _POPUP_FADE_IN_DURATION_SEC := 0.1
const _POPUP_VISIBLE_DURATION_SEC := 0.9
const _POPUP_FADE_OUT_DURATION_SEC := 0.3
const _POPUP_SLIDE_OFFSET := Vector2(15.0, -25.0) # Drift right and up.

# Score counter animation settings.
const _SCORE_INCREMENT_INTERVAL_SEC := 0.02

var player_id: int = 0

var _displayed_score: int = 0
var _target_score: int = 0
var _score_update_timer: float = 0.0
var _has_initialized_score: bool = false


func set_player_id(p_player_id: int) -> void:
	player_id = p_player_id
	_has_initialized_score = false


func _process(delta: float) -> void:
	_update_display(delta)


func _update_display(delta: float) -> void:
	if player_id == 0:
		return

	var player_match_state := G.get_player_match_state(player_id)
	if not player_match_state:
		return

	# Update name and adjective.
	%Name.text = player_match_state.bunny_name
	%Adjective.text = player_match_state.adjective

	# Hide score in lobby.
	%Score.visible = not G.is_lobby_active

	# Handle score updates.
	var actual_score: int = player_match_state.score
	if actual_score != _target_score:
		var score_delta := actual_score - _target_score
		_target_score = actual_score

		var min_score_change_for_popup := (
			1
			if G.settings.use_simple_score
			else _POPUP_MIN_SCORE_CHANGE
		)

		# On first assignment, snap immediately.
		if not _has_initialized_score:
			_displayed_score = actual_score
			_has_initialized_score = true
		# Spawn popup for any qualifying score increase.
		if score_delta >= min_score_change_for_popup:
			_spawn_score_popup(score_delta)

	# Animate displayed score toward target.
	if _displayed_score != _target_score:
		_score_update_timer += delta
		while _score_update_timer >= _SCORE_INCREMENT_INTERVAL_SEC and \
				_displayed_score != _target_score:
			_score_update_timer -= _SCORE_INCREMENT_INTERVAL_SEC
			if _displayed_score < _target_score:
				_displayed_score += 1
			else:
				_displayed_score -= 1

	%Score.text = "%d" % _displayed_score

	# White in lobby, player color in match.
	var label_color := (
		Color.WHITE if G.is_lobby_active
		else player_match_state.label_color
	)
	%Name.add_theme_color_override("font_color", label_color)
	%Adjective.add_theme_color_override("font_color", label_color)
	%Score.add_theme_color_override("font_color", label_color)

	var outline_color := (
		Color.TRANSPARENT if G.is_lobby_active
		else player_match_state.outline_color
	)
	%Name.add_theme_color_override("font_outline_color", outline_color)
	%Adjective.add_theme_color_override("font_outline_color", outline_color)
	%Score.add_theme_color_override("font_outline_color", outline_color)


func _spawn_score_popup(score_delta: int) -> void:
	# Create a wrapper that escapes PanelContainer layout.
	var wrapper := Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.top_level = true

	# Create popup label.
	var popup := Label.new()
	popup.text = "+%d" % score_delta
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Copy styling from score label.
	popup.add_theme_constant_override(
		"outline_size",
		%Score.get_theme_constant("outline_size")
	)
	var label_color: Color = %Score.get_theme_color("font_color")
	popup.add_theme_color_override("font_color", label_color)
	var outline_color: Color = %Score.get_theme_color("font_outline_color")
	popup.add_theme_color_override("font_outline_color", outline_color)

	# Add wrapper as child of PlayerDisplay, then label as child of wrapper.
	add_child(wrapper)
	wrapper.add_child(popup)

	# Position wrapper at the right edge of the score label, vertically
	# centered.
	var score_rect: Rect2 = %Score.get_global_rect()
	wrapper.position = Vector2(
		score_rect.position.x + score_rect.size.x,
		score_rect.get_center().y,
	)

	# Small offset gap from score label edge.
	popup.position = _POPUP_OFFSET

	# Defer pivot_offset assignment until label size is calculated.
	_setup_popup_pivot.call_deferred(popup)

	# Initial state.
	popup.scale = Vector2.ONE * _POPUP_INITIAL_SCALE
	popup.modulate.a = 0.0

	# Animate.
	var tween := create_tween()
	tween.set_parallel(true)

	# Fade in.
	tween.tween_property(
		popup, "modulate:a", 1.0, _POPUP_FADE_IN_DURATION_SEC
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Scale: quick grow to overshoot.
	tween.tween_property(
		popup, "scale",
		Vector2.ONE * _POPUP_OVERSHOOT_SCALE,
		_POPUP_GROW_DURATION_SEC
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Scale: elastic settle back to target.
	tween.tween_property(
		popup, "scale",
		Vector2.ONE * _POPUP_TARGET_SCALE,
		_POPUP_SETTLE_DURATION_SEC
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC) \
		.set_delay(_POPUP_GROW_DURATION_SEC)

	# Slide away and up (relative to popup's current position).
	var total_duration := \
		_POPUP_VISIBLE_DURATION_SEC + _POPUP_FADE_OUT_DURATION_SEC
	tween.tween_property(
		popup, "position",
		_POPUP_SLIDE_OFFSET,
		total_duration
	).as_relative() \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)

	# Fade out after delay.
	tween.tween_property(
		popup, "modulate:a", 0.0, _POPUP_FADE_OUT_DURATION_SEC
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD) \
		.set_delay(_POPUP_VISIBLE_DURATION_SEC)

	# Cleanup - free the wrapper (which also frees the popup child).
	tween.tween_callback(wrapper.queue_free) \
		.set_delay(total_duration)


func _setup_popup_pivot(popup: Label) -> void:
	# Center the pivot for proper scaling from center.
	popup.pivot_offset = popup.size / 2.0
	# Adjust position so label appears centered on calculated position.
	popup.position -= popup.size / 2.0
