class_name CrashReporter
extends Node
## Sends crash and error reports to the snoringcat-platform
## runtime's `crash_report` RPC (runtime/crash_report.go).
##
## Two sources feed it: errors logged through G.log.error (which
## G.log.ensure and G.log.check route through), and a Godot crash
## found in the previous session's log at boot. Each report is
## redacted, given a signature (a hash of its first error lines),
## and written to a small queue file in user:// before any send is
## tried. The queue is flushed whenever this process can
## authenticate the RPC: a player needs a live Nakama session
## (anonymous players count, but only get one once they go
## online), and a dedicated server needs NAKAMA_HTTP_KEY in its
## environment. An entry leaves the queue when the server accepts
## it, rejects it as invalid, fails _MAX_ATTEMPTS times, or turns
## _MAX_AGE_SEC old. A crash's log is marked handled only then.
##
## A report carries no account, device, or player identifiers, and
## its message and log excerpt are redacted (see
## CrashReportText.redact) before they are queued.
##
## Editor builds (development and the agent harness) keep their
## own queue file and never send unless HOPNBOP_SEND_CRASH_REPORTS
## is 1, so development errors stay out of production's reports.

## Emitted when the runtime accepts a report.
signal report_accepted(signature: String)

enum _SendOutcome {
	ACCEPTED,
	REJECTED,
	RATE_LIMITED,
	FAILED,
}

const _RPC_ID := "crash_report"
const _HTTP_KEY_ENVIRONMENT := "NAKAMA_HTTP_KEY"
const _SEND_FROM_EDITOR_ENVIRONMENT := "HOPNBOP_SEND_CRASH_REPORTS"
const _QUEUE_PATH := "user://crash_reports.json"
const _EDITOR_QUEUE_PATH := "user://crash_reports_editor.json"
const _LOG_DIRECTORY := "user://logs"
const _CURRENT_LOG_FILE := "godot.log"
const _ROLE_CLIENT := "client"
const _ROLE_SERVER := "server"
const _BUILD_EDITOR := "editor"
const _BUILD_EXPORT := "export"
const _CRASH_MESSAGE_PREFIX := "Previous session crashed: "
const _QUEUE_FORMAT_VERSION := 1
## Queue bounds. A full queue makes room by dropping its oldest
## error report; a crash report is only displaced by a newer crash.
const _MAX_QUEUE_SIZE := 5
## Reports queued per run, and each signature at most once. The
## runtime allows a player the same five per hour.
const _MAX_REPORTS_PER_RUN := 5
const _MAX_ATTEMPTS := 5
const _MAX_AGE_SEC := 7 * 24 * 60 * 60
const _MAX_HANDLED_LOGS := 10
const _FLUSH_INTERVAL_SEC := 60.0
const _RATE_LIMITED_PAUSE_SEC := 600.0
## A failed send pauses flushing for this long, doubled per failed
## attempt of that report, up to the cap.
const _RETRY_PAUSE_SEC := 60.0
const _MAX_RETRY_PAUSE_SEC := 3600.0
const _MAX_MESSAGE_LENGTH := 500
const _MAX_EXCERPT_LENGTH := 6000
## The runtime rejects payloads over 16 KiB. The excerpt shrinks
## until the encoded payload fits under this.
const _MAX_PAYLOAD_BYTES := 15000
const _EXCERPT_SHRINK_FACTOR := 0.75
const _CURRENT_LOG_TAIL_BYTES := 16384
const _PREVIOUS_LOG_MAX_BYTES := 1048576
const _ERROR_EXCERPT_LINES := 40
const _NEWLINE_BYTE := 10
const _MSEC_PER_SEC := 1000.0
## gRPC codes the runtime returns. INVALID_ARGUMENT is final: the
## same report would be rejected again.
const _GRPC_INVALID_ARGUMENT := 3
const _GRPC_RESOURCE_EXHAUSTED := 8

