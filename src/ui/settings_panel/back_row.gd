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
		_wrap_icon_with_padding(_icon)
	_apply_content_margin_to_styles(10)
	_update_focus_style()


func on_left() -> void:
	_panel.manager.pop_panel()


func on_right() -> void:
	_panel.manager.pop_panel()
