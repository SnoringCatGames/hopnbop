extends GutTest
## Unit tests for CrashReporter: queueing, sending, retries and
## drops, the previous-session crash scan, and what a report
## carries.
##
## Nothing touches the network. A fake NakamaClient stands in for
## Platform.nakama_client and answers rpc_async and
## rpc_async_with_key with canned results, and a throwaway token
## store stands in for Platform.token_store. The live Platform.auth
## node is paused meanwhile, as in test_auth_api_client_refresh.gd.
## Reporters under test are built with .new(), never enter the scene
## tree, and use fixture paths under user://test_crash_reporter.


const _FIXTURE_DIR := "user://test_crash_reporter"
const _LOG_DIR := "user://test_crash_reporter/logs"
const _QUEUE_PATH := "user://test_crash_reporter/queue.json"
const _TEST_AUTH_FILE := "user://test_crash_reporter/auth.cfg"
const _CURRENT_LOG := "godot.log"
const _PREVIOUS_LOG := "godot2026-10-11T13.25.20.log"
const _OLDER_LOG := "godot2026-10-10T09.00.00.log"
const _TEST_PLAYER_ID := "a3f1c2d4-5b6e-4f70-8a91-b2c3d4e5f607"
const _TEST_DISPLAY_NAME := "Fizz_4821"
const _TEST_DEVICE_ID := "0123456789abcdef0123456789abcdef"
const _TEST_HTTP_KEY := "test-http-key"
const _HTTP_KEY_ENVIRONMENT := "NAKAMA_HTTP_KEY"
const _RPC_ID := "crash_report"
const _ACCESS_TOKEN_LIFETIME_SEC := 7200
const _GRPC_INVALID_ARGUMENT := 3
const _GRPC_RESOURCE_EXHAUSTED := 8
const _GRPC_INTERNAL := 13
const _HTTP_BAD_REQUEST := 400
const _HTTP_TOO_MANY_REQUESTS := 429
const _HTTP_INTERNAL_ERROR := 500
const _MAX_QUEUE_SIZE := 5
const _MAX_REPORTS_PER_RUN := 5
const _MAX_ATTEMPTS := 5
const _MAX_AGE_SEC := 7 * 24 * 60 * 60
const _MAX_EXCERPT_LENGTH := 6000
const _MAX_PAYLOAD_BYTES := 15000
const _PAYLOAD_FIELDS: Array[String] = [
	"game_id",
	"game_version",
	"log_excerpt",
	"message",
	"os",
	"platform",
	"protocol_version",
	"role",
	"signature",
]


## Stands in for Platform.nakama_client. Records each crash_report
## call and answers it from next_results (success when empty).
class FakeNakamaClient extends NakamaClient:
	var session_calls: Array[Dictionary] = []
	var key_calls: Array[Dictionary] = []
	var next_results: Array[NakamaAsyncResult] = []

	func _init() -> void:
		super(
			Nakama.get_client_adapter(),
			"",
			"https",
			"fake.invalid",
			443,
			Nakama.DEFAULT_TIMEOUT,
		)

	func rpc_async(
		p_session: NakamaSession,
		p_id: String,
		p_payload = null,
	):
		session_calls.append(
			{"session": p_session, "id": p_id, "payload": p_payload})
		return _next_result()

	func rpc_async_with_key(
		p_http_key: String,
		p_id: String,
		p_payload = null,
	):
		key_calls.append(
			{"http_key": p_http_key, "id": p_id, "payload": p_payload})
		return _next_result()

	func _next_result() -> NakamaAsyncResult:
		if next_results.is_empty():
			return NakamaAPI.ApiRpc.new()
		return next_results.pop_front()


var _reporter: CrashReporter
var _nakama: FakeNakamaClient
var _store: PlatformAuthTokenStore
var _original_token_store
var _original_nakama_client
var _original_http_key := ""
var _had_http_key := false
var _was_platform_auth_processing := false


