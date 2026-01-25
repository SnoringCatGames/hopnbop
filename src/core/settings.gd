class_name Settings
extends Resource

# --- General configuration ---

@export_group("Network connection")
@export var preview_connect_to_remote_server := false
@export var preview_run_multiple_clients := false
var preview_client_count: int:
	get:
		return 2 if preview_run_multiple_clients else 1
# FIXME: [GameLift]: Set up support to connect to a remote server.
@export var remote_server_ip_address: StringName = "127.0.0.1"
@export var remote_server_port := 4433
@export var local_server_ip_address: StringName = "127.0.0.1"
@export var local_server_port := 4433
var server_ip_address: StringName:
	get:
		return remote_server_ip_address if preview_connect_to_remote_server else local_server_ip_address
var server_port: int:
	get:
		return remote_server_port if preview_connect_to_remote_server else local_server_port
@export_group("")

@export_group("Network sync")
## Network process frames happen at 60 FPS--aligned with physics frames.
@export var rollback_buffer_duration_sec := 2.0
## Whether clients can request pause/unpause from the server. If false, only
## the server can trigger pause (e.g., during GameLift initialization).
@export var is_server_pause_enabled := true
## Cooldown period between pause requests (in seconds). Prevents spam.
@export var pause_request_cooldown_sec := 0.5
@export_group("")

@export var max_client_count := 8

# FIXME: Review this.
@export_group("GameLift")
@export var use_gamelift := false
@export var gamelift_anywhere_mode := false
@export var gamelift_anywhere_websocket := ""
@export var gamelift_anywhere_auth_token := ""
@export var gamelift_anywhere_fleet_id := ""
@export var gamelift_anywhere_host_id := ""
@export var gamelift_anywhere_process_id := ""
@export_group("")

@export var dev_mode := true
@export var auto_minimize_server_window := true
@export var draw_annotations := false
@export var show_debug_console := false
@export var show_debug_player_state := false
@export var show_perf_tracker := false

@export var start_in_game := false
@export var skip_splash := false
@export var full_screen := false
@export var mute_music := false
@export var pauses_on_focus_out := false
@export var is_screenshot_hotkey_enabled := true

@export var does_up_also_trigger_jump := true

@export var show_hud := true

@export var godot_splash_duration_sec := 0.9
@export var scg_splash_duration_sec := 0.9

@export_group("Logs")
## Logs with these categories won't be shown.
@export var excluded_log_categories: Array[StringName] = [
	#ScaffolderLog.CATEGORY_DEFAULT,
	#ScaffolderLog.CATEGORY_CORE_SYSTEMS,
	ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION,
	ScaffolderLog.CATEGORY_PLAYER_ACTIONS,
	#ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
	#ScaffolderLog.CATEGORY_NETWORK_SYNC,
	#ScaffolderLog.CATEGORY_INTERACTION,
	#ScaffolderLog.CATEGORY_GAME_STATE,
]
## If true, warning logs will be shown regardless of category filtering.
@export var force_include_log_warnings := true
@export var include_category_in_logs := true
@export var include_peer_id_in_logs := true
@export var verbosity := ScaffolderLog.Verbosity.NORMAL
@export_group("")

@export var default_theme: Theme
@export var default_palette: ScaffolderColorPalette
@export var screen_style_box: StyleBox

@export_group("Local Multiplayer")
@export var local_player_max := 4
@export var lobby_level_scene: PackedScene
@export_group("")

# --- Game-specific configuration ---

@export var default_gravity_acceleration := 5000.0

@export var default_level_scene: PackedScene
@export var level_scenes: Array[PackedScene] = []

@export var default_player_scene: PackedScene
@export var player_scenes: Array[PackedScene] = []
