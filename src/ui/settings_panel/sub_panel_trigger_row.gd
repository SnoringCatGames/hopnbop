class_name SubPanelTriggerRow
extends MenuRow
## A row that opens a sub-panel when activated.
## Displays a label and the standard chevron
## affordance.


var _display_name := ""
var _panel_scene: PackedScene
var _panel: SidePanel
var _icon_texture: Texture2D

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label
@onready var _badge: Panel = %Badge


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
	_apply_icon(_icon, _icon_texture)
	# Navigates forward into a sub-panel — show the
	# chevron affordance.
	show_chevron = true
	_badge.visible = false
	_setup_badge_style()


## Show or hide the notification badge dot.
func set_badge_visible(
	is_visible: bool,
) -> void:
	if is_instance_valid(_badge):
		_badge.visible = is_visible


func _setup_badge_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.9, 0.15, 0.15)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	_badge.add_theme_stylebox_override(
		"panel", style)


func on_trigger() -> void:
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
