class_name Screen
extends PlatformScreen
## Game-side base class for full-screen UI screens.
##
## Thin subclass of PlatformScreen that adds hopnbop's
## server-side disable guard and applies the game's
## default theme + screen stylebox.


func _enter_tree() -> void:
	if Netcode.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	super._enter_tree()


func _set_default_styling() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = G.settings.default_theme
	add_theme_stylebox_override(
		"panel", G.settings.screen_style_box)
