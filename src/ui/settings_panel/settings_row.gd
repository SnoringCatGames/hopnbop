class_name SettingsRow
extends PanelContainer
## Base class for rows in the settings panel.
## Each row can be focused and responds to
## left/right input. Shows focus border on
## keyboard focus or mouse hover.


@warning_ignore("unused_signal")
signal value_changed
signal clicked

var _focus_style: StyleBox
var _unfocused_style: StyleBox

var _is_mouse_hovered := false

var is_focused := false:
	set(value):
		is_focused = value
		_update_focus_style()


func _ready() -> void:
	_focus_style = G.settings.focus_border_stylebox
	_unfocused_style = G.settings.unfocused_stylebox
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_update_focus_style()


## Called when the player presses left.
func on_left() -> void:
	pass


## Called when the player presses right.
func on_right() -> void:
	pass


func _on_mouse_entered() -> void:
	_is_mouse_hovered = true
	_update_focus_style()
	_on_hover_changed()


func _on_mouse_exited() -> void:
	_is_mouse_hovered = false
	_update_focus_style()
	_on_hover_changed()


## Override in subclasses for type-specific
## hover effects.
func _on_hover_changed() -> void:
	pass


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if (mb.pressed
				and mb.button_index
				== MOUSE_BUTTON_LEFT):
			accept_event()
			clicked.emit()


func _update_focus_style() -> void:
	if is_focused or _is_mouse_hovered:
		add_theme_stylebox_override(
			"panel", _focus_style)
	else:
		add_theme_stylebox_override(
			"panel", _unfocused_style)


## Configures a TextureRect with the given texture.
## Uses G.settings.icon_scale for sizing, or
## get_icon_display_width() when custom_scale > 0.
func _apply_icon(
	icon_rect: TextureRect,
	texture: Texture2D,
	custom_scale: int = -1,
) -> void:
	if texture != null:
		icon_rect.texture = texture
		if custom_scale > 0:
			var width := (
				G.settings
					.get_icon_display_width())
			icon_rect.custom_minimum_size = (
				Vector2(width, width))
		else:
			icon_rect.custom_minimum_size = (
				texture.get_size()
				* G.settings.icon_scale)
		icon_rect.show()
	else:
		icon_rect.hide()


## Configures a TextureRect as a right-facing
## chevron arrow, flipped for RTL layouts.
func _setup_chevron(rect: TextureRect) -> void:
	rect.texture = G.settings.chevron_icon
	var chevron_size := (
		G.settings.chevron_icon.get_size()
		* G.settings.icon_scale)
	rect.custom_minimum_size = chevron_size
	if is_layout_rtl():
		rect.pivot_offset = chevron_size / 2.0
		rect.scale.x = -1.0


## Duplicates the focus and unfocused styles and
## adds content margins on all sides.
func _apply_content_margin_to_styles(
	margin: float,
) -> void:
	_focus_style = _focus_style.duplicate()
	_focus_style.content_margin_left = margin
	_focus_style.content_margin_right = margin
	_focus_style.content_margin_top = margin
	_focus_style.content_margin_bottom = margin
	_unfocused_style = (
		_unfocused_style.duplicate())
	_unfocused_style.content_margin_left = margin
	_unfocused_style.content_margin_right = margin
	_unfocused_style.content_margin_top = margin
	_unfocused_style.content_margin_bottom = margin
