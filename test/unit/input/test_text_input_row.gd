extends GutTest
## Unit tests for TextInputRow: keyboard capture on focus, forced
## uppercasing, and auto-advance signalling.
##
## The focus/blur cases drive the LineEdit's focus_entered/focus_exited
## signals directly rather than relying on real grab_focus() semantics,
## which are unreliable headless. That still exercises the row's wiring
## (the handlers connected in _ready) and its effect on the shared
## InputDeviceManager capture flag.


const _SCENE := "res://src/ui/settings_panel/text_input_row.tscn"


func before_each() -> void:
	# The capture flag lives on the G.input_device_manager autoload and
	# is shared across tests; start each test from a known state.
	G.input_device_manager.is_text_input_captured = false


func after_each() -> void:
	G.input_device_manager.is_text_input_captured = false


func _make_row(
	max_length: int = 0,
	auto_advance: int = 0,
	force_uppercase: bool = false,
) -> TextInputRow:
	var row: TextInputRow = load(_SCENE).instantiate()
	# setup() must precede _ready(); add_child triggers _ready.
	row.setup("placeholder", max_length, auto_advance, force_uppercase)
	add_child_autofree(row)
	return row


func test_setup_applies_max_length() -> void:
	var row := _make_row(8)
	var line_edit: LineEdit = row.get_node("%LineEdit")
	assert_eq(line_edit.max_length, 8)


func test_focus_captures_and_releases_keyboard() -> void:
	var row := _make_row()
	var line_edit: LineEdit = row.get_node("%LineEdit")

	line_edit.focus_entered.emit()
	assert_true(
		G.input_device_manager.is_text_input_captured,
		"focus should capture the keyboard")

	line_edit.focus_exited.emit()
	assert_false(
		G.input_device_manager.is_text_input_captured,
		"blur should release the keyboard")


func test_exit_tree_releases_capture_if_focused() -> void:
	var row := _make_row()
	var line_edit: LineEdit = row.get_node("%LineEdit")
	line_edit.focus_entered.emit()
	assert_true(G.input_device_manager.is_text_input_captured)

	remove_child(row)
	assert_false(
		G.input_device_manager.is_text_input_captured,
		"leaving the tree while focused must release capture")
	row.free()


func test_force_uppercase_rewrites_text() -> void:
	var row := _make_row(8, 0, true)
	var line_edit: LineEdit = row.get_node("%LineEdit")
	line_edit.text = "abc"
	line_edit.text_changed.emit("abc")
	assert_eq(line_edit.text, "ABC")


func test_no_uppercase_when_disabled() -> void:
	var row := _make_row(8, 0, false)
	var line_edit: LineEdit = row.get_node("%LineEdit")
	line_edit.text = "abc"
	line_edit.text_changed.emit("abc")
	assert_eq(line_edit.text, "abc")


func test_text_changed_forwards_uppercased_value() -> void:
	var row := _make_row(8, 0, true)
	var line_edit: LineEdit = row.get_node("%LineEdit")
	watch_signals(row)
	line_edit.text = "k7q"
	line_edit.text_changed.emit("k7q")
	assert_signal_emitted_with_parameters(
		row, "text_changed", ["K7Q"])


func test_auto_advance_emits_input_complete_at_length() -> void:
	var row := _make_row(3, 3, false)
	var line_edit: LineEdit = row.get_node("%LineEdit")
	watch_signals(row)
	line_edit.text = "abc"
	line_edit.text_changed.emit("abc")
	assert_signal_emitted(row, "input_complete")


func test_auto_advance_silent_below_length() -> void:
	var row := _make_row(5, 5, false)
	var line_edit: LineEdit = row.get_node("%LineEdit")
	watch_signals(row)
	line_edit.text = "ab"
	line_edit.text_changed.emit("ab")
	assert_signal_not_emitted(row, "input_complete")


func test_no_auto_advance_when_length_zero() -> void:
	# auto_advance_length 0 (default) means "never auto-advance",
	# even for a long entry like a chat message.
	var row := _make_row(0, 0, false)
	var line_edit: LineEdit = row.get_node("%LineEdit")
	watch_signals(row)
	line_edit.text = "a long chat message"
	line_edit.text_changed.emit("a long chat message")
	assert_signal_not_emitted(row, "input_complete")