func before_each() -> void:
	_was_platform_auth_processing = Platform.auth.is_processing()
	Platform.auth.set_process(false)
	_original_token_store = Platform.token_store
	_original_nakama_client = Platform.nakama_client
	_had_http_key = OS.has_environment(_HTTP_KEY_ENVIRONMENT)
	_original_http_key = OS.get_environment(_HTTP_KEY_ENVIRONMENT)
	OS.unset_environment(_HTTP_KEY_ENVIRONMENT)

	_remove_fixture_dir()
	DirAccess.make_dir_recursive_absolute(_LOG_DIR)

	# A signed-in player without a session until a test gives one.
	_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	_store.player_id = _TEST_PLAYER_ID
	_store.display_name = _TEST_DISPLAY_NAME
	_store.local_player_id = _TEST_DEVICE_ID
	Platform.token_store = _store

	_nakama = FakeNakamaClient.new()
	Platform.nakama_client = _nakama
	_reporter = _new_reporter("client")


func after_each() -> void:
	_reporter.free()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client
	if _had_http_key:
		OS.set_environment(_HTTP_KEY_ENVIRONMENT, _original_http_key)
	else:
		OS.unset_environment(_HTTP_KEY_ENVIRONMENT)
	Platform.auth.set_process(_was_platform_auth_processing)
	_remove_fixture_dir()


# ------------------------------------------------------------------
# Queueing and sending
# ------------------------------------------------------------------


func test_report_without_session_is_queued_not_sent() -> void:
	_reporter.report_crash("ERROR  : lobby failed to load")

	assert_eq(_reporter.get_queued_entries().size(), 1)
	assert_eq(_nakama.session_calls.size(), 0, "nothing sent")
	assert_eq(_reporter.send_attempt_count, 0)
	var next_run := _new_reporter("client")
	assert_eq(
		next_run.get_queued_entries().size(), 1, "queue is on disk")
	next_run.free()


func test_queued_report_is_sent_once_a_session_exists() -> void:
	watch_signals(_reporter)
	_reporter.report_crash("ERROR  : lobby failed to load")
	_give_session()

	await _reporter.flush()

	assert_eq(_nakama.session_calls.size(), 1)
	assert_eq(_nakama.session_calls[0].id, _RPC_ID)
	assert_eq(_reporter.get_queued_entries().size(), 0)
	assert_signal_emitted(_reporter, "report_accepted")
	await _reporter.flush()
	assert_eq(_nakama.session_calls.size(), 1, "sent once")


func test_payload_has_only_the_documented_fields() -> void:
	_give_session()
	_write_log(_CURRENT_LOG, "[   1.000] lobby ready\n")

	_reporter.report_crash("ERROR  : lobby failed to load")
	await _reporter.flush()

	var payload := _sent_payload(0)
	var fields: Array = payload.keys()
	fields.sort()
	assert_eq(fields, Array(_PAYLOAD_FIELDS))
	assert_eq(payload.game_id, Platform.game_id)
	assert_eq(
		payload.game_version,
		ProjectSettings.get_setting("application/config/version"),
	)
	assert_eq(payload.role, "client")
	assert_eq(payload.platform, CrashReportText.get_platform_tag())
	assert_eq(payload.os, CrashReportText.get_os_description())
	assert_eq(payload.message, "ERROR  : lobby failed to load")
	assert_eq(
		payload.signature,
		CrashReportText.compute_signature(
			PackedStringArray(["ERROR  : lobby failed to load"])),
	)
	assert_eq(payload.log_excerpt, "[   1.000] lobby ready")
	assert_true(
		_sent_text(0).contains("\"protocol_version\":2"),
		"protocol_version is a JSON integer: %s" % _sent_text(0),
	)


