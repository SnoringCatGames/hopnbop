# class_name G
extends Node
## Add global state here for easy access.

# Note: This would be better stored on Main as an export var, so we don't have
#       to reference the path in code. But, this must be set for tests to run
#       correctly, and Main isn't run during tests.
var settings: Settings = preload("res://settings.tres")

# Note: This is shown at the top to assist with local debugging.
var preview_instance_label := ""

var args: Dictionary

var time := ScaffolderTime.new()
@warning_ignore("shadowed_global_identifier") var log := ScaffolderLog.new()
var utils := Utils.new()
var geometry := Geometry.new()
var draw_utils := DrawUtils.new()
var network := NetworkMain.new()
var input_device_manager := InputDeviceManager.new()
var process_sentinel := ProcessSentinel.new()

var main: Main
var audio: AudioMain
var hud: Hud
var super_hud: SuperHud
var screens: ScreensMain

var godot_splash_screen: GodotSplashScreen
var scg_splash_screen: SCGSplashScreen
var loading_screen: LoadingScreen
var game_over_screen: GameOverScreen
var win_screen: WinScreen
var pause_screen: PauseScreen

var game_panel: GamePanel
var match_state: MatchState
var local_session: LocalSession
var player_overhead_labels: PlayerOverheadLabels
var level: Level

var is_lobby_active: bool:
	get:
		return is_instance_valid(level) and level is LobbyLevel
var is_networked_level_active: bool:
	get:
		return is_instance_valid(level) and level is NetworkedLevel


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	args = Utils.parse_command_line_args()

	time.name = "Time"
	add_child(time)

	log.name = "Log"
	add_child(log)

	utils.name = "Utils"
	add_child(utils)

	geometry.name = "Geometry"
	add_child(geometry)

	draw_utils.name = "DrawUtils"
	add_child(draw_utils)

	network.name = "Network"
	add_child(network)

	input_device_manager.name = "InputDeviceManager"
	add_child(input_device_manager)

	process_sentinel.name = "ProcessSentinel"
	add_child(process_sentinel)


func _ready() -> void:
	G.log.log_system_ready("Global")

	if G.network.is_preview:
		if G.network.is_client:
			preview_instance_label = "Client %s" % G.network.preview_client_number
		else:
			preview_instance_label = "Server"
	else:
		preview_instance_label = ""


func get_player_match_state(player_id: int) -> PlayerMatchState:
	if not is_instance_valid(match_state) or not match_state.players_by_id.has(player_id):
		return null
	return match_state.players_by_id[player_id]


func get_player(player_id: int) -> Player:
	if (
		not is_instance_valid(level) or
		not level.players_by_id.has(player_id)
	):
		return null
	return level.players_by_id[player_id]

# --- Include some convenient access to logging/error utilities ---------------

var is_verbose: bool:
	get:
		return log.is_verbose


func print(
		message = "",
		category := ScaffolderLog.CATEGORY_DEFAULT,
		verbosity := ScaffolderLog.Verbosity.NORMAL,
) -> void:
	log.print(message, category, verbosity)


func warning(message = "", category := ScaffolderLog.CATEGORY_DEFAULT) -> void:
	log.warning(message, category)


func error(message = "", category := ScaffolderLog.CATEGORY_DEFAULT) -> void:
	log.error(message, category, false)


func fatal(message = "", category := ScaffolderLog.CATEGORY_DEFAULT) -> void:
	log.error(message, category, true)


func ensure(condition: bool, message = "") -> bool:
	return log.ensure(condition, message)


func ensure_valid(object, message = "") -> bool:
	return log.ensure(is_instance_valid(object), message)


func check(condition: bool, message = "") -> bool:
	return log.check(condition, message)


func check_valid(object, message = "") -> bool:
	return log.check(is_instance_valid(object), message)


func check_is_server() -> bool:
	return log.check(G.network.is_server,
		"This logic assumes we should be a server, but we're a client")


func check_is_client() -> bool:
	return log.check(G.network.is_client,
		"This logic assumes we should be a client, but we're a server")

# -----------------------------------------------------------------------------
