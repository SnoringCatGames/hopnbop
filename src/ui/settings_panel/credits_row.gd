class_name CreditsRow
extends SettingsRow
## A row that opens the credits overlay.
## Closes the settings menu before showing
## the overlay.


@export var _credits_overlay_scene: PackedScene

var _panel: SidePanel
var _display_name := ""

@onready var _label: Label = %Label
@onready var _arrow_label: Label = %ArrowLabel


static func new_row(
	display_name: String,
	panel: SidePanel,
) -> CreditsRow:
	var scene := preload(
		"res://src/ui/settings_panel/"
		+ "credits_row.tscn")
	var row: CreditsRow = scene.instantiate()
	row._display_name = display_name
	row._panel = panel
	return row


func _ready() -> void:
	super()
	_label.text = _display_name
	if is_layout_rtl():
		_arrow_label.text = "<"
	else:
		_arrow_label.text = ">"


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