## "editor" when running from an editor build, else "export".
## Decides the queue file and whether reports are sent.
var build_kind: String
## Whether this build may send reports. Editor builds only queue,
## unless HOPNBOP_SEND_CRASH_REPORTS=1.
var is_sending_allowed: bool
## The queue file this build uses.
var queue_path: String
## Where Godot writes its logs. Tests point it at fixtures.
var log_directory := _LOG_DIRECTORY
## "client" or "server" pins the role. Empty derives it from
## Netcode.is_server when a report is built (Netcode decides the
## role after this node is created).
var forced_role := ""
## RPC sends attempted by this process. Tests and the agent harness
## read it.
var send_attempt_count := 0

var _entries: Array[Dictionary] = []
var _handled_logs: Array[String] = []
var _is_loaded := false
var _reports_this_run := 0
var _signatures_this_run := {}
var _is_flushing := false
var _paused_until_msec := 0


func _init() -> void:
	build_kind = _BUILD_EDITOR if OS.has_feature("editor") else (
		_BUILD_EXPORT)
	is_sending_allowed = (
		build_kind == _BUILD_EXPORT
		or OS.get_environment(_SEND_FROM_EDITOR_ENVIRONMENT) == "1"
	)
	queue_path = (
		_EDITOR_QUEUE_PATH if build_kind == _BUILD_EDITOR else _QUEUE_PATH)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# GUT tests build their own reporters with fixture paths. This
	# boot-time one must not read the test process's logs.
	if TestEnvironmentDetector.is_running_in_test_env(self):
		return
	print(CrashReportText.format_build_marker(
		build_kind, _get_game_version(), _get_protocol_version()))
	var auth: PlatformAuthApiClient = Platform.auth
	if auth != null:
		auth.auth_completed.connect(_on_session_maybe_ready)
		auth.guest_jwt_obtained.connect(_on_session_maybe_ready)
	var timer := Timer.new()
	timer.name = "FlushTimer"
	timer.wait_time = _FLUSH_INTERVAL_SEC
	timer.autostart = true
	timer.timeout.connect(flush)
	add_child(timer)
	_start.call_deferred()


## Queues a report for an error logged through G.log.error, then
## tries to send it. Never logs through G.log itself, which would
## loop back here.
func report_crash(error_message: String, is_fatal := false) -> void:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		report_crash.call_deferred(error_message, is_fatal)
		return
	_ensure_loaded()
	if not _can_queue() or _reports_this_run >= _MAX_REPORTS_PER_RUN:
		return
	var account_values := _get_account_values()
	var message := CrashReportText.redact(
		CrashReportText.first_line(error_message), account_values)
	if message.is_empty():
		return
	var signature := CrashReportText.compute_signature(
		PackedStringArray([message]))
	if _signatures_this_run.has(signature):
		return
	_signatures_this_run[signature] = true
	_reports_this_run += 1
	var excerpt := CrashReportText.redact(
		_read_current_log_tail(), account_values)
	_enqueue(
		_build_payload(
			message,
			signature,
			excerpt,
			_get_game_version(),
			_get_protocol_version(),
		),
		"",
	)
	# A fatal error quits right after logging. A send cut off by the
	# exit could still store the report on the server and leave it
	# queued here, and the next run would send it twice, so its
	# report waits for the next run instead.
	if not is_fatal:
		flush()


## Looks for a Godot crash in the previous session's log and queues
## a report for it. Godot copies the last godot.log to
## godot<local time>.log at startup, so the newest such file is the
## previous session. Each log is reported at most once.
func scan_previous_session_logs() -> void:
	_ensure_loaded()
	if not _can_queue() or not DirAccess.dir_exists_absolute(log_directory):
		return
	var log_name := CrashReportText.find_latest_previous_log(
		DirAccess.get_files_at(log_directory))
	if (
		log_name.is_empty()
		or _handled_logs.has(log_name)
		or _has_entry_for_log(log_name)
	):
		return
	var text := _read_file_tail(
		log_directory.path_join(log_name), _PREVIOUS_LOG_MAX_BYTES)
	var crash := CrashReportText.find_crash(text)
	if crash.is_empty():
		return
	# The editor and exported builds share user://. A crash belongs
	# to the queue of the build that crashed. A log without the
	# marker crashed before this node started; count it as export.
	var marker := CrashReportText.parse_build_marker(text)
	if str(marker.get("build", _BUILD_EXPORT)) != build_kind:
		return
	var version := str(marker.get("version", _get_game_version()))
	if not CrashReportText.is_valid_version(version):
		version = _get_game_version()
	var protocol_version := int(
		marker.get("protocol", _get_protocol_version()))
	var account_values := _get_account_values()
	var signature_lines := PackedStringArray()
	for line: String in crash.signature_lines:
		signature_lines.append(
			CrashReportText.redact(line, account_values))
	var excerpt := CrashReportText.redact(
		CrashReportText.build_crash_excerpt(
			crash.context_lines,
			crash.block_lines,
			_MAX_EXCERPT_LENGTH,
		),
		account_values,
	)
	_enqueue(
		_build_payload(
			CrashReportText.redact(
				_CRASH_MESSAGE_PREFIX + str(crash.message),
				account_values),
			CrashReportText.compute_signature(signature_lines),
			excerpt,
			version,
			protocol_version,
		),
		log_name,
	)


