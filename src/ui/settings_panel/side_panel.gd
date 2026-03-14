class_name SidePanel
extends Control
## Base class for side-panel content. Manages a
## scrollable list of SettingsRow children with
## focus navigation and device-specific input.


var manager: SidePanelManager
var _player: Player
var _device_config: DeviceConfig
var _rows: Array[SettingsRow] = []
var _focused_index := 0
var is_input_active := true:
	set(value):
		var was_inactive := not is_input_active
		is_input_active = value
		if value and was_inactive:
			prime_input_state()

@onready var _scroll_container: ScrollContainer = (
	%ScrollContainer)
@onready var _row_container: VBoxContainer = (
	%RowContainer)

# Input state tracking for "just pressed"
# detection.
var _prev_up := false
var _prev_down := false
var _prev_left := false
var _prev_right := false
var _prev_trigger := false

# Input repeat tracking.
var _held_direction := ""
var _hold_timer := 0.0
const _INPUT_INITIAL_DELAY := 0.3
const _INPUT_REPEAT_RATE := 0.1


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_propagate_size()


func _propagate_size() -> void:
	for child in get_children():
		if child is Control:
			child.size = size


func setup(
	mgr: SidePanelManager,
	player: Player,
	device_config: DeviceConfig,
) -> void:
	manager = mgr
	_player = player
	_device_config = device_config


## Override in subclasses to populate rows.
func build_ui() -> void:
	pass


## Opens a ConfirmOverlay modal, disabling this
## panel's input while the dialog is open.
func open_confirm_dialog(
	message: String,
	accept_text: String,
	on_accept: Callable,
	reject_text: String = "",
	on_reject: Callable = Callable(),
) -> void:
	is_input_active = false
	var dialog: ConfirmOverlay = (
		G.settings.confirm_overlay_scene
			.instantiate())
	dialog.tree_exiting.connect(
		func() -> void:
			if is_instance_valid(self):
				is_input_active = true)
	G.confirm_layer.add_child(dialog)
	dialog.open(
		message,
		accept_text,
		on_accept,
		reject_text,
		on_reject,
		_device_config,
	)


func prime_input_state() -> void:
	if _device_config != null:
		_prev_up = (
			G.input_device_manager
				.get_is_action_pressed(
					&"move_up", _device_config))
		_prev_down = (
			G.input_device_manager
				.get_is_action_pressed(
					&"move_down", _device_config))
		_prev_left = (
			G.input_device_manager
				.get_is_action_pressed(
					&"move_left", _device_config))
		_prev_right = (
			G.input_device_manager
				.get_is_action_pressed(
					&"move_right", _device_config))
		_prev_trigger = _is_trigger_pressed()


## Rebuild the navigable row list from visible
## SettingsRow children.
func rebuild_row_list() -> void:
	var old_focused: SettingsRow = null
	if (_focused_index >= 0
			and _focused_index < _rows.size()):
		old_focused = _rows[_focused_index]

	_rows.clear()
	for child in _row_container.get_children():
		if child is SettingsRow and child.visible:
			_rows.append(child)

	# Try to preserve focus on the same row.
	if (old_focused != null
			and old_focused in _rows):
		_set_focus(_rows.find(old_focused))
	else:
		_set_focus(
			clampi(
				_focused_index,
				0,
				_rows.size() - 1))


func _connect_row_clicked(
	row: SettingsRow,
) -> void:
	row.clicked.connect(
		_on_row_clicked.bind(row))


func _on_row_clicked(row: SettingsRow) -> void:
	var index := _rows.find(row)
	if index < 0:
		return
	_set_focus(index)
	# LevelPrefRow has its own sub-buttons;
	# don't toggle on row click.
	if not row is LevelPrefRow:
		row.on_right()


func _set_focus(
	index: int,
	is_scroll_to_focus := true,
) -> void:
	if _rows.is_empty():
		return

	# Clear old focus.
	if (_focused_index >= 0
			and _focused_index < _rows.size()):
		_rows[_focused_index].is_focused = false

	_focused_index = index
	_rows[_focused_index].is_focused = true
	if is_scroll_to_focus:
		_ensure_focused_visible()


