class_name ScreenFocusNavigator
extends RefCounted
## Shared focus navigation for screens that use
## AnyDeviceInputPoller with a list of focusable
## Button controls. Encapsulates polling, focus
## movement, and focus visual state.


var _poller := AnyDeviceInputPoller.new()
var _focusable: Array[Control] = []
var _focused_index := 0


## Replaces the focusable list, resets focus to
## the first item, and updates visuals.
func set_focusable_list(
	items: Array[Control],
) -> void:
	_focusable = items
	_focused_index = 0
	_update_focus()


## Primes the input poller to avoid phantom
## "just pressed" detections.
func prime() -> void:
	_poller.prime()


## Returns the currently focused control, or null
## if the list is empty.
func get_focused() -> Control:
	if _focusable.is_empty():
		return null
	return _focusable[_focused_index]


## Polls input and returns true if the activate
## action was triggered (left, right, or trigger).
## Automatically handles up/down focus movement.
func poll(delta: float) -> bool:
	if _focusable.is_empty():
		return false

	_poller.poll(delta)

	if _poller.up_just:
		_move_focus(-1)
	elif _poller.down_just:
		_move_focus(1)
	elif (_poller.left_just
			or _poller.right_just
			or _poller.trigger_just):
		return true

	return false


## Sets focus to the item at the given index
## without playing the focus sound.
func focus_index(index: int) -> void:
	if _focusable.is_empty():
		return
	_focused_index = clampi(
		index, 0, _focusable.size() - 1)
	_update_focus()


func _move_focus(direction: int) -> void:
	if _focusable.is_empty():
		return
	_focused_index = (
		(_focused_index + direction)
		% _focusable.size())
	if _focused_index < 0:
		_focused_index += _focusable.size()
	_update_focus()
	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")


func _update_focus() -> void:
	for i in _focusable.size():
		if i == _focused_index:
			_focusable[i].grab_focus()
		else:
			_focusable[i].release_focus()
