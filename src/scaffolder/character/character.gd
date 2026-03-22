@tool
class_name Character
extends CharacterBody2D

const _NORMAL_SURFACES_COLLISION_MASK_BIT := 1 << 0
const _FALL_THROUGH_FLOORS_COLLISION_MASK_BIT := 1 << 1
const _WALK_THROUGH_WALLS_COLLISION_MASK_BIT := 1 << 2
const _PLAYER_COLLISION_MASK_BIT := 1 << 3
const _ENEMY_COLLISION_MASK_BIT := 1 << 4
const _PLAYER_PROJECTILE_COLLISION_MASK_BIT := 1 << 5
const _ENEMY_PROJECTILE_COLLISION_MASK_BIT := 1 << 6
const _FOOT_PROJECTILE_COLLISION_MASK_BIT := 1 << 7
const _HEAD_PROJECTILE_COLLISION_MASK_BIT := 1 << 8

# Minimum horizontal advance per frame when sliding
# off an ice edge. Ensures the character clears the
# tile corner in a reasonable number of frames even
# at very slow speeds.
const _ICE_EDGE_MIN_ADVANCE_PX := 0.5

# Duration to suppress air horizontal friction after
# leaving an ice floor. Prevents the character from
# decelerating immediately when sliding off an ice edge.
const _ICE_AIR_FRICTION_COOLDOWN_SEC := 0.2

# Vertical nudge applied before move_and_slide on the
# first frame of a launch. Lifts the collision circle
# above seams between the launch body and adjacent
# colinear floor tiles. The nudge is reversed after
# move_and_slide. Must exceed the collision shape
# radius (5px) minus the resting floor-to-center
# distance (5px) plus safe_margin (0.08px) plus any
# embedding from the previous frame's floor snap.
const _LAUNCH_SEAM_NUDGE_PX := 4.0

@export var collision_shape: CollisionShape2D:
	set(value):
		collision_shape = value
		update_configuration_warnings()

@export var animator: CharacterAnimator:
	set(value):
		animator = value
		update_configuration_warnings()

@export var movement_settings: MovementSettings:
	set(value):
		movement_settings = value
		update_configuration_warnings()

@export var state_from_server: CharacterStateFromServer:
	set(value):
		state_from_server = value
		update_configuration_warnings()

var peer_id: int:
	get:
		return state_from_server.peer_id

var start_position := Vector2.INF

var previous_position := Vector2.INF
var previous_velocity := Vector2.INF

## Velocity before move_and_slide() modifies it. Used for
## collision callbacks (Area2D) that fire after physics,
## where the post-move_and_slide velocity may have been
## zeroed by surface collision resolution.
var pre_movement_velocity := Vector2.ZERO

var last_triggered_jump_frame_index := -1
var last_water_hop_frame_index := -1

var jump_sequence_count := 0

var _current_max_horizontal_speed_multiplier := 1.0

# Frame index when force_launch was last called. Used to prevent immediate
# floor re-attachment after a bounce.
var _last_launch_frame_index := -1

# Frame index when the character was last on an ice floor.
# Used to suppress air horizontal friction after leaving ice.
var _last_ice_floor_frame_index := -1
# Duration to prevent floor attachment after a launch.
const _LAUNCH_FLOOR_ATTACHMENT_COOLDOWN_SEC := 0.05


## Top edge of the water surface (global Y).
## Updated each frame when in water.
var water_surface_y := 0.0

var surfaces := CharacterSurfaceState.new(self )
var actions := CharacterActionState.new()

# Array<CharacterActionSource>
var _action_sources := []
# Dictionary<StringName, bool>
var _previous_actions_handlers_this_frame := {}

var current_surface_max_horizontal_speed: float:
	get:
		if surfaces.is_in_water:
			return (
				movement_settings
					.water_max_horizontal_speed
			)
		return (
			movement_settings
				.max_ground_horizontal_speed
			* _current_max_horizontal_speed_multiplier
			* (
				surfaces.surface_properties
					.speed_multiplier
				if surfaces.is_attaching_to_surface
				else 1.0
			)
		)

