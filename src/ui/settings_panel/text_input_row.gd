class_name TextInputRow
extends SettingsRow
## A settings row containing a LineEdit for text
## input. Triggering (L/R or named action) toggles
## keyboard focus within the LineEdit independently
## of the outer row focus used for panel navigation.


signal text_changed(new_text: String)
signal submitted

const _EDITING_CARET_COLOR := Color(1.0, 0.85, 0.3)

var _placeholder := ""
var _max_length := 0

@onready var _line_edit: LineEdit = %LineEdit


func setup(
	placeholder: String,
	max_length: int = 0,
) -> void:
	_placeholder = placeholder
	_max_length = max_length


func get_text() -> String:
	return _line_edit.text


func _ready() -> void:
	super()
	_line_edit.placeholder_text = _placeholder
	if _max_length > 0:
		_line_edit.max_length = _max_length
	_line_edit.text_changed.connect(
		_on_text_changed)
	_line_edit.text_submitted.connect(
		_on_text_submitted)
	_line_edit.focus_entered.connect(
		_on_focus_entered)
	_line_edit.focus_exited.connect(
		_on_focus_exited)


func on_left() -> void:
	_toggle_editing()


func on_right() -> void:
	_toggle_editing()


func _toggle_editing() -> void:
	if _line_edit.has_focus():
		_line_edit.release_focus()
	else:
		_line_edit.grab_focus()


func _on_text_changed(new_text: String) -> void:
	text_changed.emit(new_text)


func _on_text_submitted(_text: String) -> void:
	submitted.emit()


func _on_focus_entered() -> void:
	_line_edit.add_theme_color_override(
		"caret_color", _EDITING_CARET_COLOR)


func _on_focus_exited() -> void:
	_line_edit.remove_theme_color_override(
		"caret_color")
