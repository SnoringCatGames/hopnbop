class_name Character
extends CharacterBody2D


# FIXME: LEFT OFF HERE: ----------------------


const _MAX_SLIDES_DEFAULT := 4
# 45 degrees
const _MAX_FLOOR_ANGLE = PI / 4.0
const _STRONG_SPEED_TO_MAINTAIN_COLLISION := 900.0
const _WALLS_AND_FLOORS_COLLISION_MASK_BIT := 0
const _FALL_THROUGH_FLOORS_COLLISION_MASK_BIT := 1
const _WALK_THROUGH_WALLS_COLLISION_MASK_BIT := 2

@export var collision_shape: CollisionShape2D
@export var animator: CharacterAnimator
@export var movement_settings: MovementSettings

var base_velocity := Vector2.ZERO
var start_position := Vector2.INF
var previous_position := Vector2.INF
var stationary_frames_count := 0

var total_distance_traveled := INF

var start_time := INF
var previous_total_time := INF
var total_time := INF

var _is_destroyed := false

var just_triggered_jump := false
var is_rising_from_jump := false
var jump_count := 0

var _current_max_horizontal_speed_multiplier := 1.0

var surface_state := CharacterSurfaceState.new(self)

var _actions_from_previous_frame := CharacterActionState.new()
var actions := CharacterActionState.new()

# Array<CharacterActionSource>
var _action_sources := []
# Dictionary<String, bool>
var _previous_actions_handlers_this_frame := {}

var _character_action_source: CharacterActionSource


func _ready() -> void:
    if not collision_shape:
        assert(false, "Character.collision_shape is not provided: %s" % name)
    if not animator:
        assert(false, "Character.animator is not provided: %s" % name)
    if not movement_settings:
        assert(false, "Character.movement_settings is not provided: %s" % name)

    movement_settings.set_up()

    total_distance_traveled = 0.0
    start_time = G.time.get_scaled_play_time()
    total_time = 0.0

    start_position = position

    surface_state.previous_center_position = self.position
    surface_state.center_position = self.position

    # Start facing right.
    surface_state.horizontal_facing_sign = 1
    animator.face_right()

    if !is_instance_valid(_character_action_source):
        _init_player_controller_action_source()

    # For move_and_slide.
    up_direction = Vector2.UP
    floor_stop_on_slope = false
    max_slides = _MAX_SLIDES_DEFAULT
    floor_max_angle = G.geometry.FLOOR_MAX_ANGLE + G.geometry.WALL_ANGLE_EPSILON


func _destroy() -> void:
    _is_destroyed = true
    if is_instance_valid(animator):
        animator._destroy()
    if !is_queued_for_deletion():
        queue_free()


func _init_player_controller_action_source() -> void:
    assert(!is_instance_valid(_character_action_source))
    self._character_action_source = PlayerActionSource.new(self, true)
    _action_sources.push_back(_character_action_source)


func _physics_process(delta: float) -> void:
    if !is_node_ready() or \
            _is_destroyed:
        return

    var delta_scaled: float = G.time.scale_delta(delta)

    previous_total_time = total_time
    total_time = G.time.get_scaled_play_time() - start_time

    previous_position = position

    surface_state.collisions.clear()
    _apply_movement()
    _maintain_preexisting_collisions()
    surface_state.collisions.reverse()

    _update_actions(delta_scaled)
    surface_state.clear_just_changed_state()
    _update_surface_state()

    actions.log_new_presses_and_releases(self)

    # Flip the horizontal direction of the animation according to which way the
    # character is facing.
    if surface_state.horizontal_facing_sign == 1:
        animator.face_right()
    elif surface_state.horizontal_facing_sign == -1:
        animator.face_left()

    _process_actions()
    _process_animation()
    _process_sounds()
    _update_collision_mask()

    if surface_state.did_move_last_frame:
        stationary_frames_count = 0
    else:
        stationary_frames_count += 1

    total_distance_traveled += position.distance_to(previous_position)


func _apply_movement() -> void:
    # Since move_and_slide automatically accounts for delta, we need to
    # compensate for that in order to support our modified framerate.
    var modified_velocity: Vector2 = base_velocity * G.time.get_combined_scale()

    velocity = modified_velocity
    max_slides = _MAX_SLIDES_DEFAULT
    move_and_slide()

    surface_state.record_collisions()