var current_air_max_horizontal_speed: float:
	get:
		if surfaces.is_in_water:
			return (
				movement_settings
					.water_max_horizontal_speed
			)
		if surfaces.is_launched:
			# Guard against stale initial_launch_velocity
			# during rollback. update_touches() resets it to
			# INF when the character lands. If a rollback
			# then rewinds to a frame where is_launched was
			# true (via bitmask), the INF would produce
			# max_launch_horizontal_speed (300) instead of
			# the correct cap. Default to
			# max_air_horizontal_speed in this case.
			if (
				surfaces.initial_launch_velocity
					== Vector2.INF
			):
				return (
					movement_settings
						.max_air_horizontal_speed
				)
			var initial_launch_horizontal_speed := absf(
				surfaces.initial_launch_velocity.x)
			if (
				initial_launch_horizontal_speed
				> movement_settings
					.max_launch_horizontal_speed
			):
				return (
					movement_settings
						.max_launch_horizontal_speed
				)
			elif (
				initial_launch_horizontal_speed
				> movement_settings
					.max_air_horizontal_speed
			):
				return initial_launch_horizontal_speed
			else:
				return (
					movement_settings
						.max_air_horizontal_speed
				)
		else:
			return (
				movement_settings
					.max_air_horizontal_speed
				* _current_max_horizontal_speed_multiplier
			)

var current_max_vertical_speed: float:
	get:
		if surfaces.is_launched:
			# Guard against stale initial_launch_velocity
			# during rollback (same pattern as horizontal).
			if (
				surfaces.initial_launch_velocity
					== Vector2.INF
			):
				return (
					movement_settings
						.max_vertical_speed
				)
			var initial_launch_vertical_speed := absf(
				surfaces.initial_launch_velocity.y)
			if (
				initial_launch_vertical_speed
				> movement_settings
					.max_launch_vertical_speed
			):
				return (
					movement_settings
						.max_launch_vertical_speed
				)
			elif (
				initial_launch_vertical_speed
				> movement_settings
					.max_vertical_speed
			):
				return initial_launch_vertical_speed
			else:
				return (
					movement_settings
						.max_vertical_speed
				)
		else:
			return movement_settings.max_vertical_speed

var current_walk_acceleration: float:
	get:
		var multiplier := 1.0
		if surfaces.is_attaching_to_surface:
			multiplier = (
				surfaces.surface_properties
					.speed_multiplier
				* surfaces.surface_properties
					.acceleration_multiplier
			)
		return (
			movement_settings.walk_acceleration
			* multiplier
		)

var current_climb_up_speed: float:
	get:
		return (
			movement_settings.climb_up_speed
			* (
				surfaces.surface_properties
					.speed_multiplier
				if surfaces.is_attaching_to_surface
				else 1.0
			)
		)

var current_climb_down_speed: float:
	get:
		return (
			movement_settings.climb_down_speed
			* (
				surfaces.surface_properties
					.speed_multiplier
				if surfaces.is_attaching_to_surface
				else 1.0
			)
		)

var current_ceiling_crawl_speed: float:
	get:
		return (
			movement_settings.ceiling_crawl_speed
			* (
				surfaces.surface_properties
					.speed_multiplier
				if surfaces.is_attaching_to_surface
				else 1.0
			)
		)

var is_sprite_visible: bool:
	set(value):
		animator.visible = value
	get:
		return animator.visible


func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	pass


func _ready() -> void:
	update_configuration_warnings()

	if Engine.is_editor_hint():
		return

	Netcode.check(_get_configuration_warnings().is_empty())

	movement_settings.set_up()

	start_position = position

	# Start facing right with rest animation.
	surfaces.is_facing_right = true
	animator.face_right()
	animator.play("Rest")

	# Initialize position/velocity in state_from_server, but leave surfaces at
	# default (0) since it's only valid after first physics update.
	state_from_server.position = position
	state_from_server.velocity = velocity
	# state_from_server.surfaces intentionally left at default 0.

	_set_up_action_sources()

	# For move_and_slide.
	up_direction = Vector2.UP
	floor_stop_on_slope = false
	max_slides = MovementSettings._MAX_SLIDES_DEFAULT
	floor_max_angle = G.geometry.FLOOR_MAX_ANGLE + G.geometry.WALL_ANGLE_EPSILON


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	pass


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	pass


func _set_up_action_sources() -> void:
	pass


## This gets called during _network_process, just before _apply_movement.
func _collect_actions() -> void:
	# Clear actions for the current frame.
	actions.clear()

	# Update actions for the current frame.
	for action_source in _action_sources:
		action_source.update(
			actions,
			Netcode.time.get_time_step_sec())

	actions.log_new_presses_and_releases(self )

	surfaces.update_actions()

	# Record the frame when jump is triggered for network reconciliation.
	if actions.just_triggered_jump:
		last_triggered_jump_frame_index = Netcode.server_frame_index


