# class_name G
extends Node
## Add global state here for easy access.

# Note: This would be better stored on Main as an export var, so we don't have
#       to reference the path in code. But, this must be set for tests to run
#       correctly, and Main isn't run during tests.
var settings: Settings = load("res://settings.tres")

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

var match_result_reporter: MatchResultReporter
var backend_api_client: BackendApiClient
var party_manager: PartyManager
var friends_notification_poller: FriendsNotificationPoller
var crash_reporter: CrashReporter
var profile_image_cache: ProfileImageCache
var auth_screen: AuthScreen
var consent_screen: ConsentScreen
var terms_screen: LegalDocScreen
var privacy_screen: LegalDocScreen
var data_deletion_screen: LegalDocScreen
var leaderboard_screen: LeaderboardScreen
var my_stats_screen: MyStatsScreen
var credits_screen: CreditsScreen
var language_screen: LanguageScreen

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
var side_panel_layer: CanvasLayer
var confirm_layer: CanvasLayer
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

var is_lobby_active: bool:
	get:
		return is_instance_valid(level) and level is LobbyLevel
var is_networked_level_active: bool:
	get:
		return is_instance_valid(level) and level is NetworkedLevel

var _peer_color_cache: Dictionary = {}


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	args = Utils.parse_command_line_args()

	# Wire the snoringcat-platform addon's autoload with this
	# game's identity. Must run before any subsystem creation so
	# Platform.token_store / Platform.nakama_client / Platform.auth
	# / etc. exist by the time addon subsystems are instantiated
	# and registered below.
	#
	# Stage 6.3 pinned auth_file_path = user://auth.cfg so existing
	# players' encrypted credentials remain readable across the
	# upgrade (the addon's default of user://%s_auth.cfg % game_id
	# would orphan every existing install).
	#
	# Stage 6.2 added the nakama_* and OAuth config keys so the
	# addon's PlatformAuthApiClient can read them without reaching
	# into game-side `settings.tres` or hardcoded constants.
	if not Platform.is_initialized:
		Platform.initialize({
			"game_id": str(
				ProjectSettings.get_setting(
					"application/config/game_id", "hopnbop")),
			"api_base_url": (
				"https://nakama.snoringcat.games"),
			"sdk_version": str(
				ProjectSettings.get_setting(
					"application/config/version", "0.0.0")),
			"auth_file_path": "user://auth.cfg",
			# Nakama connection. Server key + http key are "soft
			# secrets" (extractable from the shipped .pck) — they
			# pair with per-IP rate-limiting in Caddy. Rotation
			# requires a client release.
			"nakama_host": "nakama.snoringcat.games",
			"nakama_port": 443,
			"nakama_scheme": "https",
			"nakama_server_key": (
				"p65qPwZ3vhnsIzNU8/9tw1gR6AbkjGJ7GpTmMQbJ5fs="),
			"nakama_http_key": (
				"VVU3A4AYzs1HIh83J5KLccM4Kt6kiY2/jq3qwZHPqzQ="),
			# OAuth surface (game-specific URLs / IDs). The
			# token-broker URL points at the Cloudflare Pages
			# Function that adds GOOGLE_OAUTH_CLIENT_SECRET
			# server-side; source at
			# web/functions/api/oauth/google/exchange.js.
			"oauth_callback_url": settings.oauth_callback_url,
			"google_token_broker_url": (
				"https://hopnbop.net/api/oauth/google/exchange"),
			"google_oauth_client_id": (
				settings.google_oauth_client_id),
			"facebook_oauth_client_id": (
				settings.facebook_oauth_client_id),
		})

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

	# Stage 6.2: auth client lives in the addon as
	# PlatformAuthApiClient. Game code reads it via Platform.auth.
	# The class extends Node so we own its lifecycle via add_child;
	# register_subsystem stores the reference for consumer access.
	var auth := PlatformAuthApiClient.new()
	auth.name = "AuthApiClient"
	add_child(auth)
	Platform.register_subsystem("auth", auth)

	# Eagerly create the Nakama client so Platform.nakama_client is
	# populated before addon subsystems (Platform.friends,
	# Platform.presence, ...) are instantiated and registered below.
	# Platform.get_nakama_client() lazy-creates a NakamaClient
	# object (no network I/O) and caches it on Platform.nakama_client.
	Platform.get_nakama_client()

	match_result_reporter = MatchResultReporter.new()
	match_result_reporter.name = "MatchResultReporter"
	add_child(match_result_reporter)

	backend_api_client = BackendApiClient.new()
	backend_api_client.name = "BackendApiClient"
	add_child(backend_api_client)

	# Stage 6.4: friends client lives in the addon as
	# PlatformFriendsApiClient. Game code reads it via
	# Platform.friends. The class still extends Node so we own its
	# lifecycle via add_child; register_subsystem stores the
	# reference for consumer access.
	var friends := PlatformFriendsApiClient.new()
	friends.name = "FriendsApiClient"
	add_child(friends)
	Platform.register_subsystem("friends", friends)

	# Stage 6.7: presence (rich-presence write + online-friends
	# read) was previously bundled inside FriendsApiClient. Now its
	# own subsystem so a future game with no friend feature can
	# still ship presence (or vice versa). The platform-side RPC
	# (`update_and_get_presence`) is the same.
	var presence := PlatformPresenceApiClient.new()
	presence.name = "PresenceApiClient"
	add_child(presence)
	Platform.register_subsystem("presence", presence)

	# Stage 6.5: party client lives in the addon as
	# PlatformPartyApiClient. Game code reads it via Platform.party.
	# PartyManager (still game-side, kept that way like
	# friends_notification_poller because of its UI-dialog coupling
	# to G.toast_overlay / G.confirm_layer / G.game_panel) consumes
	# Platform.party for the underlying RPC surface.
	var party := PlatformPartyApiClient.new()
	party.name = "PartyApiClient"
	add_child(party)
	Platform.register_subsystem("party", party)

	# Stage 6.5b: realtime notification socket lives in the addon as
	# PlatformNotificationSocketClient. Game code reads it via
	# Platform.notification_socket. Must enter the tree before its
	# consumers (PartyManager, FriendsNotificationPoller) so their
	# _ready calls can connect to its signals. The socket itself
	# stays closed until auth_completed fires for a non-anonymous
	# user.
	var notification_socket := (
		PlatformNotificationSocketClient.new())
	notification_socket.name = "NotificationSocketClient"
	add_child(notification_socket)
	Platform.register_subsystem(
		"notification_socket", notification_socket)

	# Stage 6.6: Nakama matchmaker socket layer lives in the addon
	# as PlatformMatchmakingClient. Game code reads it via
	# Platform.matchmaking, with the game-side NakamaMatchmakerClient
	# SessionProvider adapter (instantiated per-session by
	# GameSessionManager) translating its platform-agnostic signals
	# into rollback-netcode session events and applying transport_type.
	# Registered here as a boot-time singleton so the same socket /
	# ticket lifecycle survives across GameSessionManager teardowns.
	var matchmaking := PlatformMatchmakingClient.new()
	matchmaking.name = "MatchmakingClient"
	add_child(matchmaking)
	Platform.register_subsystem("matchmaking", matchmaking)

	# Stage 6.8: cloud-backed settings split into two scopes
	# ("global" + "game/{game_id}"). Game code reads via
	# Platform.settings; SettingsCloudSync (still game-side) wraps
	# it with the LocalSettings serialize / apply mapping and a
	# one-shot legacy-blob migration.
	var settings_client := PlatformSettingsApiClient.new()
	settings_client.name = "SettingsApiClient"
	add_child(settings_client)
	Platform.register_subsystem("settings", settings_client)

	# Stage 6.9: passive session-lifecycle bus. The game-side
	# GameSessionManager (instantiated per-match by GamePanel) owns
	# the coordinator role and forwards each lifecycle event into
	# this node's signals so addon-side consumers can observe
	# without taking a hard dependency on the game-side class.
	var session_observer := PlatformSessionObserver.new()
	session_observer.name = "SessionObserver"
	add_child(session_observer)
	Platform.register_subsystem("session", session_observer)

	party_manager = PartyManager.new()
	party_manager.name = "PartyManager"
	add_child(party_manager)

	friends_notification_poller = (
		FriendsNotificationPoller.new())
	friends_notification_poller.name = (
		"FriendsNotificationPoller")
	add_child(friends_notification_poller)
	friends_notification_poller.start_polling()

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

	local_settings.setting_override_changed.connect(
		_on_local_setting_override_changed)

	# Cloud settings sync manager. Stage 6.2 moved the post-login
	# trigger out of the auth client (the addon shouldn't reach
	# back into game-side `G.settings_cloud_sync`) so connect it
	# here instead.
	settings_cloud_sync = SettingsCloudSync.new()
	(Platform.auth as PlatformAuthApiClient).auth_completed.connect(
		_on_auth_completed_for_cloud_sync)

	# Stage 1.5 cancellation prompt. AccountDeletionPrompt
	# subscribes to auth_completed and, when the user has a
	# pending account_deletion_queue row, opens a ConfirmOverlay
	# offering to cancel the soft-delete before the hourly cron
	# hard-deletes it.
	var deletion_prompt := AccountDeletionPrompt.new()
	deletion_prompt.name = "AccountDeletionPrompt"
	add_child(deletion_prompt)

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

	# Warm up the GameLift fleet for imminent online
	# play. Skip on dedicated server processes and
	# when the player has persisted offline-only
	# preference.
	if (not Netcode.is_server
			and not settings.prefer_offline_mode):
		backend_api_client.warm_up_fleet("startup")


func _on_auth_completed_for_cloud_sync(
	success: bool, _error: String,
) -> void:
	if success and settings_cloud_sync != null:
		settings_cloud_sync.fetch_and_merge_from_cloud()


func _on_local_setting_override_changed(
	key: StringName, value: Variant,
) -> void:
	# When the player toggles off offline mode,
	# fire a warmup so the fleet is ready by the
	# time they queue for a match.
	if (key == &"prefer_offline_mode"
			and value == false
			and not Netcode.is_server):
		backend_api_client.warm_up_fleet(
			"offline_toggle_off")


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
	# Game-over screen calls this AFTER disconnect, when
	# multiplayer.multiplayer_peer is null and get_unique_id()
	# errors. Treat any peer as remote in that case (random hue).
	var local_id := 0
	if multiplayer.multiplayer_peer != null:
		local_id = multiplayer.get_unique_id()
	var hue: float
	if peer_id == local_id and local_id != 0:
		hue = local_settings.get_anonymous_color_hue()
	else:
		hue = randf()
	var color := Color.from_hsv(hue, 0.7, 0.9)
	_peer_color_cache[peer_id] = color
	return color


## Clear cached peer colors between matches.
func clear_peer_color_cache() -> void:
	_peer_color_cache.clear()
