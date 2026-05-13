class_name SettingsCloudSync
extends RefCounted
## Synchronizes local settings overrides to cloud
## storage via Platform.settings.
##
## Stage 3.5 + 6.8: settings split into two cloud rows.
##   "global"          → locale + LocalSettings.GLOBAL_OVERRIDABLE_KEYS
##   "game/{game_id}"  → remaining OVERRIDABLE_KEYS (game-specific)
##
## Cloud-wins-by-timestamp merge runs independently per scope using
## Nakama's storage-row update_time. A one-shot legacy migration
## reads the pre-split single-blob row (key="user") on first fetch
## after the upgrade and partitions its contents into the two new
## scopes.


const _META_GLOBAL_SYNC_AT := "cloud_sync_at_global"
const _META_GAME_SYNC_AT := "cloud_sync_at_game"
const _META_LEGACY_MIGRATED := "cloud_legacy_migrated"
const _LEGACY_SCOPE := "user"
const _GLOBAL_SCOPE := "global"


var _client
var _pending_fetch_scopes: Dictionary = {}
var _signals_connected := false


func _init() -> void:
	_client = Platform.settings


func _connect_signals_once() -> void:
	if _signals_connected:
		return
	if _client == null:
		_client = Platform.settings
		if _client == null:
			return
	_client.settings_received.connect(_on_settings_received)
	_client.request_failed.connect(_on_request_failed)
	_signals_connected = true


## Push current local settings to the cloud.
func save_to_cloud() -> void:
	if not Platform.token_store.is_token_valid():
		return
	if Platform.settings == null:
		return
	_connect_signals_once()
	Platform.settings.save(
		_GLOBAL_SCOPE, _serialize_global())
	Platform.settings.save(
		_game_scope(), _serialize_per_game())


## Fetch cloud settings and merge them locally. Cloud wins when
## its update_time is newer than the locally-recorded sync-at
## value for that scope.
func fetch_and_merge_from_cloud() -> void:
	if not Platform.token_store.is_token_valid():
		return
	if Platform.settings == null:
		return
	_connect_signals_once()
	if not _has_legacy_migrated():
		_pending_fetch_scopes[_LEGACY_SCOPE] = true
		Platform.settings.fetch(_LEGACY_SCOPE)
		return
	_pending_fetch_scopes[_GLOBAL_SCOPE] = true
	_pending_fetch_scopes[_game_scope()] = true
	Platform.settings.fetch(_GLOBAL_SCOPE)
	Platform.settings.fetch(_game_scope())


func _on_settings_received(
	scope: String,
	payload: Dictionary,
	updated_at: int,
) -> void:
	if not _pending_fetch_scopes.has(scope):
		return
	_pending_fetch_scopes.erase(scope)

	if scope == _LEGACY_SCOPE:
		_handle_legacy_response(payload, updated_at)
		return

	var local_sync_at: int = _get_sync_at(scope)
	if updated_at > local_sync_at:
		_apply_scope(scope, payload)
		_set_sync_at(scope, updated_at)
	elif updated_at == 0 and local_sync_at == 0:
		# No cloud row exists yet for this scope. Push local.
		_push_scope(scope)


func _on_request_failed(scope: String, _error: String) -> void:
	if not _pending_fetch_scopes.has(scope):
		return
	_pending_fetch_scopes.erase(scope)
	# Soft-fail: leave local overrides as-is. The next save_to_cloud
	# will reconcile if the network comes back.


