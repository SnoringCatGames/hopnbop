extends GutTest
## H56: the on-screen code keyboard row. L/R moves the
## selection within the row, Trigger emits its symbol.


var _row: CodeKeyboardRow
var _chosen: Array = []


func before_each() -> void:
	_chosen = []
	_row = CodeKeyboardRow.new()
	_row.setup(["2", "3", "4", "5"])
	_row.symbol_chosen.connect(
		func(symbol: String) -> void:
			_chosen.append(symbol))
	add_child_autofree(_row)


func test_trigger_emits_the_selected_symbol() -> void:
	_row.on_trigger()

	assert_eq(_chosen, ["2"])


func test_right_moves_the_selection_and_clamps() -> void:
	_row.on_right()
	_row.on_right()
	_row.on_right()
	_row.on_right()
	_row.on_trigger()

	assert_eq(_chosen, ["5"], "selection clamps at the row end")


func test_left_moves_back_and_clamps() -> void:
	_row.on_right()
	_row.on_left()
	_row.on_left()
	_row.on_trigger()

	assert_eq(_chosen, ["2"], "selection clamps at the row start")
