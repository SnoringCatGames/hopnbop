class_name CharacterSurfaceState
extends RefCounted
## -   State relating to a character's position relative to nearby surfaces.[br]
## -   This is updated each physics frame.[br]


# FIXME: LEFT OFF HERE: Adapt this (ditch most of the old state tracking, just rely on built-in is_on_foo(), and track input for grabs), then finish adapting character.gd, then test!


var is_touching_floor: bool:
    get: return character.is_on_floor()
var is_touching_ceiling: bool:
    get: return character.is_on_ceiling()
var is_touching_left_wall := false
var is_touching_right_wall := false
var is_touching_surface: bool:
    get: return is_touching_floor or \
        is_touching_ceiling or \
        is_touching_left_wall or \
        is_touching_right_wall
var is_touching_wall: bool:
    get: return is_touching_left_wall or \
        is_touching_right_wall

var is_grabbing_floor := false
var is_grabbing_ceiling := false
var is_grabbing_left_wall := false
var is_grabbing_right_wall := false
var is_grabbing_surface: bool:
    get: return is_grabbing_floor or \
        is_grabbing_ceiling or \
        is_grabbing_left_wall or \
        is_grabbing_right_wall
var is_grabbing_wall: bool:
    get: return is_grabbing_left_wall or \
        is_grabbing_right_wall

var just_touched_floor := false
var just_touched_ceiling := false
var just_touched_left_wall := false
var just_touched_right_wall := false
var just_touched_surface: bool:
    get: return just_touched_floor or \
        just_touched_ceiling or \
        just_touched_left_wall or \
        just_touched_right_wall
var just_touched_wall: bool:
    get: return just_touched_left_wall or \
        just_touched_right_wall

var just_stopped_touching_floor := false
var just_stopped_touching_ceiling := false
var just_stopped_touching_left_wall := false
var just_stopped_touching_right_wall := false
var just_stopped_touching_surface: bool:
    get: return just_stopped_touching_floor or \
        just_stopped_touching_ceiling or \
        just_stopped_touching_left_wall or \
        just_stopped_touching_right_wall
var just_stopped_touching_wall: bool:
    get: return just_stopped_touching_left_wall or \
        just_stopped_touching_right_wall

var just_grabbed_floor := false
var just_grabbed_ceiling := false
var just_grabbed_left_wall := false
var just_grabbed_right_wall := false
var just_grabbed_surface: bool:
    get: return just_grabbed_floor or \
        just_grabbed_ceiling or \
        just_grabbed_left_wall or \
        just_grabbed_right_wall
var just_grabbed_wall: bool:
    get: return just_grabbed_left_wall or \
        just_grabbed_right_wall

var just_stopped_grabbing_floor := false
var just_stopped_grabbing_ceiling := false
var just_stopped_grabbing_left_wall := false
var just_stopped_grabbing_right_wall := false
var just_stopped_grabbing_surface: bool:
    get: return just_stopped_grabbing_floor or \
        just_stopped_grabbing_ceiling or \
        just_stopped_grabbing_left_wall or \
        just_stopped_grabbing_right_wall
var just_stopped_grabbing_wall: bool:
    get: return just_stopped_grabbing_left_wall or \
        just_stopped_grabbing_right_wall

var is_facing_wall := false
var is_pressing_into_wall := false
var is_pressing_away_from_wall := false

var is_triggering_explicit_wall_grab := false
var is_triggering_explicit_ceiling_grab := false
var is_triggering_explicit_floor_grab := false

var is_triggering_implicit_wall_grab := false
var is_triggering_implicit_ceiling_grab := false
var is_triggering_implicit_floor_grab := false

var is_triggering_wall_release := false
var is_triggering_ceiling_release := false
var is_triggering_fall_through := false
var is_triggering_jump := false

var is_descending_through_floors := false
# FIXME: -------------------------------
# - Add support for grabbing jump-through ceilings.
#   - Not via a directional key.
#   - Make this configurable for climb_adjacent_surfaces behavior.
#     - Add a property that indicates probability of climbing through instead
#       of onto.
#     - Use the same probability for fall-through-floor.
# TODO:
# - Create support for a ceiling_jump_up_action.gd?
#   - Might need a new surface state property called
#     is_triggering_jump_up_through, which would be similar to
#     is_triggering_fall_through.
# - Also create support for transitioning from standing-on-fall-through-floor
#   to clinging-to-it-from-underneath and vice versa?
#   - This might require adding support for the concept of a multi-frame
#     action?
#   - And this might require adding new Edge sub-classes for either direction?
var is_ascending_through_ceilings := false
var is_grabbing_walk_through_walls := false

