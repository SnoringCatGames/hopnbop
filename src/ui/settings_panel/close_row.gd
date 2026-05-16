class_name CloseRow
extends MenuRow
## Special row at the top of the main menu
## panel. Activating it closes the entire side-
## panel stack. (Left input at the SidePanel
## level also closes when the stack is at the
## root via pop_panel's auto-fall-through.)


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


func on_trigger() -> void:
	_panel.manager.close_all()