func _move_focus(
	direction: int,
	is_wrap := true,
	is_scroll_to_focus := true,
) -> void:
	if _rows.is_empty():
		return

	var new_index: int
	if is_wrap:
		new_index = (
			(_focused_index + direction)
			% _rows.size())
		if new_index < 0:
			new_index += _rows.size()
	else:
		new_index = clampi(
			_focused_index + direction,
			0,
			_rows.size() - 1)
		if new_index == _focused_index:
			return
	_set_focus(new_index, is_scroll_to_focus)
	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")


func _ensure_focused_visible() -> void:
	if _rows.is_empty():
		return

	var row: SettingsRow = _rows[_focused_index]

	# Wait a frame for layout to settle.
	await get_tree().process_frame

	# Scroll to show the focused row.
	_scroll_container.ensure_control_visible(row)


func _is_trigger_pressed() -> bool:
	if (Input.is_physical_key_pressed(KEY_ENTER)
			or Input.is_physical_key_pressed(
				KEY_SPACE)):
		return true
	if (_device_config != null
			and _device_config.type
			== DeviceConfig.DeviceType.GAMEPAD):
		return Input.is_action_pressed(
			&"trigger_ui",
			_device_config.device_id)
	return false


func _process(delta: float) -> void:
	if _device_config == null:
		return
	if not is_input_active:
		return

	var up := (
		G.input_device_manager
			.get_is_action_pressed(
				&"move_up", _device_config))
	var down := (
		G.input_device_manager
			.get_is_action_pressed(
				&"move_down", _device_config))
	var left := (
		G.input_device_manager
			.get_is_action_pressed(
				&"move_left", _device_config))
	var right := (
		G.input_device_manager
			.get_is_action_pressed(
				&"move_right", _device_config))

	# Detect "just pressed" transitions.
	var up_just := up and not _prev_up
	var down_just := down and not _prev_down
	var left_just := left and not _prev_left
	var right_just := right and not _prev_right

	_prev_up = up
	_prev_down = down
	_prev_left = left
	_prev_right = right

	# Determine current held direction.
	var current_dir := ""
	if up:
		current_dir = "up"
	elif down:
		current_dir = "down"
	elif left:
		current_dir = "left"
	elif right:
		current_dir = "right"

	# Handle input repeat.
	var should_repeat := false
	if (current_dir != ""
			and current_dir == _held_direction):
		_hold_timer += delta
		if _hold_timer >= _INPUT_INITIAL_DELAY:
			var time_past_delay := (
				_hold_timer - _INPUT_INITIAL_DELAY)
			var repeat_count := int(
				time_past_delay
				/ _INPUT_REPEAT_RATE)
			var prev_time := (
				_hold_timer - delta
				- _INPUT_INITIAL_DELAY)
			var prev_count := int(
				max(0, prev_time)
				/ _INPUT_REPEAT_RATE)
			if repeat_count > prev_count:
				should_repeat = true
	else:
		_held_direction = current_dir
		_hold_timer = 0.0

	# Process directional input.
	if (up_just
			or (should_repeat
			and current_dir == "up")):
		_move_focus(-1)
	elif (down_just
			or (should_repeat
			and current_dir == "down")):
		_move_focus(1)
	elif (left_just
			or (should_repeat
			and current_dir == "left")):
		if (_focused_index >= 0
				and _focused_index < _rows.size()):
			_rows[_focused_index].on_left()
	elif (right_just
			or (should_repeat
			and current_dir == "right")):
		if (_focused_index >= 0
				and _focused_index < _rows.size()):
			_rows[_focused_index].on_right()

	# Trigger detection (Enter/Space/trigger_ui).
	var trigger := _is_trigger_pressed()
	var trigger_just := trigger and not _prev_trigger
	_prev_trigger = trigger
	if trigger_just:
		if (_focused_index >= 0
				and _focused_index < _rows.size()):
			_rows[_focused_index].on_right()


func _unhandled_input(event: InputEvent) -> void:
	if not is_input_active:
		return

	# Mouse scroll wheel.
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			if (mb.button_index
					== MOUSE_BUTTON_WHEEL_UP):
				_move_focus(-1, false, false)
				get_viewport().set_input_as_handled()
			elif (mb.button_index
					== MOUSE_BUTTON_WHEEL_DOWN):
				_move_focus(1, false, false)
				get_viewport().set_input_as_handled()
