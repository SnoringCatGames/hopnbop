class_name MatchEndCelebration
extends Control
## Orchestrates the match-end celebration sequence:
## camera zoom, confetti, "WINNER" text slam, and
## iris close. Runs client-side only during the
## 5-second window after match ends.


const _CAMERA_ZOOM_DURATION := 0.5
const _TARGET_ZOOM := Vector2(3.0, 3.0)
const _CONFETTI_DELAY := 0.35
const _CONFETTI_COUNT := 40
const _CONFETTI_STAGGER := 0.45
const _CONFETTI_OFFSET_CENTER := Vector2(0, -10)
const _CONFETTI_OFFSET_UPPER_LEFT := Vector2(-40, -35)
const _CONFETTI_OFFSET_UPPER_RIGHT := Vector2(40, -35)
const _TEXT_SLAM_DELAY := 0.8
const _TEXT_SLAM_DURATION := 0.3
const _TEXT_INITIAL_SCALE := 5.0
const _TEXT_HOLD_DURATION := 1.5
const _TEXT_FADE_DURATION := 0.4
const _TEXT_SLAM_SHAKE_INTENSITY := 8.0
const _TEXT_SLAM_SHAKE_DURATION := 0.35
const _IRIS_DELAY := 3.8
const _IRIS_DURATION := 0.7
const _IRIS_CENTER_OFFSET := Vector2(0, -5)
const _IRIS_TILE_SIZE_PX := 10.0


var _camera: Camera2D
var _original_camera_parent: Node
var _original_camera_zoom := Vector2.ONE
var _was_camera_reparented := false
var _winner: Player
var _is_tracking_winner := false
var _is_updating_iris := false
var _active_tweens: Array[Tween] = []


func _enter_tree() -> void:
	G.celebration = self


func _ready() -> void:
	if Netcode.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	%WinnerText.visible = false
	%IrisOverlay.visible = false

	_connect_match_ended_deferred.call_deferred()


func _connect_match_ended_deferred() -> void:
	if is_instance_valid(G.match_state):
		G.match_state.match_ended.connect(
			start_celebration)


func _process(_delta: float) -> void:
	if not is_instance_valid(_winner):
		return

	if _is_tracking_winner:
		_track_winner_position()

	if _is_updating_iris:
		_update_iris_center()


func start_celebration() -> void:
	if Netcode.is_server:
		return

	var winner_id := _get_winner_player_id()
	if winner_id < 0:
		return

	_winner = G.get_player(winner_id)
	if not is_instance_valid(_winner):
		return

	visible = true

	# Phase 1: Zoom (t=0.0s).
	_zoom_camera_to_winner()

	# Phase 2: Confetti (t=0.5s).
	var t1 := get_tree().create_timer(
		_CONFETTI_DELAY, true, false, true)
	t1.timeout.connect(_spawn_confetti)

	# Phase 3: Text slam + shake (t=0.8s).
	var t2 := get_tree().create_timer(
		_TEXT_SLAM_DELAY, true, false, true)
	t2.timeout.connect(_slam_winner_text)
	t2.timeout.connect(func():
		G.camera_shaker.shake(
			_TEXT_SLAM_SHAKE_INTENSITY,
			_TEXT_SLAM_SHAKE_DURATION,
		)
	)

	# Phase 4: Iris close (t=3.8s).
	var t3 := get_tree().create_timer(
		_IRIS_DELAY, true, false, true)
	t3.timeout.connect(_start_iris_close)


func _get_winner_player_id() -> int:
	if not is_instance_valid(G.match_state):
		return -1
	for player_id in G.match_state.players_by_id:
		var ps: GamePlayerState = (
			G.match_state.players_by_id[player_id]
		)
		if ps.rank == 1:
			return player_id
	return -1