## This gets called during _network_process.
func _apply_movement() -> void:
	# Update collision mask BEFORE move_and_slide to ensure correct physics.
	_update_collision_mask()

	# Save state for potential collision correction.
	var saved_position := position
	var saved_velocity := velocity

	# Save velocity before move_and_slide for Area2D
	# collision callbacks that fire after physics.
	pre_movement_velocity = velocity

	# When descending through floors while pressing into a wall, temporarily
	# zero horizontal velocity to prevent wall collision from zeroing Y velocity.
	# Godot's move_and_slide collision resolution can reduce vertical velocity
	# when sliding along a wall corner.
	var saved_velocity_x := velocity.x
	var should_preserve_wall_slide := (
		surfaces.is_descending_through_floors
		and surfaces.is_pressing_into_wall
	)
	if should_preserve_wall_slide:
		velocity.x = 0.0

	# During launch cooldown, use floating motion mode so
	# move_and_slide bypasses all floor-specific behavior
	# (snap, constant speed on slopes, wall blocking).
	# Godot's internal was_on_floor state persists from the
	# pre-launch move_and_slide, causing the grounded path
	# to decompose diagonal movement differently when
	# holding sideways, which reduces effective upward
	# travel.
	var is_on_ice := (
		surfaces.is_attaching_to_floor
		and surfaces.surface_properties.is_ice
	)
	if is_on_ice:
		_last_ice_floor_frame_index = (
			Netcode.server_frame_index
		)
	var saved_motion_mode := motion_mode
	var did_launch_nudge := false
	if is_in_launch_cooldown():
		motion_mode = (
			CharacterBody2D.MOTION_MODE_FLOATING
		)
		# On the first frame after a launch, nudge
		# position up before move_and_slide and zero
		# horizontal velocity. The launch point can
		# be colinear with adjacent floor tiles
		# (e.g., spring next to terrain). The
		# collision circle catches on the seam
		# between collision bodies during diagonal
		# movement, reducing upward travel. The
		# nudge lifts the circle above the seam.
		# Zeroing horizontal velocity prevents any
		# remaining diagonal movement from clipping
		# the adjacent tile. Both are reversed after
		# move_and_slide so force_launch's own nudge
		# applies from the correct baseline and
		# horizontal speed is preserved.
		var frames_since_launch := (
			Netcode.server_frame_index
			- _last_launch_frame_index
		)
		if frames_since_launch <= 1:
			position.y -= _LAUNCH_SEAM_NUDGE_PX
			did_launch_nudge = true

	var saved_launch_velocity_x := velocity.x
	if did_launch_nudge:
		velocity.x = 0.0

	move_and_slide()

	motion_mode = saved_motion_mode

	if did_launch_nudge:
		position.y += _LAUNCH_SEAM_NUDGE_PX
		velocity.x = saved_launch_velocity_x

	# On ice, the circle collision shape gets stuck
	# at tile corners because move_and_slide cannot
	# advance past the contact point. Override
	# horizontal position to the expected value so
	# the character passes through the corner.
	# Velocity is also preserved so the character
	# maintains momentum. Only actual walls (nearly
	# horizontal collision normal) block the override.
	# Corner contacts have angled normals that are
	# distinguishable from real walls.
	var is_stuck_at_ice_edge := false
	if is_on_ice and not should_preserve_wall_slide:
		var has_true_wall := false
		for i in get_slide_collision_count():
			var n := get_slide_collision(i).get_normal()
			if absf(n.x) > 0.9:
				has_true_wall = true
				break
		if not has_true_wall:
			var delta_time := (
				Netcode.time.get_time_step_sec()
			)
			var expected_dx := (
				saved_velocity.x * delta_time
			)
			# At slow speeds, ensure a minimum advance
			# so the character clears the corner within
			# a few frames instead of imperceptibly
			# creeping past it.
			var actual_dx := (
				position.x - saved_position.x
			)
			if (
				absf(expected_dx) > 0.001
				and absf(actual_dx)
					< absf(expected_dx) * 0.9
			):
				is_stuck_at_ice_edge = true
				var min_dx := (
					signf(saved_velocity.x)
					* _ICE_EDGE_MIN_ADVANCE_PX
				)
				if absf(expected_dx) < absf(min_dx):
					expected_dx = min_dx
			position.x = (
				saved_position.x + expected_dx
			)
		velocity.x = saved_velocity.x

	# Restore horizontal velocity after move_and_slide.
	if should_preserve_wall_slide:
		velocity.x = saved_velocity_x

	# Update touch state and correct any invalid one-way collisions.
	surfaces.update_touches(saved_position, saved_velocity)

	# Re-evaluate attachment state after collision detection.
	# The first update_actions() call (during input handling) used
	# stale touching state from the rollback buffer. After
	# move_and_slide + update_touches, touching state reflects the
	# actual collision. Re-running update_actions ensures attachment
	# decisions (and thus surface_type) are based on the real
	# post-movement collision state. Without this, a character that
	# just jumped would still show surface_type=FLOOR on the next
	# frame (buffer says touching floor from before the jump moved
	# the character up), causing FloorDefaultAction to zero the
	# jump velocity.
	surfaces.update_actions()

	# When stuck at an ice edge, the position override
	# advances the character past the tile corner, but
	# collision data from move_and_slide is stale and
	# still reports floor contact. This keeps
	# surface_type as FLOOR, causing FloorDefaultAction
	# to zero velocity.y and FloorFrictionAction to
	# decelerate. Clear floor attachment to force an
	# immediate air transition so gravity applies and
	# horizontal momentum is preserved.
	if is_stuck_at_ice_edge:
		surfaces.is_attaching_to_floor = false

	# Update water state from tilemap after
	# position is finalized.
	_update_water_state()


