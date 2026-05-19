class_name WebDebugWatchdog
extends Node
## Web-only debug watchdog. In a debug build, captures
## breadcrumbs and slow-frame snapshots to browser
## localStorage so they survive a wedged main thread (a
## GDScript infinite loop or pathological recursion that
## freezes the DevTools console).
##
## After a hang, kill the tab, reopen the page, and from the
## DevTools console run:
##
##     JSON.parse(localStorage.getItem(
##         'hopnbop.debug.dumps'))
##     JSON.parse(localStorage.getItem(
##         'hopnbop.debug.breadcrumbs'))
##
## Or call G.web_debug_watchdog.clear() to wipe the stash.
##
## Disabled outside web debug builds (no-op API).
##
## Usage:
##
##     G.web_debug_watchdog.breadcrumb(
##         "game_panel.end_match.start")
##     G.web_debug_watchdog.breadcrumb(
##         "match_state.players_updated",
##         {"player_count": players.size()})
##
## Place breadcrumbs at suspected loop / hang sites. They
## are flushed to localStorage synchronously on each call,
## so keep them at coarse boundaries, not in hot loops.
##
## === Active investigation (clean up when resolved) ===
##
## Breadcrumbs are currently planted around the end-of-
## match flow to diagnose an intermittent web-client
## infinite loop. Every planted call carries the marker
## `FIXME(end-of-match-debug)` on the line where the
## expression starts. To locate and remove:
##
##     rg "FIXME\(end-of-match-debug\)"
##
## Delete each entire `G.web_debug_watchdog.breadcrumb(...)`
## expression (multi-line variants span 3-7 lines from the
## marker line through the closing `)`). Once the
## investigation closes, also remove this block.


# Frames slower than this trigger a snapshot dump. The web
# client targets ~16ms / frame; 200ms is "noticeably
# hitched" but well below a hang.
const _SLOW_FRAME_THRESHOLD_MS := 200
# How many recent breadcrumbs to retain.
const _MAX_BREADCRUMBS := 64
# How many recent slow-frame snapshots to retain.
const _MAX_DUMPS := 32

const _LS_BREADCRUMBS_KEY := "hopnbop.debug.breadcrumbs"
const _LS_DUMPS_KEY := "hopnbop.debug.dumps"


var _enabled := false
var _last_frame_msec := 0
# In-memory mirrors of the localStorage arrays so we don't
# parse-modify-restringify the stash on every breadcrumb.
var _breadcrumbs: Array = []
var _dumps: Array = []


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enabled = (
		OS.is_debug_build()
		and OS.has_feature("web")
	)
	if not _enabled:
		set_process(false)
		return
	_last_frame_msec = Time.get_ticks_msec()
	# Mark the new session so users can tell where one run
	# ends and the next begins in the persistent stash.
	breadcrumb("web_debug_watchdog.session_start", {
		"iso_timestamp": Time.get_datetime_string_from_system(
			true),
	})


func _process(_delta: float) -> void:
	# Use wall-clock delta, not the engine's `_delta` (which
	# is clamped and useless for hitch detection).
	var now := Time.get_ticks_msec()
	var frame_delta_ms := now - _last_frame_msec
	_last_frame_msec = now
	if frame_delta_ms >= _SLOW_FRAME_THRESHOLD_MS:
		_dump("slow_frame", {
			"frame_delta_ms": frame_delta_ms,
		})


## Drop a breadcrumb with optional context. Flushes to
## localStorage synchronously. No-op outside web debug
## builds.
func breadcrumb(
	label: String,
	data: Dictionary = {},
) -> void:
	if not _enabled:
		return
	_breadcrumbs.append({
		"timestamp_msec": Time.get_ticks_msec(),
		"label": label,
		"data": data,
	})
	if _breadcrumbs.size() > _MAX_BREADCRUMBS:
		_breadcrumbs = _breadcrumbs.slice(
			_breadcrumbs.size() - _MAX_BREADCRUMBS,
		)
	_flush(_LS_BREADCRUMBS_KEY, _breadcrumbs)


## Force a snapshot dump with a custom reason. Use when you
## suspect you've entered a bad code path but the frame
## hasn't yet stalled long enough to auto-dump.
func dump_now(reason: String) -> void:
	if not _enabled:
		return
	_dump(reason, {})


## Wipe both localStorage keys. Call from GDScript or by
## running `localStorage.clear()` in DevTools.
func clear() -> void:
	if not _enabled:
		return
	_breadcrumbs.clear()
	_dumps.clear()
	JavaScriptBridge.eval(
		"localStorage.removeItem('%s');"
		% _LS_BREADCRUMBS_KEY)
	JavaScriptBridge.eval(
		"localStorage.removeItem('%s');"
		% _LS_DUMPS_KEY)


func _dump(reason: String, extra: Dictionary) -> void:
	var snapshot := {
		"timestamp_msec": Time.get_ticks_msec(),
		"iso_timestamp": Time.get_datetime_string_from_system(
			true),
		"reason": reason,
		"server_frame_index": Netcode.server_frame_index,
		"is_server": Netcode.is_server,
		# get_stack() returns [] in release builds; we're
		# gated on is_debug_build() so it's populated here.
		"stack": get_stack(),
		"breadcrumbs": _breadcrumbs.duplicate(),
	}
	for k in extra:
		snapshot[k] = extra[k]
	_dumps.append(snapshot)
	if _dumps.size() > _MAX_DUMPS:
		_dumps = _dumps.slice(
			_dumps.size() - _MAX_DUMPS,
		)
	_flush(_LS_DUMPS_KEY, _dumps)
	# Also emit a console.warn so the dump shows up in
	# DevTools once the main thread is responsive again.
	JavaScriptBridge.eval(
		"console.warn('[WebDebugWatchdog]', %s);"
		% _to_js_string(JSON.stringify(snapshot)),
	)


func _flush(key: String, value: Array) -> void:
	JavaScriptBridge.eval(
		"localStorage.setItem('%s', %s);" % [
			key,
			_to_js_string(JSON.stringify(value)),
		],
	)


# Wraps a string for safe embedding as a single-quoted JS
# literal. Must escape backslashes first so subsequent
# replacements don't double-escape themselves.
func _to_js_string(s: String) -> String:
	var escaped := s
	escaped = escaped.replace("\\", "\\\\")
	escaped = escaped.replace("'", "\\'")
	escaped = escaped.replace("\n", "\\n")
	escaped = escaped.replace("\r", "\\r")
	return "'" + escaped + "'"
