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

var color: Color:
	set(value):
		%Label.add_theme_color_override(
			"font_color",
			Color(value, _OPACITY))