var surface_type := SurfaceType.AIR

var center_position := Vector2.INF
var previous_center_position := Vector2.INF
var did_move_last_frame := false
var did_move_frame_before_last := false
var grab_position := Vector2.INF
var grab_normal := Vector2.INF
var previous_grab_position := Vector2.INF
var previous_grab_normal := Vector2.INF
var grab_position_tilemap_coord := Vector2.INF
var grabbed_tilemap: TileMap
var contact_position := SurfaceContactPosition.new()
var last_contact_position := SurfaceContactPosition.new()
# FIXME
# var center_position_along_surface := PositionAlongSurface.new()
# var last_position_along_surface := PositionAlongSurface.new()

var velocity := Vector2.ZERO

var just_changed_tilemap := false
var just_changed_tilemap_coord := false
var just_changed_grab_position := false
var just_entered_air := false
var just_left_air := false

var horizontal_facing_sign := -1
var horizontal_acceleration_sign := 0
var toward_wall_sign := 0

# Dictionary<Surface, SurfaceContact>
var surfaces_to_contacts := {}
var surface_grab: SurfaceContact = null
var floor_contact: SurfaceContact
var ceiling_contact: SurfaceContact
var left_wall_contact: SurfaceContact
var right_wall_contact: SurfaceContact

var contact_count: int:
    get: return _get_contact_count()

var character: Character


func _init(p_character: Character) -> void:
    self.character = p_character


# Updates surface-related state according to the character's recent movement
# and the environment of the current frame.
func update() -> void:
    velocity = character.velocity
    previous_center_position = center_position
    center_position = character.position
    did_move_frame_before_last = did_move_last_frame
    did_move_last_frame = !G.geometry.are_points_equal_with_epsilon(
            previous_center_position, center_position, 0.00001)

    _update_contacts()
    _update_touch_state()
    _update_action_state()


func clear_just_changed_state() -> void:
    just_touched_floor = false
    just_touched_ceiling = false
    just_touched_left_wall = false
    just_touched_right_wall = false

    just_stopped_touching_floor = false
    just_stopped_touching_ceiling = false
    just_stopped_touching_left_wall = false
    just_stopped_touching_right_wall = false

    just_grabbed_floor = false
    just_grabbed_ceiling = false
    just_grabbed_left_wall = false
    just_grabbed_right_wall = false

    just_stopped_grabbing_floor = false
    just_stopped_grabbing_ceiling = false
    just_stopped_grabbing_left_wall = false
    just_stopped_grabbing_right_wall = false

    just_entered_air = false
    just_left_air = false

    just_changed_tilemap = false
    just_changed_tilemap_coord = false
    just_changed_grab_position = false


func _update_contacts() -> void:
    floor_contact = null
    left_wall_contact = null
    right_wall_contact = null
    ceiling_contact = null

    for surface_contact in surfaces_to_contacts.values():
        surface_contact._is_still_touching = false

    _update_physics_contacts()

    # Remove any surfaces that are no longer touching.
    var contacts_to_remove := []
    for contact in surfaces_to_contacts.values():
        if !contact._is_still_touching:
            contacts_to_remove.push_back(contact)
    for contact in contacts_to_remove:
        surfaces_to_contacts.erase(contact.surface)
        if surface_grab == contact:
            surface_grab = null
        #var details := (
                    #"%s; " +
                    #"v=%s") % [
                    #contact.position_along_surface.to_string(
                            #false, true),
                    #G.utils.get_vector_string(velocity, 1),
                #]
        #print(
                #"Rem contact",
                #details,
                #true)

    # FIXME: ---- REMOVE? Does this ever trigger? Even if it did, we
    #             probably want to just ignore the collision this frame.
    if !character.movement_params.bypasses_runtime_physics and \
            !character.collisions.is_empty() and \
            surfaces_to_contacts.is_empty():
        var collisions_str := ""
        for collision in character.collisions:
            collisions_str += \
                    "{p=%s, n=%s}, " % \
                    [collision.position, collision.normal]
        push_error(
                "There are only invalid collisions: %s" % collisions_str)


