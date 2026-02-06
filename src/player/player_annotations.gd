class_name PlayerAnnotations
extends Node2D
## Debug visualization for player collision shapes and rollback buffer trail.
##
## Displays:
## - White outline matching the player's collision shape.
## - Colored dots for each frame in the rollback buffer.
## - Lines connecting adjacent frames.
## - Color coding by frame authority (green=authoritative,
##   yellow=predicted, gray=unknown).
##
## Toggle at runtime with F6 (respects G.settings.draw_annotations) and F1
## (master HUD toggle via G.settings.show_hud). Both must be enabled to show.

# Configuration constants.
const COLLISION_OUTLINE_COLOR := Color(1.0, 1.0, 1.0, 0.8)
const COLLISION_OUTLINE_THICKNESS := 2.0

const DOT_RADIUS := 2.0
const LINE_THICKNESS := 1.0

# Color coding by frame authority.
const COLOR_AUTHORITATIVE := Color(0.0, 0.9, 0.6, 0.6)
const COLOR_PREDICTED := Color(1.0, 0.8, 0.0, 0.6)
const COLOR_UNKNOWN := Color(0.5, 0.5, 0.5, 0.6)

@export var player: Player


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if (
		Engine.is_editor_hint() or
		not G.settings.show_hud or
		not G.settings.draw_annotations
	):
		return

	if not is_instance_valid(player):
		return

	_draw_collision_shape()
	_draw_rollback_buffer_trail()


func _draw_collision_shape() -> void:
	if not is_instance_valid(player.collision_shape):
		return

	var local_position := player.global_position - global_position

	DrawUtils.draw_shape_outline(
		self ,
		local_position,
		player.collision_shape.shape,
		COLLISION_OUTLINE_COLOR,
		COLLISION_OUTLINE_THICKNESS,
	)


func _draw_rollback_buffer_trail() -> void:
	if not is_instance_valid(player.state_from_server):
		return

	var buffer := player.state_from_server._rollback_buffer

	if buffer == null:
		return

	var oldest_index := buffer._get_oldest_accessible_index()
	var latest_index := buffer.get_latest_index()

	var prev_local_pos: Vector2
	var has_prev := false

	for frame_index in range(oldest_index, latest_index + 1):
		if not buffer.has_at(frame_index):
			has_prev = false
			continue

		var frame_state: Array = buffer.get_at(frame_index)

		if frame_state == null or frame_state.is_empty():
			has_prev = false
			continue

		var frame_position: Vector2 = frame_state[0]
		var frame_authority: int = frame_state[frame_state.size() - 1]

		var local_pos := frame_position - global_position
		var color := _get_color_for_authority(frame_authority)

		# Draw line to previous frame if exists.
		if has_prev:
			draw_line(prev_local_pos, local_pos, color, LINE_THICKNESS)

		# Draw dot for current frame.
		draw_circle(local_pos, DOT_RADIUS, color)

		prev_local_pos = local_pos
		has_prev = true


func _get_color_for_authority(authority: int) -> Color:
	match authority:
		ReconcilableState.FrameAuthority.AUTHORITATIVE:
			return COLOR_AUTHORITATIVE
		ReconcilableState.FrameAuthority.PREDICTED:
			return COLOR_PREDICTED
		_:
			return COLOR_UNKNOWN
