class_name SettingsPanel
extends CanvasLayer
## Full-screen overlay for the settings UI.
## Uses device-specific input for navigation.
## Rendered on a high CanvasLayer to overlay
## gameplay.


signal closed

const _CloseRowScene := preload(
	"res://src/ui/settings_panel/close_row.tscn")
const _ToggleRowScene := preload(
	"res://src/ui/settings_panel/"
	+ "toggle_row.tscn")
const _CheatGroupRowScene := preload(
	"res://src/ui/settings_panel/"
	+ "cheat_group_row.tscn")
const _LevelPrefRowScene := preload(
	"res://src/ui/settings_panel/"
	+ "level_pref_row.tscn")

@export_group("Row Icons")
@export var icon_gore: Texture2D
@export var icon_critters: Texture2D
@export var icon_cheats: Texture2D
@export var icon_fullscreen: Texture2D
@export var icon_music: Texture2D
@export var icon_sfx: Texture2D

var _player: Player
var _device_config: DeviceConfig
var _rows: Array[SettingsRow] = []
var _level_pref_rows: Array[LevelPrefRow] = []
var _focused_index := 0

@onready var _scroll_container: \
	ScrollContainer = %ScrollContainer
@onready var _row_container: \
	VBoxContainer = %RowContainer

# Input state tracking for "just pressed"
# detection.
var _prev_up := false
var _prev_down := false
var _prev_left := false
var _prev_right := false

# Input repeat tracking.
var _held_direction := ""
var _hold_timer := 0.0
const _INPUT_INITIAL_DELAY := 0.3
const _INPUT_REPEAT_RATE := 0.1


func open(player: Player) -> void:
	_player = player
	_resolve_device_config()
	_build_ui()
	_set_focus(0)
	# Prime previous-input state so directions
	# already held when the panel opens are not
	# detected as "just pressed" on the first
	# frame. Without this, holding left/right
	# while landing on the settings book
	# immediately triggers CloseRow and the panel
	# closes before it is visible.
	if _device_config != null:
		_prev_up = G.input_device_manager \
			.get_is_action_pressed(
				&"move_up", _device_config)
		_prev_down = G.input_device_manager \
			.get_is_action_pressed(
				&"move_down", _device_config)
		_prev_left = G.input_device_manager \
			.get_is_action_pressed(
				&"move_left", _device_config)
		_prev_right = G.input_device_manager \
			.get_is_action_pressed(
				&"move_right", _device_config)
	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")


func close() -> void:
	# Collect and save level preferences.
	_save_level_preferences()
	G.local_settings.save_settings()

	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")

	G.is_settings_ui_shown = false
	G.settings_ui_player = null
	closed.emit()
	queue_free()


func _resolve_device_config() -> void:
	# In lobby, player_id = -(lobby_id + 1).
	var lobby_id: int = \
		-((_player.player_id) + 1)
	_device_config = \
		G.input_device_manager \
			.get_device_for_player(lobby_id)


