class_name SubPanelTriggerRow
extends SettingsRow
## A row that opens a sub-panel when activated.
## Displays a label and a ">" arrow indicator.


var _display_name := ""
var _page_scene: PackedScene
var _page: SidePanelPage

@onready var _label: Label = %Label
@onready var _arrow_label: Label = %ArrowLabel


func setup(
	display_name: String,
	page_scene: PackedScene,
	page: SidePanelPage,
) -> void:
	_display_name = display_name
	_page_scene = page_scene
	_page = page


func _ready() -> void:
	super()
	_label.text = _display_name
	if is_layout_rtl():
		_arrow_label.text = "<"
	else:
		_arrow_label.text = ">"


func on_left() -> void:
	_open_sub_panel()


func on_right() -> void:
	_open_sub_panel()


func _open_sub_panel() -> void:
	if _page_scene == null:
		return
	if not is_instance_valid(_page):
		return
	if not is_instance_valid(_page.manager):
		return
	var new_page: SidePanelPage = (
		_page_scene.instantiate())
	_page.manager.push_page(new_page)
