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

@warning_ignore("shadowed_global_identifier") var log := ScaffolderLog.new()
var utils := Utils.new()
var geometry := Geometry.new()
var draw_utils := DrawUtils.new()

var input_device_manager := InputDeviceManager.new()
var window_manager := WindowManager.new()
var input_handler := InputHandler.new()

var main: Main
var audio: AudioMain
var hud: Hud
var super_hud: SuperHud
var screens: ScreensMain

var godot_splash_screen: GodotSplashScreen
var scg_splash_screen: SCGSplashScreen
var loading_screen: LoadingScreen
var game_over_screen: GameOverScreen
var pause_screen: PauseScreen
var screen_transition: ScreenTransition

var game_panel: GamePanel
var match_state: GameMatchState
var client_session: ClientSession
var player_overhead_labels: PlayerOverheadLabels
var level: Level

var level_registry: LevelRegistry

var is_lobby_active: bool:
	get:
		return is_instance_valid(level) and level is LobbyLevel
var is_networked_level_active: bool:
	get:
		return is_instance_valid(level) and level is NetworkedLevel


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	args = Utils.parse_command_line_args()

	log.name = "Log"
	add_child(log)

	utils.name = "Utils"
	add_child(utils)

	geometry.name = "Geometry"
	add_child(geometry)

	draw_utils.name = "DrawUtils"
	add_child(draw_utils)

	# Configure Netcode plugin.
	Netcode.settings = settings
	Netcode.log = log

	settings.is_preview_mode = OS.has_feature("editor")

	input_device_manager.name = "InputDeviceManager"
	add_child(input_device_manager)

	window_manager.name = "WindowManager"
	add_child(window_manager)

	input_handler.name = "InputHandler"
	add_child(input_handler)


func _ready() -> void:
	# Initialize Netcode now that the scene tree is available.
	Netcode.initialize()

	# Initialize level registry from settings.
	_initialize_level_registry()

	G.log.log_system_ready("Global")

	if Netcode.is_preview:
		if Netcode.is_client:
			preview_instance_label = "Client %s" % Netcode.preview_client_number
		else:
			preview_instance_label = "Server"
	else:
		preview_instance_label = ""


func _initialize_level_registry() -> void:
	level_registry = LevelRegistry.new()

	# Register levels from settings.
	for level_info in settings.levels:
		level_registry.register_level(level_info)

	G.loNetcode.print(
		"Level registry initialized with %d levels" % level_registry.get_level_count(),
		NetworkLogger.CATEGORY_SYSTEM_INITIALIZATION
	)


func get_player_match_state(player_id: int) -> GamePlayerState:
	if (not is_instance_valid(match_state) or
			not match_state.players_by_id.has(player_id)):
		return null
	return match_state.players_by_id[player_id]


func get_player(player_id: int) -> Player:
	if (
		not is_instance_valid(level) or
		not level.players_by_id.has(player_id)
	):
		return null
	return level.players_by_id[player_id]