## Sends queued reports while this process can authenticate them.
## Safe to call often: it returns at once while a flush is running,
## while sending is paused after a failure, or when nothing is
## sendable.
func flush() -> void:
	_ensure_loaded()
	if (
		_is_flushing
		or not is_sending_allowed
		or Time.get_ticks_msec() < _paused_until_msec
	):
		return
	_is_flushing = true
	_drop_expired_entries()
	var role := _get_role()
	while true:
		var entry := _find_entry_for_role(role)
		if entry.is_empty():
			break
		var credentials := _get_credentials(role)
		if credentials.is_empty():
			break
		var outcome := await _send(entry.payload, credentials)
		# The queue may have changed while the request was out.
		var index := _find_entry_index(str(entry.id))
		if outcome == _SendOutcome.ACCEPTED:
			if index >= 0:
				_remove_entry(index)
			report_accepted.emit(str(entry.payload.signature))
			continue
		if outcome == _SendOutcome.REJECTED:
			if index >= 0:
				_remove_entry(index)
			continue
		if outcome == _SendOutcome.RATE_LIMITED:
			_pause(_RATE_LIMITED_PAUSE_SEC)
			break
		var attempts := 0
		if index >= 0:
			attempts = int(_entries[index].attempts) + 1
			_entries[index].attempts = attempts
			if attempts >= _MAX_ATTEMPTS:
				_remove_entry(index)
			else:
				_save_queue()
		_pause(minf(
			_RETRY_PAUSE_SEC * pow(2.0, maxi(attempts - 1, 0)),
			_MAX_RETRY_PAUSE_SEC,
		))
		break
	_is_flushing = false


## Returns copies of the queued entries, oldest first. Each has id,
## created_at, attempts, source_log ("" for an error report), and
## payload (the RPC payload).
func get_queued_entries() -> Array[Dictionary]:
	_ensure_loaded()
	var copies: Array[Dictionary] = []
	for entry in _entries:
		copies.append(entry.duplicate(true))
	return copies


## Returns the names of previous-session logs whose crash report
## has left the queue.
func get_handled_logs() -> Array[String]:
	_ensure_loaded()
	return _handled_logs.duplicate()


func _start() -> void:
	scan_previous_session_logs()
	flush()


func _on_session_maybe_ready(success: bool, _error: String) -> void:
	if success:
		flush()


## A dedicated server without the HTTP key can never send, so it
## queues nothing. A player's report waits for a session.
func _can_queue() -> bool:
	if _get_role() == _ROLE_SERVER:
		return not OS.get_environment(_HTTP_KEY_ENVIRONMENT).is_empty()
	return true


func _get_role() -> String:
	if not forced_role.is_empty():
		return forced_role
	return _ROLE_SERVER if Netcode.is_server else _ROLE_CLIENT


func _get_game_version() -> String:
	var version := str(ProjectSettings.get_setting(
		"application/config/version", "0.0.0"))
	return version if CrashReportText.is_valid_version(version) else (
		"0.0.0")


func _get_protocol_version() -> int:
	return int(ProjectSettings.get_setting(
		"application/config/protocol_version", 0))


func _get_game_id() -> String:
	if not Platform.game_id.is_empty():
		return Platform.game_id
	return str(ProjectSettings.get_setting(
		"application/config/game_id", ""))


