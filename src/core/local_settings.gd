class_name LocalSettings
extends RefCounted
## Persists local setting overrides to
## user://local_settings.cfg.
##
## Falls back to G.settings resource defaults when
## no override exists. Clears overrides that match
## the resource default to keep the file minimal.


const SETTINGS_PATH := "user://local_settings.cfg"
const SECTION_SETTINGS := "settings"
const SECTION_LEVEL_PREFS := "level_preferences"
const SECTION_APPEARANCE := "appearance"
const SECTION_META := "meta"
const META_KEY_VERSION := "game_version"
const KEY_LOCALE := "locale"
const KEY_ANONYMOUS_HUE := "anonymous_color_hue"

const SUPPORTED_LOCALES: Array[String] = [
	"ar", "zh", "en", "fr", "de", "hi",
	"it", "ja", "ko", "pt", "ru", "es", "th",
]

## Setting keys that can be locally overridden.
const OVERRIDABLE_KEYS: Array[StringName] = [
	&"is_gore_enabled",
	&"are_critters_enabled",
	&"are_cheats_enabled",
	&"full_screen",
	&"mute_music",
	&"mute_sfx",
	&"is_jetpack_enabled",
	&"is_bloodisthickerthanwater_enabled",
	&"is_lordoftheflies_enabled",
	&"is_pogostick_enabled",
	&"is_bunniesinspace_enabled",
	&"is_moregore_enabled",
	&"prefer_offline_mode",
]

var _config := ConfigFile.new()
var _defaults: Settings


func _init(defaults: Settings = null) -> void:
	_defaults = defaults


## Load settings from disk. Logs previous version
## and records current version.
func load_settings() -> void:
	var err := _config.load(SETTINGS_PATH)
	if err == OK:
		var prev_version: String = (
		_config.get_value(
			SECTION_META,
			META_KEY_VERSION,
			"unknown"))
		Netcode.print(
			"LocalSettings loaded"
			+ " (prev version: %s)" % prev_version,
			NetworkLogger
				.CATEGORY_SYSTEM_INITIALIZATION,
		)
	else:
		Netcode.print(
			"LocalSettings: No saved settings"
			+ " found, using defaults",
			NetworkLogger
				.CATEGORY_SYSTEM_INITIALIZATION,
		)

	# Record current version.
	var current_version: String = (
		ProjectSettings.get_setting(
			"application/config/version", "0.0.0"))
	_config.set_value(
		SECTION_META,
		META_KEY_VERSION,
		current_version)
	save_settings()


## Write settings to disk.
func save_settings() -> void:
	var err := _config.save(SETTINGS_PATH)
	if err != OK:
		push_warning(
			"LocalSettings: Failed to save"
			+ " (error %d)" % err)


## Store a setting override. If the value matches
## the resource default, the override is cleared
## instead.
func set_override(
	key: StringName, value: Variant,
) -> void:
	var default_value: Variant = _defaults.get(key)
	if (typeof(value) == typeof(default_value)
			and value == default_value):
		# Matches default. Clear override.
		if _config.has_section_key(
				SECTION_SETTINGS, key):
			_config.erase_section_key(
				SECTION_SETTINGS, key)
	else:
		_config.set_value(
			SECTION_SETTINGS, key, value)

	# Apply to runtime settings immediately.
	_defaults.set(key, value)


## Get the effective value for a setting key.
## Returns the override if one exists, otherwise
## returns the resource default.
func get_value(key: StringName) -> Variant:
	if _config.has_section_key(
			SECTION_SETTINGS, key):
		return _config.get_value(
			SECTION_SETTINGS, key)
	return _defaults.get(key)


## Check if an override exists for a key.
func has_override(key: StringName) -> bool:
	return _config.has_section_key(
		SECTION_SETTINGS, key)


## Remove an override for a key.
func clear_override(key: StringName) -> void:
	if _config.has_section_key(
			SECTION_SETTINGS, key):
		_config.erase_section_key(
			SECTION_SETTINGS, key)


## Apply all stored overrides to G.settings.
func apply_all_overrides() -> void:
	for key in OVERRIDABLE_KEYS:
		if _config.has_section_key(
				SECTION_SETTINGS, key):
			var value: Variant = (
				_config.get_value(
					SECTION_SETTINGS, key))
			_defaults.set(key, value)