func _zoom_camera_to_winner() -> void:
	_camera = _get_local_camera()
	if not is_instance_valid(_camera):
		return

	# Save original state for reset.
	_original_camera_parent = _camera.get_parent()
	_original_camera_zoom = _camera.zoom

	var is_local_winner := (
		_winner.peer_id == Netcode.local_peer_id
	)

	if is_local_winner:
		# Camera already follows local player.
		# Just zoom in.
		var tween := create_tween()
		_active_tweens.append(tween)
		tween.set_pause_mode(
			Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(
			_camera,
			"zoom",
			_TARGET_ZOOM,
			_CAMERA_ZOOM_DURATION,
		).set_ease(
			Tween.EASE_OUT
		).set_trans(
			Tween.TRANS_QUAD
		)
	else:
		# Reparent camera to level so it detaches
		# from local player.
		_was_camera_reparented = true
		var origin := _camera.global_position
		_camera.get_parent().remove_child(_camera)
		G.level.add_child(_camera)
		_camera.global_position = origin

		var tween := create_tween()
		_active_tweens.append(tween)
		tween.set_pause_mode(
			Tween.TWEEN_PAUSE_PROCESS)
		tween.set_parallel(true)

		tween.tween_property(
			_camera,
			"zoom",
			_TARGET_ZOOM,
			_CAMERA_ZOOM_DURATION,
		).set_ease(
			Tween.EASE_OUT
		).set_trans(
			Tween.TRANS_QUAD
		)

		tween.tween_property(
			_camera,
			"global_position",
			_winner.global_position,
			_CAMERA_ZOOM_DURATION,
		).set_ease(
			Tween.EASE_OUT
		).set_trans(
			Tween.TRANS_QUAD
		)

		# After zoom, track winner each frame.
		tween.finished.connect(func():
			_is_tracking_winner = true
		)


func _track_winner_position() -> void:
	if (
		not is_instance_valid(_camera)
		or not is_instance_valid(_winner)
	):
		_is_tracking_winner = false
		return
	_camera.global_position = _winner.global_position


func _get_local_camera() -> Camera2D:
	if not is_instance_valid(G.level):
		return null
	for player_id in G.level.players_by_id:
		var player: Player = (
			G.level.players_by_id[player_id]
		)
		if (
			is_instance_valid(player)
			and player.peer_id
			== Netcode.local_peer_id
		):
			return player.get_node(
				"%CharacterCamera")
	return null


func _spawn_confetti() -> void:
	if not is_instance_valid(_winner):
		return
	if not is_instance_valid(G.level):
		return

	var game_state := G.match_state as GameMatchState
	if not is_instance_valid(game_state):
		return

	var kill_lead := game_state.get_winner_kill_lead()

	# Tie: no confetti.
	if kill_lead == 0:
		return

	var triple_threshold: int = (
		G.settings.triple_confetti_kill_threshold)
	var double_threshold: int = (
		G.settings.double_confetti_kill_threshold)

	if kill_lead >= triple_threshold:
		# Three blasts: center, then right, then
		# left (staggered 0.2s each).
		_burst_confetti_at(_CONFETTI_OFFSET_CENTER)
		_delayed_burst(
			_CONFETTI_OFFSET_UPPER_RIGHT,
			_CONFETTI_STAGGER)
		_delayed_burst(
			_CONFETTI_OFFSET_UPPER_LEFT,
			_CONFETTI_STAGGER * 2)
	elif kill_lead >= double_threshold:
		# Two blasts: upper left, then upper right.
		_burst_confetti_at(_CONFETTI_OFFSET_UPPER_LEFT)
		_delayed_burst(
			_CONFETTI_OFFSET_UPPER_RIGHT,
			_CONFETTI_STAGGER)
	else:
		# One blast: lower center.
		_burst_confetti_at(_CONFETTI_OFFSET_CENTER)


func _burst_confetti_at(offset: Vector2) -> void:
	if not is_instance_valid(_winner):
		return
	if not is_instance_valid(G.level):
		return
	var emitter := ConfettiEmitter.new()
	G.level.add_child(emitter)
	emitter.burst(
		_winner.global_position + offset,
		_CONFETTI_COUNT,
	)
	%ConfettiAudioStreamPlayer.play()


func _delayed_burst(
	offset: Vector2,
	delay: float,
) -> void:
	var timer := get_tree().create_timer(
		delay, true, false, true)
	timer.timeout.connect(
		_burst_confetti_at.bind(offset))


func _slam_winner_text() -> void:
	var game_state := G.match_state as GameMatchState
	var is_tie := (
		is_instance_valid(game_state)
		and game_state.get_winner_kill_lead() == 0
	)

	if is_tie:
		%WinnerText.text = "TIE!"
	else:
		var ps := G.get_player_match_state(
			_winner.player_id) as GamePlayerState
		if ps:
			%WinnerText.text = (
				"%s\nWINS!" % ps.bunny_name.to_upper())
		else:
			%WinnerText.text = "WINS!"
	%WinnerText.visible = true
	%WinnerText.pivot_offset = (
		%WinnerText.size / 2)
	%WinnerText.scale = (
		Vector2.ONE * _TEXT_INITIAL_SCALE)
	%WinnerText.modulate.a = 1.0

	var tween := create_tween()
	_active_tweens.append(tween)
	tween.set_pause_mode(
		Tween.TWEEN_PAUSE_PROCESS)

	# Slam in with bounce overshoot.
	tween.tween_property(
		%WinnerText,
		"scale",
		Vector2.ONE,
		_TEXT_SLAM_DURATION,
	).set_ease(
		Tween.EASE_OUT
	).set_trans(
		Tween.TRANS_BACK
	)

	# Play boom just before the bounce-back part
	# of the easing completes.
	var boom_delay := _TEXT_SLAM_DURATION - 0.08
	get_tree().create_timer(
		boom_delay, true, false, true
	).timeout.connect(
		%BoomAudioStreamPlayer.play)

	# Hold.
	tween.tween_interval(_TEXT_HOLD_DURATION)

	# Fade out.
	tween.tween_property(
		%WinnerText,
		"modulate:a",
		0.0,
		_TEXT_FADE_DURATION,
	).set_ease(
		Tween.EASE_IN
	).set_trans(
		Tween.TRANS_QUAD
	)

	tween.finished.connect(func():
		%WinnerText.visible = false
	)


func _start_iris_close() -> void:
	%IrisOverlay.visible = true
	_is_updating_iris = true
	_update_iris_center()

	var material: ShaderMaterial = (
		%IrisOverlay.material)
	material.set_shader_parameter(
		"progress", 0.0)

	# Set aspect ratio for circular iris.
	var vp_size := Vector2(
		get_viewport().get_visible_rect().size)
	material.set_shader_parameter(
		"aspect_ratio", vp_size.x / vp_size.y)

	# Tile-based rendering parameters.
	material.set_shader_parameter(
		"tile_size", _IRIS_TILE_SIZE_PX)
	material.set_shader_parameter(
		"random_seed", randf() * 1000.0)
	material.set_shader_parameter(
		"pattern_randomness", 0.1)

	var tween := create_tween()
	_active_tweens.append(tween)
	tween.set_pause_mode(
		Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(
		func(value: float):
			material.set_shader_parameter(
				"progress", value),
		0.0,
		1.0,
		_IRIS_DURATION,
	).set_ease(
		Tween.EASE_IN_OUT
	).set_trans(
		Tween.TRANS_QUAD
	)

	tween.finished.connect(func():
		_is_updating_iris = false
	)


func _update_iris_center() -> void:
	if not is_instance_valid(_winner):
		return

	var viewport := get_viewport()
	if viewport == null:
		return

	var world_pos := (
		_winner.global_position
		+ _IRIS_CENTER_OFFSET
	)

	var screen_pos: Vector2
	if is_instance_valid(G.pixel_viewport_manager):
		screen_pos = (
			G.pixel_viewport_manager
				.world_to_screen(world_pos)
		)
	else:
		var canvas_xform := (
			viewport.get_canvas_transform()
		)
		screen_pos = canvas_xform * world_pos

	var vp_size := Vector2(
		viewport.get_visible_rect().size)

	var uv := screen_pos / vp_size

	var material: ShaderMaterial = (
		%IrisOverlay.material)
	material.set_shader_parameter("center", uv)


func reset() -> void:
	_is_tracking_winner = false
	_is_updating_iris = false

	# Kill any in-progress celebration tweens.
	for tween in _active_tweens:
		if tween and tween.is_valid():
			tween.kill()
	_active_tweens.clear()

	# Restore camera before the level is freed.
	_restore_camera()

	_winner = null
	_camera = null
	_original_camera_parent = null
	_was_camera_reparented = false
	visible = false
	%WinnerText.visible = false
	%IrisOverlay.visible = false

	# Reset iris shader progress.
	var material: ShaderMaterial = (
		%IrisOverlay.material)
	material.set_shader_parameter(
		"progress", 0.0)


func _restore_camera() -> void:
	if not is_instance_valid(_camera):
		return

	# Disable the old camera so it doesn't conflict
	# with the new lobby camera. The old level (and
	# this camera) will be queue_freed shortly after.
	_camera.enabled = false
	_camera.zoom = _original_camera_zoom
	_camera.offset = Vector2.ZERO

	# Reparent back if we moved it.
	if (
		_was_camera_reparented
		and is_instance_valid(
			_original_camera_parent)
	):
		var pos := _camera.global_position
		_camera.get_parent().remove_child(_camera)
		_original_camera_parent.add_child(_camera)
		_camera.global_position = pos