## Returns the signed-in account's own values, which redaction
## replaces wherever they appear.
func _get_account_values() -> Array[String]:
	var values: Array[String] = []
	var store = Platform.token_store
	if store == null:
		return values
	for value in [
		store.player_id,
		store.display_name,
		store.local_player_id,
		store.jwt_token,
		store.refresh_token,
		store.profile_image_url,
	]:
		if not str(value).is_empty():
			values.append(str(value))
	var session := Platform.build_session_from_store()
	if session != null and not session.username.is_empty():
		values.append(session.username)
	return values


## Returns how this process can authenticate a report right now:
## {"session": NakamaSession} for a player with a live session,
## {"http_key": String} for a dedicated server, or {} when it can't
## yet.
func _get_credentials(role: String) -> Dictionary:
	if role == _ROLE_SERVER:
		var http_key := OS.get_environment(_HTTP_KEY_ENVIRONMENT)
		return {} if http_key.is_empty() else {"http_key": http_key}
	var session := Platform.build_session_from_store()
	if session == null or not session.is_valid() or session.is_expired():
		return {}
	return {"session": session}


func _send(payload: Dictionary, credentials: Dictionary) -> _SendOutcome:
	send_attempt_count += 1
	var body := JSON.stringify(_get_typed_payload(payload))
	var client: NakamaClient = Platform.get_nakama_client()
	var result: NakamaAsyncResult
	if credentials.has("session"):
		result = await client.rpc_async(
			credentials.session, _RPC_ID, body)
	else:
		result = await client.rpc_async_with_key(
			credentials.http_key, _RPC_ID, body)
	if result == null:
		return _SendOutcome.FAILED
	if not result.is_exception():
		return _SendOutcome.ACCEPTED
	match result.get_exception().grpc_status_code:
		_GRPC_INVALID_ARGUMENT:
			return _SendOutcome.REJECTED
		_GRPC_RESOURCE_EXHAUSTED:
			return _SendOutcome.RATE_LIMITED
	return _SendOutcome.FAILED


## Returns the payload with every field at the type the runtime
## expects. A payload read back from the queue file has its numbers
## as floats (Godot's JSON parser makes every number a float), and
## the runtime rejects a protocol_version of 2.0.
func _get_typed_payload(payload: Dictionary) -> Dictionary:
	var typed := {}
	for field: String in payload:
		typed[field] = str(payload[field])
	typed.protocol_version = int(payload.get("protocol_version", 0))
	return typed


func _build_payload(
	message: String,
	signature: String,
	excerpt: String,
	version: String,
	protocol_version: int,
) -> Dictionary:
	var payload := {
		"game_id": _get_game_id(),
		"game_version": version,
		"protocol_version": protocol_version,
		"platform": CrashReportText.get_platform_tag(),
		"os": CrashReportText.get_os_description(),
		"role": _get_role(),
		"message": message.left(_MAX_MESSAGE_LENGTH),
		"signature": signature,
		"log_excerpt": excerpt.right(_MAX_EXCERPT_LENGTH),
	}
	while (
		JSON.stringify(payload).to_utf8_buffer().size() > _MAX_PAYLOAD_BYTES
		and not str(payload.log_excerpt).is_empty()
	):
		var excerpt_text := str(payload.log_excerpt)
		payload.log_excerpt = excerpt_text.right(
			int(excerpt_text.length() * _EXCERPT_SHRINK_FACTOR))
	return payload


func _enqueue(payload: Dictionary, source_log: String) -> void:
	if _entries.size() >= _MAX_QUEUE_SIZE:
		var victim := _find_eviction_index(not source_log.is_empty())
		if victim < 0:
			return
		_remove_entry(victim, false)
	_entries.append({
		"id": "%d-%d" % [Time.get_ticks_usec(), randi()],
		"created_at": int(Time.get_unix_time_from_system()),
		"attempts": 0,
		"source_log": source_log,
		"payload": payload,
	})
	_save_queue()