func _update_touch_state() -> void:
    var next_is_touching_floor := false
    var next_is_touching_ceiling := false
    var next_is_touching_left_wall := false
    var next_is_touching_right_wall := false

    for contact in surfaces_to_contacts.values():
        match contact.surface.side:
            SurfaceSide.FLOOR:
                next_is_touching_floor = true
            SurfaceSide.LEFT_WALL:
                next_is_touching_left_wall = true
            SurfaceSide.RIGHT_WALL:
                next_is_touching_right_wall = true
            SurfaceSide.CEILING:
                next_is_touching_ceiling = true
            _:
                push_error("CharacterSurfaceState._update_touch_state")

    var next_just_touched_floor := \
            next_is_touching_floor and !is_touching_floor
    var next_just_stopped_touching_floor := \
            !next_is_touching_floor and is_touching_floor

    var next_just_touched_ceiling := \
            next_is_touching_ceiling and !is_touching_ceiling
    var next_just_stopped_touching_ceiling := \
            !next_is_touching_ceiling and is_touching_ceiling

    var next_just_touched_left_wall := \
            next_is_touching_left_wall and !is_touching_left_wall
    var next_just_stopped_touching_left_wall := \
            !next_is_touching_left_wall and is_touching_left_wall

    var next_just_touched_right_wall := \
            next_is_touching_right_wall and !is_touching_right_wall
    var next_just_stopped_touching_right_wall := \
            !next_is_touching_right_wall and is_touching_right_wall

    is_touching_floor = next_is_touching_floor
    is_touching_ceiling = next_is_touching_ceiling
    is_touching_left_wall = next_is_touching_left_wall
    is_touching_right_wall = next_is_touching_right_wall

    just_touched_floor = \
            next_just_touched_floor or \
            just_touched_floor and !next_just_stopped_touching_floor
    just_stopped_touching_floor = \
            next_just_stopped_touching_floor or \
            just_stopped_touching_floor and !next_just_touched_floor

    just_touched_ceiling = \
            next_just_touched_ceiling or \
            just_touched_ceiling and !next_just_stopped_touching_ceiling
    just_stopped_touching_ceiling = \
            next_just_stopped_touching_ceiling or \
            just_stopped_touching_ceiling and !next_just_touched_ceiling

    just_touched_left_wall = \
            next_just_touched_left_wall or \
            just_touched_left_wall and !next_just_stopped_touching_left_wall
    just_stopped_touching_left_wall = \
            next_just_stopped_touching_left_wall or \
            just_stopped_touching_left_wall and !next_just_touched_left_wall

    just_touched_right_wall = \
            next_just_touched_right_wall or \
            just_touched_right_wall and !next_just_stopped_touching_right_wall
    just_stopped_touching_right_wall = \
            next_just_stopped_touching_right_wall or \
            just_stopped_touching_right_wall and !next_just_touched_right_wall

    # Calculate the sign of a colliding wall's direction.
    toward_wall_sign = \
            (-1 if is_touching_left_wall else \
            (1 if is_touching_right_wall else \
            0))


func _update_physics_contacts() -> void:
    var was_a_valid_contact_found := false

    for collision in character.collisions:
        var surface_contact := \
                _calculate_surface_contact_from_collision(collision)

        if !is_instance_valid(surface_contact):
            continue

        was_a_valid_contact_found = true

        match surface_contact.surface.side:
            SurfaceSide.FLOOR:
                floor_contact = surface_contact
            SurfaceSide.LEFT_WALL:
                left_wall_contact = surface_contact
            SurfaceSide.RIGHT_WALL:
                right_wall_contact = surface_contact
            SurfaceSide.CEILING:
                ceiling_contact = surface_contact
            _:
                push_error("CharacterSurfaceState._update_physics_contacts")


