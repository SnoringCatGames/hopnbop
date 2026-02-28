class_name ToggleRow
extends SettingsRow
## A row with a label and custom checkbox toggle.
## Left/right both toggle the value.


var _setting_key: StringName
var _display_name: String
var _value: bool
var _indent_pixels := 0
var _icon_texture: Texture2D

@onready var _checkbox: TextureButton = %Checkbox
@onready var _label: Label = %Label

@export_group("Checked Textures")
@export var tex_normal_checked: Texture2D
@export var tex_hovered_checked: Texture2D
@export var tex_pressed_checked: Texture2D
@export var tex_disabled_checked: Texture2D

@export_group("Unchecked Textures")
@export var tex_normal_unchecked: Texture2D
@export var tex_hovered_unchecked: Texture2D
@export var tex_pressed_unchecked: Texture2D
@export var tex_disabled_unchecked: Texture2D


## Set left indent in pixels. Call before
## add_child().
func set_indent(pixels: int) -> void:
	_indent_pixels = pixels


## Set an icon to display instead of the label.
## Call before add_child().
func set_icon(tex: Texture2D) -> void:
	_icon_texture = tex


func setup(
	display_name: String,
	setting_key: StringName,
) -> void:
	_display_name = display_name
	_setting_key = setting_key
	_value = G.local_settings.get_value(
		setting_key)


func _ready() -> void:
	super()
	if _icon_texture != null:
		_label.hide()
		var icon := TextureRect.new()
		icon.texture = _icon_texture
		icon.custom_minimum_size = \
			_icon_texture.get_size() * 4
		icon.stretch_mode = \
			TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = \
			Control.MOUSE_FILTER_IGNORE
		_checkbox.get_parent() \
			.add_child(icon)
	else:
		_label.text = _display_name
	if _indent_pixels > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size.x = \
			_indent_pixels
		_checkbox.get_parent() \
			.add_child(spacer)
		_checkbox.get_parent() \
			.move_child(spacer, 0)
	# Scale checkbox 2x.
	_checkbox.stretch_mode = \
		TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	if tex_normal_checked != null:
		_checkbox.custom_minimum_size = \
			tex_normal_checked.get_size() * 2
	_update_checkbox_textures()


func on_left() -> void:
	_toggle()


func on_right() -> void:
	_toggle()


func _toggle() -> void:
	_value = not _value
	G.local_settings.set_override(
		_setting_key, _value)
	_apply_side_effect()
	_update_checkbox_textures()
	if is_instance_valid(G.audio):
		G.audio.play_sound("select")
	value_changed.emit()


func _on_hover_changed() -> void:
	_update_checkbox_textures()


func _apply_side_effect() -> void:
	match _setting_key:
		&"mute_music":
			if is_instance_valid(G.audio):
				G.audio.apply_music_mute()
		&"mute_sfx":
			if is_instance_valid(G.audio):
				G.audio.apply_sfx_mute()
		&"full_screen":
			G.window_manager.update_window_mode()


func _update_checkbox_textures() -> void:
	if _value:
		_checkbox.texture_normal = \
			tex_hovered_checked \
			if _is_mouse_hovered \
			else tex_normal_checked
		_checkbox.texture_disabled = \
			tex_disabled_checked
	else:
		_checkbox.texture_normal = \
			tex_hovered_unchecked \
			if _is_mouse_hovered \
			else tex_normal_unchecked
		_checkbox.texture_disabled = \
			tex_disabled_unchecked


## Get the current toggle value.
func get_toggle_value() -> bool:
	return _value
