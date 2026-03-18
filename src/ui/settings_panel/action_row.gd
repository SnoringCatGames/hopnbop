class_name ActionRow
extends SettingsRow
## A row that delegates left and right actions
## to callables. Built programmatically without
## a scene file. Used for dynamically generated
## interactive rows in side panels.


var _on_left_action: Callable
var _on_right_action: Callable


func setup_actions(
	on_right_action: Callable = Callable(),
	on_left_action: Callable = Callable(),
) -> void:
	_on_right_action = on_right_action
	_on_left_action = on_left_action


func on_left() -> void:
	if _on_left_action.is_valid():
		_on_left_action.call()


func on_right() -> void:
	if _on_right_action.is_valid():
		_on_right_action.call()
