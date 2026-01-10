class_name Settings
extends Resource


# --- General configuration ---

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

# --- Game-specific configuration ---

@export var default_gravity_acceleration := 5000.0

@export var player_scene: PackedScene
@export var default_level_scene: PackedScene
