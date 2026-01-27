@tool
class_name Character
extends CharacterBody2D

const _NORMAL_SURFACES_COLLISION_MASK_BIT := 1
const _FALL_THROUGH_FLOORS_COLLISION_MASK_BIT := 2
const _WALK_THROUGH_WALLS_COLLISION_MASK_BIT := 4

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

var surfaces := CharacterSurfaceState.new(self)
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
		return movement_settings.max_air_horizontal_speed * \
		_current_max_horizontal_speed_multiplier

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

	G.check(_get_configuration_warnings().is_empty())

	movement_settings.set_up()

	start_position = position

	# Start facing right.
	surfaces.is_facing_right = true
	animator.face_right()

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
	pass


func _physics_process(_delta: float) -> void:
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
			G.time.get_scaled_network_time())

	actions.log_new_presses_and_releases(self)

	surfaces.update_actions()

	# Record the frame when jump is triggered for network reconciliation.
	if actions.just_triggered_jump:
		last_triggered_jump_frame_index = G.network.server_frame_index


## This gets called during _network_process.
func _apply_movement() -> void:
	var base_velocity := velocity
	# Since move_and_slide automatically accounts for delta, we need to
	# compensate for that in order to support our modified framerate.
	var scaled_velocity: Vector2 = base_velocity * G.time.get_combined_scale()

	velocity = scaled_velocity
	move_and_slide()

	surfaces.update_touches()


## Update derived behaviors based on current movement and actions.
## This gets called during _network_process, just after _apply_movement.
func _process_movement_and_actions() -> void:
	_process_facing_direction()
	_process_actions()
	_process_animation()
	_process_sounds()
	_update_collision_mask()


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
		var is_action_relevant_for_surface: bool = \
		action_handler.type == surfaces.surface_type or \
		action_handler.type == SurfaceType.OTHER or \
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
		var is_action_relevant_for_physics_mode: bool = \
		action_handler.uses_runtime_physics
		if is_action_relevant_for_surface and \
		is_action_relevant_for_physics_mode:
			var executed: bool = action_handler.process(self)
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
					G.fatal("SurfacerCharacter._process_animation")
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
			G.fatal("SurfacerCharacter._process_animation")


func _process_sounds() -> void:
	# Check for a new jump event.
	if last_triggered_jump_frame_index > _last_processed_jump_frame_index:
		var current_frame_index := G.network.server_frame_index
		var event_age := (
			(current_frame_index - last_triggered_jump_frame_index) *
			NetworkFrameDriver.TARGET_NETWORK_TIME_STEP_SEC
		)
		if event_age <= _JUMP_EVENT_STALENESS_THRESHOLD_SEC:
			play_sound("jump")
		_last_processed_jump_frame_index = last_triggered_jump_frame_index

	if surfaces.just_left_air:
		play_sound("land")
	elif surfaces.just_touched_surface:
		play_sound("land")


func play_sound(_sound_name: StringName) -> void:
	G.fatal("Abstract CharacterActionSource.update is not implemented")


func processed_action(p_name: StringName) -> bool:
	return _previous_actions_handlers_this_frame.get(p_name) == true


# Update whether or not we should currently consider collisions with
# fall-through floors and walk-through walls.
func _update_collision_mask() -> void:
	set_collision_mask_value(
		_FALL_THROUGH_FLOORS_COLLISION_MASK_BIT,
		not surfaces.is_descending_through_floors,
	)
	#set_collision_mask_value(
	#_WALK_THROUGH_WALLS_COLLISION_MASK_BIT,
	#surfaces.is_attaching_to_walk_through_walls)


func force_boost(boost: Vector2) -> void:
	velocity = boost

	position += Vector2(0.0, -1.0)
	surfaces.force_boost()


func get_next_position_prediction() -> Vector2:
	# Since move_and_slide automatically accounts for delta, we need to
	# compensate for that in order to support our modified framerate.
	var modified_velocity: Vector2 = velocity * G.time.get_combined_scale()
	return position + modified_velocity * NetworkFrameDriver.TARGET_NETWORK_TIME_STEP_SEC


func get_position_in_screen_space() -> Vector2:
	return G.utils.get_screen_position_of_node_in_level(self)


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
