extends GutTest
## Unit tests for CrashReportText: redaction, signatures, crash
## detection in Godot logs, excerpts, and the build marker.
##
## Token-shaped fixtures are built at run time from obviously fake
## parts, so no token literal sits in the source.


const _SIGNATURE_PATTERN := "^[0-9a-f]{16}$"
const _PLATFORM_PATTERN := "^[a-z0-9_]{1,16}$"
const _MAX_OS_DESCRIPTION_LENGTH := 64
const _FAKE_USER_ID := "a3f1c2d4-5b6e-4f70-8a91-b2c3d4e5f607"
const _FAKE_DEVICE_ID := "0123456789abcdef0123456789abcdef"
const _WINDOWS_CRASH := (
	"[   1.000] lobby ready\n"
	+ "[   2.000] match started\n"
	+ "================================================================\n"
	+ "CrashHandlerException: Program crashed with signal 11\n"
	+ "Engine version: Godot Engine v4.7.2.stable.official\n"
	+ "Dumping the backtrace. Please include this when reporting the bug on:"
	+ " https://github.com/godotengine/godot/issues\n"
	+ "[1] 7ff6cbd84d03 (main+40d4d03) - no debug info in PE/COFF executable\n"
	+ "[2] 7ffdb9b24702 (ntdll.dll+124702) - no debug info in PE/COFF"
	+ " executable\n"
	+ "-- END OF C++ BACKTRACE --\n"
	+ "================================================================\n"
	+ "GDScript backtrace (most recent call first):\n"
	+ "    [0] _on_match_ended (res://src/core/game_panel.gd:2527)\n"
	+ "    [1] _process (res://src/core/game_panel.gd:310)\n"
	+ "-- END OF GDSCRIPT BACKTRACE --\n"
)
const _LINUX_CRASH := (
	"[   3.000] server ready\n"
	+ "handle_crash: Program crashed with signal 6\n"
	+ "Engine version: Godot Engine v4.7.2.stable.official\n"
	+ "[1] /usr/bin/godot() [0x4a3f2c]\n"
	+ "[2] /usr/bin/godot() [0x4b0011]\n"
	+ "-- END OF C++ BACKTRACE --\n"
)


# ------------------------------------------------------------------
# redact
# ------------------------------------------------------------------


func test_redacts_jwts() -> void:
	var jwt := _fake_jwt()
	var result := CrashReportText.redact("token %s end" % jwt)
	assert_eq(result, "token <jwt> end")


func test_redacts_authorization_values() -> void:
	assert_eq(
		CrashReportText.redact(
			"{\"Authorization\": \"Basic dGVzdGtleTo=\"}"),
		"{\"Authorization\": \"Basic <redacted>\"}",
	)
	assert_eq(
		CrashReportText.redact("Authorization: Bearer abc.def_123"),
		"Authorization: Bearer <redacted>",
	)


func test_redacts_secret_parameters() -> void:
	assert_eq(
		CrashReportText.redact(
			"/v2/rpc/x?http_key=fake%2Fkey%3D&unwrap=true"),
		"/v2/rpc/x?http_key=<redacted>&unwrap=true",
	)
	assert_eq(
		CrashReportText.redact("GET /?code=4/0Ab&state=f00d HTTP/1.1"),
		"GET /?code=<redacted>&state=<redacted> HTTP/1.1",
	)


func test_redacts_identifying_json_fields() -> void:
	# nakama-godot's request logs before SDK 0.5.2 carried device
	# ids as "id" in auth bodies.
	assert_eq(
		CrashReportText.redact(
			"{\"id\": \"dev-1\", \"vars\": {\"game_id\": \"hopnbop\"},"
			+ " \"display_name\": \"Alice Smith\"}"),
		"{\"id\": \"<redacted>\", \"vars\": {\"game_id\": \"<redacted>\"},"
			+ " \"display_name\": \"<redacted>\"}",
	)


func test_redacts_ids_emails_and_addresses() -> void:
	assert_eq(
		CrashReportText.redact("user %s left" % _FAKE_USER_ID),
		"user <uuid> left",
	)
	assert_eq(
		CrashReportText.redact("device %s ok" % _FAKE_DEVICE_ID),
		"device <hex> ok",
	)
	assert_eq(
		CrashReportText.redact("steam 76561198000000000 ok"),
		"steam <number> ok",
	)
	assert_eq(
		CrashReportText.redact("mail alice.smith@example.com now"),
		"mail <email> now",
	)
	assert_eq(
		CrashReportText.redact("peer 203.0.113.7:4433 joined"),
		"peer <ip>:4433 joined",
	)


