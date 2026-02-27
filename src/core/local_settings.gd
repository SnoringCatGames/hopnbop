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
const SECTION_META := "meta"
const META_KEY_VERSION := "game_version"

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
		var prev_version: String = \
			_config.get_value(
				SECTION_META,
				META_KEY_VERSION,
				"unknown")
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
	var current_version: String = \
		ProjectSettings.get_setting(
			"application/config/version", "0.0.0")
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
	var default_value: Variant = \
		_defaults.get(key)
	if typeof(value) == typeof(default_value) \
			and value == default_value:
		# Matches default — clear override.
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
			var value: Variant = \
				_config.get_value(
					SECTION_SETTINGS, key)
			_defaults.set(key, value)


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
func load_level_preferences() \
		-> LevelPreferences:
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