func test_report_carries_no_account_values_or_tokens() -> void:
	_give_session()
	var jwt := _store.jwt_token
	_write_log(
		_CURRENT_LOG,
		(
			"Sending request [Headers: {\"Authorization\": \"Bearer %s\"}]\n"
			+ "GET /v2/rpc/x?http_key=fake%%2Fkey&unwrap=true\n"
			+ "{\"id\": \"%s\"}\n"
			+ "%s signed in as %s\n"
		) % [jwt, _TEST_DEVICE_ID, _TEST_PLAYER_ID, _TEST_DISPLAY_NAME],
	)

	_reporter.report_crash("ERROR  : %s lost %s" % [
		_TEST_DISPLAY_NAME,
		_TEST_PLAYER_ID,
	])
	await _reporter.flush()

	var sent := _sent_text(0)
	for secret: String in [
		jwt,
		_TEST_PLAYER_ID,
		_TEST_DISPLAY_NAME,
		_TEST_DEVICE_ID,
		"fake%2Fkey",
		"player_id",
	]:
		assert_false(sent.contains(secret), "sent %s" % secret)


func test_editor_build_queues_but_never_sends() -> void:
	_reporter.is_sending_allowed = false
	_give_session()

	_reporter.report_crash("ERROR  : editor-only problem")
	await _reporter.flush()

	assert_eq(_nakama.session_calls.size(), 0)
	assert_eq(_reporter.get_queued_entries().size(), 1)


func test_editor_and_export_builds_use_separate_queues() -> void:
	var reporter := CrashReporter.new()
	var expected := (
		"user://crash_reports_editor.json"
		if OS.has_feature("editor")
		else "user://crash_reports.json"
	)
	assert_eq(reporter.queue_path, expected)
	reporter.free()


func test_dedicated_server_sends_with_the_http_key() -> void:
	OS.set_environment(_HTTP_KEY_ENVIRONMENT, _TEST_HTTP_KEY)
	var server := _new_reporter("server")

	server.report_crash("ERROR  : match state desync")
	await server.flush()

	assert_eq(_nakama.key_calls.size(), 1)
	assert_eq(_nakama.key_calls[0].http_key, _TEST_HTTP_KEY)
	assert_eq(_nakama.session_calls.size(), 0)
	assert_eq(_parse(_nakama.key_calls[0].payload).role, "server")
	server.free()


func test_server_without_http_key_queues_nothing() -> void:
	var server := _new_reporter("server")

	server.report_crash("ERROR  : match state desync")

	assert_eq(server.get_queued_entries().size(), 0)
	server.free()


func test_fatal_report_waits_for_the_next_run() -> void:
	_give_session()

	_reporter.report_crash("FATAL ERROR  : unrecoverable", true)

	assert_eq(_nakama.session_calls.size(), 0, "not sent during exit")
	var next_run := _new_reporter("client")
	await next_run.flush()
	assert_eq(_nakama.session_calls.size(), 1, "sent by the next run")
	next_run.free()


func test_report_read_back_from_disk_sends_integer_protocol() -> void:
	# Godot's JSON parser reads every number back as a float, and
	# the runtime rejects a protocol_version of 2.0.
	_reporter.report_crash("ERROR  : lobby failed to load")
	var next_run := _new_reporter("client")
	_give_session()

	await next_run.flush()

	assert_true(
		_sent_text(0).contains("\"protocol_version\":2,")
			or _sent_text(0).contains("\"protocol_version\":2}"),
		_sent_text(0),
	)
	next_run.free()


# ------------------------------------------------------------------
# Server answers
# ------------------------------------------------------------------


func test_rejected_report_is_dropped() -> void:
	watch_signals(_reporter)
	_give_session()
	_nakama.next_results.append(
		_failure(_HTTP_BAD_REQUEST, _GRPC_INVALID_ARGUMENT))

	_reporter.report_crash("ERROR  : lobby failed to load")
	await _reporter.flush()

	assert_eq(_reporter.get_queued_entries().size(), 0)
	assert_signal_not_emitted(_reporter, "report_accepted")


