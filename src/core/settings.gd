class_name Settings
extends Resource


# --- General configuration ---

@export var dev_mode := true
@export var draw_annotations := false

@export var start_in_game := false
@export var full_screen := false
@export var mute_music := false
@export var pauses_on_focus_out := true
@export var is_screenshot_hotkey_enabled := true

@export var show_hud := true

# --- Game-specific configuration ---

# TODO

@export var gravity_acceleration := 5000.0
@export var gravity_slow_rise_multiplier := 0.38
@export var gravity_double_jump_slow_rise_multiplier := 0.68

@export var walk_acceleration := 8000.0
@export var in_air_horizontal_acceleration := 2500.0
@export var climb_up_speed := -230.0
@export var climb_down_speed := 120.0
@export var ceiling_crawl_speed := 230.0

@export var friction_coeff_with_sideways_input := 1.25
@export var friction_coeff_without_sideways_input := 1.0

@export var ground_jump_boost := -900.0
@export var wall_jump_horizontal_boost := 200.0
@export var wall_fall_horizontal_boost := 20.0

@export var max_horizontal_speed := 320.0
@export var max_vertical_speed := 2800.0
@export var min_horizontal_speed := 5.0
@export var min_vertical_speed := 0.0
