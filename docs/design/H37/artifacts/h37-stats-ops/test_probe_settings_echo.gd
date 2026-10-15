extends GutTest
## H37 probe (h37-stats-ops): a cloud fetch that echoes the device's
## own saved values. Does the local override survive a restart?


const _SCOPE := "game/hopnbop"

var _sync: SettingsCloudSync
var _snapshot := {}
var _override_snapshot := {}
var _game_id_snapshot := ""


func before_each() -> void:
	_snapshot = {}
	_override_snapshot = {}
	for key in LocalSettings.OVERRIDABLE_KEYS:
		_snapshot[key] = G.settings.get(key)
		if G.local_settings.has_override(key):
			_override_snapshot[key] = G.local_settings.get_value(key)
		G.local_settings.clear_override(key)
		G.settings.set(key, Settings.new().get(key))
	_game_id_snapshot = Platform.game_id
	Platform.game_id = "hopnbop"
	_sync = SettingsCloudSync.new()


func after_each() -> void:
	for key in LocalSettings.OVERRIDABLE_KEYS:
		if _override_snapshot.has(key):
			G.local_settings.set_override(key, _override_snapshot[key])
		else:
			G.local_settings.clear_override(key)
		G.settings.set(key, _snapshot[key])
	G.local_settings.save_settings()
	Platform.game_id = _game_id_snapshot


func test_boot_then_cloud_echo_keeps_the_override() -> void:
	# Session N: the player turns gore on (default off) and closes
	# Settings; the override is written to local_settings.cfg.
	G.local_settings.set_override(&"is_gore_enabled", true)
	G.local_settings.save_settings()
	# Session N+1 boot: global.gd:341-343 builds LocalSettings over a
	# fresh Settings and applies the stored overrides.
	var boot_settings := Settings.new()
	var boot := LocalSettings.new(boot_settings)
	boot.load_settings()
	boot.apply_all_overrides()
	assert_true(boot.has_override(&"is_gore_enabled"), "stored")
	assert_true(boot_settings.is_gore_enabled, "applied at boot")
	# Auth completes; the fetch returns the row this device saved in
	# session N, whose update_time is newer than the stored sync-at.
	var saved_g := G.local_settings
	G.local_settings = boot
	_sync._set_sync_at(_SCOPE, 100)
	_sync._pending_fetch_scopes[_SCOPE] = true
	_sync._on_settings_received(_SCOPE, {"is_gore_enabled": true}, 200)
	var kept := boot.has_override(&"is_gore_enabled")
	G.local_settings = saved_g
	assert_true(kept, "override survives the cloud echo")
	# Session N+2 boot.
	var next_settings := Settings.new()
	var next := LocalSettings.new(next_settings)
	next.load_settings()
	next.apply_all_overrides()
	assert_true(next_settings.is_gore_enabled, "gore still on after restart")
