extends Node
## Agent harness driver: boots the game for one process of a scenario
## and runs that process's steps. agent_bootstrap.gd loads it and calls
## configure() before any autoload enters the tree.
##
## Everything a run produces goes to --agent-out: screenshots
## (<name>.png), state snapshots (state-<name>.json), and result.json.
## The last line a finished run prints is `AGENT_RESULT {...}`, the
## same JSON as result.json. See "Agent harness" in CLAUDE.md for the
## scenario format.

const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _RESULT_PREFIX := "AGENT_RESULT "
const _LOG_PREFIX := "[agent] "

## Every backend URL points here unless --agent-allow-network is given.
## Nothing listens on the discard port, so a request that slips past
## the settings overrides fails on this machine instead of reaching
## production.
const _BLACKHOLE_HOST := "127.0.0.1"
const _BLACKHOLE_PORT := 9
const _OFFLINE_KEY := "agent-harness-offline"
## Hosts --agent-backend may name: a local stack, never production.
const _LOOPBACK_HOSTS: Array[String] = ["127.0.0.1", "localhost", "::1"]
const _BACKEND_SCHEMES: Array[String] = ["http", "https"]
## The dev stack's server key (infra/dev/docker-compose.dev.yml), used
## when --agent-backend-key is not given.
const _DEV_SERVER_KEY := "defaultkey"

const _EXIT_OK := 0
const _EXIT_FAILED := 1
const _EXIT_HARNESS_ERROR := 2
const _EXIT_REFUSED := 3

const _MODES: Array[String] = ["offline", "level", "lobby", "match"]
## Used when a scenario has no "seed". "seed": null opts out.
const _DEFAULT_SEED := 1
const _DEFAULT_TIMEOUT_SEC := 60.0
## The server outlives its clients so that it never drops them first.
const _SERVER_EXTRA_TIMEOUT_SEC := 15.0
const _DEFAULT_WAIT_TIMEOUT_SEC := 30.0
const _DEFAULT_WAIT_SEC := 1.0
const _DEFAULT_TAP_HOLD_SEC := 0.1
## Main._ready positions preview windows a frame after it enters the
## tree. The harness geometry is re-applied once that has settled.
const _GEOMETRY_SETTLE_FRAMES := 5
## Frames the server keeps ENet alive after dropping its clients so
## they hear it.
const _DISCONNECT_FLUSH_FRAMES := 5
## Physics frames to wait before re-sending a held key that the engine
## released on its own, e.g. when the window loses focus.
const _KEY_REASSERT_FRAMES := 2
const _MAX_UI_LABELS := 40
const _ROUNDING_STEP := 0.01

const _ACTION_ALIASES := {
	"up": "move_up",
	"down": "move_down",
	"left": "move_left",
	"right": "move_right",
}
## Allowed keys per step type, on top of _COMMON_STEP_KEYS.
const _STEP_KEYS := {
	"wait": ["sec", "frames"],
	"wait_until": ["expr", "timeout_sec"],
	"wait_ready": ["timeout_sec"],
	"wait_match_start": ["timeout_sec"],
	"press": ["key", "keys", "player"],
	"release": ["key", "keys", "player"],
	"tap": ["key", "keys", "player", "hold_sec", "hold_frames"],
	"screenshot": ["name", "target"],
	"state": ["name"],
	"eval": ["expr", "name"],
	"call": ["node", "method", "args", "name"],
	"sign_in": ["timeout_sec"],
	"publish": ["name", "expr"],
	"wait_shared": ["name", "timeout_sec"],
	"assert": ["expr", "message"],
	"log": ["message"],
	"quit": [],
}
const _COMMON_STEP_KEYS: Array[String] = ["do", "fatal", "comment"]
## Variables every expression step can read. Expression cannot see
## engine singletons by name, so the useful ones are passed in too.
const _EXPRESSION_INPUTS: Array[String] = [
	"G",
	"Netcode",
	"Platform",
	"level",
	"match_state",
	"snapshots",
	"driver",
	"OS",
	"Engine",
	"Input",
	"Time",
	"shared",
]

var _scenario_path := ""
var _scenario: Dictionary = {}
var _process_spec: Dictionary = {}
var _process_name := ""
var _mode := ""
var _client_count := 1
var _out_dir := ""
var _sandbox_dir := ""
var _port := 0
var _window_rect := Rect2i()
var _has_window_rect := false
var _is_network_allowed := false
## A local Nakama (--agent-backend) the game talks to instead of the
## blackhole: {scheme, host, port}, empty when none was given.
var _backend: Dictionary = {}
var _backend_url := ""
var _backend_key := _DEV_SERVER_KEY
var _base_settings_path := ""
var _timeout_sec := _DEFAULT_TIMEOUT_SEC
var _steps: Array = []
var _is_seeded := true
## The scenario seed plus this process's --client number (0 for the
## server), so two clients do not draw identical random bunnies.
var _process_seed := 0
## Settings whose working-copy value differed from the committed one.
var _settings_reset: Array[String] = []

var _refusal := ""
var _config_error := ""
var _start_msec := 0
var _is_finished := false
var _current_step_index := -1
var _steps_run := 0
var _failures: Array[Dictionary] = []
var _warnings: Array[String] = []
var _screenshots: Array[String] = []
var _state_paths: Array[String] = []
var _snapshots: Dictionary = {}
var _evals: Dictionary = {}
## Values published by this or another process (publish /
## wait_shared steps), readable from expressions as `shared`.
var _shared: Dictionary = {}
## Dictionary<Key, int>: each held key and the physics frame it was
## last sent on.
var _held_keys: Dictionary = {}
var _key_reassert_count := 0


func _enter_tree() -> void:
	if _is_seeded:
		get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if _is_finished:
		return
	# The game quit on its own (close_app, a fatal check, ...).
	_is_finished = true
	_failures.append({
		"step": _current_step_index + 1,
		"do": "harness",
		"error": "the game quit before the scenario finished",
	})
	print(_RESULT_PREFIX + JSON.stringify(_build_result(_EXIT_FAILED)))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _refusal.is_empty():
		_finish(_EXIT_REFUSED, "refused: " + _refusal)
		return
	if _config_error.is_empty():
		_config_error = _check_role()
	if not _config_error.is_empty():
		_finish(_EXIT_HARNESS_ERROR, _config_error)
		return
	get_tree().create_timer(_timeout_sec).timeout.connect(
		_on_watchdog_timeout)
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	var frame := Engine.get_physics_frames()
	for key: Variant in _held_keys.keys():
		if Input.is_physical_key_pressed(key):
			continue
		if frame - int(_held_keys[key]) < _KEY_REASSERT_FRAMES:
			continue
		_send_key(key, true)
		_held_keys[key] = frame
		_key_reassert_count += 1


