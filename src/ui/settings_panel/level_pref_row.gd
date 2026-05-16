class_name LevelPrefRow
extends MenuRow
## Row showing a level name and tri-toggle
## aggregate button (X / checkmark / heart).
##
## One of two row classes whose Left and Right have
## distinct semantics (the other is the standalone
## `BinaryToggle`). `consumes_horizontal_input()`
## returns true so the SidePanel does NOT route Left
## to its back action while a LevelPrefRow is focused.
## `on_trigger()` is aliased to `on_right()` so the
## gamepad trigger button cycles the state forward
## the same way the Right direction does.


enum LevelPrefState {
	EXCLUDED, # X. Left button.
	INCLUDED, # Checkmark. Middle button.
	PREFERRED, # Heart. Right button.
}

const _SELECTED_ICON_COLOR := (
	Color(0.9, 0.9, 0.9))
const _INDENT_MARGIN := 10

var _level_id: StringName
var _display_name: String
var _state := LevelPrefState.INCLUDED
var _panel: LevelPrefPanel
var _thumbnail: Texture2D

@export_group("Left Button Styles")
@export var left_normal: StyleBoxTexture
@export var left_pressed: StyleBoxTexture
@export var left_hovered: StyleBoxTexture
@export var left_selected: StyleBoxTexture
@export var left_disabled: StyleBoxTexture

@export_group("Middle Button Styles")
@export var middle_normal: StyleBoxTexture
@export var middle_pressed: StyleBoxTexture
@export var middle_hovered: StyleBoxTexture
@export var middle_selected: StyleBoxTexture
@export var middle_disabled: StyleBoxTexture

@export_group("Right Button Styles")
@export var right_normal: StyleBoxTexture
@export var right_pressed: StyleBoxTexture
@export var right_hovered: StyleBoxTexture
@export var right_selected: StyleBoxTexture
@export var right_disabled: StyleBoxTexture


func setup(
	level_id: StringName,
	display_name: String,
	panel: LevelPrefPanel,
	initial_state := LevelPrefState.INCLUDED,
	thumbnail: Texture2D = null,
) -> void:
	_level_id = level_id
	_display_name = display_name
	_panel = panel
	_state = initial_state
	_thumbnail = thumbnail


func _ready() -> void:
	super ()
	# Grow button height by 2 pixels per icon
	# scale unit so the buttons scale with the
	# rest of the UI.
	var extra_height := 2 * G.settings.icon_scale
	for button: Button in [
		%LeftButton, %MiddleButton, %RightButton,
	]:
		button.custom_minimum_size.y += (
			extra_height)
	# Add left-side indent by duplicating
	# styleboxes with extra content margin.
	_focus_style = _focus_style.duplicate()
	_focus_style.content_margin_left = (
		_INDENT_MARGIN)
	_unfocused_style = (
		_unfocused_style.duplicate())
	_unfocused_style.content_margin_left = (
		_INDENT_MARGIN)
	_update_focus_style()
	if _thumbnail != null:
		%Thumbnail.texture = _thumbnail
	else:
		%Thumbnail.visible = false
	_update_button_styles()


func consumes_horizontal_input() -> bool:
	return true


func on_left() -> void:
	# Move toward EXCLUDED (leftward).
	match _state:
		LevelPrefState.PREFERRED:
			set_state(LevelPrefState.INCLUDED)
		LevelPrefState.INCLUDED:
			set_state(LevelPrefState.EXCLUDED)
		LevelPrefState.EXCLUDED:
			pass # Already at leftmost.


func on_right() -> void:
	# Move toward PREFERRED (rightward).
	match _state:
		LevelPrefState.EXCLUDED:
			set_state(LevelPrefState.INCLUDED)
		LevelPrefState.INCLUDED:
			set_state(LevelPrefState.PREFERRED)
		LevelPrefState.PREFERRED:
			pass # Already at rightmost.


## Trigger button (gamepad A / Enter / Space) cycles
## forward — same as Right. Mouse-click on the row
## background is suppressed by the SidePanel because
## consumes_horizontal_input() returns true (the row's
## three sub-buttons handle their own clicks).
func on_trigger() -> void:
	on_right()


func set_state(new_state: LevelPrefState) -> void:
	var old_state := _state
	_state = new_state

	if new_state == LevelPrefState.PREFERRED:
		# Notify panel to enforce heart
		# exclusivity.
		_panel.on_level_preferred(self )

	_update_button_styles()

	if old_state != new_state:
		if is_instance_valid(G.audio):
			G.audio.play_sound("select")
		value_changed.emit()


func get_state() -> LevelPrefState:
	return _state


func get_level_id() -> StringName:
	return _level_id


func _on_left_button_pressed() -> void:
	set_state(LevelPrefState.EXCLUDED)


func _on_middle_button_pressed() -> void:
	set_state(LevelPrefState.INCLUDED)


func _on_right_button_pressed() -> void:
	set_state(LevelPrefState.PREFERRED)


func _update_button_styles() -> void:
	_apply_btn_style(
		%LeftButton, %LeftIconRect,
		left_normal, left_pressed,
		left_hovered, left_selected,
		left_disabled,
		_state == LevelPrefState.EXCLUDED)
	_apply_btn_style(
		%MiddleButton, %MiddleIconRect,
		middle_normal, middle_pressed,
		middle_hovered, middle_selected,
		middle_disabled,
		_state == LevelPrefState.INCLUDED)
	_apply_btn_style(
		%RightButton, %RightIconRect,
		right_normal, right_pressed,
		right_hovered, right_selected,
		right_disabled,
		_state == LevelPrefState.PREFERRED)


func _apply_btn_style(
	button: Button,
	icon_rect: TextureRect,
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

	if icon_rect != null:
		if is_selected:
			icon_rect.modulate = (
				_SELECTED_ICON_COLOR)
		else:
			icon_rect.modulate = Color.WHITE

	button.add_theme_stylebox_override(
		"disabled", disabled_style)
