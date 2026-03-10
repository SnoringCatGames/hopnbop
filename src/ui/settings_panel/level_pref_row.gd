class_name LevelPrefRow
extends SettingsRow
## Row showing a level name and tri-toggle
## aggregate button (X / checkmark / heart).


enum LevelPrefState {
	EXCLUDED, # X. Left button.
	INCLUDED, # Checkmark. Middle button.
	PREFERRED, # Heart. Right button.
}

const _SELECTED_ICON_COLOR := (
	Color(0.9, 0.9, 0.9))
const _VBAR_MODULATE := Color(1, 1, 1, 0.3)
@export var _vbar_texture: Texture2D

var _level_id: StringName
var _display_name: String
var _state := LevelPrefState.INCLUDED
var _panel: LevelPrefPage
var _thumbnail: Texture2D
var _left_icon_rect: TextureRect
var _middle_icon_rect: TextureRect
var _right_icon_rect: TextureRect

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
	panel: LevelPrefPage,
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
	# Add left-side indent by duplicating
	# styleboxes with extra content margin.
	_focus_style = _focus_style.duplicate()
	_focus_style.content_margin_left = 10
	_unfocused_style = (
		_unfocused_style.duplicate())
	_unfocused_style.content_margin_left = 10
	_update_focus_style()
	# Replace built-in button icons with
	# TextureRects for uniform scaling.
	_left_icon_rect = (
		_replace_btn_icon(%LeftBtn))
	_right_icon_rect = (
		_replace_btn_icon(%RightBtn))
	# Middle button also gets v-bar separators
	# flanking its icon.
	var middle_tex: Texture2D = %MiddleBtn.icon
	%MiddleBtn.icon = null
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override(
		"separation", 0)
	hbox.set_anchors_preset(
		Control.PRESET_FULL_RECT)
	hbox.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	hbox.add_child(_create_vbar())
	_middle_icon_rect = TextureRect.new()
	_middle_icon_rect.texture = middle_tex
	_middle_icon_rect.stretch_mode = (
		TextureRect
			.STRETCH_KEEP_ASPECT_CENTERED)
	_middle_icon_rect.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	_middle_icon_rect.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	hbox.add_child(_middle_icon_rect)
	hbox.add_child(_create_vbar())
	%MiddleBtn.add_child(hbox)
	if _thumbnail != null:
		%Thumbnail.texture = _thumbnail
	else:
		%Thumbnail.visible = false
	_update_button_styles()


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


func _on_left_btn_pressed() -> void:
	set_state(LevelPrefState.EXCLUDED)


func _on_middle_btn_pressed() -> void:
	set_state(LevelPrefState.INCLUDED)


func _on_right_btn_pressed() -> void:
	set_state(LevelPrefState.PREFERRED)


func _update_button_styles() -> void:
	_apply_btn_style(
		%LeftBtn, _left_icon_rect,
		left_normal, left_pressed,
		left_hovered, left_selected,
		left_disabled,
		_state == LevelPrefState.EXCLUDED)
	_apply_btn_style(
		%MiddleBtn, _middle_icon_rect,
		middle_normal, middle_pressed,
		middle_hovered, middle_selected,
		middle_disabled,
		_state == LevelPrefState.INCLUDED)
	_apply_btn_style(
		%RightBtn, _right_icon_rect,
		right_normal, right_pressed,
		right_hovered, right_selected,
		right_disabled,
		_state == LevelPrefState.PREFERRED)


func _create_vbar() -> TextureRect:
	var vbar := TextureRect.new()
	vbar.texture = _vbar_texture
	vbar.custom_minimum_size = (
		_vbar_texture.get_size() * 2)
	vbar.stretch_mode = (
		TextureRect
			.STRETCH_KEEP_ASPECT_CENTERED)
	vbar.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL)
	vbar.modulate = _VBAR_MODULATE
	vbar.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	return vbar


func _replace_btn_icon(
	btn: Button,
) -> TextureRect:
	var tex: Texture2D = btn.icon
	btn.icon = null
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = (
		TextureRect
			.STRETCH_KEEP_ASPECT_CENTERED)
	rect.set_anchors_preset(
		Control.PRESET_FULL_RECT)
	rect.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	btn.add_child(rect)
	return rect


func _apply_btn_style(
	btn: Button,
	icon_rect: TextureRect,
	normal_style: StyleBoxTexture,
	pressed_style: StyleBoxTexture,
	hover_style: StyleBoxTexture,
	selected_style: StyleBoxTexture,
	disabled_style: StyleBoxTexture,
	is_selected: bool,
) -> void:
	if is_selected:
		btn.add_theme_stylebox_override(
			"normal", selected_style)
		btn.add_theme_stylebox_override(
			"hover", selected_style)
		btn.add_theme_stylebox_override(
			"pressed", selected_style)
	else:
		btn.add_theme_stylebox_override(
			"normal", normal_style)
		btn.add_theme_stylebox_override(
			"hover", hover_style)
		btn.add_theme_stylebox_override(
			"pressed", pressed_style)

	if icon_rect != null:
		if is_selected:
			icon_rect.modulate = (
				_SELECTED_ICON_COLOR)
		else:
			icon_rect.modulate = Color.WHITE

	btn.add_theme_stylebox_override(
		"disabled", disabled_style)