func _calculate_surface_contact_from_collision(
        collision: KinematicCollision2DCopy) -> SurfaceContact:
    if not collision.collider is TileMapLayer:
        push_error("A non-TileMapLayer collider was found.")
        return null

    var collision_normal := collision.normal
    var contacted_tilemap: TileMapLayer = collision.collider

    # FIXME: LEFT OFF HERE

    contact_position.character_position = character.position
    contact_position.contact_position = collision.position

    # Modify the contact position to be closer to the character center if the
    # contact is on axially-aligned segments of both the surface and the
    # character-collider boundary.
    var centered_contact_position: Vector2 = G.geometry \
            .nudge_point_along_axially_aligned_segment_toward_shape_center(
                contact_position,
                contacted_surface,
                center_position)
    if centered_contact_position != contact_position:
        contact_position = centered_contact_position
        contact_tilemap_coord = G.geometry.world_to_tilemap(
                contact_position,
                contacted_tilemap)
        contact_tilemap_index = G.geometry.get_tilemap_index_from_grid_coord(
                contact_tilemap_coord,
                contacted_tilemap)

    var contact_normal: Vector2 = G.geometry.get_surface_normal_at_point(
            contacted_surface, contact_position)

    var just_started := !surfaces_to_contacts.has(contacted_surface)

    if just_started:
        surfaces_to_contacts[contacted_surface] = SurfaceContact.new()

    var surface_contact: SurfaceContact = \
            surfaces_to_contacts[contacted_surface]
    surface_contact.type = SurfaceContact.PHYSICS
    surface_contact.surface = contacted_surface
    surface_contact.contact_position = contact_position
    surface_contact.contact_normal = contact_normal
    surface_contact.tilemap_coord = contact_tilemap_coord
    surface_contact.tilemap_index = contact_tilemap_index
    surface_contact.position_along_surface.match_current_grab(
            contacted_surface, center_position)
    surface_contact.just_started = just_started
    surface_contact._is_still_touching = true

    #if just_started:
        #var details := (
                    #"%s; " +
                    #"v=%s; " +
                    #"_calculate_surface_contact_from_collision()"
                #) % [
                    #surface_contact.position_along_surface.to_string(
                            #false, true),
                    #G.utils.get_vector_string(velocity, 1),
                #]
        #print(
                #"Add contact",
                #details,
                #true)

    return surface_contact


func _update_action_state() -> void:
    _update_horizontal_direction()
    _update_grab_trigger_state()
    _update_grab_state()

    assert(!_get_is_grabbing_surface() or _get_is_touching_surface())

    _update_grab_contact()


func _update_horizontal_direction() -> void:
    # Flip the horizontal direction of the animation according to which way the
    # character is facing.
    if is_grabbing_left_wall or \
            is_grabbing_right_wall:
        horizontal_facing_sign = toward_wall_sign
    elif character.actions.pressed_face_right:
        horizontal_facing_sign = 1
    elif character.actions.pressed_face_left:
        horizontal_facing_sign = -1
    elif character.actions.pressed_right:
        horizontal_facing_sign = 1
    elif character.actions.pressed_left:
        horizontal_facing_sign = -1

    if is_grabbing_left_wall or \
            is_grabbing_right_wall:
        horizontal_acceleration_sign = 0
    elif character.actions.pressed_right:
        horizontal_acceleration_sign = 1
    elif character.actions.pressed_left:
        horizontal_acceleration_sign = -1
    else:
        horizontal_acceleration_sign = 0

    is_facing_wall = \
            (is_touching_right_wall and \
                horizontal_facing_sign > 0) or \
            (is_touching_left_wall and \
                horizontal_facing_sign < 0)
    is_pressing_into_wall = \
            (is_touching_right_wall and \
                character.actions.pressed_right) or \
            (is_touching_left_wall and \
                character.actions.pressed_left)
    is_pressing_away_from_wall = \
            (is_touching_right_wall and \
                character.actions.pressed_left) or \
            (is_touching_left_wall and \
                character.actions.pressed_right)