## Update derived behaviors based on current movement and actions.
## This gets called during _network_process, just after _apply_movement.
func _process_movement_and_actions() -> void:
	_process_facing_direction()
	_process_actions()
	_process_animation()
	_process_sounds()
	_update_collision_mask()


## Called every network frame regardless of death state. Override
## in subclasses to handle client-side effects (sounds, particles)
## that must fire even when the character is dead.
func _process_client_effects() -> void:
	pass


func _process_facing_direction() -> void:
	# Flip the horizontal direction of the animation according to which way the
	# character is facing.
	if surfaces.horizontal_facing_sign == 1:
		animator.face_right()
	elif surfaces.horizontal_facing_sign == -1:
		animator.face_left()


# Updates physics and character states in response to the current actions.
func _process_actions() -> void:
	_previous_actions_handlers_this_frame.clear()

	for action_handler in movement_settings.action_handlers:
		# Don't run FloorDefaultAction when descending through floors, as it
		# zeros velocity and prevents gravity from accumulating. But DO allow
		# FallThroughFloorAction to run so we get the initial velocity launch.
		var is_blocked_floor_action := (
			surfaces.is_descending_through_floors
			and action_handler.name
				== &"FloorDefaultAction"
		)

		# Our surface-state logic considers the current actions, and
		# surface-state is updated before we process actions here.
		# Furthermore, we use action-handlers to actually apply the
		# changes for things like jump impulses that are needed to
		# actually transition the character from a surface. So we need
		# to also consider the surface that we are currently leaving,
		# and allow an action-handler of that departure-surface-type to
		# handle this frame. However, "Default" actions maintain steady-
		# state behavior and should not run during surface transitions.
		var is_just_left_and_not_default: bool = (
			action_handler.type
				== surfaces.just_left_surface_type
			and surfaces.just_left_surface_type
				!= SurfaceType.OTHER
			and !action_handler.name.contains("Default")
		)
		var is_action_relevant_for_surface: bool = (
			action_handler.type == surfaces.surface_type
			or action_handler.type == SurfaceType.OTHER
			or is_just_left_and_not_default
		)
		var is_action_relevant_for_physics_mode: bool = (
			action_handler.uses_runtime_physics
		)
		if (is_action_relevant_for_surface
				and is_action_relevant_for_physics_mode
				and not is_blocked_floor_action):
			var executed: bool = (
				action_handler.process(self )
			)
			_previous_actions_handlers_this_frame[
				action_handler.name
			] = executed

	assert(!Geometry.is_point_partial_inf(velocity))


func _update_water_state() -> void:
	if not is_instance_valid(G.level):
		surfaces.is_in_water = false
		return
	var in_water := G.level.is_position_in_water(
		global_position)
	surfaces.is_in_water = in_water
	if surfaces.just_entered_water:
		surfaces.last_water_entry_frame_index = (
			Netcode.server_frame_index
		)
	if in_water:
		water_surface_y = (
			G.level.get_water_surface_y(
				global_position)
		)


