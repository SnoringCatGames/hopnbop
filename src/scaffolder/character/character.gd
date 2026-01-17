class_name Character
extends CharacterBody2D


# FIXME: [Logs]: Re-introduce some character, surface state, and action logs.


const _NORMAL_SURFACES_COLLISION_MASK_BIT := 1
const _FALL_THROUGH_FLOORS_COLLISION_MASK_BIT := 2
const _WALK_THROUGH_WALLS_COLLISION_MASK_BIT := 4

@export var collision_shape: CollisionShape2D
@export var animator: CharacterAnimator
@export var movement_settings: MovementSettings

@export var state_from_server: CharacterStateFromServer

var multiplayer_id: int:
    set(value):
        state_from_server.multiplayer_id = value
    get:
        return state_from_server.multiplayer_id

var start_position := Vector2.INF

var just_triggered_jump := false
var jump_sequence_count := 0

var _current_max_horizontal_speed_multiplier := 1.0

var surfaces := CharacterSurfaceState.new(self)
var actions := CharacterActionState.new()

# Array<CharacterActionSource>
var _action_sources := []
# Dictionary<String, bool>
var _previous_actions_handlers_this_frame := {}

var current_surface_max_horizontal_speed: float:
    get: return movement_settings.max_ground_horizontal_speed * \
            _current_max_horizontal_speed_multiplier * \
            (surfaces.surface_properties.speed_multiplier if \
            surfaces.is_attaching_to_surface else \
            1.0)

var current_air_max_horizontal_speed: float:
    get: return movement_settings.max_air_horizontal_speed * \
            _current_max_horizontal_speed_multiplier

var current_walk_acceleration: float:
    get: return movement_settings.walk_acceleration * \
            (surfaces.surface_properties.speed_multiplier if \
            surfaces.is_attaching_to_surface else \
            1.0)

var current_climb_up_speed: float:
    get: return movement_settings.climb_up_speed * \
            (surfaces.surface_properties.speed_multiplier if \
            surfaces.is_attaching_to_surface else \
            1.0)

var current_climb_down_speed: float:
    get: return movement_settings.climb_down_speed * \
            (surfaces.surface_properties.speed_multiplier if \
            surfaces.is_attaching_to_surface else \
            1.0)

var current_ceiling_crawl_speed: float:
    get: return movement_settings.ceiling_crawl_speed * \
            (surfaces.surface_properties.speed_multiplier if \
            surfaces.is_attaching_to_surface else \
            1.0)

var is_sprite_visible: bool:
    set(value): animator.visible = value
    get: return animator.visible


func _enter_tree() -> void:
    pass


func _exit_tree() -> void:
    pass


func _ready() -> void:
    # FIXME: Add configuration warnings for these as well.
    G.check_valid(collision_shape,
        "collision_shape is not set: %s" % name)
    G.check_valid(animator,
        "animator is not set: %s" % name)
    G.check_valid(movement_settings,
        "movement_settings is not set: %s" % name)
    G.check_valid(state_from_server,
        "state_from_server is not set: %s" % name)

    movement_settings.set_up()

    start_position = position

    # Start facing right.
    surfaces.is_facing_right = true
    animator.face_right()

    state_from_server.position = position
    state_from_server.velocity = velocity
    state_from_server.surfaces = surfaces.bitmask

    if _action_sources.is_empty():
        var player_action_source := PlayerActionSource.new(self, true)
        _action_sources.push_back(player_action_source)

    # For move_and_slide.
    up_direction = Vector2.UP
    floor_stop_on_slope = false
    max_slides = MovementSettings._MAX_SLIDES_DEFAULT
    floor_max_angle = G.geometry.FLOOR_MAX_ANGLE + G.geometry.WALL_ANGLE_EPSILON


## This gets called just before _network_process.
func _update_actions() -> void:
    # Clear actions for the current frame.
    actions.clear()

    # Update actions for the current frame.
    for action_source in _action_sources:
        action_source.update(
            actions,
            G.time.get_scaled_network_time())

    surfaces.update_actions()
    actions.log_new_presses_and_releases(self)


func _network_process() -> void:
    # FIXME: LEFT OFF HERE: ACTUALLY, ACTUALLY, ACTUALLY: Character process.
    # - THINK ABOUT POSITION BEFORE/AFTER _network_process, and how that
    #   corresponds to the networked state.
    #   - I guess we shouldn't call _network_process for a frame if we already
    #     know what the authoritative state is for the frame.
    pass

    _apply_movement()

    # update derived behaviors based on current movement and actions.
    _process_facing_direction()
    _process_actions()
    _process_animation()
    _process_sounds()
    _update_collision_mask()


func _apply_movement() -> void:
    var base_velocity := velocity
    # Since move_and_slide automatically accounts for delta, we need to
    # compensate for that in order to support our modified framerate.
    var scaled_velocity: Vector2 = base_velocity * G.time.get_combined_scale()

    velocity = scaled_velocity
    move_and_slide()

    surfaces.update_touches()


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
    # FIXME: LEFT OFF HERE: ACTUALLY: Refactor how instantaneous events are handled:
    # - Instead of a just_triggered_jump like this, network
    #   last_triggered_jump_time, and track locally the latest triggered jump
    #   time that we've processed. If it's a new time (and less than some delay
    #   threshold), then trigger the sound.
    # - AND, I guess we should think of it the same way it terms of detecting
    #   just-did-this for other behavior on non-authoritative sources.
    #   - This will also be important for correctly handling, on the server,
    #     when a player has pressed jump.
    #     - The server could easily miss the just-pressed-jump frame and then
    #       get a later jump-already-pressed frame, or EVEN WORSE, jump was only
    #       pressed for one frame and the server missed it.
    if just_triggered_jump:
        play_sound("jump")

    if surfaces.just_left_air:
        play_sound("land")
    elif surfaces.just_touched_surface:
        play_sound("land")


func play_sound(_sound_name: String) -> void:
    G.fatal("Abstract CharacterActionSource.update is not implemented")


func processed_action(p_name: String) -> bool:
    return _previous_actions_handlers_this_frame.get(p_name) == true


# Update whether or not we should currently consider collisions with
# fall-through floors and walk-through walls.
func _update_collision_mask() -> void:
    set_collision_mask_value(
            _FALL_THROUGH_FLOORS_COLLISION_MASK_BIT,
            not surfaces.is_descending_through_floors)
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