## Called by agent_bootstrap.gd from SceneTree._initialize, before any
## autoload has entered the tree. Everything that must precede
## G._enter_tree and G._ready happens here.
func configure() -> void:
	_start_msec = Time.get_ticks_msec()
	_config_error = _parse_arguments()
	if _config_error.is_empty():
		_config_error = _load_scenario()
	if not _out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_out_dir)
	# Safety comes first and is unconditional: even a refused or
	# misconfigured run boots the autoloads for a frame before it quits.
	_refusal = _check_sandbox()
	if _refusal.is_empty() and not _backend_url.is_empty():
		_refusal = _check_backend()
	if not _backend.is_empty() and _refusal.is_empty():
		_initialize_local_platform()
	elif not _is_network_allowed or not _refusal.is_empty():
		_initialize_offline_platform()
	var is_runnable := _config_error.is_empty() and _refusal.is_empty()
	if is_runnable:
		_config_error = _reset_settings_to_committed()
	G.settings.preview_connect_to_remote_server = false
	G.settings.generate_level_thumbnails = false
	if is_runnable and _config_error.is_empty():
		_config_error = _apply_settings_overrides()
	if _is_seeded:
		seed(_process_seed)


# --- Helpers that expression steps can call -------------------------------


## Player nodes in the current level, each once, sorted by player id.
## Level.players_by_id can hold one node under two keys (the server
## registers a player in _enter_tree before its id is set, which
## leaves a stale key 0), so this dedupes; state snapshots keep the
## raw keys.
func players() -> Array[Player]:
	var result: Array[Player] = []
	if not is_instance_valid(G.level):
		return result
	for node: Variant in G.level.players_by_id.values():
		if (is_instance_valid(node)
				and node is Player
				and not result.has(node)):
			result.append(node)
	result.sort_custom(
		func(a: Player, b: Player) -> bool: return a.player_id < b.player_id)
	return result


func player(player_id: int) -> Player:
	for node in players():
		if node.player_id == player_id:
			return node
	return null


## The index-th local player of this process, or null (always null on
## the server).
func local_player(index: int = 0) -> Player:
	var local_ids := _local_player_ids()
	if index < 0 or index >= local_ids.size():
		return null
	return player(int(local_ids[index]))


func player_count() -> int:
	return players().size()


func peer_count() -> int:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return 0
	if (peer.get_connection_status()
			== MultiplayerPeer.CONNECTION_DISCONNECTED):
		return 0
	return multiplayer.get_peers().size()


## The current ScreensMain.ScreenType name, e.g. "LOBBY" or "GAME".
func screen() -> String:
	if not is_instance_valid(G.screens):
		return ""
	var screen_name: Variant = ScreensMain.ScreenType.find_key(
		G.screens.current_screen)
	return str(screen_name) if screen_name != null else ""


func level_id() -> String:
	if not is_instance_valid(G.level):
		return ""
	for info: LevelInfo in G.settings.levels:
		if (info != null
				and info.scene != null
				and info.scene.resource_path == G.level.scene_file_path):
			return String(info.id)
	return ""


func snap(snapshot_name: String) -> Dictionary:
	return _snapshots.get(snapshot_name, {})


## Visible label and button text under the node at node_path.
func ui_labels(node_path: String = "/root") -> Array[String]:
	var labels: Array[String] = []
	var node := get_node_or_null(NodePath(node_path))
	if node != null:
		_collect_visible_labels(node, labels)
	return labels


func build_snapshot(snapshot_name: String) -> Dictionary:
	var snapshot := {
		"name": snapshot_name,
		"process": _process_name,
		"role": _role(),
		"seed": _process_seed if _is_seeded else null,
		"preview_client_number": Netcode.preview_client_number,
		"local_mode": Netcode.is_local_mode,
		"connected": Netcode.is_connected_to_server,
		"local_peer_id": Netcode.local_peer_id,
		"peers": peer_count(),
		"frame": Netcode.server_frame_index,
		"physics_frames": Engine.get_physics_frames(),
		"elapsed_sec": _elapsed_sec(),
		"screen": screen(),
		"level": _level_snapshot(),
		"match": _match_snapshot(),
		"players": _players_snapshot(),
		"local_player_ids": _local_player_ids(),
		"hud": _hud_snapshot(),
	}
	if DisplayServer.get_name() != "headless":
		var size := DisplayServer.window_get_size()
		var position := DisplayServer.window_get_position()
		snapshot["window"] = {
			"x": position.x,
			"y": position.y,
			"width": size.x,
			"height": size.y,
		}
	return snapshot


# --- Configuration ---------------------------------------------------------


func _parse_arguments() -> String:
	for argument in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"--agent-scenario":
				_scenario_path = value
			"--agent-process":
				_process_name = value
			"--agent-out":
				_out_dir = value.replace("\\", "/")
			"--agent-sandbox":
				_sandbox_dir = value.replace("\\", "/")
			"--agent-port":
				_port = int(value)
			"--agent-window":
				var numbers := value.split(",")
				if numbers.size() != 4:
					return "--agent-window must be x,y,width,height"
				_window_rect = Rect2i(
					int(numbers[0]),
					int(numbers[1]),
					int(numbers[2]),
					int(numbers[3]),
				)
				_has_window_rect = true
			"--agent-allow-network":
				_is_network_allowed = true
			"--agent-backend":
				_backend_url = value
			"--agent-backend-key":
				_backend_key = value
			"--agent-base-settings":
				_base_settings_path = value.replace("\\", "/")
	if _scenario_path.is_empty():
		return "missing --agent-scenario"
	if _process_name.is_empty():
		return "missing --agent-process"
	if _out_dir.is_empty():
		return "missing --agent-out"
	return ""


