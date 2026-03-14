class_name AuthTokenStore
extends RefCounted
## Persists authentication tokens to encrypted local storage.
##
## Stores JWT, refresh token, and player metadata in an
## encrypted ConfigFile at user://auth.cfg. In preview
## mode, secondary clients use separate files to avoid
## identity collisions during matchmaking. Uses
## OS.get_unique_id() as the encryption passphrase for
## basic obfuscation.

const LEGAL_VERSION := "1.1"

const _SECTION := "auth"
const _REFRESH_MARGIN_SEC := 3600

var _auth_file_path := "user://auth.cfg"

var jwt_token := ""
var refresh_token := ""
var player_id := ""
var display_name := ""
var provider := ""
var is_anonymous := false
var expires_at := 0
var rating := 1500
var linked_providers: Array[String] = []
var consent_accepted_at := 0
var consent_legal_version := ""
var profile_image_url := ""


func _init() -> void:
	# In preview mode, each client uses a separate
	# auth file so they don't overwrite each other.
	# Parse args directly because Netcode is not yet
	# initialized when this runs (G autoloads first).
	var client_num := _get_preview_client_number()
	if client_num > 1:
		_auth_file_path = (
			"user://auth_client%d.cfg"
			% client_num)
	load_tokens()


static func _get_preview_client_number() -> int:
	if not OS.has_feature("editor"):
		return 0
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--client="):
			return int(arg.substr(9))
	return 0


## Returns true when a JWT exists and has not expired.
func is_token_valid() -> bool:
	if jwt_token.is_empty():
		return false
	var now := int(Time.get_unix_time_from_system())
	return now < expires_at


## Returns true when consent has been given for
## the specified legal version.
func has_valid_consent(
	current_version: String,
) -> bool:
	return (
		consent_accepted_at > 0
		and consent_legal_version
			== current_version
	)


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
	var server_consent: int = data.get(
		"consent_accepted_at", 0
	)
	if server_consent > 0:
		consent_accepted_at = server_consent
		consent_legal_version = data.get(
			"consent_legal_version", ""
		)
	profile_image_url = data.get(
		"profile_image_url", ""
	)
	linked_providers.clear()
	var lp: Array = data.get("linked_providers", [])
	for p in lp:
		linked_providers.append(str(p))
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
	linked_providers.clear()
	consent_accepted_at = 0
	consent_legal_version = ""
	profile_image_url = ""
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(_auth_file_path)
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
	config.set_value(
		_SECTION, "linked_providers",
		linked_providers,
	)
	config.set_value(
		_SECTION, "consent_accepted_at",
		consent_accepted_at,
	)
	config.set_value(
		_SECTION, "consent_legal_version",
		consent_legal_version,
	)
	config.set_value(
		_SECTION, "profile_image_url",
		profile_image_url,
	)
	config.save_encrypted_pass(
		_auth_file_path, _get_passphrase()
	)


## Load auth state from encrypted file.
func load_tokens() -> void:
	var config := ConfigFile.new()
	var err := config.load_encrypted_pass(
		_auth_file_path, _get_passphrase()
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
	linked_providers.clear()
	var lp: Array = config.get_value(
		_SECTION, "linked_providers", []
	)
	for p in lp:
		linked_providers.append(str(p))
	consent_accepted_at = config.get_value(
		_SECTION, "consent_accepted_at", 0
	)
	consent_legal_version = config.get_value(
		_SECTION, "consent_legal_version", ""
	)
	profile_image_url = config.get_value(
		_SECTION, "profile_image_url", ""
	)


func _get_passphrase() -> String:
	return OS.get_unique_id().sha256_text()