func _update_grab_trigger_state() -> void:
    var is_touching_wall_and_pressing_up: bool = \
            character.actions.pressed_up and \
            _get_is_touching_wall()
    var is_touching_wall_and_pressing_grab: bool = \
            character.actions.pressed_grab and \
            _get_is_touching_wall()

    var just_pressed_jump: bool = \
            character.actions.just_pressed_jump
    var is_pressing_floor_grab_input: bool = \
            character.actions.pressed_down and \
            !just_pressed_jump
    var is_pressing_ceiling_grab_input: bool = \
            character.actions.pressed_up and \
            !character.actions.pressed_down and \
            !just_pressed_jump
    var is_pressing_wall_grab_input := \
            is_pressing_into_wall and \
            !is_pressing_away_from_wall and \
            !just_pressed_jump
    var is_pressing_ceiling_release_input: bool = \
            character.actions.pressed_down and \
            !character.actions.pressed_up and \
            !character.actions.pressed_grab or \
            just_pressed_jump
    var is_pressing_wall_release_input := \
            is_pressing_away_from_wall and \
            !is_pressing_into_wall or \
            just_pressed_jump
    var is_pressing_fall_through_input: bool = \
            character.actions.pressed_down and \
            character.actions.just_pressed_jump

    is_triggering_explicit_floor_grab = \
            is_touching_floor and \
            is_pressing_floor_grab_input and \
            character.movement_params.can_grab_floors and \
            !just_pressed_jump
    is_triggering_explicit_ceiling_grab = \
            is_touching_ceiling and \
            is_pressing_ceiling_grab_input and \
            character.movement_params.can_grab_ceilings and \
            !just_pressed_jump
    is_triggering_explicit_wall_grab = \
            _get_is_touching_wall() and \
            is_pressing_wall_grab_input and \
            character.movement_params.can_grab_walls and \
            !just_pressed_jump

    var current_grabbed_side := \
            grabbed_surface.side if \
            is_instance_valid(grabbed_surface) else \
            SurfaceSide.NONE
    var previous_grabbed_side := \
            previous_grabbed_surface.side if \
            is_instance_valid(previous_grabbed_surface) else \
            SurfaceSide.NONE

    var are_current_and_previous_surfaces_convex_neighbors := \
            is_instance_valid(grabbed_surface) and \
            is_instance_valid(previous_grabbed_surface) and \
            (previous_grabbed_surface.clockwise_convex_neighbor == \
                    grabbed_surface or \
            previous_grabbed_surface.counter_clockwise_convex_neighbor == \
                    grabbed_surface)

    var is_facing_previous_wall := \
            (previous_grabbed_side == SurfaceSide.RIGHT_WALL and \
                horizontal_facing_sign > 0) or \
            (previous_grabbed_side == SurfaceSide.LEFT_WALL and \
                horizontal_facing_sign < 0)
    var is_pressing_into_previous_wall: bool = \
            (previous_grabbed_side == SurfaceSide.RIGHT_WALL and \
                character.actions.pressed_right) or \
            (previous_grabbed_side == SurfaceSide.LEFT_WALL and \
                character.actions.pressed_left)
    var is_pressing_away_from_previous_wall: bool = \
            (previous_grabbed_side == SurfaceSide.RIGHT_WALL and \
                character.actions.pressed_left) or \
            (previous_grabbed_side == SurfaceSide.LEFT_WALL and \
                character.actions.pressed_right)
    var is_facing_into_previous_wall_and_pressing_up: bool = \
            character.actions.pressed_up and is_facing_previous_wall
    var is_facing_into_previous_wall_and_pressing_grab: bool = \
            character.actions.pressed_grab and is_facing_previous_wall
    var is_pressing_previous_wall_grab_input := \
            (is_pressing_into_previous_wall or \
            is_facing_into_previous_wall_and_pressing_up or \
            is_facing_into_previous_wall_and_pressing_grab) and \
            !is_pressing_away_from_previous_wall and \
            !just_pressed_jump

    is_triggering_implicit_floor_grab = \
            is_touching_floor and \
            character.movement_params.can_grab_floors and \
            !just_pressed_jump
    is_triggering_implicit_ceiling_grab = \
            is_touching_ceiling and \
                character.actions.pressed_grab and \
            character.movement_params.can_grab_ceilings and \
            !just_pressed_jump
    is_triggering_implicit_wall_grab = \
            (is_touching_wall_and_pressing_up or \
            is_touching_wall_and_pressing_grab) and \
            character.movement_params.can_grab_walls and \
            !just_pressed_jump

    is_triggering_ceiling_release = \
            is_grabbing_ceiling and \
            is_pressing_ceiling_release_input and \
            !is_triggering_explicit_ceiling_grab and \
            !is_triggering_implicit_ceiling_grab
    is_triggering_wall_release = \
            _get_is_grabbing_wall() and \
            is_pressing_wall_release_input and \
            !is_triggering_explicit_wall_grab and \
            !is_triggering_implicit_wall_grab
    is_triggering_fall_through = \
            is_touching_floor and \
            is_pressing_fall_through_input
    is_triggering_jump = \
            just_pressed_jump and \
            !is_triggering_fall_through