func _build_ui() -> void:
	# Top padding.
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = \
		Vector2(0, 30)
	_row_container.add_child(top_spacer)

	# Close row.
	var close_row: CloseRow = \
		_CloseRowScene.instantiate()
	close_row.setup(self)
	_row_container.add_child(close_row)
	_connect_row_clicked(close_row)

	# Spacer below close button.
	var close_spacer := Control.new()
	close_spacer.custom_minimum_size = \
		Vector2(0, 20)
	_row_container.add_child(close_spacer)

	# Gore toggle.
	_add_toggle_row(
		"Gore", &"is_gore_enabled",
		0, icon_gore)

	# Critters toggle.
	_add_toggle_row(
		"Critters", &"are_critters_enabled",
		0, icon_critters)

	# Cheats group toggle.
	var cheats_row: CheatGroupRow = \
		_CheatGroupRowScene.instantiate()
	cheats_row.set_icon(icon_cheats)
	cheats_row.setup(
		"Cheats", &"are_cheats_enabled")
	_row_container.add_child(cheats_row)
	_connect_row_clicked(cheats_row)

	# Cheat sub-rows.
	var cheat_sub_rows: Array[SettingsRow] = []

	var cheat_indent := 24
	cheat_sub_rows.append(
		_add_toggle_row(
			"jetpack",
			&"is_jetpack_enabled",
			cheat_indent))
	cheat_sub_rows.append(
		_add_toggle_row(
			"bloodisthickerthanwater",
			&"is_bloodisthickerthanwater_enabled",
			cheat_indent))
	cheat_sub_rows.append(
		_add_toggle_row(
			"lordoftheflies",
			&"is_lordoftheflies_enabled",
			cheat_indent))
	cheat_sub_rows.append(
		_add_toggle_row(
			"pogostick",
			&"is_pogostick_enabled",
			cheat_indent))
	cheat_sub_rows.append(
		_add_toggle_row(
			"bunniesinspace",
			&"is_bunniesinspace_enabled",
			cheat_indent))
	cheat_sub_rows.append(
		_add_toggle_row(
			"moregore",
			&"is_moregore_enabled",
			cheat_indent))

	cheats_row.set_sub_rows(
		cheat_sub_rows, self)

	# Full screen toggle.
	_add_toggle_row(
		"Full Screen", &"full_screen",
		0, icon_fullscreen)

	# Music toggle (inverted: checked = enabled).
	_add_toggle_row(
		"Music", &"mute_music",
		0, icon_music, true)

	# SFX toggle (inverted: checked = enabled).
	_add_toggle_row(
		"SFX", &"mute_sfx",
		0, icon_sfx, true)

	# Spacer above level preferences.
	var level_spacer := Control.new()
	level_spacer.custom_minimum_size = \
		Vector2(0, 20)
	_row_container.add_child(level_spacer)

	# Load persisted level preferences.
	var saved_prefs: LevelPreferences = \
		G.local_settings.load_level_preferences()

	# Level preference rows.
	for level_info: LevelInfo \
			in G.level_registry._levels:
		var initial_state := \
			LevelPrefRow.LevelPrefState.INCLUDED
		if saved_prefs != null:
			if level_info.id \
					== saved_prefs.preferred_level:
				initial_state = \
					LevelPrefRow.LevelPrefState \
						.PREFERRED
			elif level_info.id \
					in saved_prefs.exclusion_list:
				initial_state = \
					LevelPrefRow.LevelPrefState \
						.EXCLUDED

		var level_row: LevelPrefRow = \
			_LevelPrefRowScene.instantiate()
		level_row.setup(
			level_info.id,
			level_info.display_name,
			self,
			initial_state)
		_row_container.add_child(level_row)
		_connect_row_clicked(level_row)
		_level_pref_rows.append(level_row)

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = \
		Vector2(0, 30)
	_row_container.add_child(bottom_spacer)

	# Build initial navigable row list.
	rebuild_row_list()


func _add_toggle_row(
	display_name: String,
	setting_key: StringName,
	indent_pixels := 0,
	icon: Texture2D = null,
	is_inverted := false,
) -> ToggleRow:
	var row: ToggleRow = \
		_ToggleRowScene.instantiate()
	if indent_pixels > 0:
		row.set_indent(indent_pixels)
	if icon != null:
		row.set_icon(icon)
	if is_inverted:
		row.set_inverted()
	row.setup(display_name, setting_key)
	_row_container.add_child(row)
	_connect_row_clicked(row)
	return row


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


## Rebuild the navigable row list from visible
## SettingsRow children.
func rebuild_row_list() -> void:
	var old_focused: SettingsRow = null
	if _focused_index >= 0 \
			and _focused_index < _rows.size():
		old_focused = _rows[_focused_index]

	_rows.clear()
	for child in _row_container.get_children():
		if child is SettingsRow and child.visible:
			_rows.append(child)

	# Try to preserve focus on the same row.
	if old_focused != null \
			and old_focused in _rows:
		_set_focus(_rows.find(old_focused))
	else:
		_set_focus(
			clampi(
				_focused_index,
				0,
				_rows.size() - 1))