## One-shot migration from the pre-split single-blob row. Apply
## any legacy values to local overrides, then proceed to the normal
## fetch-merge flow. Cloud-side writing is left to the normal merge
## path so we don't clobber newer partitioned rows another device
## may have already written.
func _handle_legacy_response(
	payload: Dictionary,
	_updated_at: int,
) -> void:
	if not payload.is_empty():
		var partitioned := _partition_legacy(payload)
		_apply_scope(
			_GLOBAL_SCOPE, partitioned[_GLOBAL_SCOPE])
		_apply_scope(_game_scope(), partitioned[_game_scope()])
	_mark_legacy_migrated()
	# Continue with the normal fetch path. If another device has
	# already migrated and pushed newer global / game rows, those
	# will win on update_time. If neither row exists yet (this is
	# the first device to migrate), the empty-cloud-empty-local
	# branch will push our just-applied legacy values to the new
	# rows.
	_pending_fetch_scopes[_GLOBAL_SCOPE] = true
	_pending_fetch_scopes[_game_scope()] = true
	Platform.settings.fetch(_GLOBAL_SCOPE)
	Platform.settings.fetch(_game_scope())


func _partition_legacy(
	payload: Dictionary,
) -> Dictionary:
	var global_part := {}
	var game_part := {}
	for key in payload:
		var string_name := StringName(key)
		if key == "locale":
			global_part[key] = payload[key]
		elif string_name in LocalSettings.GLOBAL_OVERRIDABLE_KEYS:
			global_part[key] = payload[key]
		elif string_name in LocalSettings.OVERRIDABLE_KEYS:
			game_part[key] = payload[key]
		# Unknown keys (e.g. from a future client version) are
		# dropped — they don't fit either bucket and the user-
		# facing surface didn't know about them anyway.
	return {
		_GLOBAL_SCOPE: global_part,
		_game_scope(): game_part,
	}


func _push_scope(scope: String) -> void:
	if scope == _GLOBAL_SCOPE:
		Platform.settings.save(
			_GLOBAL_SCOPE, _serialize_global())
	else:
		Platform.settings.save(
			scope, _serialize_per_game())


func _serialize_global() -> Dictionary:
	var result := {}
	for key in LocalSettings.GLOBAL_OVERRIDABLE_KEYS:
		if G.local_settings.has_override(key):
			result[String(key)] = (
				G.local_settings.get_value(key))
	var locale := G.local_settings.get_locale()
	if locale != "en":
		result["locale"] = locale
	return result


func _serialize_per_game() -> Dictionary:
	var result := {}
	for key in LocalSettings.OVERRIDABLE_KEYS:
		if key in LocalSettings.GLOBAL_OVERRIDABLE_KEYS:
			continue
		if G.local_settings.has_override(key):
			result[String(key)] = (
				G.local_settings.get_value(key))
	return result


func _apply_scope(
	scope: String,
	payload: Dictionary,
) -> void:
	for key in payload:
		var string_name := StringName(key)
		if key == "locale":
			G.local_settings.set_locale(payload[key])
		elif string_name in LocalSettings.OVERRIDABLE_KEYS:
			G.local_settings.set_override(
				string_name, payload[key])
	G.local_settings.save_settings()


func _game_scope() -> String:
	var game_id: String = Platform.game_id
	if game_id.is_empty():
		game_id = "unknown"
	return "game/%s" % game_id


func _get_sync_at(scope: String) -> int:
	var meta_key := (
		_META_GLOBAL_SYNC_AT
		if scope == _GLOBAL_SCOPE
		else _META_GAME_SYNC_AT
	)
	return G.local_settings._config.get_value(
		LocalSettings.SECTION_META, meta_key, 0)


func _set_sync_at(scope: String, value: int) -> void:
	var meta_key := (
		_META_GLOBAL_SYNC_AT
		if scope == _GLOBAL_SCOPE
		else _META_GAME_SYNC_AT
	)
	G.local_settings._config.set_value(
		LocalSettings.SECTION_META, meta_key, value)
	G.local_settings.save_settings()


func _has_legacy_migrated() -> bool:
	return G.local_settings._config.get_value(
		LocalSettings.SECTION_META,
		_META_LEGACY_MIGRATED, false)


func _mark_legacy_migrated() -> void:
	G.local_settings._config.set_value(
		LocalSettings.SECTION_META,
		_META_LEGACY_MIGRATED, true)
	G.local_settings.save_settings()