func test_rate_limited_report_stays_queued_and_pauses() -> void:
	_give_session()
	_nakama.next_results.append(
		_failure(_HTTP_TOO_MANY_REQUESTS, _GRPC_RESOURCE_EXHAUSTED))

	_reporter.report_crash("ERROR  : lobby failed to load")
	await _reporter.flush()
	await _reporter.flush()

	assert_eq(_nakama.session_calls.size(), 1, "paused after the 429")
	var entries := _reporter.get_queued_entries()
	assert_eq(entries.size(), 1)
	assert_eq(int(entries[0].attempts), 0, "a 429 is not a failure")


func test_failing_report_is_dropped_after_max_attempts() -> void:
	for _i in _MAX_ATTEMPTS:
		_nakama.next_results.append(
			_failure(_HTTP_INTERNAL_ERROR, _GRPC_INTERNAL))

	_reporter.report_crash("ERROR  : lobby failed to load")
	_give_session()
	for attempt in range(1, _MAX_ATTEMPTS + 1):
		_end_pause()
		await _reporter.flush()
		assert_eq(_nakama.session_calls.size(), attempt)
		if attempt < _MAX_ATTEMPTS:
			assert_eq(
				int(_reporter.get_queued_entries()[0].attempts), attempt)

	assert_eq(_reporter.get_queued_entries().size(), 0)


func test_failure_pauses_sending() -> void:
	_give_session()
	_nakama.next_results.append(
		_failure(_HTTP_INTERNAL_ERROR, _GRPC_INTERNAL))

	_reporter.report_crash("ERROR  : lobby failed to load")
	await _reporter.flush()
	await _reporter.flush()

	assert_eq(_nakama.session_calls.size(), 1)


func test_old_report_ages_out_unsent() -> void:
	_reporter.report_crash("ERROR  : lobby failed to load")
	_reporter._entries[0].created_at = (
		int(Time.get_unix_time_from_system()) - _MAX_AGE_SEC - 1)
	_give_session()

	await _reporter.flush()

	assert_eq(_nakama.session_calls.size(), 0)
	assert_eq(_reporter.get_queued_entries().size(), 0)


# ------------------------------------------------------------------
# Limits
# ------------------------------------------------------------------


func test_same_signature_is_reported_once_per_run() -> void:
	_reporter.report_crash("ERROR  : player 3 missing")
	_reporter.report_crash("ERROR  : player 4 missing")

	assert_eq(_reporter.get_queued_entries().size(), 1)


func test_reports_per_run_are_capped() -> void:
	_give_session()
	for i in _MAX_REPORTS_PER_RUN + 2:
		_reporter.report_crash("ERROR  : problem %s" % char(65 + i))
		await _reporter.flush()

	assert_eq(_nakama.session_calls.size(), _MAX_REPORTS_PER_RUN)


func test_queue_is_bounded_and_drops_oldest_error() -> void:
	for i in _MAX_QUEUE_SIZE:
		_reporter.report_crash("ERROR  : problem %s" % char(65 + i))
	_write_log(_PREVIOUS_LOG, _windows_crash_log("export"))

	_reporter.scan_previous_session_logs()

	var entries := _reporter.get_queued_entries()
	assert_eq(entries.size(), _MAX_QUEUE_SIZE)
	assert_eq(entries[-1].source_log, _PREVIOUS_LOG, "crash queued")
	assert_eq(entries[0].payload.message, "ERROR  : problem B")


func test_full_queue_of_crashes_drops_a_new_error() -> void:
	var crash_entries: Array[Dictionary] = []
	for i in _MAX_QUEUE_SIZE:
		crash_entries.append({
			"id": "crash-%d" % i,
			"created_at": int(Time.get_unix_time_from_system()),
			"attempts": 0,
			"source_log": "godot2026-10-0%dT00.00.00.log" % (i + 1),
			"payload": {"role": "client", "signature": "0".repeat(16)},
		})
	var file := FileAccess.open(_QUEUE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(
		{"version": 1, "entries": crash_entries, "handled_logs": []}))
	file.close()
	var reporter := _new_reporter("client")

	reporter.report_crash("ERROR  : a new error")

	var entries := reporter.get_queued_entries()
	assert_eq(entries.size(), _MAX_QUEUE_SIZE)
	for entry in entries:
		assert_false(str(entry.source_log).is_empty())
	reporter.free()


