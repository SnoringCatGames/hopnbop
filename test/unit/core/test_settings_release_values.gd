extends GutTest
## The release overrides exported builds apply over settings.tres
## (ledger H4). The gated entry point, apply_release_overrides(),
## is editor-aware, so these tests call the value application
## directly and check the gate is a no-op under the editor.


func _duplicated_settings() -> Settings:
	# Duplicate so the shared cached resource G loaded stays
	# untouched for other tests.
	var settings: Settings = load("res://settings.tres").duplicate()
	return settings


func test_release_values_replace_debug_values() -> void:
	var settings := _duplicated_settings()
	settings.match_duration_sec = 10.0
	settings.show_hud = false
	settings.show_player_overhead_labels = false
	settings.skip_splash = true
	settings.is_server_pause_enabled = true

	settings._apply_release_values()

	assert_eq(
		settings.match_duration_sec,
		Settings.RELEASE_MATCH_DURATION_SEC,
		"Release builds run 180 s matches.")
	assert_eq(settings.match_duration_sec, 180.0)
	assert_true(settings.show_hud, "Release builds show the HUD.")
	assert_true(
		settings.show_player_overhead_labels,
		"Release builds show overhead labels.")
	assert_false(settings.skip_splash, "Release builds play the splash.")
	assert_false(
		settings.is_server_pause_enabled,
		"Release builds disable networked pause (H39).")


func test_editor_runs_keep_settings_as_is() -> void:
	# GUT runs under the editor binary, so the gated entry point
	# must change nothing here; previews and the agent harness
	# rely on that.
	var settings := _duplicated_settings()
	settings.match_duration_sec = 10.0
	settings.show_hud = false

	settings.apply_release_overrides()

	assert_eq(settings.match_duration_sec, 10.0)
	assert_false(settings.show_hud)
