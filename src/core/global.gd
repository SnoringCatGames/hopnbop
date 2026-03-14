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

var auth_token_store: AuthTokenStore
var auth_client: AuthClient
var match_result_reporter: MatchResultReporter
var backend_api_client: BackendApiClient
var friends_api_client: FriendsApiClient
var party_api_client: PartyApiClient
var party_manager: PartyManager
var crash_reporter: CrashReporter
var profile_image_cache: ProfileImageCache
var auth_screen: AuthScreen
var consent_screen: ConsentScreen

var godot_splash_screen: GodotSplashScreen
var scg_splash_screen: SCGSplashScreen
var loading_screen: LoadingScreen
var game_over_screen: GameOverScreen
var pause_screen: PauseScreen
var toast_overlay: ToastOverlay
var screen_transition: ScreenTransition

var cheat_manager: CheatManager
var camera_shaker: CameraShaker
var celebration: MatchEndCelebration
var pixel_viewport_manager: PixelViewportManager
var game_panel: GamePanel
var match_state: GameMatchState
var client_session: ClientSession
var player_overhead_labels: PlayerOverheadLabels
var player_annotations: PlayerAnnotations
var level: Level

var level_registry: LevelRegistry
var local_settings: LocalSettings
var settings_cloud_sync: SettingsCloudSync

# Whether the settings UI is currently shown.
var is_settings_ui_shown := false

# The player that opened the settings UI (null when closed).
var settings_ui_player: Player = null

# Whether a global UI overlay (confirm dialog,
# credits, etc.) is blocking all player input.
var is_ui_interaction_mode_enabled := false

var _peer_color_cache: Dictionary = {}

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

	auth_token_store = AuthTokenStore.new()

	auth_client = AuthClient.new()
	auth_client.name = "AuthClient"
	add_child(auth_client)

	match_result_reporter = MatchResultReporter.new()
	match_result_reporter.name = "MatchResultReporter"
	add_child(match_result_reporter)

	backend_api_client = BackendApiClient.new()
	backend_api_client.name = "BackendApiClient"
	add_child(backend_api_client)

	friends_api_client = FriendsApiClient.new()
	friends_api_client.name = "FriendsApiClient"
	add_child(friends_api_client)

	party_api_client = PartyApiClient.new()
	party_api_client.name = "PartyApiClient"
	add_child(party_api_client)

	party_manager = PartyManager.new()
	party_manager.name = "PartyManager"
	add_child(party_manager)

	crash_reporter = CrashReporter.new()
	crash_reporter.name = "CrashReporter"
	add_child(crash_reporter)

	profile_image_cache = ProfileImageCache.new()
	profile_image_cache.name = "ProfileImageCache"
	add_child(profile_image_cache)

	cheat_manager = CheatManager.new()
	cheat_manager.name = "CheatManager"
	add_child(cheat_manager)

	camera_shaker = CameraShaker.new()
	camera_shaker.name = "CameraShaker"
	add_child(camera_shaker)


func _ready() -> void:
	# Initialize Netcode now that the scene tree is available.
	Netcode.initialize()

	# Read server API key from environment variable
	# (set via GameLift container group definition).
	var env_api_key := OS.get_environment(
		"SERVER_API_KEY")
	if not env_api_key.is_empty():
		settings.server_api_key = env_api_key

	# Initialize level registry from settings.
	_initialize_level_registry()

	# Initialize local settings persistence.
	local_settings = LocalSettings.new(settings)
	local_settings.load_settings()
	local_settings.apply_all_overrides()
	local_settings.apply_locale()

	# Cloud settings sync manager.
	settings_cloud_sync = SettingsCloudSync.new()

	# Configure font fallbacks for non-Latin scripts.
	FontFallbackConfig.configure_fallbacks()

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

	Netcode.print(
		"Level registry initialized with %d levels" % level_registry.get_level_count(),
		NetworkLogger.CATEGORY_SYSTEM_INITIALIZATION
	)


func get_player_match_state(
	player_id: int,
) -> GamePlayerState:
	if (not is_instance_valid(match_state)
			or not match_state.players_by_id
				.has(player_id)):
		return null
	return match_state.players_by_id[player_id]


func get_player(player_id: int) -> Player:
	if (
		not is_instance_valid(level)
		or not level.players_by_id
			.has(player_id)
	):
		return null
	return level.players_by_id[player_id]


## Return the anonymous icon color for a given
## peer. The local client's color is persisted
## across sessions. Remote peers get a random
## color cached for the current session.
func get_peer_anonymous_color(
	peer_id: int,
) -> Color:
	if peer_id in _peer_color_cache:
		return _peer_color_cache[peer_id]
	var hue: float
	if peer_id == multiplayer.get_unique_id():
		hue = local_settings.get_anonymous_color_hue()
	else:
		hue = randf()
	var color := Color.from_hsv(hue, 0.7, 0.9)
	_peer_color_cache[peer_id] = color
	return color


## Clear cached peer colors between matches.
func clear_peer_color_cache() -> void:
	_peer_color_cache.clear()