func test_payload_fits_the_runtime_size_limit() -> void:
	# Three-byte characters: a 6000-character excerpt of them is
	# about 18 KB, over the runtime's 16 KiB payload limit.
	_give_session()
	_write_log(_CURRENT_LOG, ("界".repeat(150) + "\n").repeat(100))

	_reporter.report_crash("ERROR  : lobby failed to load")
	await _reporter.flush()

	var payload := _sent_payload(0)
	assert_lte(str(payload.log_excerpt).length(), _MAX_EXCERPT_LENGTH)
	assert_lte(_sent_text(0).to_utf8_buffer().size(), _MAX_PAYLOAD_BYTES)


# ------------------------------------------------------------------
# Previous-session crash scan
# ------------------------------------------------------------------


func test_scan_queues_a_windows_crash() -> void:
	_write_log(_PREVIOUS_LOG, _windows_crash_log("export"))

	_reporter.scan_previous_session_logs()

	var entries := _reporter.get_queued_entries()
	assert_eq(entries.size(), 1)
	assert_eq(entries[0].source_log, _PREVIOUS_LOG)
	var payload: Dictionary = entries[0].payload
	assert_eq(
		payload.message,
		(
			"Previous session crashed: CrashHandlerException: Program"
			+ " crashed with signal 11"
		),
	)
	assert_eq(payload.game_version, "0.52.0", "version that crashed")
	assert_eq(int(payload.protocol_version), 2)
	assert_true(payload.log_excerpt.contains("game_panel.gd:2527"))


func test_scan_queues_a_linux_crash() -> void:
	_write_log(
		_PREVIOUS_LOG,
		(
			CrashReportText.format_build_marker("export", "0.52.0", 2)
			+ "\nhandle_crash: Program crashed with signal 6\n"
			+ "[1] /usr/bin/godot() [0x4a3f2c]\n"
		),
	)

	_reporter.scan_previous_session_logs()

	var entries := _reporter.get_queued_entries()
	assert_eq(entries.size(), 1)
	assert_true(
		entries[0].payload.message.ends_with(
			"handle_crash: Program crashed with signal 6"))


func test_scan_ignores_a_clean_log() -> void:
	_write_log(_PREVIOUS_LOG, "[  1.0] ready\n[  9.0] quit\n")

	_reporter.scan_previous_session_logs()

	assert_eq(_reporter.get_queued_entries().size(), 0)


func test_scan_reads_only_the_newest_godot4_log() -> void:
	# The current log, a Godot 3 name, and an older session all
	# contain a crash; the newest previous log is clean.
	_write_log(_CURRENT_LOG, _windows_crash_log("export"))
	_write_log("godot_2026_10_12_09.00.00.log", _windows_crash_log("export"))
	_write_log(_OLDER_LOG, _windows_crash_log("export"))
	_write_log(_PREVIOUS_LOG, "[  1.0] ready\n")

	_reporter.scan_previous_session_logs()

	assert_eq(_reporter.get_queued_entries().size(), 0)


func test_crash_from_the_other_build_is_left_alone() -> void:
	_write_log(_PREVIOUS_LOG, _windows_crash_log("editor"))

	_reporter.scan_previous_session_logs()

	assert_eq(_reporter.get_queued_entries().size(), 0)


func test_crash_is_marked_reported_only_after_acceptance() -> void:
	_write_log(_PREVIOUS_LOG, _windows_crash_log("export"))
	_reporter.scan_previous_session_logs()
	assert_eq(_reporter.get_handled_logs().size(), 0, "not yet sent")

	var next_run := _new_reporter("client")
	next_run.scan_previous_session_logs()
	assert_eq(
		next_run.get_queued_entries().size(), 1, "not queued twice")

	_give_session()
	await next_run.flush()
	assert_eq(next_run.get_handled_logs(), [_PREVIOUS_LOG])
	assert_eq(next_run.get_queued_entries().size(), 0)
	next_run.scan_previous_session_logs()
	assert_eq(next_run.get_queued_entries().size(), 0, "reported once")
	next_run.free()


