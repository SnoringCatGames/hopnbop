class_name DeleteAccountRow
extends MenuRow
## A row that opens a dedicated confirmation sub-panel for
## account deletion. The sub-panel handles the grace-period
## messaging and the type-the-word verification step; this row
## just routes there. The previous in-row delete flow (single
## ConfirmOverlay → RPC → toast) was insufficient for
## app-store deletion-confirmation expectations.


@export var _confirm_panel_scene: PackedScene

var _panel: SidePanel
var _icon_texture: Texture2D

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label


## Set an icon to display before the label. Call
## before add_child().
func set_icon(tex: Texture2D) -> void:
	_icon_texture = tex


func setup(panel: SidePanel) -> void:
	_panel = panel


func _ready() -> void:
	super()
	_label.text = tr("SETTINGS.DELETE_ACCOUNT")
	_apply_icon(_icon, _icon_texture)


func on_trigger() -> void:
	_activate()


func _activate() -> void:
	if not is_instance_valid(_panel):
		return
	if _confirm_panel_scene == null:
		return
	if not is_instance_valid(_panel.manager):
		return
	_panel.manager.push_panel(
		_confirm_panel_scene.instantiate())