func test_redacts_device_ids_and_glued_ids() -> void:
	# The SDK's preview matchmaking logs another account's device
	# id, which logs that account in.
	assert_eq(
		CrashReportText.redact(
			"[PlatformMatchmaking] Preview device_id=preview_%s_C1 uid=x"
			% _FAKE_USER_ID),
		"[PlatformMatchmaking] Preview device_id=<redacted> uid=x",
	)
	assert_eq(
		CrashReportText.redact("group party_%s" % _FAKE_USER_ID),
		"group party_<uuid>",
	)
	assert_eq(
		CrashReportText.redact("local_%s" % _FAKE_DEVICE_ID),
		"local_<hex>",
	)


func test_redacts_signaling_url_tokens() -> void:
	assert_eq(
		CrashReportText.redact(
			"wss://signaling.snoringcat.games/connect/"
			+ "MTAuMC4wLjE6NDQzNDoxNzAwMDAwMDAwOmFiY2Q"),
		"wss://signaling.snoringcat.games/connect/<redacted>",
	)


func test_redacts_home_directory_user_names() -> void:
	# A real crash's script frames and Godot's own messages carry
	# absolute paths, and an OS account name is often a real name.
	assert_eq(
		CrashReportText.redact(
			"[0] _run (C:/Users/Alice Smith/AppData/x.gd:54)"),
		"[0] _run (C:/Users/<user>/AppData/x.gd:54)",
	)
	assert_eq(
		CrashReportText.redact(
			"open C:\\Users\\asmith\\AppData\\Roaming\\Godot failed"),
		"open C:\\Users\\<user>\\AppData\\Roaming\\Godot failed",
	)
	assert_eq(
		CrashReportText.redact("/home/asmith/.local/share/godot"),
		"/home/<user>/.local/share/godot",
	)
	assert_eq(
		CrashReportText.redact("/Users/asmith/Library/Godot"),
		"/Users/<user>/Library/Godot",
	)


func test_redacts_account_values_longest_first() -> void:
	var account_values: Array[String] = ["Fizz", "Fizz_4821", "ab"]
	assert_eq(
		CrashReportText.redact(
			"Fizz_4821 joined; ab stays", account_values),
		"<account> joined; ab stays",
	)


func test_leaves_ordinary_log_lines_alone() -> void:
	for line: String in [
		"basic configuration loaded",
		"[  12.345|  678][CS] Version: 0.53.0",
		"SCRIPT ERROR: res://src/core/game_panel.gd:2527 - Invalid call",
		"CrashHandlerException: Program crashed with signal 11",
		"Engine version: Godot Engine v4.7.2.stable.official",
		"[1] 7ff6cbd84d03 (main+40d4d03) - no debug info in PE/COFF executable",
		"frame 1234 rollback to 1200",
		"res://assets/images/gui/Level2Background/tiles.png",
	]:
		assert_eq(CrashReportText.redact(line), line)


# ------------------------------------------------------------------
# Signatures
# ------------------------------------------------------------------


func test_signature_shape() -> void:
	var signature := CrashReportText.compute_signature(
		PackedStringArray(["ERROR  : something broke"]))
	assert_true(
		RegEx.create_from_string(_SIGNATURE_PATTERN).search(signature)
			!= null,
		"16 lowercase hex characters: %s" % signature,
	)


func test_signature_ignores_numbers_and_addresses() -> void:
	assert_eq(
		CrashReportText.compute_signature(
			PackedStringArray(["ERROR  : Player 3 missing at 0x7ff6a0"])),
		CrashReportText.compute_signature(
			PackedStringArray(["ERROR  :  Player 12 missing at 0x1b"])),
	)


func test_signature_survives_address_randomization() -> void:
	# Windows C++ frames print bare-hex addresses that move with
	# ASLR on every run (captured from a real 4.7.2 crash).
	var first_run := (
		"[1] 7ff6cbd84d03 (main+40d4d03) - no debug info in PE/COFF"
		+ " executable")
	var second_run := (
		"[1] 7ff7a1c94e13 (main+40d4d03) - no debug info in PE/COFF"
		+ " executable")
	assert_eq(
		CrashReportText.normalize_for_signature(first_run),
		CrashReportText.normalize_for_signature(second_run),
	)
	assert_eq(
		CrashReportText.normalize_for_signature("facade decade"),
		"facade decade",
		"words made of hex letters are not addresses",
	)


func test_signature_tells_different_errors_apart() -> void:
	assert_ne(
		CrashReportText.compute_signature(
			PackedStringArray(["ERROR  : Player missing"])),
		CrashReportText.compute_signature(
			PackedStringArray(["ERROR  : Level missing"])),
	)


func test_first_line() -> void:
	assert_eq(
		CrashReportText.first_line("\n  ERROR  : a  \nsecond"),
		"ERROR  : a",
	)
	assert_eq(CrashReportText.first_line(" \n "), "")


# ------------------------------------------------------------------
# Logs and crashes
# ------------------------------------------------------------------