func _update_grab_state() -> void:
    var standard_is_grabbing_ceiling: bool = \
            is_touching_ceiling and \
            (is_grabbing_ceiling or \
                is_triggering_explicit_ceiling_grab or \
                (is_triggering_implicit_ceiling_grab and \
                !is_grabbing_floor and \
                !_get_is_grabbing_wall())) and \
            !is_triggering_ceiling_release and \
            !is_triggering_jump and \
            (is_triggering_explicit_ceiling_grab or \
                 !is_triggering_explicit_wall_grab)

    var standard_is_grabbing_wall: bool = \
            _get_is_touching_wall() and \
            (_get_is_grabbing_wall() or \
                is_triggering_explicit_wall_grab or \
                (is_triggering_implicit_wall_grab and \
                !is_grabbing_floor and \
                !is_grabbing_ceiling)) and \
            !is_triggering_wall_release and \
            !is_triggering_jump and \
            !is_triggering_explicit_floor_grab and \
            !is_triggering_explicit_ceiling_grab

    var standard_is_grabbing_floor: bool = \
            is_touching_floor and \
            (is_grabbing_floor or \
                is_triggering_explicit_floor_grab or \
                (is_triggering_implicit_floor_grab and \
                !is_grabbing_ceiling and \
                !_get_is_grabbing_wall())) and \
            !is_triggering_fall_through and \
            !is_triggering_jump and \
            (is_triggering_explicit_floor_grab or \
                !is_triggering_explicit_wall_grab)

    var next_is_grabbing_ceiling := \
            standard_is_grabbing_ceiling and \
            !is_triggering_ceiling_release

    var next_is_grabbing_floor := \
            standard_is_grabbing_floor and \
            !is_triggering_fall_through and \
            !next_is_grabbing_ceiling

    var next_is_grabbing_wall := \
            standard_is_grabbing_wall and \
            !is_triggering_wall_release and \
            !next_is_grabbing_floor and \
            !next_is_grabbing_ceiling

    var next_is_grabbing_left_wall: bool
    var next_is_grabbing_right_wall: bool
    if next_is_grabbing_wall:
        next_is_grabbing_left_wall = is_touching_left_wall
        next_is_grabbing_right_wall = is_touching_right_wall
    else:
        next_is_grabbing_left_wall = false
        next_is_grabbing_right_wall = false

    var next_is_grabbing_surface := \
            next_is_grabbing_floor or \
            next_is_grabbing_ceiling or \
            next_is_grabbing_wall

    var next_just_grabbed_floor := \
            next_is_grabbing_floor and !is_grabbing_floor
    var next_just_stopped_grabbing_floor := \
            !next_is_grabbing_floor and is_grabbing_floor

    var next_just_grabbed_ceiling := \
            next_is_grabbing_ceiling and !is_grabbing_ceiling
    var next_just_stopped_grabbing_ceiling := \
            !next_is_grabbing_ceiling and is_grabbing_ceiling

    var next_just_grabbed_left_wall := \
            next_is_grabbing_left_wall and !is_grabbing_left_wall
    var next_just_stopped_grabbing_left_wall := \
            !next_is_grabbing_left_wall and is_grabbing_left_wall

    var next_just_grabbed_right_wall := \
            next_is_grabbing_right_wall and !is_grabbing_right_wall
    var next_just_stopped_grabbing_right_wall := \
            !next_is_grabbing_right_wall and is_grabbing_right_wall

    var next_just_entered_air := \
            !next_is_grabbing_surface and _get_is_grabbing_surface()
    var next_just_left_air := \
            next_is_grabbing_surface and !_get_is_grabbing_surface()

    is_grabbing_floor = next_is_grabbing_floor
    is_grabbing_ceiling = next_is_grabbing_ceiling
    is_grabbing_left_wall = next_is_grabbing_left_wall
    is_grabbing_right_wall = next_is_grabbing_right_wall

    just_grabbed_floor = \
            next_just_grabbed_floor or \
            just_grabbed_floor and \
            !next_just_stopped_grabbing_floor
    just_stopped_grabbing_floor = \
            next_just_stopped_grabbing_floor or \
            just_stopped_grabbing_floor and \
            !next_just_grabbed_floor

    just_grabbed_ceiling = \
            next_just_grabbed_ceiling or \
            just_grabbed_ceiling and \
            !next_just_stopped_grabbing_ceiling
    just_stopped_grabbing_ceiling = \
            next_just_stopped_grabbing_ceiling or \
            just_stopped_grabbing_ceiling and \
            !next_just_grabbed_ceiling

    just_grabbed_left_wall = \
            next_just_grabbed_left_wall or \
            just_grabbed_left_wall and \
            !next_just_stopped_grabbing_left_wall
    just_stopped_grabbing_left_wall = \
            next_just_stopped_grabbing_left_wall or \
            just_stopped_grabbing_left_wall and \
            !next_just_grabbed_left_wall

    just_grabbed_right_wall = \
            next_just_grabbed_right_wall or \
            just_grabbed_right_wall and \
            !next_just_stopped_grabbing_right_wall
    just_stopped_grabbing_right_wall = \
            next_just_stopped_grabbing_right_wall or \
            just_stopped_grabbing_right_wall and \
            !next_just_grabbed_right_wall

    just_entered_air = \
            next_just_entered_air or \
            just_entered_air and \
            !next_just_left_air
    just_left_air = \
            next_just_left_air or \
            just_left_air and \
            !next_just_entered_air

    if is_grabbing_floor:
        surface_type = SurfaceType.FLOOR
    elif _get_is_grabbing_wall():
        surface_type = SurfaceType.WALL
    elif is_grabbing_ceiling:
        surface_type = SurfaceType.CEILING
    else:
        surface_type = SurfaceType.AIR

    # Whether we should fall through fall-through floors.
    match surface_type:
        SurfaceType.FLOOR:
            is_descending_through_floors = is_triggering_fall_through
        SurfaceType.WALL:
            is_descending_through_floors = character.actions.pressed_down
        SurfaceType.CEILING:
            is_descending_through_floors = false
        SurfaceType.AIR, \
        SurfaceType.OTHER:
            is_descending_through_floors = character.actions.pressed_down
        _:
            push_error("CharacterSurfaceState._update_grab_state")

    # FIXME: ------- Add support for an ascend-through ceiling input.
    # Whether we should ascend-up through jump-through ceilings.
    is_ascending_through_ceilings = \
            !character.movement_params.can_grab_ceilings or \
                (!is_grabbing_ceiling and true)

    # Whether we should fall through fall-through floors.
    is_grabbing_walk_through_walls = \
            character.movement_params.can_grab_walls and \
                (_get_is_grabbing_wall() or \
                    character.actions.pressed_up)


