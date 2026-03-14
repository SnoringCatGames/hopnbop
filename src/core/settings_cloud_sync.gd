class_name SettingsCloudSync
extends RefCounted
## Synchronizes local settings overrides to cloud
## storage via the backend API. Uses a "cloud wins"
## merge strategy based on timestamps.


const _META_CLOUD_SYNC_AT := "cloud_sync_at"


## Serialize local settings into a dictionary for
## cloud storage.
func _serialize_local_settings() -> Dictionary:
	var result := {}
	for key in LocalSettings.OVERRIDABLE_KEYS:
		if G.local_settings.has_override(key):
			result[String(key)] = (
				G.local_settings.get_value(key))
	var locale := G.local_settings.get_locale()
	if locale != "en":
		result["locale"] = locale
	return result


## Apply cloud settings to local overrides.
func _apply_cloud_settings(
	settings: Dictionary,
) -> void:
	for key in settings:
		var string_name := StringName(key)
		if key == "locale":
			G.local_settings.set_locale(
				settings[key])
		elif (string_name
				in LocalSettings.OVERRIDABLE_KEYS):
			G.local_settings.set_override(
				string_name, settings[key])
	G.local_settings.save_settings()


## Push current local settings to the cloud.
func save_to_cloud() -> void:
	if not G.auth_token_store.is_token_valid():
		return
	var data := _serialize_local_settings()
	G.backend_api_client.save_player_settings(data)


## Fetch cloud settings and merge them locally.
## Cloud wins when its timestamp is newer.
func fetch_and_merge_from_cloud() -> void:
	if not G.auth_token_store.is_token_valid():
		return
	if not G.backend_api_client.settings_received.is_connected(
			_on_settings_received):
		G.backend_api_client.settings_received.connect(
			_on_settings_received,
			CONNECT_ONE_SHOT)
		G.backend_api_client.request_failed.connect(
			_on_fetch_failed,
			CONNECT_ONE_SHOT)
	G.backend_api_client.fetch_player_settings()


func _on_settings_received(
	data: Dictionary,
) -> void:
	if G.backend_api_client.request_failed.is_connected(
			_on_fetch_failed):
		G.backend_api_client.request_failed.disconnect(
			_on_fetch_failed)

	var cloud_updated_at: int = data.get(
		"updated_at", 0)
	var local_sync_at: int = _get_cloud_sync_at()

	if cloud_updated_at > local_sync_at:
		var settings: Dictionary = data.get(
			"settings", {})
		_apply_cloud_settings(settings)
		_set_cloud_sync_at(cloud_updated_at)
	elif local_sync_at == 0:
		# No cloud settings exist yet. Push local.
		save_to_cloud()


func _on_fetch_failed(_error: String) -> void:
	if G.backend_api_client.settings_received.is_connected(
			_on_settings_received):
		G.backend_api_client.settings_received.disconnect(
			_on_settings_received)
	# 404 means no cloud settings. Push local.
	if _error == "No cloud settings found":
		save_to_cloud()


func _get_cloud_sync_at() -> int:
	return G.local_settings._config.get_value(
		LocalSettings.SECTION_META,
		_META_CLOUD_SYNC_AT,
		0,
	)


func _set_cloud_sync_at(value: int) -> void:
	G.local_settings._config.set_value(
		LocalSettings.SECTION_META,
		_META_CLOUD_SYNC_AT,
		value,
	)
	G.local_settings.save_settings()
