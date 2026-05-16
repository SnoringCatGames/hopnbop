class_name ActionRow
extends MenuRow
## A row that delegates its primary action to a
## single Callable. Built programmatically without a
## scene file. Used for dynamically generated
## interactive rows in side panels (friend rows,
## party-member rows, blocked-user rows, etc.).
##
## Call setup_label() to get a standard icon +
## label layout. Uses the same TextureRect +
## _apply_icon() sizing path as SubPanelTriggerRow
## so icons and padding are consistent.


var _callback: Callable

var disabled := false:
	set(value):
		disabled = value
		modulate.a = 0.4 if disabled else 1.0


## Set the action to fire on `on_trigger()` (Right
## input, gamepad trigger, Enter/Space, mouse-click).
func setup_action(callback: Callable) -> void:
	_callback = callback


## Builds a standard HBoxContainer with an
## optional icon TextureRect and a label. Sizing
## matches SubPanelTriggerRow: icon_scale for the
## TextureRect minimum size, icon_padding margin
## wrap via _apply_icon().
func setup_label(
	text: String,
	icon: Texture2D = null,
) -> void:
	var container := HBoxContainer.new()
	container.add_theme_constant_override(
		"separation", 8)
	container.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	add_child(container)

	if icon != null:
		var icon_rect := TextureRect.new()
		icon_rect.expand_mode = (
			TextureRect.EXPAND_IGNORE_SIZE)
		icon_rect.stretch_mode = (
			TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		icon_rect.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE)
		icon_rect.visible = false
		container.add_child(icon_rect)
		_apply_icon(icon_rect, icon)

	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	container.add_child(label)


func on_trigger() -> void:
	if disabled:
		return
	if _callback.is_valid():
		_callback.call()
