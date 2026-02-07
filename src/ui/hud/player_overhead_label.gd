class_name PlayerOverheadLabel
extends Control


const _OPACITY := 0.7


var player_id: int
var label: Label
var tween: Tween
var shown := true

var text: String:
	get:
		return %Label.text
	set(value):
		%Label.text = value
		_center_label()

var color: Color:
	set(value):
		%Label.add_theme_color_override("font_color", Color(value, _OPACITY))


func _ready() -> void:
	_center_label()


func _center_label() -> void:
	if not is_node_ready():
		return

	# Wait for next frame to ensure text has been rendered and size calculated.
	await get_tree().process_frame

	var label_width: float = %Label.size.x
	%Label.offset_left = -label_width / 2.0
	%Label.offset_right = label_width / 2.0
