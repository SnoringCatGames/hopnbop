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
## Wraps in a MarginContainer to apply icon_padding.
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
		_wrap_icon_with_padding(icon_rect)
		icon_rect.show()
	else:
		icon_rect.hide()


## Configures a TextureRect as a right-facing
## chevron arrow, flipped for RTL layouts.
## Wraps in a MarginContainer to apply icon_padding.
func _setup_chevron(rect: TextureRect) -> void:
	rect.texture = G.settings.chevron_icon
	var icon_size := (
		G.settings.chevron_icon.get_size()
		* G.settings.icon_scale)
	rect.custom_minimum_size = icon_size
	_wrap_icon_with_padding(rect)
	if is_layout_rtl():
		rect.pivot_offset = icon_size / 2.0
		rect.scale.x = -1.0


## Wraps icon_rect in a MarginContainer if not already
## wrapped, and applies G.settings.icon_padding on all
## sides. Does nothing when icon_padding is zero.
func _wrap_icon_with_padding(
	icon_rect: TextureRect,
) -> void:
	var pad := G.settings.icon_padding
	if pad <= 0:
		return
	var parent := icon_rect.get_parent()
	var mc: MarginContainer
	if parent is MarginContainer:
		mc = parent as MarginContainer
	else:
		mc = MarginContainer.new()
		mc.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE)
		parent.add_child(mc)
		parent.move_child(
			mc, icon_rect.get_index())
		icon_rect.reparent(mc)
	mc.add_theme_constant_override(
		"margin_left", pad)
	mc.add_theme_constant_override(
		"margin_right", pad)
	mc.add_theme_constant_override(
		"margin_top", pad)
	mc.add_theme_constant_override(
		"margin_bottom", pad)


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
