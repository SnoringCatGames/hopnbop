extends GutTest
## Unit tests for SettingsCloudSync pure-logic helpers.
##
## Stage 3.5 + 6.8: settings split into two cloud rows
## ("global" + "game/{game_id}"). The merge-from-cloud path
## is HTTP-driven and exercised live by the compliance suite
## (test_settings.gd). These tests cover the deterministic
## partitioning + serialize + scope helpers that decide which
## key belongs to which cloud row.


var _sync: SettingsCloudSync
# Snapshot the override-state + the runtime Settings values for
# every key the tests may touch. LocalSettings.set_override mutates
# G.settings.<key> even when called with the default value, so a
# test that flips a key to non-default and back must also restore
# the runtime Settings value to keep subsequent tests' "default"
# comparisons valid.
var _override_snapshot: Dictionary
var _settings_snapshot: Dictionary
var _platform_game_id_snap: String


func before_each() -> void:
	_override_snapshot = {}
	_settings_snapshot = {}
	for key in LocalSettings.OVERRIDABLE_KEYS:
		_settings_snapshot[key] = G.settings.get(key)
		if G.local_settings.has_override(key):
			_override_snapshot[key] = (
				G.local_settings.get_value(key))
		G.local_settings.clear_override(key)
		# Force G.settings.<key> back to the resource default so
		# set_override's "matches default → clear" branch works
		# from the same baseline every test.
		var resource_default: Variant = Settings.new().get(key)
		G.settings.set(key, resource_default)

	_platform_game_id_snap = Platform.game_id
	Platform.game_id = "hopnbop"
	_sync = SettingsCloudSync.new()


func after_each() -> void:
	for key in LocalSettings.OVERRIDABLE_KEYS:
		if _override_snapshot.has(key):
			G.local_settings.set_override(
				key, _override_snapshot[key])
		else:
			G.local_settings.clear_override(key)
		G.settings.set(key, _settings_snapshot[key])
	Platform.game_id = _platform_game_id_snap


# ------------------------------------------------------------------
# _game_scope
# ------------------------------------------------------------------


func test_game_scope_prefixes_game_id() -> void:
	Platform.game_id = "hopnbop"
	assert_eq(_sync._game_scope(), "game/hopnbop")


func test_game_scope_falls_back_when_empty() -> void:
	# Empty Platform.game_id shouldn't yield "game/" — a bad row
	# key would either silently store nothing or collide with the
	# real per-game row. Resolver substitutes "unknown".
	Platform.game_id = ""
	assert_eq(_sync._game_scope(), "game/unknown")


# ------------------------------------------------------------------
# _partition_legacy
# ------------------------------------------------------------------


func test_partition_legacy_locale_goes_to_global() -> void:
	var partitioned := _sync._partition_legacy(
		{"locale": "es"})
	assert_eq(
		partitioned["global"], {"locale": "es"})
	assert_eq(partitioned["game/hopnbop"], {})


func test_partition_legacy_global_key_goes_to_global() -> void:
	# full_screen is in GLOBAL_OVERRIDABLE_KEYS.
	var partitioned := _sync._partition_legacy(
		{"full_screen": true})
	assert_eq(
		partitioned["global"], {"full_screen": true})
	assert_eq(partitioned["game/hopnbop"], {})


func test_partition_legacy_game_key_goes_to_game_scope() -> void:
	# is_gore_enabled is in OVERRIDABLE_KEYS but NOT in
	# GLOBAL_OVERRIDABLE_KEYS, so it's game-scoped.
	var partitioned := _sync._partition_legacy(
		{"is_gore_enabled": false})
	assert_eq(partitioned["global"], {})
	assert_eq(
		partitioned["game/hopnbop"],
		{"is_gore_enabled": false})


func test_partition_legacy_mixed_payload_splits_correctly() -> void:
	var partitioned := _sync._partition_legacy({
		"locale": "fr",
		"mute_music": true,
		"is_gore_enabled": false,
		"is_jetpack_enabled": true,
	})
	assert_eq(
		partitioned["global"],
		{"locale": "fr", "mute_music": true})
	assert_eq(
		partitioned["game/hopnbop"],
		{
			"is_gore_enabled": false,
			"is_jetpack_enabled": true,
		})


func test_partition_legacy_unknown_keys_are_dropped() -> void:
	# Keys from a future client version that don't fit either
	# bucket are dropped. They don't crash the migration.
	var partitioned := _sync._partition_legacy({
		"ghost_key_from_the_future": "spooky",
		"full_screen": true,
	})
	assert_eq(
		partitioned["global"], {"full_screen": true})
	assert_eq(partitioned["game/hopnbop"], {})