func _update_grab_contact() -> void:
    var previous_grabbed_tilemap := grabbed_tilemap
    var previous_grab_position_tilemap_coord := grab_position_tilemap_coord

    surface_grab = null

    if _get_is_grabbing_surface():
        surface_grab = _get_grab_contact()
        assert(is_instance_valid(surface_grab))

        var next_grabbed_surface := surface_grab.surface
        var next_grab_position := surface_grab.contact_position
        var next_grab_normal := surface_grab.contact_normal
        grabbed_tilemap = surface_grab.surface.tile_map
        grab_position_tilemap_coord = surface_grab.tilemap_coord
        PositionAlongSurface.copy(
                center_position_along_surface,
                surface_grab.position_along_surface)
        PositionAlongSurface.copy(
                last_position_along_surface,
                center_position_along_surface)

        just_changed_surface = \
                just_changed_surface or \
                just_left_air or \
                next_grabbed_surface != grabbed_surface
        if just_changed_surface and \
                next_grabbed_surface != grabbed_surface and \
                is_instance_valid(grabbed_surface):
            previous_grabbed_surface = grabbed_surface
        grabbed_surface = next_grabbed_surface

        just_changed_grab_position = \
                just_changed_grab_position or \
                just_left_air or \
                next_grab_position != grab_position
        if just_changed_grab_position and \
                next_grab_position != grab_position and \
                grab_position != Vector2.INF:
            previous_grab_position = grab_position
            previous_grab_normal = grab_normal
        grab_position = next_grab_position
        grab_normal = next_grab_normal

        just_changed_tilemap = \
                just_changed_tilemap or \
                just_left_air or \
                grabbed_tilemap != previous_grabbed_tilemap

        just_changed_tilemap_coord = \
                just_changed_tilemap_coord or \
                just_left_air or \
                grab_position_tilemap_coord != \
                    previous_grab_position_tilemap_coord

    else:
        if just_entered_air:
            just_changed_grab_position = true
            just_changed_tilemap = true
            just_changed_tilemap_coord = true
            just_changed_surface = true
            previous_grabbed_surface = \
                    grabbed_surface if \
                    is_instance_valid(grabbed_surface) else \
                    previous_grabbed_surface
            previous_grab_position = \
                    grab_position if \
                    grab_position != Vector2.INF else \
                    previous_grab_position
            previous_grab_normal = \
                    grab_normal if \
                    grab_normal != Vector2.INF else \
                    previous_grab_normal

        surface_grab = null
        grab_position = Vector2.INF
        grab_normal = Vector2.INF
        grabbed_tilemap = null
        grab_position_tilemap_coord = Vector2.INF
        grabbed_surface = null
        center_position_along_surface.reset()


