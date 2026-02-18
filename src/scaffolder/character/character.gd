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

var last_triggered_jump_frame_index := -1
var _last_processed_jump_frame_index := -1
const _JUMP_EVENT_STALENESS_THRESHOLD_SEC := 0.5

var jump_sequence_count := 0

var _current_max_horizontal_speed_multiplier := 1.0

# Frame index when force_launch was last called. Used to prevent immediate
# floor re-attachment after a bounce.
var _last_launch_frame_index := -1
# Number of frames to prevent floor attachment after a launch.
const _LAUNCH_FLOOR_ATTACHMENT_COOLDOWN_FRAMES := 3

var surfaces := CharacterSurfaceState.new(self )
var actions := CharacterActionState.new()

# Array<CharacterActionSource>
var _action_sources := []
# Dictionary<StringName, bool>
var _previous_actions_handlers_this_frame := {}

var current_surface_max_horizontal_speed: float:
	get:
		return movement_settings.max_ground_horizontal_speed * \
		_current_max_horizontal_speed_multiplier * \
		(surfaces.surface_properties.speed_multiplier if \
			surfaces.is_attaching_to_surface else \
			1.0)

var current_air_max_horizontal_speed: float:
	get:
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
				initial_launch_horizontal_speed >
				movement_settings.max_launch_horizontal_speed
			):
				return movement_settings.max_launch_horizontal_speed
			elif (
				initial_launch_horizontal_speed >
				movement_settings.max_air_horizontal_speed
			):
				return initial_launch_horizontal_speed
			else:
				return movement_settings.max_air_horizontal_speed
		else:
			return (
				movement_settings.max_air_horizontal_speed *
				_current_max_horizontal_speed_multiplier
			)

var current_walk_acceleration: float:
	get:
		return movement_settings.walk_acceleration * \
		(surfaces.surface_properties.speed_multiplier if \
			surfaces.is_attaching_to_surface else \
			1.0)

var current_climb_up_speed: float:
	get:
		return movement_settings.climb_up_speed * \
		(surfaces.surface_properties.speed_multiplier if \
			surfaces.is_attaching_to_surface else \
			1.0)

var current_climb_down_speed: float:
	get:
		return movement_settings.climb_down_speed * \
		(surfaces.surface_properties.speed_multiplier if \
			surfaces.is_attaching_to_surface else \
			1.0)

var current_ceiling_crawl_speed: float:
	get:
		return movement_settings.ceiling_crawl_speed * \
		(surfaces.surface_properties.speed_multiplier if \
			surfaces.is_attaching_to_surface else \
			1.0)

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
	# default (0) since it's only valid after first physics update
	state_from_server.position = position
	state_from_server.velocity = velocity
	# state_from_server.surfaces intentionally left at default 0

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

	# When descending through floors while pressing into a wall, temporarily
	# zero horizontal velocity to prevent wall collision from zeroing Y velocity.
	# Godot's move_and_slide collision resolution can reduce vertical velocity
	# when sliding along a wall corner.
	var saved_velocity_x := velocity.x
	var should_preserve_wall_slide := (
		surfaces.is_descending_through_floors and
		surfaces.is_pressing_into_wall
	)
	if should_preserve_wall_slide:
		velocity.x = 0.0

	move_and_slide()

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
			surfaces.is_descending_through_floors and
			action_handler.name == &"FloorDefaultAction"
		)

		var is_action_relevant_for_surface: bool = (
			action_handler.type == surfaces.surface_type or
			action_handler.type == SurfaceType.OTHER or
			# Our surface-state logic considers the current actions, and
			# surface-state is updated before we process actions here.
			# Furthermore, we use action-handlers to actually apply the
			# changes for things like jump impulses that are needed to
			# actually transition the character from a surface. So we need
			# to also consider the surface that we are currently leaving,
			# and allow an action-handler of that departure-surface-type to
			# handle this frame.
			(action_handler.type == surfaces.just_left_surface_type and
				surfaces.just_left_surface_type != SurfaceType.OTHER)
		)
		var is_action_relevant_for_physics_mode: bool = (
			action_handler.uses_runtime_physics
		)
		if (is_action_relevant_for_surface and
			is_action_relevant_for_physics_mode and
			not is_blocked_floor_action
		):
			var executed: bool = action_handler.process(self )
			_previous_actions_handlers_this_frame[action_handler.name] = \
			executed

	assert(!Geometry.is_point_partial_inf(velocity))


func _process_animation() -> void:
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
	# Check for a new jump event.
	if last_triggered_jump_frame_index > _last_processed_jump_frame_index:
		var current_frame_index := Netcode.server_frame_index
		var event_age := (
			(current_frame_index - last_triggered_jump_frame_index) *
			Netcode.frame_driver.target_network_time_step_sec
		)
		if event_age <= _JUMP_EVENT_STALENESS_THRESHOLD_SEC:
			play_sound("jump")
		_last_processed_jump_frame_index = last_triggered_jump_frame_index

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
	var frames_since_launch := Netcode.server_frame_index - _last_launch_frame_index
	return frames_since_launch < _LAUNCH_FLOOR_ATTACHMENT_COOLDOWN_FRAMES


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
