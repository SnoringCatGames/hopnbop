class_name PlayerOverheadLabel
extends Control


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
		%Label.add_theme_color_override("font_outline_color", value)
