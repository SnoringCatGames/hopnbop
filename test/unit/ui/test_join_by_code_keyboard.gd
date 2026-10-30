extends GutTest
## H111: typing a full code on the on-screen keyboard
## (H56) enables Join; deleting a symbol disables it
## again. TextInputRow.set_text must run the same
## text_changed path typed input does, or
## JoinByCodePanel._on_code_changed never runs and
## Join stays disabled forever.
##
## H112: a completed code hands focus to the Join row
## itself, not one row down from wherever focus sits:
## keyboard entry used to land on the next keyboard
## row, typed entry on the first keyboard row.


const _PANEL_PATH := (
	"res://src/ui/party/join_by_code_panel.tscn")

var _panel: JoinByCodePanel


func before_each() -> void:
	G.settings.is_code_keyboard_enabled = true
	_panel = load(_PANEL_PATH).instantiate()
	add_child_autofree(_panel)
	_panel.build_ui()


func after_each() -> void:
	G.settings.is_code_keyboard_enabled = false


func test_keyboard_typed_code_enables_join() -> void:
	var rows := _keyboard_rows()
	assert_eq(rows.size(), 8, "eight keyboard rows")

	for symbol in "234567":
		_type_symbol(rows, symbol)

	assert_eq(_panel._code_input.get_text(), "234567")
	assert_false(_panel._join_row.disabled,
		"a full keyboard-typed code enables Join")

	_delete_row().on_trigger()

	assert_eq(_panel._code_input.get_text(), "23456")
	assert_true(_panel._join_row.disabled,
		"deleting below the code length disables Join")


func test_keyboard_completed_code_focuses_join() -> void:
	_panel.rebuild_row_list()
	# The player sits on a keyboard row while typing.
	_panel._set_focus(
		_panel._rows.find(_keyboard_rows()[0]))

	for symbol in "234567":
		_type_symbol(_keyboard_rows(), symbol)

	assert_same(_focused_row(), _panel._join_row,
		"a complete keyboard-typed code focuses Join")


func test_field_completed_code_focuses_join_keyboard_on() -> void:
	_panel.rebuild_row_list()
	_panel._set_focus(
		_panel._rows.find(_panel._code_input))

	_type_into_field(_panel, "234567")

	assert_same(_focused_row(), _panel._join_row,
		"a complete field-typed code focuses Join")


func test_field_completed_code_focuses_join_keyboard_off() -> void:
	G.settings.is_code_keyboard_enabled = false
	var panel: JoinByCodePanel = (
		load(_PANEL_PATH).instantiate())
	add_child_autofree(panel)
	panel.build_ui()
	panel.rebuild_row_list()
	panel._set_focus(
		panel._rows.find(panel._code_input))

	_type_into_field(panel, "234567")

	assert_same(
		panel._rows[panel._focused_index],
		panel._join_row,
		"with the keyboard off, focus still lands on Join")


func _focused_row() -> MenuRow:
	return _panel._rows[_panel._focused_index]


## Types into the field the way keystrokes do: the
## LineEdit's text grows one symbol at a time and each
## change goes through its text_changed signal.
func _type_into_field(
	panel: JoinByCodePanel,
	code: String,
) -> void:
	var line_edit: LineEdit = (
		panel._code_input.get_node("%LineEdit"))
	for symbol in code:
		line_edit.text += symbol
		line_edit.text_changed.emit(line_edit.text)


func _keyboard_rows() -> Array:
	var rows: Array = []
	for child in _panel._row_container.get_children():
		if child is CodeKeyboardRow:
			rows.append(child)
	return rows


func _type_symbol(
	rows: Array,
	symbol: String,
) -> void:
	for row: CodeKeyboardRow in rows:
		# Four symbols per row; the walk clamps at the
		# row end, so four steps visit every symbol.
		for step in 4:
			if row.selected_symbol() == symbol:
				row.on_trigger()
				return
			row.on_right()
	fail_test("no keyboard row holds %s" % symbol)


func _delete_row() -> ActionRow:
	for child in _panel._row_container.get_children():
		if (child is ActionRow
				and child != _panel._join_row):
			return child
	fail_test("no delete row found")
	return null
