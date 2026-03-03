class_name ControlDisplays
extends Node2D
## Cycles through control display labels one at a time,
## skipping displays whose device is in use by a player.


const _SHOW_SEC := 1
const _BLINK_SEC := 0.5

# Maps keyboard device names to display node names.
const _DEVICE_TO_DISPLAY := {
	"WASD": &"WASDControls",
	"IJKL": &"IJKLControls",
	"ArrowKeys": &"ArrowControls",
	"NumPad": &"NumPadControls",
}

# Ordered list of all display node names for cycling.
const _ALL_DISPLAY_NAMES: Array[StringName] = [
	&"WASDControls",
	&"IJKLControls",
	&"ArrowControls",
	&"NumPadControls",
	&"GamepadControls",
]

# Dictionary<StringName, bool> - true if the display's
# device is currently in use by a player.
var _in_use := {}

# Tracks the number of gamepad players (multiple
# gamepads share one display).
var _gamepad_count := 0

# Index into _ALL_DISPLAY_NAMES for the display
# currently shown (or last shown before blink).
var _current_index := 0

# Accumulated time in the current phase.
var _elapsed := 0.0

# Whether currently in the blink (hidden) phase.
var _is_blinking := false


func _ready() -> void:
	# Initialize all displays as not-in-use and hidden.
	for display_name in _ALL_DISPLAY_NAMES:
		_in_use[display_name] = false
		_get_display(display_name).visible = false
	# Show the first available display.
	_show_current()


func _process(delta: float) -> void:
	_update_cycle(delta)


## Marks a device's control display as in-use or
## available. Handles gamepad reference counting.
func set_device_in_use(
	device_name: StringName,
	in_use: bool,
) -> void:
	# Handle gamepad reference counting.
	if str(device_name).begins_with("GamePad_"):
		if in_use:
			_gamepad_count += 1
		else:
			_gamepad_count -= 1
		# Gamepad display is "in use" when any gamepad
		# player is active.
		_in_use[&"GamepadControls"] = (
			_gamepad_count > 0)
		_on_availability_changed()
		return

	# Keyboard display mapping.
	if _DEVICE_TO_DISPLAY.has(device_name):
		var node_name: StringName = (
			_DEVICE_TO_DISPLAY[device_name])
		_in_use[node_name] = in_use
		_on_availability_changed()


## Called when any display's availability changes.
## Re-evaluates what should be shown.
func _on_availability_changed() -> void:
	var available_count := _get_available_count()
	if available_count == 0:
		_hide_all()
		return
	# If the currently shown display just became
	# unavailable, advance immediately.
	if _is_current_in_use():
		_advance_to_next_available()
	# Reset phase and show the current display.
	_show_current()


func _update_cycle(delta: float) -> void:
	var available_count := _get_available_count()
	if available_count <= 1:
		# Zero or one available. No cycling needed.
		return

	_elapsed += delta

	if _is_blinking:
		if _elapsed >= _BLINK_SEC:
			_elapsed = 0.0
			_is_blinking = false
			_advance_to_next_available()
			_show_current()
	else:
		if _elapsed >= _SHOW_SEC:
			_elapsed = 0.0
			_is_blinking = true
			_hide_all()


## Returns the number of displays not currently in use.
func _get_available_count() -> int:
	var count := 0
	for display_name in _ALL_DISPLAY_NAMES:
		if not _in_use[display_name]:
			count += 1
	return count


## Hides all control displays.
func _hide_all() -> void:
	for display_name in _ALL_DISPLAY_NAMES:
		_get_display(display_name).visible = false


## Shows the display at _current_index if it is
## available. Ensures only one display is visible.
func _show_current() -> void:
	_hide_all()
	var available_count := _get_available_count()
	if available_count == 0:
		return
	# Ensure _current_index points to an available
	# display.
	if _is_current_in_use():
		_advance_to_next_available()
	_get_display(
		_ALL_DISPLAY_NAMES[_current_index]
	).visible = true
	_is_blinking = false
	_elapsed = 0.0


## Advances _current_index to the next available
## (not in-use) display, wrapping around.
func _advance_to_next_available() -> void:
	var count := _ALL_DISPLAY_NAMES.size()
	for i in range(1, count + 1):
		var candidate := (
			(_current_index + i) % count
		)
		if not _in_use[_ALL_DISPLAY_NAMES[candidate]]:
			_current_index = candidate
			return


## Returns true if the display at _current_index is
## in use by a player.
func _is_current_in_use() -> bool:
	return _in_use[
		_ALL_DISPLAY_NAMES[_current_index]]


func _get_display(
	display_name: StringName,
) -> AnimatedSprite2D:
	return get_node("%" + display_name)