## Returns the index of the entry to drop for a new one, or -1 to
## drop the new one instead.
func _find_eviction_index(is_new_entry_crash: bool) -> int:
	for index in _entries.size():
		if str(_entries[index].source_log).is_empty():
			return index
	return 0 if is_new_entry_crash else -1


func _find_entry_for_role(role: String) -> Dictionary:
	for entry in _entries:
		if str(entry.payload.get("role", "")) == role:
			return entry
	return {}


func _find_entry_index(entry_id: String) -> int:
	for index in _entries.size():
		if str(_entries[index].id) == entry_id:
			return index
	return -1


func _has_entry_for_log(log_name: String) -> bool:
	for entry in _entries:
		if str(entry.source_log) == log_name:
			return true
	return false


## Removes an entry for good. A crash's log goes on the handled
## list, so the scan doesn't report it again.
func _remove_entry(index: int, should_save := true) -> void:
	var source_log := str(_entries[index].source_log)
	_entries.remove_at(index)
	if not source_log.is_empty() and not _handled_logs.has(source_log):
		_handled_logs.append(source_log)
		while _handled_logs.size() > _MAX_HANDLED_LOGS:
			_handled_logs.remove_at(0)
	if should_save:
		_save_queue()


func _drop_expired_entries() -> void:
	var now := int(Time.get_unix_time_from_system())
	var index := _entries.size() - 1
	var did_drop := false
	while index >= 0:
		if now - int(_entries[index].created_at) > _MAX_AGE_SEC:
			_remove_entry(index, false)
			did_drop = true
		index -= 1
	if did_drop:
		_save_queue()


func _pause(seconds: float) -> void:
	_paused_until_msec = Time.get_ticks_msec() + int(
		seconds * _MSEC_PER_SEC)


func _ensure_loaded() -> void:
	if _is_loaded:
		return
	_is_loaded = true
	_entries.clear()
	_handled_logs.clear()
	if not FileAccess.file_exists(queue_path):
		return
	var data: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(queue_path))
	if not data is Dictionary:
		return
	for entry: Variant in data.get("entries", []):
		if _is_valid_entry(entry) and _entries.size() < _MAX_QUEUE_SIZE:
			_entries.append(entry)
	for log_name: Variant in data.get("handled_logs", []):
		if log_name is String and _handled_logs.size() < _MAX_HANDLED_LOGS:
			_handled_logs.append(log_name)


func _is_valid_entry(entry: Variant) -> bool:
	return (
		entry is Dictionary
		and entry.get("id") is String
		and entry.get("source_log") is String
		and entry.get("payload") is Dictionary
		and _is_number(entry.get("created_at"))
		and _is_number(entry.get("attempts"))
	)


func _is_number(value: Variant) -> bool:
	return value is int or value is float


## Writes the queue to a temporary file, then renames it over the
## queue, so a crash mid-write can't leave a torn file.
func _save_queue() -> void:
	var temporary_path := queue_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"version": _QUEUE_FORMAT_VERSION,
		"entries": _entries,
		"handled_logs": _handled_logs,
	}))
	file.close()
	DirAccess.rename_absolute(temporary_path, queue_path)


## Returns the last lines of this session's godot.log, which hold
## the error that is being reported.
func _read_current_log_tail() -> String:
	var path := log_directory.path_join(_CURRENT_LOG_FILE)
	if not FileAccess.file_exists(path):
		return ""
	var lines := _read_file_tail(path, _CURRENT_LOG_TAIL_BYTES).split("\n")
	var first := maxi(0, lines.size() - _ERROR_EXCERPT_LINES)
	return CrashReportText.build_tail_excerpt(
		"\n".join(lines.slice(first)), _MAX_EXCERPT_LENGTH)


## Returns at most max_bytes from the end of a file, starting after
## a newline so the text never begins mid-line or mid-character.
func _read_file_tail(path: String, max_bytes: int) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var length := file.get_length()
	var start := maxi(0, length - max_bytes)
	file.seek(start)
	var bytes := file.get_buffer(length - start)
	file.close()
	if start > 0:
		var newline := bytes.find(_NEWLINE_BYTE)
		bytes = bytes.slice(newline + 1) if newline >= 0 else (
			PackedByteArray())
	return bytes.get_string_from_utf8()
