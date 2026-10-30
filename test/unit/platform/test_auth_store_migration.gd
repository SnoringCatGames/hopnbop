extends GutTest
## SP44 migration safety: a store file written with the old
## (device-derived) passphrase must still load and keep its
## guest identity, and an unreadable file must never cause a
## fresh identity to be minted over it.


const _TEST_AUTH_FILE := "user://test_auth_store_migration.cfg"
const _LEGACY_GUEST_ID := "guest-legacy-1"


func after_each() -> void:
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(_TEST_AUTH_FILE))
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(
			_TEST_AUTH_FILE.get_basename() + "_key.cfg"))


func test_old_passphrase_file_still_loads() -> void:
	_write_legacy_file()
	var store := PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	store.load_tokens()
	assert_eq(
		store.local_player_id, _LEGACY_GUEST_ID,
		"legacy guest identity kept")
	assert_true(store.is_anonymous)


func test_empty_file_is_flagged_not_missing() -> void:
	# A saved file with no guest identity yet: the client must
	# still see that a file exists. (An unreadable file takes
	# the same path: load leaves the id empty, the file stays.)
	var config := ConfigFile.new()
	config.set_value("auth", "is_anonymous", true)
	config.save_encrypted_pass(
		_TEST_AUTH_FILE, OS.get_unique_id().sha256_text())
	var store := PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	store.load_tokens()
	assert_eq(store.local_player_id, "", "nothing invented")
	assert_true(
		store.has_auth_file(),
		"client can tell a file exists and refuse to re-mint")


func test_save_rekeys_and_reloads() -> void:
	var store := PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	store.is_anonymous = true
	store.local_player_id = _LEGACY_GUEST_ID
	store.save_tokens()
	assert_true(
		FileAccess.file_exists(
			_TEST_AUTH_FILE.get_basename() + "_key.cfg"),
		"install key written on save")
	var reloaded := PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	reloaded.load_tokens()
	assert_eq(reloaded.local_player_id, _LEGACY_GUEST_ID)


func test_state_nonce_shape() -> void:
	var client := PlatformAuthApiClient.new()
	var first := client._generate_state_nonce()
	var second := client._generate_state_nonce()
	assert_eq(first.length(), 32, "16 bytes hex-encoded")
	assert_ne(first, second, "nonces differ")
	client.free()


## Write a store file exactly as pre-SP44 code did: encrypted
## with the device-derived passphrase.
func _write_legacy_file() -> void:
	var config := ConfigFile.new()
	config.set_value("auth", "is_anonymous", true)
	config.set_value("auth", "local_player_id", _LEGACY_GUEST_ID)
	config.set_value("auth", "display_name", "")
	config.set_value("auth", "consent_accepted_at", 0)
	config.set_value("auth", "consent_legal_version", "")
	var legacy := OS.get_unique_id().sha256_text()
	assert_eq(
		config.save_encrypted_pass(_TEST_AUTH_FILE, legacy), OK)
