class_name SubPanelTriggerRow
extends SettingsRow
## A row that opens a sub-panel when activated.
## Displays a label and a ">" arrow indicator.


var _display_name := ""
var _panel_scene: PackedScene
var _panel: SidePanel

@onready var _label: Label = %Label
@onready var _arrow_label: Label = %ArrowLabel


func setup(
	display_name: String,
	panel_scene: PackedScene,
	panel: SidePanel,
) -> void:
	_display_name = display_name
	_panel_scene = panel_scene
	_panel = panel


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
	if _panel_scene == null:
		return
	if not is_instance_valid(_panel):
		return
	if not is_instance_valid(_panel.manager):
		return
	var new_panel: SidePanel = (
		_panel_scene.instantiate())
	_panel.manager.push_panel(new_panel)