## Get the stored locale, or detect from OS.
func get_locale() -> String:
	if _config.has_section_key(
			SECTION_SETTINGS, KEY_LOCALE):
		var stored: String = _config.get_value(
			SECTION_SETTINGS, KEY_LOCALE)
		if stored in SUPPORTED_LOCALES:
			return stored
	# Auto-detect from OS.
	var os_lang := OS.get_locale_language()
	if os_lang in SUPPORTED_LOCALES:
		return os_lang
	return "en"


## Set the locale and persist it.
func set_locale(locale: String) -> void:
	if locale not in SUPPORTED_LOCALES:
		locale = "en"
	_config.set_value(
		SECTION_SETTINGS, KEY_LOCALE, locale)
	TranslationServer.set_locale(locale)
	LocalizedNameConfig.clear_cache()
	save_settings()

	# Refresh overhead labels so names update.
	if (is_instance_valid(G.player_overhead_labels)
			and G.player_overhead_labels
				.has_method("refresh_label_text")):
		G.player_overhead_labels.refresh_label_text()

	# Force layout refresh after locale change.
	# Switching between LTR and RTL can leave the
	# renderer in a stale state. A 1px window
	# resize triggers a full layout recalculation.
	var window := G.get_window()
	if window:
		var size := window.size
		window.size = size + Vector2i(1, 0)
		window.size = size


## Apply the stored locale to TranslationServer.
func apply_locale() -> void:
	var locale := get_locale()
	TranslationServer.set_locale(locale)


## Save level preferences to local storage.
func save_level_preferences(
	prefs: LevelPreferences,
) -> void:
	var data := prefs.to_dict()
	_config.set_value(
		SECTION_LEVEL_PREFS,
		"inclusion",
		data.get("inclusion", []))
	_config.set_value(
		SECTION_LEVEL_PREFS,
		"exclusion",
		data.get("exclusion", []))
	_config.set_value(
		SECTION_LEVEL_PREFS,
		"preferred",
		data.get("preferred", ""))
	save_settings()


## Load level preferences from local storage.
## Returns null if no preferences are stored.
func load_level_preferences() -> LevelPreferences:
	if not _config.has_section(SECTION_LEVEL_PREFS):
		return null

	var data := {}
	if _config.has_section_key(
			SECTION_LEVEL_PREFS, "inclusion"):
		data["inclusion"] = _config.get_value(
			SECTION_LEVEL_PREFS, "inclusion")
	if _config.has_section_key(
			SECTION_LEVEL_PREFS, "exclusion"):
		data["exclusion"] = _config.get_value(
			SECTION_LEVEL_PREFS, "exclusion")
	if _config.has_section_key(
			SECTION_LEVEL_PREFS, "preferred"):
		data["preferred"] = _config.get_value(
			SECTION_LEVEL_PREFS, "preferred")

	if data.is_empty():
		return null

	return LevelPreferences.from_dict(data)


## Get the persisted anonymous color hue for this
## client. Generates and saves a random hue on
## first access.
func get_anonymous_color_hue() -> float:
	if _config.has_section_key(
			SECTION_APPEARANCE,
			KEY_ANONYMOUS_HUE):
		return _config.get_value(
			SECTION_APPEARANCE,
			KEY_ANONYMOUS_HUE)
	# Generate and persist on first access.
	var hue := randf()
	_config.set_value(
		SECTION_APPEARANCE,
		KEY_ANONYMOUS_HUE,
		hue)
	save_settings()
	return hue


## Clear all local user state. Called on logout
## so the next session starts clean.
func clear_user_state() -> void:
	if _config.has_section(SECTION_SETTINGS):
		_config.erase_section(SECTION_SETTINGS)
	if _config.has_section(SECTION_LEVEL_PREFS):
		_config.erase_section(SECTION_LEVEL_PREFS)
	_config.erase_section_key(
		SECTION_META, "cloud_sync_at")
	_config.erase_section_key(
		SECTION_META, "rounds_played")
	save_settings()


## Get the number of rounds played locally.
func get_rounds_played() -> int:
	return _config.get_value(
		SECTION_META, "rounds_played", 0)


## Increment the local rounds played counter.
func increment_rounds_played() -> void:
	var current := get_rounds_played()
	_config.set_value(
		SECTION_META, "rounds_played",
		current + 1)
	save_settings()