func _get_grab_contact() -> SurfaceContact:
    for surface in surfaces_to_contacts:
        if surface.side == SurfaceSide.FLOOR and \
                    is_grabbing_floor or \
                surface.side == SurfaceSide.LEFT_WALL and \
                    is_grabbing_left_wall or \
                surface.side == SurfaceSide.RIGHT_WALL and \
                    is_grabbing_right_wall or \
                surface.side == SurfaceSide.CEILING and \
                    is_grabbing_ceiling:
            return surfaces_to_contacts[surface]
    return null


func _get_contact_count() -> int:
    return surfaces_to_contacts.size()


func clear_current_state() -> void:
    # Let these properties be updated in the normal way:
    # -   previous_center_position
    # -   did_move_frame_before_last
    # -   previous_grab_position
    # -   previous_grab_normal
    # -   previous_grabbed_surface
    # -   last_position_along_surface
    is_touching_floor = false
    is_touching_ceiling = false
    is_touching_left_wall = false
    is_touching_right_wall = false

    is_grabbing_floor = false
    is_grabbing_ceiling = false
    is_grabbing_left_wall = false
    is_grabbing_right_wall = false

    just_touched_floor = false
    just_touched_ceiling = false
    just_touched_left_wall = false
    just_touched_right_wall = false

    just_stopped_touching_floor = false
    just_stopped_touching_ceiling = false
    just_stopped_touching_left_wall = false
    just_stopped_touching_right_wall = false

    just_grabbed_floor = false
    just_grabbed_ceiling = false
    just_grabbed_left_wall = false
    just_grabbed_right_wall = false

    just_stopped_grabbing_floor = false
    just_stopped_grabbing_ceiling = false
    just_stopped_grabbing_left_wall = false
    just_stopped_grabbing_right_wall = false

    is_facing_wall = false
    is_pressing_into_wall = false
    is_pressing_away_from_wall = false

    is_triggering_explicit_wall_grab = false
    is_triggering_explicit_ceiling_grab = false
    is_triggering_explicit_floor_grab = false

    is_triggering_implicit_wall_grab = false
    is_triggering_implicit_ceiling_grab = false
    is_triggering_implicit_floor_grab = false

    is_triggering_wall_release = false
    is_triggering_ceiling_release = false
    is_triggering_fall_through = false
    is_triggering_jump = false

    is_descending_through_floors = false
    is_ascending_through_ceilings = false
    is_grabbing_walk_through_walls = false

    surface_type = SurfaceType.AIR

    did_move_last_frame = !G.geometry.are_points_equal_with_epsilon(
            previous_center_position,
            center_position,
            0.00001)
    grab_position = Vector2.INF
    grab_normal = Vector2.INF
    grab_position_tilemap_coord = Vector2.INF
    grabbed_tilemap = null
    grabbed_surface = null
    center_position_along_surface.reset()

    just_changed_surface = false
    just_changed_tilemap = false
    just_changed_tilemap_coord = false
    just_changed_grab_position = false
    just_entered_air = false
    just_left_air = false

    horizontal_facing_sign = -1
    horizontal_acceleration_sign = 0
    toward_wall_sign = 0

    surfaces_to_contacts.clear()
    surface_grab = null
    floor_contact = null
    ceiling_contact = null
    left_wall_contact = null
    right_wall_contact = null

    contact_count = 0
