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
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(
			_TEST_AUTH_FILE + ".unreadable"))


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


func test_legacy_file_loads_with_key_file_present() -> void:
	# The legacy retry: an install key exists beside the
	# file, but the file predates it and only opens with
	# the device passphrase.
	_write_legacy_file()
	var key_config := ConfigFile.new()
	key_config.set_value("auth", "install_key", "0123abcd")
	assert_eq(
		key_config.save(
			_TEST_AUTH_FILE.get_basename() + "_key.cfg"),
		OK)
	# The constructor's load tries the install key first
	# (one expected decryption error), then the legacy
	# passphrase.
	var store := PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	assert_eq(
		store.local_player_id, _LEGACY_GUEST_ID,
		"legacy guest identity kept via the retry")
	assert_false(store.load_failed)
	assert_engine_error("MD5 sum of the decrypted file")


func test_lost_key_leaves_the_file_in_place() -> void:
	var store := PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	store.is_anonymous = true
	store.local_player_id = _LEGACY_GUEST_ID
	store.save_tokens()
	var key_path := _TEST_AUTH_FILE.get_basename() + "_key.cfg"
	assert_true(
		FileAccess.file_exists(key_path), "install key written")
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(key_path))

	var reloaded := PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	assert_eq(
		reloaded.local_player_id, "", "identity unreadable")
	assert_true(reloaded.load_failed, "failed load recorded")
	assert_true(
		reloaded.has_auth_file(), "file left in place")
	assert_engine_error("MD5 sum of the decrypted file")


func test_unreadable_file_is_moved_aside_for_a_new_guest() -> void:
	# Damaged bytes where the auth file should be.
	var damaged := FileAccess.open(
		_TEST_AUTH_FILE, FileAccess.WRITE)
	damaged.store_string("not an encrypted store")
	damaged.close()
	var store := PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	assert_true(store.load_failed, "failed load recorded")
	assert_engine_error("magic != 0x43454447")

	var original_store = Platform.token_store
	Platform.token_store = store
	var client := PlatformAuthApiClient.new()
	client.login_anonymous()
	client.free()
	Platform.token_store = original_store

	assert_true(
		FileAccess.file_exists(_TEST_AUTH_FILE + ".unreadable"),
		"unreadable file kept aside")
	assert_ne(
		store.local_player_id, "", "new guest identity minted")
	assert_true(
		store.has_auth_file(), "fresh auth file written")


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
