class_name MenuRow
extends PanelContainer
## Focusable, triggerable row widget. Used in both
## SidePanel rows and Screen buttons.
##
## Input contract (driven by SidePanel._process and the
## ScreenFocusNavigator polling loop):
##
##   - Trigger button + Right input: `on_trigger()` fires.
##   - Left input: NOT routed to this row — instead routed
##     by the panel/screen as a "back" action. Exception:
##     rows whose Left and Right have distinct semantics
##     override `consumes_horizontal_input()` to return
##     true, in which case the panel/screen calls
##     `on_left()` / `on_right()` directly.
##   - Mouse click: `on_trigger()` fires.
##
## The base class fires the `triggered` signal on
## `on_trigger()` and on mouse-click; subclasses can either
## override `on_trigger()` or connect to the signal.
##
## Visual chrome:
##   - Left-side icon: configurable via `set_icon(tex)`
##     pattern in subclasses; uses `_apply_icon()` helper.
##   - Right-side chevron: configurable via `show_chevron`.
##     Subclasses that have a child `TextureRect` with the
##     unique name `%Chevron` will see it shown/hidden
##     based on the flag. Subclasses without a chevron
##     node just leave the flag at its default (false).


@warning_ignore("unused_signal")
signal value_changed
signal triggered

var _focus_style: StyleBox
var _unfocused_style: StyleBox

var _is_mouse_hovered := false

var is_focused := false:
	set(value):
		is_focused = value
		_update_focus_style()

## When true, a child TextureRect with unique name
## `%Chevron` (if present) is shown; otherwise hidden.
## Subclasses that navigate forward (SubPanelTriggerRow,
## ScreenTriggerRow, CreditsRow) set this to true in
## their `_ready()`. Programmatic callers (e.g.,
## ActionRow instances used as sub-panel triggers in
## party_lobby_panel.gd) can set it per-instance.
var show_chevron := false:
	set(value):
		show_chevron = value
		_apply_chevron_visibility()


func _ready() -> void:
	_focus_style = G.settings.focus_border_stylebox
	_unfocused_style = G.settings.unfocused_stylebox
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_update_focus_style()
	_apply_chevron_visibility()


## Override in subclasses whose Left and Right have
## distinct semantics. Defaults to false. When false, the
## panel/screen routes Left to its back action and Right
## to `on_trigger()`. When true, the panel/screen calls
## `on_left()` / `on_right()` directly and Trigger still
## calls `on_trigger()` (which subclasses typically alias
## to the Right behavior for keyboard-trigger parity).
func consumes_horizontal_input() -> bool:
	return false


## Universal action method. Fired by Right input, Trigger
## input, and mouse-click. Subclasses override to perform
## their primary action.
func on_trigger() -> void:
	pass


## Used by horizontal-selector subclasses
## (LevelPrefRow, BinaryToggle). Default no-op.
func on_left() -> void:
	pass


## Used by horizontal-selector subclasses
## (LevelPrefRow, BinaryToggle). Default no-op.
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
			triggered.emit()
			# Horizontal-selector rows have their own
			# sub-button click handlers (e.g., the three
			# X / check / heart buttons of LevelPrefRow,
			# the two side-by-side buttons of
			# BinaryToggle). Clicking the row background
			# itself should only set focus, not cycle the
			# state — the sub-buttons own activation.
			if not consumes_horizontal_input():
				on_trigger()


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


## Toggle the chevron node's visibility based on the
## `show_chevron` flag. Subclasses opt in by declaring
## a child TextureRect with unique name `%Chevron`.
## No-op when no chevron node is present.
func _apply_chevron_visibility() -> void:
	if not is_inside_tree():
		return
	if not has_node("%Chevron"):
		return
	var chevron := get_node("%Chevron") as TextureRect
	if is_instance_valid(chevron):
		chevron.visible = show_chevron


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
