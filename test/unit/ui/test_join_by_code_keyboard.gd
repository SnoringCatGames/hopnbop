extends GutTest
## H111: typing a full code on the on-screen keyboard
## (H56) enables Join; deleting a symbol disables it
## again. TextInputRow.set_text must run the same
## text_changed path typed input does, or
## JoinByCodePanel._on_code_changed never runs and
## Join stays disabled forever.


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