# -   The move_and_slide system depends on some velocity always pushing the
#     character into the floor (or other touched surface).
# -   If we just zero this out, move_and_slide will produce false-negatives for
#     collisions.
func _maintain_preexisting_collisions() -> void:
    if !surface_state.is_grabbing_surface or \
            (surface_state.is_triggering_wall_release and \
            surface_state.is_grabbing_wall) or \
            (surface_state.is_triggering_ceiling_release and \
            surface_state.is_grabbing_ceiling) or \
            (surface_state.is_triggering_fall_through and \
            surface_state.is_grabbing_floor) or \
            actions.just_pressed_jump:
        return

    var normal := surface_state.attachment_normal

    var maintain_collision_velocity: Vector2 = \
            _STRONG_SPEED_TO_MAINTAIN_COLLISION * -normal

    max_slides = 1

    # Also maintain wall collisions.
    if !surface_state.is_grabbing_wall and \
            surface_state.is_touching_wall and \
            !surface_state.is_triggering_wall_release and \
            !surface_state.is_pressing_away_from_wall:
        maintain_collision_velocity.x = \
                _STRONG_SPEED_TO_MAINTAIN_COLLISION * \
                surface_state.toward_wall_sign
        max_slides = 2

    # Trigger another move_and_slide.
    # -   This will maintain collision state within Godot's collision system.
    # -   This will also ensure the character snaps to the surface.
    velocity = maintain_collision_velocity
    move_and_slide()

    surface_state.record_collisions()


func _update_actions(delta_scaled: float) -> void:
    # Record actions for the previous frame.
    _actions_from_previous_frame.copy(actions)
    # Clear actions for the current frame.
    actions.clear()

    actions.delta_scaled = delta_scaled

    # Update actions for the current frame.
    for action_source in _action_sources:
        action_source.update(
                actions,
                _actions_from_previous_frame,
                G.time.get_scaled_play_time(),
                delta_scaled)

    CharacterActionSource.update_for_implicit_key_events(
            actions,
            _actions_from_previous_frame)


# Updates physics and character states in response to the current actions.
func _process_actions() -> void:
    _previous_actions_handlers_this_frame.clear()

    for action_handler in movement_settings.action_handlers:
        var is_action_relevant_for_surface: bool = \
                action_handler.type == surface_state.surface_type or \
                action_handler.type == SurfaceType.OTHER
        var is_action_relevant_for_physics_mode: bool = \
                !action_handler.uses_runtime_physics
        if is_action_relevant_for_surface and \
                is_action_relevant_for_physics_mode:
            var executed: bool = action_handler.process(self)
            _previous_actions_handlers_this_frame[action_handler.name] = \
                    executed

            # TODO: This is sometimes useful for debugging.
#            if executed and \
#                    action_handler.name != AllDefaultAction.NAME and \
#                    action_handler.name != CapVelocityAction.NAME and \
#                    action_handler.name != FloorDefaultAction.NAME and \
#                    action_handler.name != FloorFrictionAction.NAME and \
#                    action_handler.name != FloorWalkAction.NAME and \
#                    action_handler.name != AirDefaultAction.NAME:
#                var name_str: String = G.utils.resize_string(
#                        action_handler.name,
#                        20)
#                _log(name_str,
#                        "",
#                        CharacterLogType.ACTION,
#                        true)

    assert(!Geometry.is_point_partial_inf(base_velocity))


func _process_animation() -> void:
    match surface_state.surface_type:
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
                    push_error("SurfacerCharacter._process_animation")
            else:
                animator.play("RestOnWall")
        SurfaceType.CEILING:
            if actions.pressed_left or actions.pressed_right:
                animator.play("CrawlOnCeiling")
            else:
                animator.play("RestOnCeiling")
        SurfaceType.AIR:
            if base_velocity.y > 0:
                animator.play("JumpFall")
            else:
                animator.play("JumpRise")
        _:
            push_error("SurfacerCharacter._process_animation")


func _process_sounds() -> void:
    if just_triggered_jump:
        G.audio.play_sound("jump")

    if surface_state.just_left_air:
        G.audio.play_sound("land")
    elif surface_state.just_touched_surface:
        G.audio.play_sound("land")