func test_finds_newest_godot4_previous_log() -> void:
	var names := PackedStringArray([
		"godot.log",
		"godot_2026_10_12_09.00.00.log",
		"godot2026-10-10T09.00.00.log",
		"godot2026-10-11T13.25.20.log",
		"godot2026-10-11T13.25.20.log.txt",
		"notes.log",
	])
	assert_eq(
		CrashReportText.find_latest_previous_log(names),
		"godot2026-10-11T13.25.20.log",
	)
	assert_eq(
		CrashReportText.find_latest_previous_log(
			PackedStringArray(["godot.log"])),
		"",
	)


func test_finds_windows_crash_with_script_frames() -> void:
	var crash := CrashReportText.find_crash(_WINDOWS_CRASH)
	assert_eq(
		crash.message,
		"CrashHandlerException: Program crashed with signal 11",
	)
	assert_eq(
		Array(crash.signature_lines),
		[
			"CrashHandlerException: Program crashed with signal 11",
			"[0] _on_match_ended (res://src/core/game_panel.gd:2527)",
			"[1] _process (res://src/core/game_panel.gd:310)",
		],
	)
	assert_eq(crash.context_lines.size(), 3)
	assert_true(
		crash.block_lines[0].begins_with("CrashHandlerException"))


func test_finds_linux_crash_with_engine_frames() -> void:
	var crash := CrashReportText.find_crash(_LINUX_CRASH)
	assert_eq(crash.message, "handle_crash: Program crashed with signal 6")
	assert_eq(crash.signature_lines.size(), 3, "crash line + 2 frames")
	assert_true(crash.signature_lines[1].begins_with("[1] /usr/bin/godot"))


func test_clean_log_has_no_crash() -> void:
	assert_eq(
		CrashReportText.find_crash("[ 1.0] ready\nERROR: not a crash\n"),
		{},
	)


func test_crash_excerpt_keeps_the_crash_first() -> void:
	var crash := CrashReportText.find_crash(_WINDOWS_CRASH)
	var full := CrashReportText.build_crash_excerpt(
		crash.context_lines, crash.block_lines, 10000)
	assert_true(full.begins_with("[   1.000] lobby ready"))
	assert_true(full.contains("game_panel.gd:2527"))
	var short := CrashReportText.build_crash_excerpt(
		crash.context_lines, crash.block_lines, 80)
	assert_true(
		short.begins_with("CrashHandlerException"),
		"context dropped before the crash line: %s" % short,
	)
	assert_lte(short.length(), 80)


func test_tail_excerpt_keeps_the_end() -> void:
	var excerpt := CrashReportText.build_tail_excerpt(
		"first\nsecond\nthird\n", 13)
	assert_eq(excerpt, "second\nthird")


func test_build_marker_round_trip() -> void:
	var line := CrashReportText.format_build_marker("export", "0.52.0", 2)
	assert_eq(line, "[CrashReporter] build=export version=0.52.0 protocol=2")
	assert_eq(
		CrashReportText.parse_build_marker("x\n[  0.1] %s\ny" % line),
		{"build": "export", "version": "0.52.0", "protocol": 2},
	)
	assert_eq(CrashReportText.parse_build_marker("no marker"), {})


func test_version_check() -> void:
	assert_true(CrashReportText.is_valid_version("0.53.0"))
	assert_true(CrashReportText.is_valid_version("1.0.0-rc.1+build5"))
	assert_false(CrashReportText.is_valid_version(""))
	assert_false(CrashReportText.is_valid_version("0.53 beta"))


func test_platform_and_os_fit_the_runtime_limits() -> void:
	var platform := CrashReportText.get_platform_tag()
	assert_true(
		RegEx.create_from_string(_PLATFORM_PATTERN).search(platform)
			!= null,
		"platform tag %s" % platform,
	)
	var os_description := CrashReportText.get_os_description()
	assert_false(os_description.is_empty())
	assert_lte(os_description.length(), _MAX_OS_DESCRIPTION_LENGTH)
	assert_true(os_description.begins_with(OS.get_name()))


## A JWT-shaped string: base64url JSON header and claims, fake
## signature.
func _fake_jwt() -> String:
	return "%s.%s.ZmFrZS1zaWduYXR1cmU" % [
		_base64url("{\"alg\":\"none\"}"),
		_base64url("{\"uid\":\"fake\"}"),
	]


func _base64url(text: String) -> String:
	return (
		Marshalls.utf8_to_base64(text)
		.replace("+", "-")
		.replace("/", "_")
		.replace("=", "")
	)


func test_exit_noise_is_recognized() -> void:
	assert_true(CrashReportText.is_exit_noise(
		"ERROR: 2 RID allocations of type 'PN13Renderer' leaked"))
	assert_true(CrashReportText.is_exit_noise(
		"ERROR: 82 resources still in use at exit"))
	assert_true(CrashReportText.is_exit_noise(
		"ERROR: Pages in use exist at exit in PagedAllocator"))
	assert_false(CrashReportText.is_exit_noise(
		"SCRIPT ERROR: Invalid call in lobby"))
