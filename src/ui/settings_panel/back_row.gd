class_name BackRow
extends SettingsRow
## Row at the top of sub-panels. Pressing left
## or right pops the current panel, returning
## to the previous one.


var _panel: SidePanel

@onready var _icon: TextureRect = %Icon


func setup(panel: SidePanel) -> void:
	_panel = panel


func _ready() -> void:
	super()
	# Scale icon 2x.
	if _icon.texture != null:
		_icon.custom_minimum_size = (
			_icon.texture.get_size() * 2)
	# Add 8px content margin.
	_focus_style = _focus_style.duplicate()
	_focus_style.content_margin_left = 10
	_focus_style.content_margin_right = 10
	_focus_style.content_margin_top = 10
	_focus_style.content_margin_bottom = 10
	_unfocused_style = (
		_unfocused_style.duplicate())
	_unfocused_style.content_margin_left = 10
	_unfocused_style.content_margin_right = 10
	_unfocused_style.content_margin_top = 10
	_unfocused_style.content_margin_bottom = 10
	_update_focus_style()


func on_left() -> void:
	_panel.manager.pop_panel()


func on_right() -> void:
	_panel.manager.pop_panel()
