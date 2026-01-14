class_name Settings
extends Resource


# --- General configuration ---

@export_group("Network connection")
@export var connect_to_remote_server := false
@export var run_multiple_clients := false
# FIXME: [GameLift]: Set up support to connect to a remote server.
@export var remote_server_ip_address: StringName = "127.0.0.1"
@export var remote_server_port := 4433
@export var local_server_ip_address: StringName = "127.0.0.1"
@export var local_server_port := 4433
var server_ip_address: StringName:
    get: return remote_server_ip_address if connect_to_remote_server else local_server_ip_address
var server_port: int:
    get: return remote_server_port if connect_to_remote_server else local_server_port
@export_group("")

@export_group("Network sync")
## Presumably network process frames happen at 60 FPS--aligned with physics frames.
@export var rollback_buffer_duration_sec := 1.5
@export_group("")

@export var max_client_count := 8

@export var dev_mode := true
@export var draw_annotations := false
@export var show_debug_console := false
@export var show_debug_player_state := false

@export var start_in_game := true
@export var full_screen := false
@export var mute_music := false
@export var pauses_on_focus_out := true
@export var is_screenshot_hotkey_enabled := true

@export var show_hud := true

@export_group("Logs")
## Logs with these categories won't be shown.
@export var excluded_log_categories: Array[StringName] = [
    #ScaffolderLog.CATEGORY_DEFAULT,
    #ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION,
    #ScaffolderLog.CATEGORY_PLAYER_MOVEMENT,
    #ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
]
## If true, warning logs will be shown regardless of category filtering.
@export var force_include_log_warnings := true
@export var include_category_in_logs := true
@export var include_multiplayer_id_in_logs := true
@export_group("")

@export var default_theme: Theme
@export var default_palette: ColorPalette
@export var screen_style_box: StyleBox

# --- Game-specific configuration ---

@export var default_gravity_acceleration := 5000.0

@export var default_level_scene: PackedScene
@export var level_scenes: Array[PackedScene] = []

@export var default_player_scene: PackedScene
@export var player_scenes: Array[PackedScene] = []
