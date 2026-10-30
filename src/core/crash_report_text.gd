class_name CrashReportText
extends RefCounted
## Text helpers for crash reports, free of state so CrashReporter
## and its tests share one implementation: redaction, error
## signatures, crash detection in Godot logs, excerpts, platform
## names, and the build marker line.

## Length of an error signature: the first hex characters of a
## SHA-256 over the normalized first error lines. The runtime's
## crash_report RPC accepts exactly this many lowercase hex digits.
const SIGNATURE_LENGTH := 16
## Replaces a value that belongs to the signed-in account.
const ACCOUNT_PLACEHOLDER := "<account>"
## Starts the line CrashReporter prints at startup. A later run
## reads it from the previous session's log to learn which build,
## version, and protocol crashed.
const BUILD_MARKER_PREFIX := "[CrashReporter] build="
## Text Godot's crash handlers print. Windows:
## platform/windows/crash_handler_windows_seh.cpp. Linux and macOS:
## crash_handler_linuxbsd.cpp and crash_handler_macos.mm.
const CRASH_MARKERS: Array[String] = [
	"CrashHandlerException: Program crashed",
	"handle_crash: Program crashed",
]
## Godot 4 copies the previous session's godot.log to
## godot<local time>.log at startup, for example
## godot2026-10-11T13.25.20.log. Godot 3 used a godot_ prefix.
const PREVIOUS_LOG_PATTERN := (
	"^godot\\d{4}-\\d{2}-\\d{2}T\\d{2}\\.\\d{2}\\.\\d{2}\\.log$"
)

## Account values shorter than this are not redacted literally,
## because short display names are common words.
const _MIN_ACCOUNT_VALUE_LENGTH := 3
## Lines kept before a crash line, and from it, in an excerpt.
const _CRASH_CONTEXT_LINES := 30
const _CRASH_BLOCK_LINES := 50
## Backtrace frames that go into a crash signature.
const _SIGNATURE_FRAME_COUNT := 8
## Godot prints this header before a script backtrace, after the
## C++ frames. Script frames name functions even in release
## builds, so they make a better signature.
const _SCRIPT_BACKTRACE_HEADER := "backtrace (most recent call first)"
const _MAX_OS_DESCRIPTION_LENGTH := 64
const _WEB_HOST_FEATURES := {
	"web_android": "Android",
	"web_ios": "iOS",
	"web_macos": "macOS",
	"web_windows": "Windows",
	"web_linuxbsd": "Linux",
}
## Each rule is [pattern, replacement], applied in order after the
## literal account values. The runtime runs a similar list again.
const _REDACTION_RULES: Array = [
	# Nakama session and refresh tokens are JWTs; every JWT header
	# encodes to "eyJ".
	["eyJ[A-Za-z0-9_-]*\\.[A-Za-z0-9_-]*\\.[A-Za-z0-9_-]*", "<jwt>"],
	# An Authorization value. Requiring a digit or one of +/= keeps
	# the English word "basic" from eating the next word.
	[
		(
			"(?i)\\b(bearer|basic)\\s+[A-Za-z0-9._~+/-]*[0-9+/=]"
			+ "[A-Za-z0-9._~+/=-]*"
		),
		"$1 <redacted>",
	],
	# name=value and "name": "value" pairs whose name says secret
	# or identifier. A device id logs its account in, so it is a
	# credential; Nakama bodies carry it as "id", and preview
	# matchmaking logs device_id=preview_<machine id>_C1.
	[
		(
			"(?i)\\b([a-z_]*(?:key|token|secret|password|device_id"
			+ "|player_id|user_id))=[^&\\s\"',;]+"
		),
		"$1=<redacted>",
	],
	["(?i)([?&](?:code|state))=[^&\\s\"',;]+", "$1=<redacted>"],
	# The token in a signed signaling URL
	# (wss://signaling.../connect/<token>) admits its holder to a
	# match for five minutes.
	["(/connect/)[A-Za-z0-9_=-]{16,}", "$1<redacted>"],
	[
		(
			"(?i)\"([a-z_]*(?:key|token|secret|password|id|username"
			+ "|display_name|email))\"\\s*:\\s*\"[^\"]*\""
		),
		"\"$1\": \"<redacted>\"",
	],
	# Nakama user, session, and match ids are UUIDs. No word
	# boundaries: an id glued to a prefix ("party_<uuid>") is still
	# an id.
	[
		(
			"(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}"
			+ "-[0-9a-f]{12}"
		),
		"<uuid>",
	],
	# The OS account name in a home directory path, such as
	# C:/Users/<name>/AppData/Roaming/Godot. It is often a real name.
	[
		(
			"(?i)\\b([a-z]:[\\\\/](?:users|documents and settings)"
			+ "[\\\\/])[^\\\\/\\r\\n\"'<>|:*?]+"
		),
		"$1<user>",
	],
	["(/home/|/Users/)[^/\\s\"']+", "$1<user>"],
	# Anonymous players' device ids are 32 hex characters, glued to
	# a prefix or not.
	["[0-9A-Fa-f]{32,}", "<hex>"],
	# Steam, Facebook, and Google account ids are long numbers.
	["\\b\\d{15,}\\b", "<number>"],
	["[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", "<email>"],
	["\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b", "<ip>"],
]
const _FRAME_PATTERN := "^\\s*\\[\\d+\\]"
const _HEX_NUMBER_PATTERN := "0x[0-9A-Fa-f]+"
## Bare hex such as the addresses in Windows C++ frames
## ("[1] 7ff6cbd84d03 (main+40d4d03)"), which move every run. The
## digit requirement spares words like "facade".
const _HEX_RUN_PATTERN := "\\b(?=[0-9A-Fa-f]*\\d)[0-9A-Fa-f]{6,}\\b"
const _DIGITS_PATTERN := "\\d+"
const _WHITESPACE_PATTERN := "\\s+"
const _BUILD_MARKER_PATTERN := (
	"\\[CrashReporter\\] build=(\\w+) version=(\\S+) protocol=(\\d+)"
)
const _VERSION_PATTERN := "^[0-9A-Za-z][0-9A-Za-z.+_-]{0,31}$"

