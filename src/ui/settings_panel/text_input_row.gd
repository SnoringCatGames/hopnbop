class_name TextInputRow
extends MenuRow
## A settings row containing a LineEdit for text
## input. Activating toggles keyboard focus within
## the LineEdit independently of the outer row
## focus used for panel navigation.
##
## While the LineEdit has GUI focus it captures the
## physical keyboard (via InputDeviceManager): every
## keyboard action is suppressed so typing can't move
## a character or navigate a panel. Gamepad players
## keep control. Escape releases focus. Optionally the
## field can force-uppercase its text and auto-advance
## focus to the next row once it reaches a target
## length (used by fixed-length code fields).


signal text_changed(new_text: String)
signal submitted
## Emitted when the field reaches its auto-advance length. The owning
## panel typically connects this to focus_next_row so the confirm
## button takes over. Never fires when auto_advance_length is 0.
signal input_complete

const _EDITING_CARET_COLOR := Color(1.0, 0.85, 0.3)

var _placeholder := ""
var _max_length := 0
var _auto_advance_length := 0
var _force_uppercase := false
# True while this row holds the InputDeviceManager keyboard capture.
# Tracked so we only ever clear a capture we set, and can clear it
# defensively from _exit_tree if the row is freed while focused.
var _did_capture := false

@onready var _line_edit: LineEdit = %LineEdit


func setup(
	placeholder: String,
	max_length: int = 0,
	auto_advance_length: int = 0,
	force_uppercase: bool = false,
) -> void:
	_placeholder = placeholder
	_max_length = max_length
	_auto_advance_length = auto_advance_length
	_force_uppercase = force_uppercase


func get_text() -> String:
	return _line_edit.text


## Reset the field to empty. Used by the chat panel after a
## send so the user can type the next message without manually
## clearing the LineEdit.
func clear_text() -> void:
	_line_edit.text = ""


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


func _exit_tree() -> void:
	# If the row is freed while focused (panel closed mid-edit),
	# focus_exited may not fire; drop any capture we hold so the
	# keyboard isn't left globally suppressed.
	_release_capture()


func _input(event: InputEvent) -> void:
	# Escape exits the field (back to row navigation) without also
	# bubbling up to close the panel. Only act while we hold focus.
	if not _line_edit.has_focus():
		return
	if (event is InputEventKey
			and event.pressed
			and not event.echo
			and event.physical_keycode == KEY_ESCAPE):
		_line_edit.release_focus()
		get_viewport().set_input_as_handled()


func on_trigger() -> void:
	_toggle_editing()


func _toggle_editing() -> void:
	if _line_edit.has_focus():
		_line_edit.release_focus()
	else:
		_line_edit.grab_focus()


func _on_text_changed(new_text: String) -> void:
	if _force_uppercase:
		var upper := new_text.to_upper()
		if upper != new_text:
			# In-place rewrite. Setting .text programmatically does
			# not re-emit text_changed, so there's no recursion.
			# Preserve the caret across the swap.
			var caret := _line_edit.caret_column
			_line_edit.text = upper
			_line_edit.caret_column = mini(caret, upper.length())
			new_text = upper
	text_changed.emit(new_text)
	if (_auto_advance_length > 0
			and new_text.length() >= _auto_advance_length):
		# Field is full: hand focus back to the panel so the next row
		# (typically the confirm button) takes over. release_focus
		# fires focus_exited, which clears the keyboard capture.
		_line_edit.release_focus()
		input_complete.emit()


func _on_text_submitted(_text: String) -> void:
	submitted.emit()


func _on_focus_entered() -> void:
	_line_edit.add_theme_color_override(
		"caret_color", _EDITING_CARET_COLOR)
	if is_instance_valid(G.input_device_manager):
		G.input_device_manager.is_text_input_captured = true
		_did_capture = true


func _on_focus_exited() -> void:
	_line_edit.remove_theme_color_override(
		"caret_color")
	_release_capture()


## Drop the keyboard capture if we hold it. Idempotent, so both
## focus_exited and _exit_tree can call it safely.
func _release_capture() -> void:
	if not _did_capture:
		return
	_did_capture = false
	if is_instance_valid(G.input_device_manager):
		G.input_device_manager.is_text_input_captured = false
