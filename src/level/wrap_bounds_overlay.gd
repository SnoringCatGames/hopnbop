@tool
class_name WrapBoundsOverlay
extends Node2D
## Renders black bars outside the wrap bounds at
## runtime, and debug boundary lines in the editor.

const _BAR_EXTENT := 2000.0
const _DEBUG_COLOR := Color(
	1.0, 0.5, 0.0, 0.5)
const _DEBUG_LINE_WIDTH := 2.0


func _ready() -> void:
	# Render on top of all game content.
	z_index = 100


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	# Continuously redraw in editor so inspector
	# property changes are reflected.
	queue_redraw()


func _get_bounds() -> Rect2:
	var p := get_parent()
	if p is NetworkedLevel:
		return p.wrap_bounds
	return Rect2()


func _draw() -> void:
	var bounds := _get_bounds()
	if bounds.size == Vector2.ZERO:
		return

	if Engine.is_editor_hint():
		_draw_debug_bounds(bounds)
	else:
		_draw_black_bars(bounds)


func _draw_black_bars(bounds: Rect2) -> void:
	var left := bounds.position.x
	var right := bounds.end.x
	var top := bounds.position.y
	var bottom := bounds.end.y
	# Left bar.
	draw_rect(
		Rect2(
			left - _BAR_EXTENT,
			top - _BAR_EXTENT,
			_BAR_EXTENT,
			bounds.size.y + _BAR_EXTENT * 2.0),
		Color.BLACK)
	# Right bar.
	draw_rect(
		Rect2(
			right,
			top - _BAR_EXTENT,
			_BAR_EXTENT,
			bounds.size.y + _BAR_EXTENT * 2.0),
		Color.BLACK)
	# Top bar.
	draw_rect(
		Rect2(
			left - _BAR_EXTENT,
			top - _BAR_EXTENT,
			bounds.size.x + _BAR_EXTENT * 2.0,
			_BAR_EXTENT),
		Color.BLACK)
	# Bottom bar.
	draw_rect(
		Rect2(
			left - _BAR_EXTENT,
			bottom,
			bounds.size.x + _BAR_EXTENT * 2.0,
			_BAR_EXTENT),
		Color.BLACK)


func _draw_debug_bounds(bounds: Rect2) -> void:
	draw_rect(
		bounds,
		_DEBUG_COLOR,
		false,
		_DEBUG_LINE_WIDTH)
