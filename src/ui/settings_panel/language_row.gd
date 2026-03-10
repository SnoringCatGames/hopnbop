class_name LanguageRow
extends SettingsRow
## A row that cycles through supported languages.
## Displays the language name in its native script.


const _LOCALE_DISPLAY_NAMES := {
	"en": "English",
	"zh": "中文",
	"es": "Español",
	"hi": "हिन्दी",
	"ar": "العربية",
	"fr": "Français",
	"pt": "Português",
	"ru": "Русский",
	"ja": "日本語",
	"de": "Deutsch",
	"ko": "한국어",
	"it": "Italiano",
	"th": "ไทย",
}

var _panel: SettingsPanel
var _current_index := 0

@onready var _label: Label = %Label
@onready var _value_label: Label = %ValueLabel


func setup(panel: SettingsPanel) -> void:
	_panel = panel
	var current_locale := (
		G.local_settings.get_locale())
	var locales := (
		LocalSettings.SUPPORTED_LOCALES)
	_current_index = locales.find(current_locale)
	if _current_index < 0:
		_current_index = 0


func _ready() -> void:
	super()
	_label.text = tr("SETTINGS.LANGUAGE")
	_update_display()


func on_left() -> void:
	_cycle(-1)


func on_right() -> void:
	_cycle(1)


func _cycle(direction: int) -> void:
	var locales := (
		LocalSettings.SUPPORTED_LOCALES)
	_current_index = (
		(_current_index + direction)
		% locales.size())
	if _current_index < 0:
		_current_index += locales.size()

	var new_locale: String = (
		locales[_current_index])
	G.local_settings.set_locale(new_locale)
	_update_display()

	if is_instance_valid(G.audio):
		G.audio.play_sound("select")

	# Rebuild the settings panel so all labels
	# update with the new locale.
	if is_instance_valid(_panel):
		_panel.close()


func _update_display() -> void:
	if not is_instance_valid(_value_label):
		return
	var locales := (
		LocalSettings.SUPPORTED_LOCALES)
	var locale: String = locales[_current_index]
	_value_label.text = (
		_LOCALE_DISPLAY_NAMES.get(
			locale, locale))
