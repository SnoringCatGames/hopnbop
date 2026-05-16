class_name LanguageOptionRow
extends MenuRow
## A row displaying a single locale option.
## Shows the native language name and a checkmark
## icon indicator for the currently active locale.
## The icon space is always reserved so all row
## text aligns vertically regardless of selection.


@export var _checkmark_icon: Texture2D

var _locale := ""
var _native_name := ""
var _panel: SidePanel
var _is_current := false

@onready var _check_icon: TextureRect = %CheckIcon
@onready var _label: Label = %Label


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
	# Size and pad the icon slot. Always reserve
	# space so text aligns across all rows.
	if _checkmark_icon != null:
		_check_icon.custom_minimum_size = (
			_checkmark_icon.get_size()
			* G.settings.icon_scale)
		_wrap_icon_with_padding(_check_icon)
	# Show checkmark only for the current locale.
	_check_icon.texture = (
		_checkmark_icon if _is_current else null)


func on_trigger() -> void:
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
