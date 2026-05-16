class_name CreditsRow
extends MenuRow
## A row that opens the credits screen.
## Closes the settings menu before showing
## the screen.


var _panel: SidePanel
var _display_name := ""
var _icon_texture: Texture2D

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label


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
	# Navigates forward into the Credits screen — show
	# the chevron affordance.
	show_chevron = true


func on_trigger() -> void:
	_open_credits()


func _open_credits() -> void:
	if not is_instance_valid(_panel):
		return
	if not is_instance_valid(_panel.manager):
		return
	G.credits_screen.set_return_screen(
		G.screens.current_screen)
	_panel.manager.close_all()
	G.screens.client_open_screen(
		ScreensMain.ScreenType.CREDITS)
