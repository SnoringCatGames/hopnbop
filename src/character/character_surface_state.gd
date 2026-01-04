class_name CharacterSurfaceState
extends RefCounted
## -   State relating to a character's position relative to nearby surfaces.[br]
## -   This is updated each physics frame.[br]


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

var is_attaching_to_floor := false
var is_attaching_to_ceiling := false
var is_attaching_to_left_wall := false
var is_attaching_to_right_wall := false
var is_attaching_to_surface: bool:
    get: return is_attaching_to_floor or \
        is_attaching_to_ceiling or \
        is_attaching_to_left_wall or \
        is_attaching_to_right_wall
var is_attaching_to_wall: bool:
    get: return is_attaching_to_left_wall or \
        is_attaching_to_right_wall

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

var just_attached_floor := false
var just_attached_ceiling := false
var just_attached_left_wall := false
var just_attached_right_wall := false
var just_attached_surface: bool:
    get: return just_attached_floor or \
        just_attached_ceiling or \
        just_attached_left_wall or \
        just_attached_right_wall
var just_attached_wall: bool:
    get: return just_attached_left_wall or \
        just_attached_right_wall

var just_stopped_attaching_to_floor := false
var just_stopped_attaching_to_ceiling := false
var just_stopped_attaching_to_left_wall := false
var just_stopped_attaching_to_right_wall := false
var just_stopped_attaching_to_surface: bool:
    get: return just_stopped_attaching_to_floor or \
        just_stopped_attaching_to_ceiling or \
        just_stopped_attaching_to_left_wall or \
        just_stopped_attaching_to_right_wall
var just_stopped_attaching_to_wall: bool:
    get: return just_stopped_attaching_to_left_wall or \
        just_stopped_attaching_to_right_wall

var is_facing_wall := false
var is_pressing_into_wall := false
var is_pressing_away_from_wall := false

var is_triggering_explicit_wall_attachment := false
var is_triggering_explicit_ceiling_attachment := false
var is_triggering_explicit_floor_attachment := false

var is_triggering_implicit_wall_attachment := false
var is_triggering_implicit_ceiling_attachment := false
var is_triggering_implicit_floor_attachment := false

var is_triggering_wall_release := false
var is_triggering_ceiling_release := false
var is_triggering_fall_through := false
var is_triggering_jump := false

var is_descending_through_floors := false
# FIXME(OLD): -------------------------------
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
var is_attaching_to_walk_through_walls := false

var surface_type := SurfaceType.AIR

var center_position := Vector2.INF
var previous_center_position := Vector2.INF
var did_move_last_frame := false
var did_move_frame_before_last := false

var attachment_position := Vector2.INF
var attachment_normal := Vector2.INF
var previous_attachment_position := Vector2.INF
var previous_attachment_normal := Vector2.INF

var velocity := Vector2.ZERO

var just_changed_attachment_position := false
var just_entered_air := false
var just_left_air := false

var horizontal_facing_sign := -1
var horizontal_acceleration_sign := 0
var toward_wall_sign := 0

var surface_contacts: Array[KinematicCollision2DCopy] = []

var attachment_contact: KinematicCollision2DCopy = null
var floor_contact: KinematicCollision2DCopy = null
var ceiling_contact: KinematicCollision2DCopy = null
var left_wall_contact: KinematicCollision2DCopy = null
var right_wall_contact: KinematicCollision2DCopy = null

