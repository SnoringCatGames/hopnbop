class_name ActionRow
extends SettingsRow
## A row that delegates left and right actions
## to callables. Built programmatically without
## a scene file. Used for dynamically generated
## interactive rows in side panels.
##
## Call setup_label() to get a standard icon +
## label layout. Uses the same TextureRect +
## _apply_icon() sizing path as SubPanelTriggerRow
## so icons and padding are consistent.


var _on_left_action: Callable
var _on_right_action: Callable

var disabled := false:
	set(value):
		disabled = value
		modulate.a = 0.4 if disabled else 1.0


func setup_actions(
	on_right_action: Callable = Callable(),
	on_left_action: Callable = Callable(),
) -> void:
	_on_right_action = on_right_action
	_on_left_action = on_left_action


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


func on_left() -> void:
	if disabled:
		return
	if _on_left_action.is_valid():
		_on_left_action.call()


func on_right() -> void:
	if disabled:
		return
	if _on_right_action.is_valid():
		_on_right_action.call()
