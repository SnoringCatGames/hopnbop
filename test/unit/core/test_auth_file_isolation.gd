extends GutTest
## Guards against a GUT run loading the developer's real credentials.
##
## Every GUT process boots the game's autoloads, so G initializes
## Platform before any test runs. While G handed Platform the real
## user://auth.cfg, PlatformAuthApiClient refreshed that session
## against production Nakama on the first frame, and a rejected
## refresh cleared the file, signing the developer out (LEDGER H2).
## Test runs now get a credentials file of their own.


func test_test_runs_use_their_own_credentials_file() -> void:
	# PlatformAuthTokenStore has no public accessor for its path, and
	# the path is what this guard is about.
	assert_eq(
		Platform.token_store._auth_file_path,
		G.TEST_AUTH_FILE_PATH,
	)
	assert_ne(G.TEST_AUTH_FILE_PATH, G.AUTH_FILE_PATH)


func test_each_test_run_starts_signed_out() -> void:
	# Something a test saved in an earlier run.
	var file := FileAccess.open(G.TEST_AUTH_FILE_PATH, FileAccess.WRITE)
	file.store_string("stale")
	file.close()

	assert_eq(G._get_auth_file_path(), G.TEST_AUTH_FILE_PATH)
	assert_false(FileAccess.file_exists(G.TEST_AUTH_FILE_PATH))
