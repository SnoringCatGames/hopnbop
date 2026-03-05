class_name AuthTokenStore
extends RefCounted
## Persists authentication tokens to encrypted local storage.
##
## Stores JWT, refresh token, and player metadata in an
## encrypted ConfigFile at user://auth.cfg. Uses
## OS.get_unique_id() as the encryption passphrase for
## basic obfuscation.

const _AUTH_FILE_PATH := "user://auth.cfg"
const _SECTION := "auth"
const _REFRESH_MARGIN_SEC := 3600

var jwt_token := ""
var refresh_token := ""
var player_id := ""
var display_name := ""
var provider := ""
var is_anonymous := false
var expires_at := 0
var rating := 1500


func _init() -> void:
	load_tokens()


## Returns true when a JWT exists and has not expired.
func is_token_valid() -> bool:
	if jwt_token.is_empty():
		return false
	var now := int(Time.get_unix_time_from_system())
	return now < expires_at


## Returns true when the JWT is close to expiring
## but a refresh token is available.
func needs_refresh() -> bool:
	if refresh_token.is_empty():
		return false
	if jwt_token.is_empty():
		return false
	var now := int(Time.get_unix_time_from_system())
	return now >= (expires_at - _REFRESH_MARGIN_SEC)


## Populate fields from a backend auth response dict.
func store_from_response(data: Dictionary) -> void:
	jwt_token = data.get("jwt_token", "")
	refresh_token = data.get("refresh_token", "")
	player_id = data.get("player_id", "")
	display_name = data.get("display_name", "")
	is_anonymous = data.get("is_anonymous", false)
	expires_at = data.get("expires_at", 0)
	rating = data.get("rating", 1500)
	provider = data.get("provider", "")
	save_tokens()


## Delete all stored auth state.
func clear_tokens() -> void:
	jwt_token = ""
	refresh_token = ""
	player_id = ""
	display_name = ""
	provider = ""
	is_anonymous = false
	expires_at = 0
	rating = 1500
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(_AUTH_FILE_PATH)
	)


## Persist current auth state to encrypted file.
func save_tokens() -> void:
	var config := ConfigFile.new()
	config.set_value(_SECTION, "jwt_token", jwt_token)
	config.set_value(
		_SECTION, "refresh_token", refresh_token
	)
	config.set_value(_SECTION, "player_id", player_id)
	config.set_value(
		_SECTION, "display_name", display_name
	)
	config.set_value(_SECTION, "provider", provider)
	config.set_value(
		_SECTION, "is_anonymous", is_anonymous
	)
	config.set_value(_SECTION, "expires_at", expires_at)
	config.set_value(_SECTION, "rating", rating)
	config.save_encrypted_pass(
		_AUTH_FILE_PATH, _get_passphrase()
	)


## Load auth state from encrypted file.
func load_tokens() -> void:
	var config := ConfigFile.new()
	var err := config.load_encrypted_pass(
		_AUTH_FILE_PATH, _get_passphrase()
	)
	if err != OK:
		return
	jwt_token = config.get_value(
		_SECTION, "jwt_token", ""
	)
	refresh_token = config.get_value(
		_SECTION, "refresh_token", ""
	)
	player_id = config.get_value(
		_SECTION, "player_id", ""
	)
	display_name = config.get_value(
		_SECTION, "display_name", ""
	)
	provider = config.get_value(
		_SECTION, "provider", ""
	)
	is_anonymous = config.get_value(
		_SECTION, "is_anonymous", false
	)
	expires_at = config.get_value(
		_SECTION, "expires_at", 0
	)
	rating = config.get_value(
		_SECTION, "rating", 1500
	)


func _get_passphrase() -> String:
	return OS.get_unique_id().sha256_text()
