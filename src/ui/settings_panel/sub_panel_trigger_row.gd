class_name SubPanelTriggerRow
extends SettingsRow
## A row that opens a sub-panel when activated.
## Displays a label and a ">" arrow indicator.


var _display_name := ""
var _panel_scene: PackedScene
var _panel: SidePanel
var _icon_texture: Texture2D

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label
@onready var _arrow: TextureRect = %Arrow


## Set an icon to display before the label. Call
## before add_child().
func set_icon(tex: Texture2D) -> void:
	_icon_texture = tex


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
	if _icon_texture != null:
		_icon.texture = _icon_texture
		_icon.custom_minimum_size = (
			_icon_texture.get_size()
			* G.settings.icon_scale)
		_icon.show()
	else:
		_icon.hide()
	_setup_chevron(_arrow)


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


func _setup_chevron(rect: TextureRect) -> void:
	rect.texture = G.settings.chevron_icon
	var chevron_size := (
		G.settings.chevron_icon.get_size()
		* G.settings.icon_scale)
	rect.custom_minimum_size = chevron_size
	if is_layout_rtl():
		rect.pivot_offset = chevron_size / 2.0
		rect.scale.x = -1.0
