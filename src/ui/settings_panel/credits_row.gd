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


func setup(
	display_name: String,
	panel: SidePanel,
) -> void:
	_display_name = display_name
	_panel = panel


func _ready() -> void:
	super()
	_label.text = _display_name
	_apply_icon(_icon, _icon_texture)
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
