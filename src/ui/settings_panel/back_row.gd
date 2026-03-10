class_name BackRow
extends SettingsRow
## Row at the top of sub-pages. Pressing left or
## right pops the current page, returning to the
## previous panel.


var _page: SidePanelPage

@onready var _icon: TextureRect = %Icon


func setup(page: SidePanelPage) -> void:
	_page = page


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
	_page.manager.pop_page()


func on_right() -> void:
	_page.manager.pop_page()