## Enforce heart exclusivity: only one level can
## have PREFERRED state at a time.
func on_level_preferred(
	preferred_row: LevelPrefRow,
) -> void:
	for row in _level_pref_rows:
		if row != preferred_row \
				and row.get_state() == \
				LevelPrefRow.LevelPrefState \
					.PREFERRED:
			row.set_state(
				LevelPrefRow.LevelPrefState \
					.INCLUDED)


func _set_focus(index: int) -> void:
	if _rows.is_empty():
		return

	# Clear old focus.
	if _focused_index >= 0 \
			and _focused_index < _rows.size():
		_rows[_focused_index].is_focused = false

	_focused_index = index
	_rows[_focused_index].is_focused = true
	_ensure_focused_visible()


func _move_focus(
	direction: int,
	is_wrap := true,
) -> void:
	if _rows.is_empty():
		return

	var new_index: int
	if is_wrap:
		new_index = \
			(_focused_index + direction) \
			% _rows.size()
		if new_index < 0:
			new_index += _rows.size()
	else:
		new_index = clampi(
			_focused_index + direction,
			0,
			_rows.size() - 1)
		if new_index == _focused_index:
			return
	_set_focus(new_index)
	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")


func _ensure_focused_visible() -> void:
	if _rows.is_empty():
		return

	var row: SettingsRow = \
		_rows[_focused_index]

	# Wait a frame for layout to settle.
	await get_tree().process_frame

	# Scroll to show the focused row.
	_scroll_container.ensure_control_visible(row)


func _process(delta: float) -> void:
	if _device_config == null:
		return

	var up := G.input_device_manager \
		.get_is_action_pressed(
			&"move_up", _device_config)
	var down := G.input_device_manager \
		.get_is_action_pressed(
			&"move_down", _device_config)
	var left := G.input_device_manager \
		.get_is_action_pressed(
			&"move_left", _device_config)
	var right := G.input_device_manager \
		.get_is_action_pressed(
			&"move_right", _device_config)

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
	if current_dir != "" \
			and current_dir == _held_direction:
		_hold_timer += delta
		if _hold_timer >= _INPUT_INITIAL_DELAY:
			var time_past_delay := \
				_hold_timer - _INPUT_INITIAL_DELAY
			var repeat_count := int(
				time_past_delay \
				/ _INPUT_REPEAT_RATE)
			var prev_time := \
				_hold_timer - delta \
				- _INPUT_INITIAL_DELAY
			var prev_count := int(
				max(0, prev_time) \
				/ _INPUT_REPEAT_RATE)
			if repeat_count > prev_count:
				should_repeat = true
	else:
		_held_direction = current_dir
		_hold_timer = 0.0

	# Process directional input.
	if up_just or \
			(should_repeat and current_dir == "up"):
		_move_focus(-1)
	elif down_just or \
			(should_repeat \
			and current_dir == "down"):
		_move_focus(1)
	elif left_just or \
			(should_repeat \
			and current_dir == "left"):
		if _focused_index >= 0 \
				and _focused_index < _rows.size():
			_rows[_focused_index].on_left()
	elif right_just or \
			(should_repeat \
			and current_dir == "right"):
		if _focused_index >= 0 \
				and _focused_index < _rows.size():
			_rows[_focused_index].on_right()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_pause"):
		close()
		get_viewport() \
			.set_input_as_handled()
		return

	# Mouse scroll wheel.
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			if mb.button_index == \
					MOUSE_BUTTON_WHEEL_UP:
				_move_focus(-1, false)
				get_viewport() \
					.set_input_as_handled()
			elif mb.button_index == \
					MOUSE_BUTTON_WHEEL_DOWN:
				_move_focus(1, false)
				get_viewport() \
					.set_input_as_handled()


func _save_level_preferences() -> void:
	var prefs := LevelPreferences.new()
	for row in _level_pref_rows:
		match row.get_state():
			LevelPrefRow.LevelPrefState.EXCLUDED:
				prefs.exclude_level(
					row.get_level_id())
			LevelPrefRow.LevelPrefState.INCLUDED:
				prefs.include_level(
					row.get_level_id())
			LevelPrefRow.LevelPrefState.PREFERRED:
				prefs.set_preferred(
					row.get_level_id())
	G.local_settings.save_level_preferences(prefs)
