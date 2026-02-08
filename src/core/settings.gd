class_name Settings
extends NetworkSettings
## Game settings extending rollback netcode configuration.
##
## This class extends NetworkSettings to provide all network settings plus
## game-specific configuration. Dynamic values like
## is_preview_mode are computed during initialization.


# FIXME: Review this.
@export_group("GameLift")
@export var gamelift_anywhere_mode := false
@export var gamelift_anywhere_websocket := ""
@export var gamelift_anywhere_auth_token := ""
@export var gamelift_anywhere_fleet_id := ""
@export var gamelift_anywhere_host_id := ""
@export var gamelift_anywhere_process_id := ""
@export var gamelift_backend_api_url := "https://api.example.com"
@export var gamelift_matchmaking_timeout_sec := 30.0
@export_group("")

@export_group("Debug & Development")
@export var dev_mode := true
## If your machine isn't super powerful, you might want to keep the server
## window up, so its performance isn't throttled.
@export var auto_minimize_server_window := false
@export var move_preview_windows_to_other_display := true
@export var draw_annotations := false
@export var show_debug_console := false
@export var show_debug_player_state := false
@export var show_perf_tracker := false
@export_group("")

@export var start_in_game := false
@export var skip_splash := false
@export var full_screen := false
@export var mute_music := false

@export var does_up_also_trigger_jump := true

@export var show_hud := true
@export var show_player_overhead_labels := true
@export var show_player_outlines := true

@export var godot_splash_duration_sec := 0.9
@export var scg_splash_duration_sec := 0.9
@export var screen_transition_duration := 0.7

@export var bunny_collision_shape: Shape2D

@export var use_simple_score := true
@export var is_gore_enabled := false

@export_group("Logs")
## Logs with these categories won't be shown.
@export var excluded_log_categories: Array[StringName] = [
	#NetworkLogger.CATEGORY_DEFAULT,
	#NetworkLogger.CATEGORY_CORE_SYSTEMS,
	NetworkLogger.CATEGORY_SYSTEM_INITIALIZATION,
	NetworkLogger.CATEGORY_PLAYER_ACTIONS,
	#NetworkLogger.CATEGORY_CONNECTIONS,
	NetworkLogger.CATEGORY_NETWORK_SYNC,
	#NetworkLogger.CATEGORY_INTERACTION,
	#NetworkLogger.CATEGORY_GAME_STATE,
]
## If true, warning logs will be shown regardless of category filtering.
@export var force_include_log_warnings := true
@export var include_category_in_logs := true
@export var include_peer_id_in_logs := true
@export_group("")

@export var default_theme: Theme
@export var default_palette: ScaffolderColorPalette
@export var screen_style_box: StyleBox

@export_group("Local Multiplayer")
## Lobby level scene for local multiplayer.
@export var lobby_level_scene: PackedScene
@export_group("")

# --- Game-specific configuration ---

@export var default_gravity_acceleration := 1300.0

@export_group("Level Registry")
## Registered levels for dynamic selection. The first enabled level is the
## default.
@export var levels: Array[LevelInfo] = []
@export_group("")

@export var default_player_scene: PackedScene
@export var player_scenes: Array[PackedScene] = []

@export_group("Player Mechanics")
@export var player_respawn_cooldown_sec := 2.0
@export var player_invincibility_duration_sec := 2.0
@export var player_invincibility_blink_frequency_hz := 8.0
@export_group("")

@export_group("Match Settings")
@export var match_duration_sec := 1 * 60.0 # 5 minutes
@export var match_end_disconnect_delay_sec := 3.0
@export_group("")
