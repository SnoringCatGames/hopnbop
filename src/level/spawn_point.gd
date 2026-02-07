@tool
class_name SpawnPoint
extends Node2D


const _DEBUG_ANNOTATION_SIZE := Vector2i(16, 24)
const _DEBUG_ANNOTATION_LINE_WIDTH := 2.0
const _DEBUG_ANNOTATION_COLOR := Color(0.645, 0.21, 1.0, 0.576)
const _DEBUG_ANNOTATION_IS_FILLED := true
const _DEBUG_ANNOTATION_SECTOR_ARC_LENGTH := 2

const SNAP_X := 8
const SNAP_Y := 16


var spawn_position: Vector2:
	get:
		return Vector2(
			roundf(global_position.x / SNAP_X) * SNAP_X,
			ceilf(global_position.y / SNAP_Y) * SNAP_Y
		)

var _previous_position: Vector2


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return

	if global_position != _previous_position:
		_previous_position = global_position
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	# Draw at the snapped position offset from the node's actual position.
	var snap_offset := spawn_position - global_position

	var circle_center := snap_offset + Vector2(
		0,
		-_DEBUG_ANNOTATION_SIZE.y + _DEBUG_ANNOTATION_SIZE.x / 2.0)
	var circle_radius := _DEBUG_ANNOTATION_SIZE.x / 2.0

	DrawUtils.draw_ice_cream_cone(
		self,
		snap_offset,
		circle_center,
		circle_radius,
		_DEBUG_ANNOTATION_COLOR,
		_DEBUG_ANNOTATION_IS_FILLED,
		_DEBUG_ANNOTATION_LINE_WIDTH,
		_DEBUG_ANNOTATION_SECTOR_ARC_LENGTH,
	)
