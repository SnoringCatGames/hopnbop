class_name LanguageOptionRow
extends SettingsRow
## A row displaying a single locale option.
## Shows the native language name and a checkmark
## indicator for the currently active locale.


var _locale := ""
var _native_name := ""
var _panel: SidePanel
var _is_current := false

@onready var _label: Label = %Label
@onready var _check_label: Label = %CheckLabel


func setup(
	locale: String,
	native_name: String,
	is_current: bool,
	panel: SidePanel,
) -> void:
	_locale = locale
	_native_name = native_name
	_is_current = is_current
	_panel = panel


func _ready() -> void:
	super()
	_label.text = _native_name
	if _is_current:
		_check_label.text = "✓"
	else:
		_check_label.text = ""


func on_left() -> void:
	_select()


func on_right() -> void:
	_select()


func _select() -> void:
	G.local_settings.set_locale(_locale)

	if is_instance_valid(G.audio):
		G.audio.play_sound("select")

	# Close the entire settings menu so all
	# labels rebuild with the new locale.
	if (is_instance_valid(_panel)
			and is_instance_valid(_panel.manager)):
		_panel.manager.close_all()
