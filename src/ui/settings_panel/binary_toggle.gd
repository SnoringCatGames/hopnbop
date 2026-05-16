class_name BinaryToggle
extends PanelContainer
## Binary toggle: two aggregate buttons (left and
## right). The selected option is highlighted.
## Modeled after LevelPrefRow but with two text
## buttons instead of three icon buttons.
##
## Distinct from MenuRow: this widget is used standalone
## inside Screens (leaderboard_panel) and is not part of
## the SettingsRow / MenuRow inheritance chain. It still
## advertises `consumes_horizontal_input()` so that the
## screen-side input dispatcher (ScreenFocusNavigator
## consumer) can route Left/Right to its own handlers
## instead of treating Left as "back".


signal option_changed(index: int)

const _SELECTED_ICON_COLOR := Color(0.9, 0.9, 0.9)

var _selected_index := 0
var _focus_style: StyleBox
var _unfocused_style: StyleBox

@export_group("Left Button Styles")
@export var left_normal: StyleBoxTexture
@export var left_pressed: StyleBoxTexture
@export var left_hovered: StyleBoxTexture
@export var left_selected: StyleBoxTexture
@export var left_disabled: StyleBoxTexture

@export_group("Right Button Styles")
@export var right_normal: StyleBoxTexture
@export var right_pressed: StyleBoxTexture
@export var right_hovered: StyleBoxTexture
@export var right_selected: StyleBoxTexture
@export var right_disabled: StyleBoxTexture


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	var extra_height := 2 * G.settings.icon_scale
	for button: Button in [%LeftButton, %RightButton]:
		button.custom_minimum_size.y += extra_height
		button.focus_mode = Control.FOCUS_NONE
	focus_entered.connect(_on_focus_changed)
	focus_exited.connect(_on_focus_changed)
	_update_button_styles()


func setup(
	left_label: String,
	right_label: String,
	initial_index: int,
	p_focus_style: StyleBox,
	p_unfocused_style: StyleBox,
) -> void:
	%LeftButton.text = left_label
	%RightButton.text = right_label
	_focus_style = p_focus_style
	_unfocused_style = p_unfocused_style
	_update_panel_style()
	set_option(initial_index)


func set_option(index: int) -> void:
	_selected_index = index
	_update_button_styles()


func get_option() -> int:
	return _selected_index


## Duck-typed by screen-side dispatchers (parallel to
## `MenuRow.consumes_horizontal_input`). Returns true so
## screens that route Left to their `on_back()` skip
## doing so while a BinaryToggle has focus.
func consumes_horizontal_input() -> bool:
	return true


func on_left() -> void:
	if _selected_index == 0:
		return
	set_option(0)
	if is_instance_valid(G.audio):
		G.audio.play_sound("select")
	option_changed.emit(0)


func on_right() -> void:
	if _selected_index == 1:
		return
	set_option(1)
	if is_instance_valid(G.audio):
		G.audio.play_sound("select")
	option_changed.emit(1)


## Trigger button parity: picks option 1 (same as
## Right) for keyboard / gamepad trigger.
func on_trigger() -> void:
	on_right()


func _on_left_button_pressed() -> void:
	on_left()


func _on_right_button_pressed() -> void:
	on_right()


func _on_focus_changed() -> void:
	_update_panel_style()


func _update_panel_style() -> void:
	if _focus_style == null:
		return
	if has_focus():
		add_theme_stylebox_override("panel", _focus_style)
	else:
		add_theme_stylebox_override("panel", _unfocused_style)


func _update_button_styles() -> void:
	_apply_btn_style(
		%LeftButton,
		left_normal, left_pressed,
		left_hovered, left_selected,
		left_disabled,
		_selected_index == 0)
	_apply_btn_style(
		%RightButton,
		right_normal, right_pressed,
		right_hovered, right_selected,
		right_disabled,
		_selected_index == 1)


func _apply_btn_style(
	button: Button,
	normal_style: StyleBoxTexture,
	pressed_style: StyleBoxTexture,
	hover_style: StyleBoxTexture,
	selected_style: StyleBoxTexture,
	disabled_style: StyleBoxTexture,
	is_selected: bool,
) -> void:
	if is_selected:
		button.add_theme_stylebox_override(
			"normal", selected_style)
		button.add_theme_stylebox_override(
			"hover", selected_style)
		button.add_theme_stylebox_override(
			"pressed", selected_style)
	else:
		button.add_theme_stylebox_override(
			"normal", normal_style)
		button.add_theme_stylebox_override(
			"hover", hover_style)
		button.add_theme_stylebox_override(
			"pressed", pressed_style)
	button.add_theme_stylebox_override(
		"disabled", disabled_style)