func _process_animation() -> void:
	# Water animation overrides surface-type
	# animations.
	if surfaces.is_in_water:
		if velocity.y < 0:
			animator.play("JumpRise")
		elif velocity.y > 0:
			animator.play("JumpFall")
		else:
			animator.play("Swim")
		return

	match surfaces.surface_type:
		SurfaceType.FLOOR:
			if actions.pressed_left or actions.pressed_right:
				animator.play("Walk")
			else:
				animator.play("Rest")
		SurfaceType.WALL:
			if processed_action("WallClimbAction"):
				if actions.pressed_up:
					animator.play("ClimbUp")
				elif actions.pressed_down:
					animator.play("ClimbDown")
				else:
					Netcode.fatal("SurfacerCharacter._process_animation")
			else:
				animator.play("RestOnWall")
		SurfaceType.CEILING:
			if actions.pressed_left or actions.pressed_right:
				animator.play("CrawlOnCeiling")
			else:
				animator.play("RestOnCeiling")
		SurfaceType.AIR:
			if velocity.y > 0:
				animator.play("JumpFall")
			else:
				animator.play("JumpRise")
		_:
			Netcode.fatal("SurfacerCharacter._process_animation")


func _process_sounds() -> void:
	if actions.just_triggered_jump:
		play_sound("jump")
	elif (
		last_water_hop_frame_index
			== Netcode.server_frame_index
	):
		# The before-contact water hop fires without
		# just_triggered_jump, so play the sound here.
		play_sound("jump")

	if surfaces.just_left_air:
		play_sound("land")
	# Don't play wall-impact sounds. Too many false-positives.
	#elif surfaces.just_touched_surface:
		#play_sound("land")


func play_sound(_sound_name: StringName) -> void:
	Netcode.fatal("Abstract CharacterActionSource.update is not implemented")


func processed_action(p_name: StringName) -> bool:
	return _previous_actions_handlers_this_frame.get(p_name) == true


# Update whether or not we should currently consider collisions with
# fall-through floors and walk-through walls.
func _update_collision_mask() -> void:
	# Only disable fall-through floor collision when explicitly descending.
	# Invalid one-way collisions (from the side) are now handled by
	# post-collision filtering in _fix_invalid_one_way_collisions().
	var is_fall_through_floor_bit_enabled := not surfaces.is_descending_through_floors
	set_collision_mask_value(
		_FALL_THROUGH_FLOORS_COLLISION_MASK_BIT,
		is_fall_through_floor_bit_enabled,
	)
	#set_collision_mask_value(
	#_WALK_THROUGH_WALLS_COLLISION_MASK_BIT,
	#surfaces.is_attaching_to_walk_through_walls)


## Virtual method to set collision and visibility state based on collidability.
## Override in subclasses to handle character-specific collision logic.
func set_is_collidable(_is_collidable: bool) -> void:
	# Default: no-op. Subclasses override to implement specific behavior.
	pass


func force_launch(boost: Vector2) -> void:
	velocity = boost

	position += Vector2(0.0, -1.0)
	surfaces.force_launch(boost)

	# Record the frame when launch was applied to prevent floor re-attachment.
	_last_launch_frame_index = Netcode.server_frame_index


## Returns true if floor attachment should be blocked due to recent launch.
## This prevents the character from immediately re-attaching to the floor
## after a bounce (kill/bump), which would cause FloorDefaultAction to zero
## the upward velocity.
func is_in_launch_cooldown() -> bool:
	if _last_launch_frame_index < 0:
		return false
	var frames_since_launch := (
		Netcode.server_frame_index
		- _last_launch_frame_index
	)
	var cooldown_frames := int(
		_LAUNCH_FLOOR_ATTACHMENT_COOLDOWN_SEC
		/ Netcode.time.get_time_step_sec()
	)
	return frames_since_launch < cooldown_frames


## Returns true if air horizontal friction should be
## suppressed because the character recently left an
## ice floor. This prevents immediate deceleration
## when sliding off an ice edge.
func is_in_ice_air_friction_cooldown() -> bool:
	if _last_ice_floor_frame_index < 0:
		return false
	var frames_since_ice := (
		Netcode.server_frame_index
		- _last_ice_floor_frame_index
	)
	var cooldown_frames := int(
		_ICE_AIR_FRICTION_COOLDOWN_SEC
		/ Netcode.time.get_time_step_sec()
	)
	return frames_since_ice < cooldown_frames


func get_next_position_prediction() -> Vector2:
	# Since move_and_slide automatically accounts for delta, we need to
	# compensate for that in order to support our modified framerate.
	return position + velocity * Netcode.frame_driver.target_network_time_step_sec


func get_position_in_screen_space() -> Vector2:
	return G.utils.get_screen_position_of_node_in_level(self )


func get_is_player_control_active() -> bool:
	return false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_instance_valid(collision_shape):
		warnings.append("collision_shape is not set")
	if not is_instance_valid(animator):
		warnings.append("animator is not set")
	if not is_instance_valid(movement_settings):
		warnings.append("movement_settings is not set")
	if not is_instance_valid(state_from_server):
		warnings.append("state_from_server is not set")
	return warnings
