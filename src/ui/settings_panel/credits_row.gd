class_name CreditsRow
extends SettingsRow
## A row that opens the credits overlay.
## Closes the settings menu before showing
## the overlay.


@export var _credits_overlay_scene: PackedScene

var _panel: SidePanel
var _display_name := ""
var _icon_texture: Texture2D

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label
@onready var _arrow: TextureRect = %Arrow


## Set an icon to display before the label. Call
## before add_child().
func set_icon(tex: Texture2D) -> void:
	_icon_texture = tex


static func new_row(
	display_name: String,
	panel: SidePanel,
	icon: Texture2D = null,
) -> CreditsRow:
	var scene := preload(
		"res://src/ui/settings_panel/"
		+ "credits_row.tscn")
	var row: CreditsRow = scene.instantiate()
	row._display_name = display_name
	row._panel = panel
	if icon != null:
		row.set_icon(icon)
	return row


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
	_open_credits()


func on_right() -> void:
	_open_credits()


func _open_credits() -> void:
	if not is_instance_valid(_panel):
		return
	if not is_instance_valid(_panel.manager):
		return

	# Add the overlay to the tree root.
	# queue_free from close_all is deferred, so
	# the tree root is still accessible.
	var root := get_tree().root
	var overlay: CreditsOverlay = (
		_credits_overlay_scene.instantiate())
	root.add_child(overlay)

	# Close settings menu.
	_panel.manager.close_all()


func _setup_chevron(rect: TextureRect) -> void:
	rect.texture = G.settings.chevron_icon
	var chevron_size := (
		G.settings.chevron_icon.get_size()
		* G.settings.icon_scale)
	rect.custom_minimum_size = chevron_size
	if is_layout_rtl():
		rect.pivot_offset = chevron_size / 2.0
		rect.scale.x = -1.0