func test_crash_that_keeps_failing_is_marked_handled() -> void:
	_write_log(_PREVIOUS_LOG, _windows_crash_log("export"))
	_give_session()
	for _i in _MAX_ATTEMPTS:
		_nakama.next_results.append(
			_failure(_HTTP_INTERNAL_ERROR, _GRPC_INTERNAL))

	_reporter.scan_previous_session_logs()
	for _i in _MAX_ATTEMPTS:
		_end_pause()
		await _reporter.flush()

	assert_eq(_reporter.get_queued_entries().size(), 0)
	assert_eq(_reporter.get_handled_logs(), [_PREVIOUS_LOG])


func test_crash_report_redacts_old_sdk_token_logs() -> void:
	# Logs from before SDK 0.5.2 hold nakama-godot's DEBUG request
	# dumps: session and refresh tokens, the server key, device ids.
	var jwt := _fake_jwt(int(Time.get_unix_time_from_system()))
	var refresh_jwt := _fake_jwt(0)
	var token_lines := (
		(
			"=== Nakama : DEBUG === Sending request [Headers:"
			+ " {\"Authorization\": \"Bearer %s\"}, Body:"
			+ " {\"token\":\"%s\"}]\n"
			+ "=== Nakama : DEBUG === Sending request [Headers:"
			+ " {\"Authorization\": \"Basic dGVzdGtleTo=\"}, Body:"
			+ " {\"id\":\"%s\",\"vars\":{\"game_id\":\"hopnbop\"}}]\n"
		) % [jwt, refresh_jwt, _TEST_DEVICE_ID]
	)
	_write_log(
		_PREVIOUS_LOG,
		_windows_crash_log("export").replace(
			"[   2.000] match started\n", token_lines))
	_give_session()

	_reporter.scan_previous_session_logs()
	await _reporter.flush()

	var sent := _sent_text(0)
	assert_true(sent.contains("CrashHandlerException"))
	for secret: String in [jwt, refresh_jwt, _TEST_DEVICE_ID, "dGVzdGtleTo="]:
		assert_false(sent.contains(secret), "sent %s" % secret)


func test_crash_report_redacts_home_directory_user_name() -> void:
	_write_log(
		_PREVIOUS_LOG,
		_windows_crash_log("export").replace(
			"res://src/core/game_panel.gd",
			"C:/Users/Alice Smith/AppData/Roaming/mod.gd"),
	)
	_give_session()

	_reporter.scan_previous_session_logs()
	await _reporter.flush()

	var sent := _sent_text(0)
	assert_false(sent.contains("Alice Smith"), "sent the OS user name")
	assert_true(sent.contains("C:/Users/<user>/AppData"))


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------


func _new_reporter(role: String) -> CrashReporter:
	var reporter := CrashReporter.new()
	reporter.queue_path = _QUEUE_PATH
	reporter.log_directory = _LOG_DIR
	reporter.forced_role = role
	reporter.build_kind = "export"
	reporter.is_sending_allowed = true
	return reporter


## Gives the test player a live session.
func _give_session() -> void:
	_store.expires_at = (
		int(Time.get_unix_time_from_system()) + _ACCESS_TOKEN_LIFETIME_SEC)
	_store.jwt_token = _fake_jwt(_store.expires_at)


## Lets the next flush send right away, as if the pause after a
## failure had run out.
func _end_pause() -> void:
	_reporter._paused_until_msec = 0