func processed_action(p_name: String) -> bool:
    return _previous_actions_handlers_this_frame.get(p_name) == true


func _update_surface_state() -> void:
    surface_state.update()

    #if surface_state.just_entered_air:
        #print("Released",
                #"grab_p=%s, %s" % [
                    #G.utils.get_vector_string(surface_state.grab_position, 1),
                    #surface_state.previous_grabbed_surface.to_string(false),
                #],
                #false)
    #elif surface_state.just_changed_surface:
        #print("Grabbed",
                #"grab_p=%s, %s" % [
                    #G.utils.get_vector_string(surface_state.grab_position, 1),
                    #surface_state.grabbed_surface.to_string(false),
                #],
                #false)
    #elif surface_state.just_touched_surface:
        #var side_prefixes := []
        #if surface_state.is_touching_floor:
            #side_prefixes.push_back("F")
        #elif surface_state.is_touching_ceiling:
            #side_prefixes.push_back("C")
        #elif surface_state.is_touching_left_wall:
            #side_prefixes.push_back("LW")
        #elif surface_state.is_touching_right_wall:
            #side_prefixes.push_back("RW")
        #print("Touched",
                #"side=%s" % G.utils.join(side_prefixes),
                #false)


# Update whether or not we should currently consider collisions with
# fall-through floors and walk-through walls.
func _update_collision_mask() -> void:
    set_collision_mask_value(
            _FALL_THROUGH_FLOORS_COLLISION_MASK_BIT,
            !surface_state.is_descending_through_floors and \
                    base_velocity.y > 0)
    set_collision_mask_value(
            _FALL_THROUGH_FLOORS_COLLISION_MASK_BIT,
            !surface_state.is_ascending_through_ceilings and \
                    base_velocity.y < 0)
    set_collision_mask_value(
            _WALK_THROUGH_WALLS_COLLISION_MASK_BIT,
            surface_state.is_grabbing_walk_through_walls)


func force_boost(boost: Vector2) -> void:
    surface_state.clear_current_state()

    base_velocity = boost
    surface_state.velocity = base_velocity

    position += Vector2(0.0, -1.0)
    surface_state.center_position = position
    surface_state.center_position_along_surface \
            .match_current_grab(null, position)


func _get_current_surface_max_horizontal_speed() -> float:
    return movement_settings.max_horizontal_speed_default * \
            movement_settings.surface_speed_multiplier * \
            _current_max_horizontal_speed_multiplier * \
            (surface_state.grabbed_surface.properties.speed_multiplier if \
            surface_state.is_grabbing_surface else \
            1.0)


func _get_current_air_max_horizontal_speed() -> float:
    return movement_settings.max_horizontal_speed_default * \
            movement_settings.air_horizontal_speed_multiplier * \
            _current_max_horizontal_speed_multiplier


func _get_current_walk_acceleration() -> float:
    return movement_settings.walk_acceleration * \
            (surface_state.grabbed_surface.properties.speed_multiplier if \
            surface_state.is_grabbing_surface else \
            1.0)


func _get_current_climb_up_speed() -> float:
    return movement_settings.climb_up_speed * \
            (surface_state.grabbed_surface.properties.speed_multiplier if \
            surface_state.is_grabbing_surface else \
            1.0)


func _get_current_climb_down_speed() -> float:
    return movement_settings.climb_down_speed * \
            (surface_state.grabbed_surface.properties.speed_multiplier if \
            surface_state.is_grabbing_surface else \
            1.0)


func _get_current_ceiling_crawl_speed() -> float:
    return movement_settings.ceiling_crawl_speed * \
            (surface_state.grabbed_surface.properties.speed_multiplier if \
            surface_state.is_grabbing_surface else \
            1.0)


func get_next_position_prediction() -> Vector2:
    # Since move_and_slide automatically accounts for delta, we need to
    # compensate for that in order to support our modified framerate.
    var modified_velocity: Vector2 = base_velocity * G.time.get_combined_scale()
    return position + modified_velocity * G.time.PHYSICS_TIME_STEP


func set_is_sprite_visible(p_is_visible: bool) -> void:
    animator.visible = p_is_visible


func get_is_sprite_visible() -> bool:
    return animator.visible


func get_position_in_screen_space() -> Vector2:
    return G.utils.get_screen_position_of_node_in_level(self)
