class_name CodeKeyboardRow
extends MenuRow
## One row of the on-screen code keyboard (H56): four
## symbols, L/R moves the selection, Trigger types the
## selected symbol. The owning panel supplies the symbols
## and connects symbol_chosen. Gamepad players can enter
## fixed-alphabet codes (party invite codes, friend codes)
## without a physical keyboard.


signal symbol_chosen(symbol: String)

var _symbols: Array[String] = []
var _selected := 0
var _label: Label


func setup(symbols: Array[String]) -> void:
	_symbols = symbols
	_selected = 0
	_refresh_label()


func selected_symbol() -> String:
	if _symbols.is_empty():
		return ""
	return _symbols[_selected]


func consumes_horizontal_input() -> bool:
	return true


func on_left() -> void:
	if _symbols.is_empty():
		return
	_selected = maxi(0, _selected - 1)
	_refresh_label()


func on_right() -> void:
	if _symbols.is_empty():
		return
	_selected = mini(_symbols.size() - 1, _selected + 1)
	_refresh_label()


func on_trigger() -> void:
	if _symbols.is_empty():
		return
	symbol_chosen.emit(_symbols[_selected])


func _ready() -> void:
	super()
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	_refresh_label()


func _refresh_label() -> void:
	if _label == null:
		return
	var parts: Array[String] = []
	for i in _symbols.size():
		if i == _selected:
			parts.append("[ %s ]" % _symbols[i])
		else:
			parts.append("  %s  " % _symbols[i])
	_label.text = " ".join(parts)