static var _redaction_regexes: Array[RegEx] = []
static var _regexes_by_pattern := {}


## Returns text with the signed-in account's own values and every
## token-shaped or identifying string replaced by a placeholder.
static func redact(
	text: String,
	account_values: Array[String] = [],
) -> String:
	var result := text
	var literals: Array[String] = account_values.duplicate()
	# Longest first, so a value inside another is not left behind
	# half-replaced.
	literals.sort_custom(
		func(a: String, b: String) -> bool: return a.length() > b.length())
	for value in literals:
		if value.length() >= _MIN_ACCOUNT_VALUE_LENGTH:
			result = result.replace(value, ACCOUNT_PLACEHOLDER)
	var regexes := _get_redaction_regexes()
	for index in regexes.size():
		result = regexes[index].sub(
			result, str(_REDACTION_RULES[index][1]), true)
	return result


## Exit-time engine noise (H28): leak and allocator lines
## Godot prints while tearing down. They are not errors a
## report could act on, and H86's engine logger must skip
## them.
const _EXIT_NOISE_MARKERS: Array[String] = [
	"leaked at exit",
	"still in use at exit",
	"Pages in use exist at exit",
	"instances were leaked at exit",
	"RID allocations of type",
]


static func is_exit_noise(line: String) -> bool:
	for marker in _EXIT_NOISE_MARKERS:
		if marker in line:
			return true
	return false


## Returns the first non-empty line of text, trimmed.
static func first_line(text: String) -> String:
	for line in text.split("\n", false):
		var trimmed := line.strip_edges()
		if not trimmed.is_empty():
			return trimmed
	return ""


## Returns line with numbers, hex addresses, and runs of whitespace
## collapsed, so the same error at a different frame, player, or
## address gets the same signature.
static func normalize_for_signature(line: String) -> String:
	var text := line.strip_edges()
	text = _get_regex(_HEX_NUMBER_PATTERN).sub(text, "#", true)
	text = _get_regex(_HEX_RUN_PATTERN).sub(text, "#", true)
	text = _get_regex(_DIGITS_PATTERN).sub(text, "#", true)
	text = _get_regex(_WHITESPACE_PATTERN).sub(text, " ", true)
	return text


## Returns the signature of the given first error lines.
static func compute_signature(lines: PackedStringArray) -> String:
	var normalized := PackedStringArray()
	for line in lines:
		normalized.append(normalize_for_signature(line))
	return "\n".join(normalized).sha256_text().left(SIGNATURE_LENGTH)


## Returns the newest previous-session log name in file_names, or
## "" when there is none. The names embed a fixed-width local
## timestamp, so the newest sorts last.
static func find_latest_previous_log(
	file_names: PackedStringArray,
) -> String:
	var pattern := _get_regex(PREVIOUS_LOG_PATTERN)
	var latest := ""
	for file_name in file_names:
		if pattern.search(file_name) != null and file_name > latest:
			latest = file_name
	return latest


## Looks for a Godot crash in log text. Returns {} when there is
## none. Otherwise returns:
##   message: the crash line, from the marker on.
##   signature_lines: the crash line, then up to 8 backtrace
##     frames (script frames when the log has them).
##   context_lines: up to 30 lines before the crash line.
##   block_lines: up to 50 lines from the crash line on.
static func find_crash(log_text: String) -> Dictionary:
	var lines := log_text.split("\n")
	for index in lines.size():
		for marker in CRASH_MARKERS:
			var at := lines[index].find(marker)
			if at >= 0:
				return _describe_crash(
					lines, index, lines[index].substr(at).strip_edges())
	return {}