var contact_count: int:
    get: return surface_contacts.size()

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
    did_move_last_frame = !Geometry.are_points_equal_with_epsilon(
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

    just_attached_floor = false
    just_attached_ceiling = false
    just_attached_left_wall = false
    just_attached_right_wall = false

    just_stopped_attaching_to_floor = false
    just_stopped_attaching_to_ceiling = false
    just_stopped_attaching_to_left_wall = false
    just_stopped_attaching_to_right_wall = false

    just_entered_air = false
    just_left_air = false

    just_changed_attachment_position = false


func _update_contacts() -> void:
    surface_contacts.clear()
    floor_contact = null
    left_wall_contact = null
    right_wall_contact = null
    ceiling_contact = null
    
    for collision in character.collisions:
        surface_contacts.append(collision)
        match collision.surface.side:
            SurfaceSide.FLOOR:
                floor_contact = collision
            SurfaceSide.LEFT_WALL:
                left_wall_contact = collision
            SurfaceSide.RIGHT_WALL:
                right_wall_contact = collision
            SurfaceSide.CEILING:
                ceiling_contact = collision
            _:
                push_error("CharacterSurfaceState._update_contacts")


func _update_touch_state() -> void:
    var next_is_touching_floor := false
    var next_is_touching_ceiling := false
    var next_is_touching_left_wall := false
    var next_is_touching_right_wall := false

    for contact in surface_contacts:
        match contact.side:
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

    just_touched_floor = \
        next_is_touching_floor and !is_touching_floor
    just_stopped_touching_floor = \
        !next_is_touching_floor and is_touching_floor

    just_touched_ceiling = \
        next_is_touching_ceiling and !is_touching_ceiling
    just_stopped_touching_ceiling = \
        !next_is_touching_ceiling and is_touching_ceiling

    just_touched_left_wall = \
        next_is_touching_left_wall and !is_touching_left_wall
    just_stopped_touching_left_wall = \
        !next_is_touching_left_wall and is_touching_left_wall

    just_touched_right_wall = \
        next_is_touching_right_wall and !is_touching_right_wall
    just_stopped_touching_right_wall = \
        !next_is_touching_right_wall and is_touching_right_wall

    is_touching_floor = next_is_touching_floor
    is_touching_ceiling = next_is_touching_ceiling
    is_touching_left_wall = next_is_touching_left_wall
    is_touching_right_wall = next_is_touching_right_wall

    # Calculate the sign of a colliding wall's direction.
    toward_wall_sign = \
        (-1 if is_touching_left_wall else \
        (1 if is_touching_right_wall else \
        0))


func _update_action_state() -> void:
    _update_horizontal_direction()
    _update_attachment_trigger_state()
    _update_attachment_state()

    assert(!is_attaching_to_surface or is_touching_surface)

    _update_attachment_contact()


func _update_horizontal_direction() -> void:
    # Flip the horizontal direction of the animation according to which way the
    # character is facing.
    if is_attaching_to_left_wall or \
            is_attaching_to_right_wall:
        horizontal_facing_sign = toward_wall_sign
    elif character.actions.pressed_face_right:
        horizontal_facing_sign = 1
    elif character.actions.pressed_face_left:
        horizontal_facing_sign = -1
    elif character.actions.pressed_right:
        horizontal_facing_sign = 1
    elif character.actions.pressed_left:
        horizontal_facing_sign = -1

    if is_attaching_to_left_wall or \
            is_attaching_to_right_wall:
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


func _update_attachment_trigger_state() -> void:
    var is_touching_wall_and_pressing_up: bool = \
        character.actions.pressed_up and \
        is_touching_wall
    var is_touching_wall_and_pressing_attachment: bool = \
        character.actions.pressed_attachment and \
        is_touching_wall

    var just_pressed_jump: bool = \
        character.actions.just_pressed_jump
    var is_pressing_floor_attachment_input: bool = \
        character.actions.pressed_down and \
        !just_pressed_jump
    var is_pressing_ceiling_attachment_input: bool = \
        character.actions.pressed_up and \
        !character.actions.pressed_down and \
        !just_pressed_jump
    var is_pressing_wall_attachment_input := \
        is_pressing_into_wall and \
        !is_pressing_away_from_wall and \
        !just_pressed_jump
    var is_pressing_ceiling_release_input: bool = \
        character.actions.pressed_down and \
        !character.actions.pressed_up and \
        !character.actions.pressed_attachment or \
        just_pressed_jump
    var is_pressing_wall_release_input := \
        is_pressing_away_from_wall and \
        !is_pressing_into_wall or \
        just_pressed_jump
    var is_pressing_fall_through_input: bool = \
        character.actions.pressed_down and \
        character.actions.just_pressed_jump

    is_triggering_explicit_floor_attachment = \
        is_touching_floor and \
        is_pressing_floor_attachment_input and \
        character.movement_params.can_attach_to_floors and \
        !just_pressed_jump
    is_triggering_explicit_ceiling_attachment = \
        is_touching_ceiling and \
        is_pressing_ceiling_attachment_input and \
        character.movement_params.can_attach_to_ceilings and \
        !just_pressed_jump
    is_triggering_explicit_wall_attachment = \
        is_touching_wall and \
        is_pressing_wall_attachment_input and \
        character.movement_params.can_attach_to_walls and \
        !just_pressed_jump
    
    is_triggering_implicit_floor_attachment = \
        is_touching_floor and \
        character.movement_params.can_attach_to_floors and \
        !just_pressed_jump
    is_triggering_implicit_ceiling_attachment = \
        is_touching_ceiling and \
        character.actions.pressed_attachment and \
        character.movement_params.can_attach_to_ceilings and \
        !just_pressed_jump
    is_triggering_implicit_wall_attachment = \
        (is_touching_wall_and_pressing_up or \
        is_touching_wall_and_pressing_attachment) and \
        character.movement_params.can_attach_to_walls and \
        !just_pressed_jump

    is_triggering_ceiling_release = \
        is_attaching_to_ceiling and \
        is_pressing_ceiling_release_input and \
        !is_triggering_explicit_ceiling_attachment and \
        !is_triggering_implicit_ceiling_attachment
    is_triggering_wall_release = \
        is_attaching_to_wall and \
        is_pressing_wall_release_input and \
        !is_triggering_explicit_wall_attachment and \
        !is_triggering_implicit_wall_attachment
    is_triggering_fall_through = \
        is_touching_floor and \
        is_pressing_fall_through_input
    is_triggering_jump = \
        just_pressed_jump and \
        !is_triggering_fall_through


func _update_attachment_state() -> void:
    var standard_is_attaching_to_ceiling: bool = \
        is_touching_ceiling and \
        (is_attaching_to_ceiling or \
        is_triggering_explicit_ceiling_attachment or \
        (is_triggering_implicit_ceiling_attachment and \
        !is_attaching_to_floor and \
        !is_attaching_to_wall)) and \
        !is_triggering_ceiling_release and \
        !is_triggering_jump and \
        (is_triggering_explicit_ceiling_attachment or \
                !is_triggering_explicit_wall_attachment)

    var standard_is_attaching_to_wall: bool = \
        is_touching_wall and \
        (is_attaching_to_wall or \
        is_triggering_explicit_wall_attachment or \
        (is_triggering_implicit_wall_attachment and \
        !is_attaching_to_floor and \
        !is_attaching_to_ceiling)) and \
        !is_triggering_wall_release and \
        !is_triggering_jump and \
        !is_triggering_explicit_floor_attachment and \
        !is_triggering_explicit_ceiling_attachment

    var standard_is_attaching_to_floor: bool = \
        is_touching_floor and \
        (is_attaching_to_floor or \
        is_triggering_explicit_floor_attachment or \
        (is_triggering_implicit_floor_attachment and \
        !is_attaching_to_ceiling and \
        !is_attaching_to_wall)) and \
        !is_triggering_fall_through and \
        !is_triggering_jump and \
        (is_triggering_explicit_floor_attachment or \
        !is_triggering_explicit_wall_attachment)

    var next_is_attaching_to_ceiling := \
        standard_is_attaching_to_ceiling and \
        !is_triggering_ceiling_release

    var next_is_attaching_to_floor := \
        standard_is_attaching_to_floor and \
        !is_triggering_fall_through and \
        !next_is_attaching_to_ceiling

    var next_is_attaching_to_wall := \
        standard_is_attaching_to_wall and \
        !is_triggering_wall_release and \
        !next_is_attaching_to_floor and \
        !next_is_attaching_to_ceiling

    var next_is_attaching_to_left_wall: bool
    var next_is_attaching_to_right_wall: bool
    if next_is_attaching_to_wall:
        next_is_attaching_to_left_wall = is_touching_left_wall
        next_is_attaching_to_right_wall = is_touching_right_wall
    else:
        next_is_attaching_to_left_wall = false
        next_is_attaching_to_right_wall = false

    var next_is_attaching_to_surface := \
        next_is_attaching_to_floor or \
        next_is_attaching_to_ceiling or \
        next_is_attaching_to_wall

    var next_just_attached_floor := \
        next_is_attaching_to_floor and !is_attaching_to_floor
    var next_just_stopped_attaching_to_floor := \
        !next_is_attaching_to_floor and is_attaching_to_floor

    var next_just_attached_ceiling := \
        next_is_attaching_to_ceiling and !is_attaching_to_ceiling
    var next_just_stopped_attaching_to_ceiling := \
        !next_is_attaching_to_ceiling and is_attaching_to_ceiling

    var next_just_attached_left_wall := \
        next_is_attaching_to_left_wall and !is_attaching_to_left_wall
    var next_just_stopped_attaching_to_left_wall := \
        !next_is_attaching_to_left_wall and is_attaching_to_left_wall

    var next_just_attached_right_wall := \
        next_is_attaching_to_right_wall and !is_attaching_to_right_wall
    var next_just_stopped_attaching_to_right_wall := \
        !next_is_attaching_to_right_wall and is_attaching_to_right_wall

    var next_just_entered_air := \
        !next_is_attaching_to_surface and is_attaching_to_surface
    var next_just_left_air := \
        next_is_attaching_to_surface and !is_attaching_to_surface

    is_attaching_to_floor = next_is_attaching_to_floor
    is_attaching_to_ceiling = next_is_attaching_to_ceiling
    is_attaching_to_left_wall = next_is_attaching_to_left_wall
    is_attaching_to_right_wall = next_is_attaching_to_right_wall

    just_attached_floor = \
        next_just_attached_floor or \
        just_attached_floor and \
        !next_just_stopped_attaching_to_floor
    just_stopped_attaching_to_floor = \
        next_just_stopped_attaching_to_floor or \
        just_stopped_attaching_to_floor and \
        !next_just_attached_floor

    just_attached_ceiling = \
        next_just_attached_ceiling or \
        just_attached_ceiling and \
        !next_just_stopped_attaching_to_ceiling
    just_stopped_attaching_to_ceiling = \
        next_just_stopped_attaching_to_ceiling or \
        just_stopped_attaching_to_ceiling and \
        !next_just_attached_ceiling

    just_attached_left_wall = \
        next_just_attached_left_wall or \
        just_attached_left_wall and \
        !next_just_stopped_attaching_to_left_wall
    just_stopped_attaching_to_left_wall = \
        next_just_stopped_attaching_to_left_wall or \
        just_stopped_attaching_to_left_wall and \
        !next_just_attached_left_wall

    just_attached_right_wall = \
        next_just_attached_right_wall or \
        just_attached_right_wall and \
        !next_just_stopped_attaching_to_right_wall
    just_stopped_attaching_to_right_wall = \
        next_just_stopped_attaching_to_right_wall or \
        just_stopped_attaching_to_right_wall and \
        !next_just_attached_right_wall

    just_entered_air = \
        next_just_entered_air or \
        just_entered_air and \
        !next_just_left_air
    just_left_air = \
        next_just_left_air or \
        just_left_air and \
        !next_just_entered_air

    if is_attaching_to_floor:
        surface_type = SurfaceType.FLOOR
    elif is_attaching_to_wall:
        surface_type = SurfaceType.WALL
    elif is_attaching_to_ceiling:
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
            push_error("CharacterSurfaceState._update_attachment_state")

    # FIXME(OLD): ------- Add support for an ascend-through ceiling input.
    # Whether we should ascend-up through jump-through ceilings.
    is_ascending_through_ceilings = \
        !character.movement_params.can_attach_to_ceilings or \
        (!is_attaching_to_ceiling and true)

    # Whether we should fall through fall-through floors.
    is_attaching_to_walk_through_walls = \
        character.movement_params.can_attach_to_walls and \
        (is_attaching_to_wall or \
                character.actions.pressed_up)


func _update_attachment_contact() -> void:
    attachment_contact = null

    if is_attaching_to_surface:
        attachment_contact = _get_attachment_contact()
        assert(is_instance_valid(attachment_contact))
        
        var next_attachment_position := attachment_contact.position
        var next_attachment_normal := attachment_contact.normal

        just_changed_attachment_position = \
            just_left_air or \
            next_attachment_position != attachment_position
        if just_changed_attachment_position and \
                next_attachment_position != attachment_position and \
                attachment_position != Vector2.INF:
            previous_attachment_position = attachment_position
            previous_attachment_normal = attachment_normal
        attachment_position = next_attachment_position
        attachment_normal = next_attachment_normal

    else:
        if just_entered_air:
            just_changed_attachment_position = true
            previous_attachment_position = \
                    attachment_position if \
                    attachment_position != Vector2.INF else \
                    previous_attachment_position
            previous_attachment_normal = \
                    attachment_normal if \
                    attachment_normal != Vector2.INF else \
                    previous_attachment_normal

        attachment_contact = null
        attachment_position = Vector2.INF
        attachment_normal = Vector2.INF


func _get_attachment_contact() -> KinematicCollision2DCopy:
    for surface in surface_contacts:
        if surface.side == SurfaceSide.FLOOR and \
                is_attaching_to_floor or \
            surface.side == SurfaceSide.LEFT_WALL and \
                is_attaching_to_left_wall or \
            surface.side == SurfaceSide.RIGHT_WALL and \
                is_attaching_to_right_wall or \
            surface.side == SurfaceSide.CEILING and \
                is_attaching_to_ceiling:
            return surface_contacts[surface]
    return null


func clear_current_state() -> void:
    # Let these properties be updated in the normal way:
    # -   previous_center_position
    # -   did_move_frame_before_last
    # -   previous_attachment_position
    # -   previous_attachment_normal
    is_touching_floor = false
    is_touching_ceiling = false
    is_touching_left_wall = false
    is_touching_right_wall = false

    is_attaching_to_floor = false
    is_attaching_to_ceiling = false
    is_attaching_to_left_wall = false
    is_attaching_to_right_wall = false

    just_touched_floor = false
    just_touched_ceiling = false
    just_touched_left_wall = false
    just_touched_right_wall = false

    just_stopped_touching_floor = false
    just_stopped_touching_ceiling = false
    just_stopped_touching_left_wall = false
    just_stopped_touching_right_wall = false

    just_attached_floor = false
    just_attached_ceiling = false
    just_attached_left_wall = false
    just_attached_right_wall = false

    just_stopped_attaching_to_floor = false
    just_stopped_attaching_to_ceiling = false
    just_stopped_attaching_to_left_wall = false
    just_stopped_attaching_to_right_wall = false

    is_facing_wall = false
    is_pressing_into_wall = false
    is_pressing_away_from_wall = false

    is_triggering_explicit_wall_attachment = false
    is_triggering_explicit_ceiling_attachment = false
    is_triggering_explicit_floor_attachment = false

    is_triggering_implicit_wall_attachment = false
    is_triggering_implicit_ceiling_attachment = false
    is_triggering_implicit_floor_attachment = false

    is_triggering_wall_release = false
    is_triggering_ceiling_release = false
    is_triggering_fall_through = false
    is_triggering_jump = false

    is_descending_through_floors = false
    is_ascending_through_ceilings = false
    is_attaching_to_walk_through_walls = false

    surface_type = SurfaceType.AIR

    did_move_last_frame = !G.geometry.are_points_equal_with_epsilon(
            previous_center_position,
            center_position,
            0.00001)
    attachment_position = Vector2.INF
    attachment_normal = Vector2.INF

    just_changed_attachment_position = false
    just_entered_air = false
    just_left_air = false

    horizontal_facing_sign = -1
    horizontal_acceleration_sign = 0
    toward_wall_sign = 0

    surface_contacts.clear()
    attachment_contact = null
    floor_contact = null
    ceiling_contact = null
    left_wall_contact = null
    right_wall_contact = null

    contact_count = 0
