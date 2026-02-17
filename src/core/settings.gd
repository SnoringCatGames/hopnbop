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
@export var show_network_simulation := false
@export var are_cheats_enabled := true
@export var jetpack_acceleration := 1000.0
@export var jetpack_max_upward_speed := 270.0
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
@export var are_bumps_enabled := true

@export_group("Gore")
@export var is_gore_enabled := false
@export var gore_particle_scene: PackedScene
## Number of particles spawned per death.
@export var gore_particles_per_death := 20
## Spawn area offset from death position (player body center).
@export var gore_spawn_offset := Vector2(0.0, -6.0)
## Particles originate randomly within this radius of the death
## position.
@export var gore_spawn_scatter_radius := 7.0
## Initial speed range for fast particles (types 0-3).
@export var gore_fast_speed_min := 180.0
@export var gore_fast_speed_max := 320.0
## Initial speed range for slow particles (types 4-7).
@export var gore_slow_speed_min := 80.0
@export var gore_slow_speed_max := 160.0
## Added to random velocity Y to bias particles upward.
@export var gore_upward_bias := -120.0
## Velocity multiplier applied on each bounce.
@export var gore_bounce_damping := 0.4
## Velocity multiplier applied on each surface contact.
@export var gore_friction := 0.92
## Speed below which a particle is considered at rest.
@export var gore_rest_speed_threshold := 15.0
## Consecutive frames below rest threshold before rasterizing.
@export var gore_rest_frame_count := 3
@export var gore_collision_radius := 0.33
## Collision radius per particle type (pixels). Array length
## defines the number of particle types.
@export var gore_sprite_radii: Array[float] = [
	0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5,
]
## Gore texture paths (used when is_gore_enabled = true).
@export var gore_texture_paths: Array[String] = [
	"res://assets/images/gore/gore_0.png",
	"res://assets/images/gore/gore_1.png",
	"res://assets/images/gore/gore_2.png",
	"res://assets/images/gore/gore_3.png",
	"res://assets/images/gore/gore_4.png",
	"res://assets/images/gore/gore_5.png",
	"res://assets/images/gore/gore_6.png",
	"res://assets/images/gore/gore_7.png",
]
## Flower texture paths (used when is_gore_enabled = false).
@export var gore_flower_texture_paths: Array[String] = [
	"res://assets/images/flowers/flower_0.png",
	"res://assets/images/flowers/flower_1.png",
	"res://assets/images/flowers/flower_2.png",
	"res://assets/images/flowers/flower_3.png",
	"res://assets/images/flowers/flower_4.png",
	"res://assets/images/flowers/flower_5.png",
	"res://assets/images/flowers/flower_6.png",
	"res://assets/images/flowers/flower_7.png",
]
## Scene for kickable gore pieces.
@export var gore_kickable_scene: PackedScene
## Number of kickables spawned per death.
@export var gore_kickables_per_death := 5
## Collision radius for large kickable pieces.
@export var gore_kickable_collision_radius := 1.5
## Collision radius for small kickable pieces.
@export var gore_kickable_small_collision_radius := 1.0
## Radius of the Area2D that detects player kicks.
@export var gore_kickable_kick_area_radius := 6.0
## Minimum initial speed for kickables.
@export var gore_kickable_speed_min := 60.0
## Maximum initial speed for kickables.
@export var gore_kickable_speed_max := 140.0
## Velocity multiplier when kicked by a player.
@export var gore_kickable_kick_multiplier := 1.2
## Minimum upward velocity applied on kick (pixels/sec).
@export var gore_kickable_min_kick_pop := 200.0
## Repulsion speed pushing gore away from the kicking player.
@export var gore_kickable_repulsion_speed := 120.0
## Maximum speed a kickable can reach from a kick.
@export var gore_kickable_max_kick_speed := 400.0
## Seconds before a kickable starts fading.
@export var gore_kickable_lifetime_sec := 5.0
## Duration of the fade-out tween.
@export var gore_kickable_fade_duration_sec := 2.0
## Bounce damping for kickables (0 = no bounce, 1 = full).
@export var gore_kickable_bounce_damping := 0.35
## Friction multiplier for kickables on contact.
@export var gore_kickable_friction := 0.92
## Cooldown between kicks (seconds).
@export var gore_kickable_kick_cooldown_sec := 0.15
@export_group("")

# Types 0 through half are "fast", the rest are "slow".
const GORE_FAST_TYPE_END := 3

@export_group("Logs")
## Logs with these categories won't be shown.
@export var excluded_log_categories: Array[StringName] = [
	#NetworkLogger.CATEGORY_DEFAULT,
	#NetworkLogger.CATEGORY_CORE_SYSTEMS,
	NetworkLogger.CATEGORY_SYSTEM_INITIALIZATION,
	NetworkLogger.CATEGORY_PLAYER_ACTIONS,
	#NetworkLogger.CATEGORY_CONNECTIONS,
	#NetworkLogger.CATEGORY_NETWORK_SYNC,
	#NetworkLogger.CATEGORY_USER_INTERACTION,
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

@export var default_gravity_acceleration := 1000.0

@export_group("Level Registry")
## Registered levels for dynamic selection. The first enabled level is the
## default.
@export var levels: Array[LevelInfo] = []
@export_group("")

@export var default_player_scene: PackedScene
@export var player_scenes: Array[PackedScene] = []

@export_group("Player Appearance")
## Available body types. Index matches body_type_index
## in GamePlayerState.
@export var body_types: Array[BodyTypeConfig] = []
## Available costumes. Index matches costume_index in
## GamePlayerState. All costumes work with all body
## types.
@export var costumes: Array[CostumeConfig] = []
## Crown costume config. Shown as an additional overlay
## independent of the selected costume.
@export var crown_costume: CostumeConfig = null
@export_group("")

@export_group("Player Mechanics")
@export var player_respawn_cooldown_sec := 2.0
@export var player_invincibility_duration_sec := 2.0
@export var player_invincibility_blink_frequency_hz := 8.0
@export_group("")

@export_group("Match Settings")
@export var match_duration_sec := 1 * 60.0 # 5 minutes
@export var match_end_disconnect_delay_sec := 3.0
@export_group("")


func gore_is_fast_type(type_index: int) -> bool:
	return type_index <= GORE_FAST_TYPE_END


func gore_get_speed_range(type_index: int) -> Vector2:
	if gore_is_fast_type(type_index):
		return Vector2(gore_fast_speed_min, gore_fast_speed_max)
	return Vector2(gore_slow_speed_min, gore_slow_speed_max)