func _load_scenario() -> String:
	var text := FileAccess.get_file_as_string(_scenario_path)
	if text.is_empty():
		return "cannot read scenario %s" % _scenario_path
	var json := JSON.new()
	if json.parse(text) != OK:
		return "scenario %s line %d: %s" % [
			_scenario_path,
			json.get_error_line(),
			json.get_error_message(),
		]
	if not json.data is Dictionary:
		return "the scenario must be a JSON object"
	_scenario = json.data
	_mode = str(_scenario.get("mode", "offline"))
	if not (_mode in _MODES):
		return "unknown mode '%s'; use one of %s" % [_mode, _MODES]
	if _mode == "level" and not _scenario.has("level"):
		return "mode 'level' needs a 'level' (an id such as level_4)"
	var default_clients := 2 if _mode == "match" else 1
	_client_count = int(_scenario.get("clients", default_clients))
	if _mode == "match" and (_client_count < 1 or _client_count > 2):
		return "'clients' must be 1 or 2 (preview_client_count caps it)"

	var raw_seed: Variant = _scenario.get("seed", _DEFAULT_SEED)
	_is_seeded = raw_seed != null
	if _is_seeded:
		if not (raw_seed is float or raw_seed is int):
			return "'seed' must be an integer or null"
		_process_seed = int(raw_seed) + _client_number()

	var processes: Variant = _scenario.get("processes", {})
	if not processes is Dictionary:
		return "'processes' must be an object"
	var is_server := _process_name == "server"
	var spec: Variant = processes.get(_process_name, null)
	if spec == null and _process_name.begins_with("client"):
		spec = processes.get("client", null)
	if spec == null:
		spec = {}
	if not spec is Dictionary:
		return "'processes.%s' must be an object" % _process_name
	_process_spec = spec
	_timeout_sec = float(_process_spec.get(
		"timeout_sec",
		_scenario.get("timeout_sec", _DEFAULT_TIMEOUT_SEC),
	))
	if is_server:
		_timeout_sec += _SERVER_EXTRA_TIMEOUT_SEC

	# Top-level steps apply to every client. The server never inherits
	# them.
	var raw_steps: Variant = _process_spec.get("steps", null)
	if raw_steps == null and not is_server:
		raw_steps = _scenario.get("steps", null)
	if raw_steps == null:
		_steps = _default_steps()
	elif raw_steps is Array:
		_steps = raw_steps
	else:
		return "'steps' must be an array"
	return _validate_steps()


func _default_steps() -> Array:
	if _process_name == "server":
		return [
			{"do": "wait_ready"},
			{"do": "state", "name": "ready"},
			{
				"do": "wait_until",
				"expr": "peer_count() == 0",
				"timeout_sec": _timeout_sec,
			},
		]
	var steps: Array = [{"do": "wait_ready"}]
	if _mode != "lobby":
		steps.append({"do": "wait_match_start"})
	steps.append({"do": "wait", "sec": _DEFAULT_WAIT_SEC})
	steps.append({"do": "screenshot", "name": "ready"})
	steps.append({"do": "state", "name": "ready"})
	return steps


func _validate_steps() -> String:
	for index in range(_steps.size()):
		var step: Variant = _steps[index]
		if not step is Dictionary:
			return "step %d is not an object" % (index + 1)
		var kind := str(step.get("do", ""))
		if not _STEP_KEYS.has(kind):
			return "step %d: unknown 'do' value '%s'; known: %s" % [
				index + 1,
				kind,
				_STEP_KEYS.keys(),
			]
		var allowed: Array = _STEP_KEYS[kind]
		for key: Variant in step:
			if not (key in allowed or key in _COMMON_STEP_KEYS):
				return "step %d (%s): unknown key '%s'; allowed: %s" % [
					index + 1,
					kind,
					key,
					allowed + _COMMON_STEP_KEYS,
				]
	return ""


## Returns why this run must not proceed, or "" when it is safe. The
## user data dir must sit inside the sandbox run-game.ps1 made (it sets
## APPDATA per process), and no auth file may be visible there.
func _check_sandbox() -> String:
	if _sandbox_dir.is_empty():
		return "no --agent-sandbox; launch through scripts/agent/run-game.ps1"
	var user_dir := OS.get_user_data_dir().replace("\\", "/")
	var sandbox := _sandbox_dir.trim_suffix("/")
	if not user_dir.to_lower().begins_with(sandbox.to_lower() + "/"):
		return "user data dir %s is outside the sandbox %s" % [
			user_dir,
			sandbox,
		]
	for file_name in DirAccess.get_files_at(user_dir):
		var lowered := file_name.to_lower()
		if lowered.begins_with("auth") and lowered.ends_with(".cfg"):
			return "%s is visible in the user data dir" % file_name
	return ""


