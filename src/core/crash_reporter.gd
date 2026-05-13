class_name CrashReporter
extends Node
## Sends crash and error reports to the Nakama runtime via the
## `crash_report` RPC. Fire-and-forget. Does not block gameplay
## or require authentication beyond a normal session token.


const _MAX_MESSAGE_LENGTH := 4096
const _COOLDOWN_SEC := 5.0
const _MAX_REPORTS_PER_SESSION := 20
const _LOG_DIRECTORY := "user://logs/"
const _PREVIOUS_LOG_PREFIX := "godot_"
const _CRASH_MARKER := "handle_crash: Program crashed"
const _REPORTED_MARKER_PATH := "user://logs/.crash_reported"

var _report_count := 0
var _last_report_time := 0.0
var _in_flight := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Check for crashes from the previous session after the
	# current frame to avoid blocking startup.
	_check_previous_session_crash.call_deferred()


func report_crash(
	error_message: String,
	is_fatal := false,
) -> void:
	# Skip in offline / preview mode (no Nakama session to
	# authenticate the RPC). Use Object.get() to avoid the
	# cyclic-reference parser failure on web/server exports.
	# See CLAUDE.md "Web Build Cyclic-Reference Parser Failures".
	var token_store = G.get("auth_token_store")
	if (
		not is_instance_valid(token_store)
		or token_store.player_id.is_empty()
	):
		return
	# Rate limiting.
	if _report_count >= _MAX_REPORTS_PER_SESSION:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if (
		_last_report_time > 0.0
		and now - _last_report_time < _COOLDOWN_SEC
	):
		return
	if _in_flight:
		return

	_report_count += 1
	_last_report_time = now

	if error_message.length() > _MAX_MESSAGE_LENGTH:
		error_message = error_message.left(_MAX_MESSAGE_LENGTH)

	_send_async(error_message, is_fatal)


func _send_async(
	error_message: String,
	is_fatal: bool,
) -> void:
	_in_flight = true
	var session = Platform.build_session_from_store()
	if session == null:
		_in_flight = false
		return
	var payload := _build_payload(error_message, is_fatal)
	# Fire-and-forget RPC. We don't act on errors — that's the
	# whole point of a crash reporter that can't itself crash.
	var _result = await Platform.get_nakama_client().rpc_async(
		session, "crash_report", JSON.stringify(payload))
	_in_flight = false


func _build_payload(
	error_message: String,
	is_fatal: bool,
) -> Dictionary:
	var version: String = ProjectSettings.get_setting(
		"application/config/version", "unknown")
	var player_id := ""
	if (
		is_instance_valid(Platform.token_store)
		and not Platform.token_store.player_id.is_empty()
	):
		player_id = Platform.token_store.player_id
	var render_fps := 0.0
	var physics_fps := 0.0
	var network_ping_ms := 0.0
	if is_instance_valid(Netcode.perf_tracker):
		render_fps = Netcode.perf_tracker._current_render_fps
		physics_fps = Netcode.perf_tracker._current_physics_fps
		network_ping_ms = (
			Netcode.perf_tracker._current_network_ping_ms)
	var utc := Time.get_datetime_dict_from_system(true)
	var timestamp_utc := "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		utc.year, utc.month, utc.day,
		utc.hour, utc.minute, utc.second,
	]
	return {
		"error_message": error_message,
		"is_fatal": is_fatal,
		"game_version": version,
		"operating_system": OS.get_name(),
		"player_id": player_id,
		"is_server": Netcode.is_server,
		"server_frame_index": Netcode.server_frame_index,
		"render_fps": render_fps,
		"physics_fps": physics_fps,
		"network_ping_ms": network_ping_ms,
		"timestamp_utc": timestamp_utc,
	}


func _check_previous_session_crash() -> void:
	var dir := DirAccess.open(_LOG_DIRECTORY)
	if not dir:
		return
	var last_reported := ""
	if FileAccess.file_exists(_REPORTED_MARKER_PATH):
		var marker := FileAccess.open(
			_REPORTED_MARKER_PATH, FileAccess.READ)
		if marker:
			last_reported = marker.get_as_text().strip_edges()
			marker.close()
	var latest_log := ""
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if (
			file_name.begins_with(_PREVIOUS_LOG_PREFIX)
			and file_name.ends_with(".log")
			and file_name > latest_log
		):
			latest_log = file_name
		file_name = dir.get_next()
	dir.list_dir_end()
	if latest_log.is_empty():
		return
	if latest_log == last_reported:
		return
	var crash_text := _scan_log_for_crash(
		_LOG_DIRECTORY + latest_log)
	if crash_text.is_empty():
		return
	report_crash(crash_text, true)
	var marker := FileAccess.open(
		_REPORTED_MARKER_PATH, FileAccess.WRITE)
	if marker:
		marker.store_string(latest_log)
		marker.close()


func _scan_log_for_crash(log_path: String) -> String:
	var file := FileAccess.open(log_path, FileAccess.READ)
	if not file:
		return ""
	var content := file.get_as_text()
	file.close()
	var crash_index := content.find(_CRASH_MARKER)
	if crash_index == -1:
		return ""
	var crash_text := content.substr(crash_index)
	if crash_text.length() > _MAX_MESSAGE_LENGTH:
		crash_text = crash_text.left(_MAX_MESSAGE_LENGTH)
	return "Previous session crash:\n" + crash_text