func _write_log(file_name: String, text: String) -> void:
	var file := FileAccess.open(
		_LOG_DIR.path_join(file_name), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _windows_crash_log(build: String) -> String:
	return (
		"Godot Engine v4.7.2.stable.official - https://godotengine.org\n"
		+ CrashReportText.format_build_marker(build, "0.52.0", 2) + "\n"
		+ "[   1.000] lobby ready\n"
		+ "[   2.000] match started\n"
		+ "================================================================\n"
		+ "CrashHandlerException: Program crashed with signal 11\n"
		+ "Engine version: Godot Engine v4.7.2.stable.official\n"
		+ "[1] 7ff6cbd84d03 (main+40d4d03) - no debug info in PE/COFF"
		+ " executable\n"
		+ "-- END OF C++ BACKTRACE --\n"
		+ "GDScript backtrace (most recent call first):\n"
		+ "    [0] _on_match_ended (res://src/core/game_panel.gd:2527)\n"
		+ "-- END OF GDSCRIPT BACKTRACE --\n"
	)


func _failure(status_code: int, grpc_status_code: int) -> NakamaAsyncResult:
	return NakamaAPI.ApiRpc.new(
		NakamaException.new("failed", status_code, grpc_status_code))


func _sent_text(index: int) -> String:
	return str(_nakama.session_calls[index].payload)


func _sent_payload(index: int) -> Dictionary:
	return _parse(_sent_text(index))


func _parse(text: Variant) -> Dictionary:
	var data: Variant = JSON.parse_string(str(text))
	return data if data is Dictionary else {}


## A JWT-shaped string NakamaSession can parse: "eyJ" JSON header,
## claims with uid and exp, fake signature.
func _fake_jwt(expires_at: int) -> String:
	var claims := JSON.stringify({
		"exp": expires_at,
		"uid": _TEST_PLAYER_ID,
		"usn": "user_%s" % _TEST_DEVICE_ID.left(8),
	})
	return "%s.%s.ZmFrZS1zaWduYXR1cmU" % [
		_base64url("{\"alg\":\"none\"}"),
		_base64url(claims),
	]


func _base64url(text: String) -> String:
	return (
		Marshalls.utf8_to_base64(text)
		.replace("+", "-")
		.replace("/", "_")
		.replace("=", "")
	)


func _remove_fixture_dir() -> void:
	var root := ProjectSettings.globalize_path(_FIXTURE_DIR)
	if not DirAccess.dir_exists_absolute(root):
		return
	for directory: String in [_LOG_DIR, _FIXTURE_DIR]:
		var path := ProjectSettings.globalize_path(directory)
		for file_name in DirAccess.get_files_at(path):
			DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_LOG_DIR))
	DirAccess.remove_absolute(root)


# ------------------------------------------------------------------
# H86: the engine logger
# ------------------------------------------------------------------


func test_engine_logger_reports_an_error_once() -> void:
	var logger := EngineErrorLogger.new(_reporter)
	logger._log_error(
		"", "res://src/lobby.gd", 12,
		"SCRIPT ERROR: Invalid call", "",
		false, Logger.ERROR_TYPE_ERROR, [])
	logger._log_error(
		"", "res://src/lobby.gd", 12,
		"SCRIPT ERROR: Invalid call", "",
		false, Logger.ERROR_TYPE_ERROR, [])

	assert_eq(
		_reporter.get_queued_entries().size(), 1,
		"the same signature is queued once per run",
	)


func test_engine_logger_skips_warnings_and_exit_noise() -> void:
	var logger := EngineErrorLogger.new(_reporter)
	logger._log_error(
		"", "res://src/lobby.gd", 12,
		"WARNING: something mild", "",
		false, Logger.ERROR_TYPE_WARNING, [])
	logger._log_error(
		"", "", 0,
		"ERROR: 82 resources still in use at exit", "",
		false, Logger.ERROR_TYPE_ERROR, [])

	assert_eq(_reporter.get_queued_entries().size(), 0)


func test_engine_logger_stops_when_the_reporter_exits() -> void:
	_reporter.is_exiting = true
	var logger := EngineErrorLogger.new(_reporter)
	logger._log_error(
		"", "res://src/lobby.gd", 12,
		"SCRIPT ERROR: Invalid call", "",
		false, Logger.ERROR_TYPE_ERROR, [])

	assert_eq(_reporter.get_queued_entries().size(), 0)
