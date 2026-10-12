extends GutTest
## Guards against nakama-godot logging requests on players'
## machines.
##
## At NakamaLogger's DEBUG level, which Nakama.create_client()
## defaults to, nakama-godot prints every HTTP request's headers and
## body and the realtime socket's connect URI. Those carry session
## tokens, refresh tokens, and the server key, and the output lands
## in user://logs/godot.log. Platform creates the shared client
## during boot (global.gd), so the level it chose is in force by the
## time a test runs.


func test_platform_created_the_shared_client() -> void:
	assert_not_null(Platform.nakama_client)


func test_nakama_logger_does_not_log_requests() -> void:
	assert_lt(
		Nakama.logger._level,
		NakamaLogger.LOG_LEVEL.DEBUG,
		"DEBUG logs request headers, bodies, and socket URIs",
	)