## Joins a crash's lines into an excerpt of at most max_length
## characters. The crash block comes first in priority; context
## lines before it are kept, nearest first, while they fit.
static func build_crash_excerpt(
	context_lines: PackedStringArray,
	block_lines: PackedStringArray,
	max_length: int,
) -> String:
	var kept := PackedStringArray()
	var length := 0
	for line in block_lines:
		if length + line.length() + 1 > max_length:
			break
		kept.append(line)
		length += line.length() + 1
	for index in range(context_lines.size() - 1, -1, -1):
		var line := context_lines[index]
		if length + line.length() + 1 > max_length:
			break
		kept.insert(0, line)
		length += line.length() + 1
	return "\n".join(kept)


## Returns the last lines of text that fit in max_length
## characters, never starting mid-line.
static func build_tail_excerpt(text: String, max_length: int) -> String:
	var lines := text.strip_edges(false, true).split("\n")
	var kept := PackedStringArray()
	var length := 0
	for index in range(lines.size() - 1, -1, -1):
		var line := lines[index]
		if length + line.length() + 1 > max_length:
			break
		kept.insert(0, line)
		length += line.length() + 1
	return "\n".join(kept).strip_edges()


## Returns the build marker line CrashReporter prints at startup.
static func format_build_marker(
	build: String,
	version: String,
	protocol_version: int,
) -> String:
	return "%s%s version=%s protocol=%d" % [
		BUILD_MARKER_PREFIX,
		build,
		version,
		protocol_version,
	]


## Reads the build marker from a log. Returns {} when there is
## none, else {"build": String, "version": String, "protocol": int}.
static func parse_build_marker(log_text: String) -> Dictionary:
	var found := _get_regex(_BUILD_MARKER_PATTERN).search(log_text)
	if found == null:
		return {}
	return {
		"build": found.get_string(1),
		"version": found.get_string(2),
		"protocol": int(found.get_string(3)),
	}


## Whether version is a game version the runtime accepts.
static func is_valid_version(version: String) -> bool:
	return _get_regex(_VERSION_PATTERN).search(version) != null


## Returns the platform this build runs on, in the same words the
## matchmaker uses: web, windows, linux, macos, android, ios.
static func get_platform_tag() -> String:
	if OS.has_feature("web"):
		return "web"
	match OS.get_name():
		"Windows":
			return "windows"
		"macOS":
			return "macos"
		"Linux":
			return "linux"
		"Android":
			return "android"
		"iOS":
			return "ios"
		"FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return "bsd"
	return "other"


## Returns the operating system and its version, such as
## "Windows 10.0.26300", or "Web on Android" in a browser.
static func get_os_description() -> String:
	var description := OS.get_name()
	if OS.has_feature("web"):
		for feature: String in _WEB_HOST_FEATURES:
			if OS.has_feature(feature):
				description = "Web on %s" % _WEB_HOST_FEATURES[feature]
				break
	else:
		var version := OS.get_version().strip_edges()
		if not version.is_empty():
			description += " " + version
	description = _get_regex("[\\x00-\\x1f\\x7f]").sub(
		description, " ", true).strip_edges()
	return description.left(_MAX_OS_DESCRIPTION_LENGTH)


static func _describe_crash(
	lines: PackedStringArray,
	index: int,
	crash_line: String,
) -> Dictionary:
	var block_end := mini(lines.size(), index + _CRASH_BLOCK_LINES)
	var frame_regex := _get_regex(_FRAME_PATTERN)
	var engine_frames := PackedStringArray()
	var script_frames := PackedStringArray()
	var is_in_script_backtrace := false
	for line_index in range(index + 1, block_end):
		var line := lines[line_index]
		if line.contains(_SCRIPT_BACKTRACE_HEADER):
			is_in_script_backtrace = true
			continue
		if frame_regex.search(line) == null:
			continue
		if is_in_script_backtrace:
			script_frames.append(line.strip_edges())
		else:
			engine_frames.append(line.strip_edges())
	var frames := engine_frames
	if not script_frames.is_empty():
		frames = script_frames
	var signature_lines := PackedStringArray([crash_line])
	signature_lines.append_array(frames.slice(0, _SIGNATURE_FRAME_COUNT))
	return {
		"message": crash_line,
		"signature_lines": signature_lines,
		"context_lines": lines.slice(
			maxi(0, index - _CRASH_CONTEXT_LINES), index),
		"block_lines": lines.slice(index, block_end),
	}


static func _get_redaction_regexes() -> Array[RegEx]:
	if _redaction_regexes.is_empty():
		for rule: Array in _REDACTION_RULES:
			_redaction_regexes.append(
				RegEx.create_from_string(str(rule[0])))
	return _redaction_regexes


static func _get_regex(pattern: String) -> RegEx:
	if not _regexes_by_pattern.has(pattern):
		_regexes_by_pattern[pattern] = RegEx.create_from_string(pattern)
	return _regexes_by_pattern[pattern]
