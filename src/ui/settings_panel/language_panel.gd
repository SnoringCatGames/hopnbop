class_name LanguagePage
extends SidePanelPage
## Language selection sub-panel. Displays one row
## per supported locale with the native name.


@export var _back_row_scene: PackedScene
@export var _language_option_row_scene: PackedScene

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


func build_ui() -> void:
	# Top padding.
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 30)
	_row_container.add_child(top_spacer)

	# Back row.
	var back_row: BackRow = (
		_back_row_scene.instantiate())
	back_row.setup(self)
	_row_container.add_child(back_row)
	_connect_row_clicked(back_row)

	# Spacer below back button.
	var back_spacer := Control.new()
	back_spacer.custom_minimum_size = (
		Vector2(0, 20))
	_row_container.add_child(back_spacer)

	# One row per supported locale.
	var current_locale := (
		G.local_settings.get_locale())
	for locale in LocalSettings.SUPPORTED_LOCALES:
		var native_name: String = (
			_LOCALE_DISPLAY_NAMES.get(
				locale, locale))
		var is_current := locale == current_locale

		var row: LanguageOptionRow = (
			_language_option_row_scene.instantiate())
		row.setup(
			locale, native_name,
			is_current, self)
		_row_container.add_child(row)
		_connect_row_clicked(row)

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(bottom_spacer)
