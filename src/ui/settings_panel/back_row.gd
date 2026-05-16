class_name BackRow
extends MenuRow
## Row at the top of sub-panels. Activating it
## pops the current panel back to its parent.
## The panel's Left input is also routed to pop
## (at the SidePanel level), so this row is
## primarily a clickable / focusable affordance.


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
	_panel.manager.pop_panel()