## Copies every stored setting from the committed settings.tres, which
## run-game.ps1 extracts with git, over the working copy that G
## loaded. A run then never depends on local edits to settings.tres.
## Simple values that differed are recorded for the result.
func _reset_settings_to_committed() -> String:
	if _base_settings_path.is_empty():
		return ""
	var committed: Resource = ResourceLoader.load(
		_base_settings_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not committed is Settings:
		return "cannot load committed settings from %s" % _base_settings_path
	for property: Dictionary in committed.get_property_list():
		var usage: int = property["usage"]
		if (
			(usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0
			or (usage & PROPERTY_USAGE_STORAGE) == 0
		):
			continue
		var property_name: String = property["name"]
		var value: Variant = committed.get(property_name)
		var current: Variant = G.settings.get(property_name)
		if (typeof(value) < TYPE_OBJECT
				and (typeof(value) != typeof(current) or value != current)):
			_settings_reset.append(
				"%s: %s -> %s" % [property_name, current, value])
		G.settings.set(property_name, value)
	return ""


## Returns why --agent-backend can't be used, or "" when it names a
## local stack: an http or https URL on a loopback host, with a port.
## Production is refused even with --agent-allow-network.
func _check_backend() -> String:
	var parsed := _parse_backend_url(_backend_url)
	if parsed.is_empty():
		return "--agent-backend must be scheme://host:port, not %s" % (
			_backend_url)
	if not (parsed.host in _LOOPBACK_HOSTS):
		return (
			"--agent-backend must be a loopback stack (%s), not %s"
			% [", ".join(_LOOPBACK_HOSTS), parsed.host]
		)
	_backend = parsed
	return ""


## Splits scheme://host:port (no path) into {scheme, host, port}, or
## returns {} when the URL has another shape.
func _parse_backend_url(url: String) -> Dictionary:
	var scheme_end := url.find("://")
	if scheme_end <= 0:
		return {}
	var scheme := url.substr(0, scheme_end).to_lower()
	var authority := url.substr(scheme_end + 3).trim_suffix("/")
	var colon := authority.rfind(":")
	if not (scheme in _BACKEND_SCHEMES) or colon <= 0:
		return {}
	var host := authority.substr(0, colon).trim_prefix("[").trim_suffix("]")
	var port_text := authority.substr(colon + 1)
	if host.is_empty() or not port_text.is_valid_int():
		return {}
	return {"scheme": scheme, "host": host, "port": port_text.to_int()}


## Initializes Platform before G does, pointing Nakama at the local
## stack --agent-backend names and every other backend URL (OAuth,
## token broker) at the blackhole.
func _initialize_local_platform() -> void:
	if Platform.is_initialized:
		return
	var blackhole_url := "http://%s:%d" % [_BLACKHOLE_HOST, _BLACKHOLE_PORT]
	Platform.initialize({
		"game_id": str(ProjectSettings.get_setting(
			"application/config/game_id", "hopnbop")),
		"api_base_url": _backend_url,
		"sdk_version": str(ProjectSettings.get_setting(
			"application/config/version", "0.0.0")),
		"auth_file_path": "user://auth.cfg",
		"nakama_host": _backend.host,
		"nakama_port": _backend.port,
		"nakama_scheme": _backend.scheme,
		"nakama_server_key": _backend_key,
		"oauth_callback_url": blackhole_url,
		"google_token_broker_url": blackhole_url,
		"google_oauth_client_id": "",
		"facebook_oauth_client_id": "",
	})


## Initializes Platform before G does (G skips its own call when
## Platform.is_initialized), pointing every backend URL at the
## blackhole and using throwaway keys.
func _initialize_offline_platform() -> void:
	if Platform.is_initialized:
		return
	var blackhole_url := "http://%s:%d" % [_BLACKHOLE_HOST, _BLACKHOLE_PORT]
	Platform.initialize({
		"game_id": str(ProjectSettings.get_setting(
			"application/config/game_id", "hopnbop")),
		"api_base_url": blackhole_url,
		"sdk_version": str(ProjectSettings.get_setting(
			"application/config/version", "0.0.0")),
		"auth_file_path": "user://auth.cfg",
		"nakama_host": _BLACKHOLE_HOST,
		"nakama_port": _BLACKHOLE_PORT,
		"nakama_scheme": "http",
		"nakama_server_key": _OFFLINE_KEY,
		"oauth_callback_url": blackhole_url,
		"google_token_broker_url": blackhole_url,
		"google_oauth_client_id": "",
		"facebook_oauth_client_id": "",
	})


func _apply_settings_overrides() -> String:
	var settings: Settings = G.settings
	var is_server := _process_name == "server"
	settings.skip_auth = true
	settings.skip_splash = true
	settings.full_screen = false
	settings.move_preview_windows_to_other_display = false
	settings.auto_minimize_server_window = false
	settings.mute_music = true
	settings.mute_sfx = true
	settings.network_sim_enabled = false
	settings.start_in_game = _mode != "lobby" and not is_server
	settings.prefer_offline_mode = _mode != "match"
	settings.preview_run_multiple_clients = (
		_client_count > 1 and _mode in ["match", "lobby"])
	if _port > 0:
		settings.server_port = _port

	var level: Variant = _scenario.get("level", null)
	if level != null:
		var index := _resolve_level_index(level)
		if index < 0:
			return "unknown level '%s'; known: %s" % [
				level,
				_known_level_ids(),
			]
		settings.level_override_for_preview = index

	# Process settings win over scenario-wide ones.
	var overrides: Dictionary = {}
	var sources: Array = [
		_scenario.get("settings", {}),
		_process_spec.get("settings", {}),
	]
	for source: Variant in sources:
		if not source is Dictionary:
			return "'settings' must be an object"
		overrides.merge(source, true)
	for key: Variant in overrides:
		var property := str(key)
		if not (property in settings):
			return "unknown setting '%s'" % property
		settings.set(
			property,
			_coerce_setting(settings.get(property), overrides[key]),
		)

	if (settings.preview_connect_to_remote_server
			and not _is_network_allowed and _backend.is_empty()):
		return (
			"preview_connect_to_remote_server needs run-game.ps1"
			+ " -AllowNetwork"
		)
	return ""


func _resolve_level_index(level: Variant) -> int:
	var levels: Array[LevelInfo] = G.settings.levels
	var text := str(level)
	if level is float or level is int or text.is_valid_int():
		var index := text.to_int() if level is String else int(level)
		return index if index >= 0 and index < levels.size() else -1
	for index in range(levels.size()):
		if levels[index] != null and String(levels[index].id) == text:
			return index
	return -1


func _known_level_ids() -> Array[String]:
	var ids: Array[String] = []
	for info: LevelInfo in G.settings.levels:
		if info != null:
			ids.append(String(info.id))
	return ids


func _coerce_setting(current: Variant, value: Variant) -> Variant:
	match typeof(current):
		TYPE_BOOL:
			return bool(value)
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_STRING:
			return str(value)
		TYPE_STRING_NAME:
			return StringName(str(value))
	return value


## This process's --client number, or 0 for the server. Netcode has not
## parsed the command line yet when configure() runs, so this reads the
## process name.
func _client_number() -> int:
	return _process_name.trim_prefix("client").to_int()


## Main._enter_tree calls randomize(), and level setup plus the spawns
## it makes should replay identically however many frames came before.
## So the seed is applied again right after main.tscn, and each level,
## enters the tree: node_added fires after the node's own _enter_tree
## and before its children enter.
func _on_node_added(node: Node) -> void:
	if node is Main or node is Level:
		seed(_process_seed)
		_print("seeded the RNG with %d as %s entered the tree" % [
			_process_seed,
			node.name,
		])


## The editor binary decides the role from --client=N (Netcode reads
## it in _enter_tree), so the process name has to agree with it.
func _check_role() -> String:
	var wants_server := _process_name == "server"
	if wants_server != Netcode.is_server:
		return "process '%s' launched as %s; check --client=N" % [
			_process_name,
			_role(),
		]
	return ""


# --- Running ---------------------------------------------------------------


func _run() -> void:
	_print("process=%s mode=%s role=%s steps=%d seed=%s user_dir=%s" % [
		_process_name,
		_mode,
		_role(),
		_steps.size(),
		_process_seed if _is_seeded else "none",
		OS.get_user_data_dir(),
	])
	if _base_settings_path.is_empty():
		_print("settings: the working copy of settings.tres")
	else:
		_print("settings: committed settings.tres; reset %s" % [
			_settings_reset])
	var error := get_tree().change_scene_to_file(_MAIN_SCENE_PATH)
	if error != OK:
		_finish(
			_EXIT_HARNESS_ERROR,
			"cannot load %s: %s" % [_MAIN_SCENE_PATH, error_string(error)],
		)
		return
	while not is_instance_valid(G.main):
		await get_tree().process_frame
	if _has_window_rect:
		await _apply_window_geometry()
	for index in range(_steps.size()):
		if _is_finished:
			return
		_current_step_index = index
		var should_continue: bool = await _run_step(index, _steps[index])
		_steps_run += 1
		if not should_continue or _is_finished:
			break
	_current_step_index = -1
	_finish(_EXIT_OK)


## Main._ready sizes and places preview windows for the editor's
## multi-instance layout. Put the window back where run-game.ps1 asked.
func _apply_window_geometry() -> void:
	for i in range(_GEOMETRY_SETTLE_FRAMES):
		await get_tree().process_frame
	if (DisplayServer.window_get_mode()
			!= DisplayServer.WINDOW_MODE_WINDOWED):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_window_rect.size)
	DisplayServer.window_set_position(_window_rect.position)


## Runs one step. Returns false when the scenario should stop.
func _run_step(index: int, step: Dictionary) -> bool:
	var kind := str(step.get("do", ""))
	_print("step %d/%d %s" % [index + 1, _steps.size(), JSON.stringify(step)])
	var error := ""
	match kind:
		"wait":
			error = await _step_wait(step)
		"wait_until":
			error = await _step_wait_until(step)
		"wait_ready":
			error = await _wait_for(
				_is_ready,
				float(step.get("timeout_sec", _DEFAULT_WAIT_TIMEOUT_SEC)),
				"the %s process to be ready" % _process_name,
			)
		"wait_match_start":
			error = await _wait_for(
				_has_match_started,
				float(step.get("timeout_sec", _DEFAULT_WAIT_TIMEOUT_SEC)),
				"the match-start countdown to end",
			)
		"press":
			error = _step_press(step, true)
		"release":
			error = _step_press(step, false)
		"tap":
			error = await _step_tap(step)
		"screenshot":
			error = await _step_screenshot(step)
		"state":
			error = _step_state(step)
		"eval":
			error = _step_eval(step)
		"call":
			error = _step_call(step)
		"assert":
			error = _step_assert(step)
		"sign_in":
			error = await _step_sign_in(step)
		"publish":
			error = _step_publish(step)
		"wait_shared":
			error = await _step_wait_shared(step)
		"log":
			_print(str(step.get("message", "")))
		"quit":
			return false
	if error.is_empty():
		return true
	_failures.append({"step": index + 1, "do": kind, "error": error})
	_print("FAILED step %d: %s" % [index + 1, error])
	# Asserts keep going so one run reports every failed check.
	var is_fatal := bool(step.get("fatal", kind != "assert"))
	return not is_fatal


func _step_wait(step: Dictionary) -> String:
	if step.has("frames"):
		for i in range(int(step.get("frames"))):
			await get_tree().physics_frame
		return ""
	await get_tree().create_timer(
		float(step.get("sec", _DEFAULT_WAIT_SEC))).timeout
	return ""


func _step_wait_until(step: Dictionary) -> String:
	var text := str(step.get("expr", ""))
	var parsed := _parse_expression(text)
	if parsed[0] == null:
		return parsed[1]
	var expression: Expression = parsed[0]
	return await _wait_for(
		func() -> Variant: return _execute(expression, text),
		float(step.get("timeout_sec", _DEFAULT_WAIT_TIMEOUT_SEC)),
		text,
	)


## Polls the predicate once per physics frame. The predicate returns a
## bool, or [ok, value] from _execute. Returns "" once it holds, or an
## error on timeout or when evaluation fails.
func _wait_for(
	predicate: Callable,
	timeout_sec: float,
	description: String,
) -> String:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not _is_finished:
		var outcome: Variant = predicate.call()
		if outcome is Array:
			if not outcome[0]:
				return str(outcome[1])
			outcome = outcome[1]
		if outcome:
			return ""
		if Time.get_ticks_msec() >= deadline:
			return "timed out after %.1fs waiting for %s" % [
				timeout_sec,
				description,
			]
		await get_tree().physics_frame
	return "the scenario finished while waiting for %s" % description


func _is_ready() -> bool:
	match _mode:
		"lobby":
			return G.is_lobby_active and screen() == "LOBBY"
		"match":
			if Netcode.is_server:
				return (
					G.is_networked_level_active
					and player_count() >= _client_count
				)
	return G.is_networked_level_active and local_player() != null


func _has_match_started() -> bool:
	if Netcode.frame_driver == null or not G.is_networked_level_active:
		return false
	var end_frame := Netcode.frame_driver.match_start_countdown_end_frame_index
	return end_frame >= 0 and Netcode.server_frame_index >= end_frame


func _step_press(step: Dictionary, is_pressed: bool) -> String:
	var resolved := _resolve_keys(step)
	if not resolved[1].is_empty():
		return resolved[1]
	for key: Key in resolved[0]:
		_send_key(key, is_pressed)
		if is_pressed:
			_held_keys[key] = Engine.get_physics_frames()
		else:
			_held_keys.erase(key)
	return ""


func _step_tap(step: Dictionary) -> String:
	var error := _step_press(step, true)
	if not error.is_empty():
		return error
	if step.has("hold_frames"):
		for i in range(int(step.get("hold_frames"))):
			await get_tree().physics_frame
	else:
		await get_tree().create_timer(
			float(step.get("hold_sec", _DEFAULT_TAP_HOLD_SEC))).timeout
	return _step_press(step, false)


## Maps step "key"/"keys" to keycodes. Movement names (move_left, left,
## jump, ...) use the keyboard partition of step "player" (1 = WASD +
## Space, 2 = IJKL + Shift, 3 = arrows + Enter, 4 = numpad). Anything
## else is a Godot key name such as "Escape" or "F1". Returns
## [keys, error].
func _resolve_keys(step: Dictionary) -> Array:
	var names: Array = []
	var raw_keys: Variant = step.get("keys", null)
	if raw_keys is Array:
		names = raw_keys
	elif step.has("key"):
		names = [step.get("key")]
	if names.is_empty():
		return [[], "missing 'key' or 'keys'"]
	var partitions: Array = InputDeviceManager.KEYBOARD_PARTITION_BINDINGS
	var player_number := int(step.get("player", 1))
	if player_number < 1 or player_number > partitions.size():
		return [[], "'player' must be 1-%d" % partitions.size()]
	var bindings: Dictionary = partitions[player_number - 1]
	var keys: Array[Key] = []
	for raw_name: Variant in names:
		var key_name := str(raw_name)
		var action: String = _ACTION_ALIASES.get(key_name, key_name)
		if action != "name" and bindings.has(action):
			keys.append(bindings[action])
			continue
		var keycode := OS.find_keycode_from_string(key_name)
		if keycode == KEY_NONE:
			return [[], "unknown key '%s'" % key_name]
		keys.append(keycode)
	return [keys, ""]


## The game polls Input.is_physical_key_pressed, so physical_keycode is
## the field that matters.
func _send_key(key: Key, is_pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = is_pressed
	Input.parse_input_event(event)


func _release_held_keys() -> void:
	for key: Key in _held_keys.keys():
		_send_key(key, false)
	_held_keys.clear()


func _step_screenshot(step: Dictionary) -> String:
	var shot_name := _sanitize_name(
		str(step.get("name", "shot_%d" % (_current_step_index + 1))))
	if DisplayServer.get_name() == "headless":
		_warnings.append("screenshot '%s' skipped: headless run" % shot_name)
		return ""
	await RenderingServer.frame_post_draw
	var target := str(step.get("target", "window"))
	# A screenshot right after a screen change can catch the
	# fade-from-black (about 0.7 s); _capture_with_retry waits
	# it out.
	var texture: Texture2D = null
	match target:
		"window":
			texture = get_viewport().get_texture()
		"game":
			if (not is_instance_valid(G.pixel_viewport_manager)
					or not is_instance_valid(
						G.pixel_viewport_manager.sub_viewport)):
				return "no game viewport to capture yet"
			texture = G.pixel_viewport_manager.sub_viewport.get_texture()
		_:
			return "unknown screenshot target '%s'; use window or game" % (
				target)
	var image := await _capture_with_retry(texture)
	if image == null or image.is_empty():
		return "captured an empty image"
	var path := _out_dir.path_join(shot_name + ".png")
	var error := image.save_png(path)
	if error != OK:
		return "cannot save %s: %s" % [path, error_string(error)]
	_screenshots.append(path)
	_print("screenshot %s (%dx%d)" % [
		path,
		image.get_width(),
		image.get_height(),
	])
	return ""


## Captures the texture, retrying for up to a second while the
## frame is still (nearly) all black, as it is during the fade
## after a screen change.
func _capture_with_retry(texture: Texture2D) -> Image:
	var image := texture.get_image()
	for attempt in 20:
		if image == null or not _is_mostly_black(image):
			break
		await RenderingServer.frame_post_draw
		image = texture.get_image()
	return image


func _is_mostly_black(image: Image) -> bool:
	var step_x := maxi(1, image.get_width() / 16)
	var step_y := maxi(1, image.get_height() / 16)
	var sampled := 0
	var dark := 0
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			sampled += 1
			var c := image.get_pixel(x, y)
			if c.r + c.g + c.b < 0.05:
				dark += 1
	return sampled > 0 and dark * 20 >= sampled * 19


func _step_state(step: Dictionary) -> String:
	var state_name := _sanitize_name(
		str(step.get("name", "state_%d" % (_current_step_index + 1))))
	var snapshot := build_snapshot(state_name)
	_snapshots[state_name] = snapshot
	var path := _out_dir.path_join("state-%s.json" % state_name)
	var error := _write_json(path, snapshot)
	if not error.is_empty():
		return error
	_state_paths.append(path)
	_print("state %s %s -> %s" % [
		state_name,
		_summarize_snapshot(snapshot),
		path,
	])
	return ""


func _step_eval(step: Dictionary) -> String:
	var text := str(step.get("expr", ""))
	var parsed := _parse_expression(text)
	if parsed[0] == null:
		return parsed[1]
	var outcome := _execute(parsed[0], text)
	if not outcome[0]:
		return outcome[1]
	_store_eval(step, outcome[1])
	return ""


func _step_call(step: Dictionary) -> String:
	var node_path := str(step.get("node", ""))
	var method := str(step.get("method", ""))
	if method.is_empty():
		return "missing 'method'"
	var target := get_node_or_null(NodePath(node_path))
	if target == null:
		return "no node at '%s'" % node_path
	if not target.has_method(method):
		return "%s has no method '%s'" % [node_path, method]
	var args: Variant = step.get("args", [])
	if not args is Array:
		return "'args' must be an array"
	_store_eval(step, target.callv(method, args))
	return ""


## Signs in as a guest against the -Backend stack, so backend
## scenarios can act as a real signed-in player (H75). Each
## process has its own sandbox, so each gets its own account.
## Accepts the consent screen if it follows.
func _step_sign_in(step: Dictionary) -> String:
	if _backend.is_empty():
		return "sign_in needs run-game.ps1 -Backend <local stack>"
	var timeout := float(step.get(
		"timeout_sec", _DEFAULT_WAIT_TIMEOUT_SEC))
	if Platform.token_store.is_token_valid():
		_print("sign_in: already signed in")
		return ""
	# A fresh sandbox shows the consent screen before sign-in;
	# accepting it lands on the auth screen, ready to sign in.
	if screen() == "CONSENT" and is_instance_valid(G.consent_screen):
		G.consent_screen._on_continue_pressed()
		await _wait_for(
			func() -> bool: return screen() != "CONSENT",
			10.0, "the auth screen after consent")
	# login_anonymous is a local-only identity; the Nakama
	# session (which party and matchmaking calls need) comes
	# from get_guest_jwt's device auth.
	var outcome: Array = []
	var on_jwt := func(success: bool, error: String) -> void:
		outcome.append([success, error])
	Platform.auth.guest_jwt_obtained.connect(
		on_jwt, CONNECT_ONE_SHOT)
	Platform.auth.login_anonymous()
	Platform.auth.get_guest_jwt()
	var wait_error := await _wait_for(
		func() -> bool: return not outcome.is_empty(),
		timeout, "guest sign-in")
	if not wait_error.is_empty():
		return wait_error
	if not outcome[0][0]:
		return "sign-in failed: %s" % outcome[0][1]
	_print("sign_in: signed in as %s" %
		Platform.token_store.player_id)
	if screen() == "CONSENT" and is_instance_valid(G.consent_screen):
		G.consent_screen._on_continue_pressed()
	return ""


## Connects the party invite-code signal into shared.invite_code,
## for scenarios: eval driver.capture_invite_code(), request the
## code, then publish shared.invite_code. Expression steps cannot
## declare lambdas, so the connection lives here.
func capture_invite_code() -> void:
	Platform.party.party_invite_code_received.connect(
		func(data: Dictionary) -> void:
			_shared["invite_code"] = str(data.get("code", "")),
		CONNECT_ONE_SHOT)


## The directory every process in the run shares (publish /
## wait_shared), next to the per-process output dirs.
func _shared_dir() -> String:
	return _out_dir.get_base_dir().path_join("shared")


## Publishes the string form of an expression's value for the
## other processes in the run (an invite code, a match id).
func _step_publish(step: Dictionary) -> String:
	var name := _sanitize_name(str(step.get("name", "")))
	if name.is_empty():
		return "publish needs a 'name'"
	var text := str(step.get("expr", ""))
	var parsed := _parse_expression(text)
	if parsed[0] == null:
		return parsed[1]
	var outcome := _execute(parsed[0], text)
	if not outcome[0]:
		return outcome[1]
	var value := str(outcome[1])
	DirAccess.make_dir_recursive_absolute(_shared_dir())
	var path := _shared_dir().path_join(name + ".txt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot publish to %s" % path
	file.store_string(value)
	file.close()
	_shared[name] = value
	_print("published %s = %s" % [name, value])
	return ""


## Waits for another process to publish a name, then exposes
## the value to expressions as shared.<name>.
func _step_wait_shared(step: Dictionary) -> String:
	var name := _sanitize_name(str(step.get("name", "")))
	if name.is_empty():
		return "wait_shared needs a 'name'"
	var path := _shared_dir().path_join(name + ".txt")
	var wait_error := await _wait_for(
		func() -> bool: return FileAccess.file_exists(path),
		float(step.get("timeout_sec", _DEFAULT_WAIT_TIMEOUT_SEC)),
		"shared value '%s'" % name)
	if not wait_error.is_empty():
		return wait_error
	_shared[name] = FileAccess.get_file_as_string(
		path).strip_edges()
	_print("shared %s = %s" % [name, _shared[name]])
	return ""


func _step_assert(step: Dictionary) -> String:
	var text := str(step.get("expr", ""))
	var parsed := _parse_expression(text)
	if parsed[0] == null:
		return parsed[1]
	var outcome := _execute(parsed[0], text)
	if not outcome[0]:
		return outcome[1]
	if outcome[1]:
		_print("assert ok: %s" % text)
		return ""
	var message := str(step.get("message", ""))
	return "assert failed: %s%s (got %s)" % [
		text,
		" [%s]" % message if not message.is_empty() else "",
		JSON.stringify(_to_json_safe(outcome[1])),
	]


func _store_eval(step: Dictionary, value: Variant) -> void:
	var eval_name := str(
		step.get("name", "eval_%d" % (_current_step_index + 1)))
	_evals[eval_name] = _to_json_safe(value)
	_print("eval %s = %s" % [eval_name, JSON.stringify(_evals[eval_name])])


## Returns [Expression, ""] or [null, error].
func _parse_expression(text: String) -> Array:
	if text.strip_edges().is_empty():
		return [null, "missing 'expr'"]
	var expression := Expression.new()
	var error := expression.parse(
		text, PackedStringArray(_EXPRESSION_INPUTS))
	if error != OK:
		return [null, "cannot parse '%s': %s" % [
			text,
			expression.get_error_text(),
		]]
	return [expression, ""]


## Returns [true, value] or [false, error]. Unqualified calls such as
## local_player() resolve against this node.
func _execute(expression: Expression, text: String) -> Array:
	var value: Variant = expression.execute(
		[
			G,
			Netcode,
			Platform,
			G.level if is_instance_valid(G.level) else null,
			G.match_state,
			_snapshots,
			self,
			OS,
			Engine,
			Input,
			Time,
			_shared,
		],
		self,
		false,
	)
	if expression.has_execute_failed():
		return [false, "cannot evaluate '%s': %s" % [
			text,
			expression.get_error_text(),
		]]
	return [true, value]


func _on_watchdog_timeout() -> void:
	if _is_finished:
		return
	_finish(
		_EXIT_FAILED,
		"the scenario timed out after %.0fs" % _timeout_sec,
	)


func _finish(exit_code: int, error: String = "") -> void:
	if _is_finished:
		return
	_is_finished = true
	if not error.is_empty():
		_failures.append({
			"step": _current_step_index + 1,
			"do": "harness",
			"error": error,
		})
	if exit_code == _EXIT_OK and not _failures.is_empty():
		exit_code = _EXIT_FAILED
	_release_held_keys()
	var result := _build_result(exit_code)
	if not _out_dir.is_empty():
		var write_error := _write_json(result["result_path"], result)
		if not write_error.is_empty():
			_print(write_error)
	print(_RESULT_PREFIX + JSON.stringify(result))
	await _disconnect_gracefully()
	get_tree().quit(exit_code)


func _build_result(exit_code: int) -> Dictionary:
	return {
		"ok": exit_code == _EXIT_OK,
		"exit_code": exit_code,
		"scenario": str(_scenario.get("name", "")),
		"process": _process_name,
		"mode": _mode,
		"role": _role(),
		"seed": _process_seed if _is_seeded else null,
		"settings_source": (
			"working copy" if _base_settings_path.is_empty() else "committed"),
		"settings_reset": _settings_reset,
		"steps_total": _steps.size(),
		"steps_run": _steps_run,
		"elapsed_sec": _elapsed_sec(),
		"failures": _failures,
		"warnings": _warnings,
		"screenshots": _screenshots,
		"states": _state_paths,
		"evals": _evals,
		"key_reasserts": _key_reassert_count,
		"out_dir": _out_dir,
		"result_path": _out_dir.path_join("result.json"),
		"user_data_dir": OS.get_user_data_dir(),
	}


## Tells the other side we are leaving so it does not wait out an ENet
## timeout.
func _disconnect_gracefully() -> void:
	if not is_inside_tree():
		return
	if Netcode.connector == null or Netcode.is_local_mode:
		return
	if Netcode.is_client and Netcode.is_connected_to_server:
		# Same order as GamePanel._client_cleanup_after_match. Pause the
		# frame driver, which otherwise logs errors every frame it
		# simulates without a peer. Then drop the peer right after
		# disconnecting (freeing it sends the disconnect). If the
		# disconnect event arrived mid-match instead, the game would
		# start its reconnect loop, and the process crashes tearing
		# that down.
		Netcode.frame_driver.client_reset()
		Netcode.connector.client_disconnect()
		multiplayer.multiplayer_peer = null
	elif Netcode.is_server and peer_count() > 0:
		Netcode.connector.server_disconnect_all_clients()
		for i in range(_DISCONNECT_FLUSH_FRAMES):
			await get_tree().process_frame


# --- Snapshots ---------------------------------------------------------------


func _level_snapshot() -> Dictionary:
	if not is_instance_valid(G.level):
		return {"kind": "none"}
	var kind := "other"
	if G.level is LobbyLevel:
		kind = "lobby"
	elif G.level is NetworkedLevel:
		kind = "networked"
	return {
		"kind": kind,
		"id": level_id(),
		"name": String(G.level.name),
		"scene": G.level.scene_file_path,
	}


func _match_snapshot() -> Dictionary:
	var match_state := G.match_state
	if match_state == null:
		return {}
	var kills_by_id := {}
	var deaths_by_id := {}
	var self_kills_by_id := {}
	var bumps_by_id := {}
	var kills := match_state.kills
	for i in range(0, kills.size() - 1, 2):
		var killer := kills[i]
		var killee := kills[i + 1]
		if killer == killee:
			self_kills_by_id[killer] = self_kills_by_id.get(killer, 0) + 1
		else:
			kills_by_id[killer] = kills_by_id.get(killer, 0) + 1
		deaths_by_id[killee] = deaths_by_id.get(killee, 0) + 1
	var bumps := match_state.bumps
	for i in range(0, bumps.size() - 1, 2):
		for player_id in [bumps[i], bumps[i + 1]]:
			bumps_by_id[player_id] = bumps_by_id.get(player_id, 0) + 1

	var entries: Array = []
	var ids: Array = match_state.players_by_id.keys()
	ids.sort()
	for player_id: Variant in ids:
		var player_state: PlayerState = match_state.players_by_id[player_id]
		var entry := {
			"id": player_id,
			"peer_id": player_state.peer_id,
			"connected": player_state.is_connected_to_server,
			"kills": kills_by_id.get(player_id, 0),
			"deaths": deaths_by_id.get(player_id, 0),
			"self_kills": self_kills_by_id.get(player_id, 0),
			"bumps": bumps_by_id.get(player_id, 0),
		}
		if player_state is GamePlayerState:
			entry["name"] = String(player_state.full_name)
			entry["score"] = player_state.score
			entry["rank"] = player_state.rank
		entries.append(entry)

	var countdown_end_frame := -1
	if Netcode.frame_driver != null:
		countdown_end_frame = (
			Netcode.frame_driver.match_start_countdown_end_frame_index)
	return {
		"active": match_state.is_match_active,
		"ended": match_state.is_match_ended,
		"time_remaining_sec": snappedf(
			match_state.match_time_remaining_sec, _ROUNDING_STEP),
		"start_frame": match_state.match_start_frame_index,
		"countdown_end_frame": countdown_end_frame,
		"kill_events": floori(kills.size() / 2.0),
		"bump_events": floori(bumps.size() / 2.0),
		"players": entries,
	}


## One entry per player node. "keys" lists every Level.players_by_id
## key that points at the node, so a stale duplicate stays visible.
func _players_snapshot() -> Array:
	var entries: Array = []
	if not is_instance_valid(G.level):
		return entries
	var local_ids := _local_player_ids()
	for bunny in players():
		var keys: Array = []
		for key: Variant in G.level.players_by_id:
			if G.level.players_by_id[key] == bunny:
				keys.append(key)
		var entry := {
			"keys": keys,
			"id": bunny.player_id,
			"peer_id": bunny.peer_id,
			"is_local": local_ids.has(bunny.player_id),
			"x": snappedf(bunny.global_position.x, _ROUNDING_STEP),
			"y": snappedf(bunny.global_position.y, _ROUNDING_STEP),
			"vx": snappedf(bunny.velocity.x, _ROUNDING_STEP),
			"vy": snappedf(bunny.velocity.y, _ROUNDING_STEP),
			"on_floor": bunny.surfaces.is_touching_floor,
			"on_wall": bunny.surfaces.is_touching_wall,
			"on_ceiling": bunny.surfaces.is_touching_ceiling,
			"surfaces": bunny.surfaces.bitmask,
			"actions": bunny.actions.bitmask,
			"visible": bunny.is_visible_in_tree(),
			"sprite_visible": bunny.is_sprite_visible,
			"node": str(bunny.get_path()),
		}
		if is_instance_valid(bunny.state_from_server):
			entry["is_dead"] = bunny.state_from_server.is_dead
			entry["is_invincible"] = bunny.state_from_server.is_invincible
		entries.append(entry)
	return entries


func _local_player_ids() -> Array:
	if G.client_session == null:
		return []
	return Array(G.client_session.local_player_ids)


func _hud_snapshot() -> Dictionary:
	if not is_instance_valid(G.hud):
		return {}
	var labels: Array[String] = []
	_collect_visible_labels(G.hud, labels)
	return {"visible": G.hud.is_visible_in_tree(), "labels": labels}


func _collect_visible_labels(node: Node, labels: Array[String]) -> void:
	if labels.size() >= _MAX_UI_LABELS:
		return
	if node is CanvasItem and not node.is_visible_in_tree():
		return
	var text := ""
	if node is Label or node is Button:
		text = node.text
	elif node is RichTextLabel:
		text = node.get_parsed_text()
	text = text.strip_edges()
	if not text.is_empty():
		labels.append(text)
	for child in node.get_children():
		_collect_visible_labels(child, labels)


func _summarize_snapshot(snapshot: Dictionary) -> String:
	var parts: Array[String] = []
	for entry: Dictionary in snapshot.get("players", []):
		parts.append("%s@(%d,%d)%s" % [
			entry.get("id"),
			roundi(float(entry.get("x", 0.0))),
			roundi(float(entry.get("y", 0.0))),
			"*" if entry.get("is_local", false) else "",
		])
	return "screen=%s level=%s frame=%d players=[%s]" % [
		snapshot.get("screen", ""),
		snapshot.get("level", {}).get("id", ""),
		int(snapshot.get("frame", 0)),
		" ".join(parts),
	]


# --- Utilities ---------------------------------------------------------------


func _role() -> String:
	return "server" if Netcode.is_server else "client"


func _elapsed_sec() -> float:
	return snappedf(
		(Time.get_ticks_msec() - _start_msec) / 1000.0, _ROUNDING_STEP)


func _sanitize_name(text: String) -> String:
	var result := ""
	for character in text:
		var is_safe := (
			(character >= "a" and character <= "z")
			or (character >= "A" and character <= "Z")
			or (character >= "0" and character <= "9")
			or character in ["-", "_", "."]
		)
		result += character if is_safe else "_"
	return result if not result.is_empty() else "unnamed"


func _write_json(path: String, data: Variant) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot write %s: %s" % [
			path,
			error_string(FileAccess.get_open_error()),
		]
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return ""


## Converts a value to something JSON.stringify writes faithfully.
func _to_json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			return str(value) if is_nan(value) or is_inf(value) else value
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_DICTIONARY:
			var result := {}
			for key: Variant in value:
				result[str(key)] = _to_json_safe(value[key])
			return result
		TYPE_OBJECT:
			if value is Node and is_instance_valid(value):
				return str(value.get_path())
			return str(value)
	if value is Array or typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
		var items: Array = []
		for item: Variant in value:
			items.append(_to_json_safe(item))
		return items
	return str(value)


func _print(message: String) -> void:
	print(_LOG_PREFIX + message)