func test_partition_legacy_empty_input_yields_empty_buckets() -> void:
	var partitioned := _sync._partition_legacy({})
	assert_eq(partitioned["global"], {})
	assert_eq(partitioned["game/hopnbop"], {})


# ------------------------------------------------------------------
# _serialize_global / _serialize_per_game
# ------------------------------------------------------------------


func test_serialize_global_returns_only_global_overrides() -> void:
	# Use values opposite the resource defaults so set_override
	# actually persists (matching-default clears the override).
	G.local_settings.set_override(&"full_screen", true)
	G.local_settings.set_override(&"is_gore_enabled", true)
	var serialized := _sync._serialize_global()
	assert_true(serialized.has("full_screen"))
	assert_false(
		serialized.has("is_gore_enabled"),
		"Game-scoped key must NOT leak into global serialize")


func test_serialize_global_omits_default_locale() -> void:
	# get_locale() returns "en" by default; serialize_global
	# should skip it to avoid round-tripping the default.
	var serialized := _sync._serialize_global()
	assert_false(
		serialized.has("locale"),
		"Default 'en' locale should be omitted")


func test_serialize_per_game_excludes_global_keys() -> void:
	# Use values opposite the resource defaults so set_override
	# actually persists (matching-default clears the override).
	G.local_settings.set_override(&"full_screen", true)
	G.local_settings.set_override(&"is_gore_enabled", true)
	var serialized := _sync._serialize_per_game()
	assert_false(
		serialized.has("full_screen"),
		"Global-scoped key must NOT leak into per-game serialize")
	assert_true(serialized.has("is_gore_enabled"))


func test_serialize_skips_unoverridden_keys() -> void:
	# Cleared by before_each. Both serializers should return {}.
	assert_eq(_sync._serialize_global(), {})
	assert_eq(_sync._serialize_per_game(), {})


# ------------------------------------------------------------------
# _apply_scope
# ------------------------------------------------------------------


func test_apply_scope_writes_known_override_keys() -> void:
	# is_gore_enabled defaults to false; supply true so the
	# override actually persists (matching-default clears).
	_sync._apply_scope(
		"game/hopnbop", {"is_gore_enabled": true})
	assert_true(
		G.local_settings.has_override(&"is_gore_enabled"))
	assert_eq(
		G.local_settings.get_value(&"is_gore_enabled"),
		true)


func test_apply_scope_ignores_unknown_keys() -> void:
	# Future-version key from cloud should not blow up locally
	# (and should NOT round-trip into LocalSettings either).
	_sync._apply_scope(
		"global", {"ghost_from_future": "spooky"})
	# No override should exist for any known key as a result.
	for key in LocalSettings.OVERRIDABLE_KEYS:
		assert_false(
			G.local_settings.has_override(key),
			"No override should be set for known key '%s'"
			% String(key))


# ------------------------------------------------------------------
# _has_legacy_migrated / _mark_legacy_migrated
# ------------------------------------------------------------------


func test_legacy_migration_round_trip() -> void:
	# Snapshot the meta flag so we don't corrupt the user's real
	# settings file.
	var original: bool = G.local_settings._config.get_value(
		LocalSettings.SECTION_META,
		"cloud_legacy_migrated",
		false)

	# Force-clear so we observe the false->true transition.
	G.local_settings._config.set_value(
		LocalSettings.SECTION_META,
		"cloud_legacy_migrated", false)
	assert_false(_sync._has_legacy_migrated())

	_sync._mark_legacy_migrated()
	assert_true(_sync._has_legacy_migrated())

	# Restore.
	G.local_settings._config.set_value(
		LocalSettings.SECTION_META,
		"cloud_legacy_migrated", original)


# ------------------------------------------------------------------
# _get_sync_at / _set_sync_at
# ------------------------------------------------------------------


func test_sync_at_round_trip_per_scope() -> void:
	# Snapshot both meta values.
	var snap_global: int = G.local_settings._config.get_value(
		LocalSettings.SECTION_META,
		"cloud_sync_at_global", 0)
	var snap_game: int = G.local_settings._config.get_value(
		LocalSettings.SECTION_META,
		"cloud_sync_at_game", 0)

	_sync._set_sync_at("global", 12345)
	_sync._set_sync_at("game/hopnbop", 99999)
	assert_eq(_sync._get_sync_at("global"), 12345)
	assert_eq(_sync._get_sync_at("game/hopnbop"), 99999)

	# Restore.
	G.local_settings._config.set_value(
		LocalSettings.SECTION_META,
		"cloud_sync_at_global", snap_global)
	G.local_settings._config.set_value(
		LocalSettings.SECTION_META,
		"cloud_sync_at_game", snap_game)
