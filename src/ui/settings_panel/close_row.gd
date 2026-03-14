class_name CloseRow
extends SettingsRow
## Special row at the top of the main menu
## panel. Pressing left or right closes the
## entire side-panel stack.


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
	_apply_content_margin_to_styles(10)
	_update_focus_style()


func on_left() -> void:
	_panel.manager.close_all()


func on_right() -> void:
	_panel.manager.close_all()
