class_name CharacterSurfaceState
extends RefCounted
## -   State relating to a character's position relative to nearby surfaces.[br]
## -   This is updated each physics frame.[br]

# TODO: Add support for tracking is_sliding
# - When is_touching_wall and not is_attached_to_surface and not is_attached_to_floor.

const BIT_TOUCHING_FLOOR := 0
const BIT_TOUCHING_CEILING := 1
const BIT_TOUCHING_LEFT_WALL := 2
const BIT_TOUCHING_RIGHT_WALL := 3
const BIT_ATTACHING_TO_FLOOR := 4
const BIT_ATTACHING_TO_CEILING := 5
const BIT_ATTACHING_TO_LEFT_WALL := 6
const BIT_ATTACHING_TO_RIGHT_WALL := 7
const BIT_FACING_LEFT := 8

## The underlying state is stored as a bitmask.
##
## Bit layout:
##   0: is_touching_floor
##   1: is_touching_ceiling
##   2: is_touching_left_wall
##   3: is_touching_right_wall
##   4: is_attaching_to_floor
##   5: is_attaching_to_ceiling
##   6: is_attaching_to_left_wall
##   7: is_attaching_to_right_wall
##   8: is_facing_left
var bitmask: int = 0
var previous_bitmask: int = 0

var is_touching_floor: bool:
	set(value):
		_set_bit(BIT_TOUCHING_FLOOR, value)
	get:
		return _get_bit(bitmask, BIT_TOUCHING_FLOOR)
var is_touching_ceiling: bool:
	set(value):
		_set_bit(BIT_TOUCHING_CEILING, value)
	get:
		return _get_bit(bitmask, BIT_TOUCHING_CEILING)
var is_touching_left_wall: bool:
	set(value):
		_set_bit(BIT_TOUCHING_LEFT_WALL, value)
	get:
		return _get_bit(bitmask, BIT_TOUCHING_LEFT_WALL)
var is_touching_right_wall: bool:
	set(value):
		_set_bit(BIT_TOUCHING_RIGHT_WALL, value)
	get:
		return _get_bit(bitmask, BIT_TOUCHING_RIGHT_WALL)
var is_touching_surface: bool:
	get:
		return (
			is_touching_floor
			or is_touching_ceiling
			or is_touching_left_wall
			or is_touching_right_wall
		)
var is_touching_wall: bool:
	get:
		return is_touching_left_wall or is_touching_right_wall

var is_attaching_to_floor: bool:
	set(value):
		_set_bit(BIT_ATTACHING_TO_FLOOR, value)
	get:
		return _get_bit(bitmask, BIT_ATTACHING_TO_FLOOR)
var is_attaching_to_ceiling: bool:
	set(value):
		_set_bit(BIT_ATTACHING_TO_CEILING, value)
	get:
		return _get_bit(bitmask, BIT_ATTACHING_TO_CEILING)
var is_attaching_to_left_wall: bool:
	set(value):
		_set_bit(BIT_ATTACHING_TO_LEFT_WALL, value)
	get:
		return _get_bit(bitmask, BIT_ATTACHING_TO_LEFT_WALL)
var is_attaching_to_right_wall: bool:
	set(value):
		_set_bit(BIT_ATTACHING_TO_RIGHT_WALL, value)
	get:
		return _get_bit(bitmask, BIT_ATTACHING_TO_RIGHT_WALL)
var is_attaching_to_surface: bool:
	get:
		return (
			is_attaching_to_floor
			or is_attaching_to_ceiling
			or is_attaching_to_left_wall
			or is_attaching_to_right_wall
		)
var is_attaching_to_wall: bool:
	get:
		return is_attaching_to_left_wall or is_attaching_to_right_wall

var just_touched_floor: bool:
	get:
		return is_touching_floor and not _get_bit(previous_bitmask, BIT_TOUCHING_FLOOR)
var just_touched_ceiling: bool:
	get:
		return is_touching_ceiling and not _get_bit(previous_bitmask, BIT_TOUCHING_CEILING)
var just_touched_left_wall: bool:
	get:
		return is_touching_left_wall and not _get_bit(previous_bitmask, BIT_TOUCHING_LEFT_WALL)
var just_touched_right_wall: bool:
	get:
		return is_touching_right_wall and not _get_bit(previous_bitmask, BIT_TOUCHING_RIGHT_WALL)
var just_touched_surface: bool:
	get:
		return (
			just_touched_floor
			or just_touched_ceiling
			or just_touched_left_wall
			or just_touched_right_wall
		)
var just_touched_wall: bool:
	get:
		return just_touched_left_wall or just_touched_right_wall

var just_stopped_touching_floor: bool:
	get:
		return not is_touching_floor and _get_bit(previous_bitmask, BIT_TOUCHING_FLOOR)
var just_stopped_touching_ceiling: bool:
	get:
		return not is_touching_ceiling and _get_bit(previous_bitmask, BIT_TOUCHING_CEILING)
var just_stopped_touching_left_wall: bool:
	get:
		return not is_touching_left_wall and _get_bit(previous_bitmask, BIT_TOUCHING_LEFT_WALL)
var just_stopped_touching_right_wall: bool:
	get:
		return not is_touching_right_wall and _get_bit(previous_bitmask, BIT_TOUCHING_RIGHT_WALL)
var just_stopped_touching_surface: bool:
	get:
		return (
			just_stopped_touching_floor
			or just_stopped_touching_ceiling
			or just_stopped_touching_left_wall
			or just_stopped_touching_right_wall
		)
var just_stopped_touching_wall: bool:
	get:
		return just_stopped_touching_left_wall or just_stopped_touching_right_wall

var just_attached_floor: bool:
	get:
		return is_attaching_to_floor and not _get_bit(previous_bitmask, BIT_ATTACHING_TO_FLOOR)
var just_attached_ceiling: bool:
	get:
		return is_attaching_to_ceiling and not _get_bit(previous_bitmask, BIT_ATTACHING_TO_CEILING)
var just_attached_left_wall: bool:
	get:
		return (
			is_attaching_to_left_wall and not _get_bit(previous_bitmask, BIT_ATTACHING_TO_LEFT_WALL)
		)
var just_attached_right_wall: bool:
	get:
		return (
			is_attaching_to_right_wall
			and not _get_bit(previous_bitmask, BIT_ATTACHING_TO_RIGHT_WALL)
		)
var just_attached_surface: bool:
	get:
		return (
			just_attached_floor
			or just_attached_ceiling
			or just_attached_left_wall
			or just_attached_right_wall
		)
var just_attached_wall: bool:
	get:
		return just_attached_left_wall or just_attached_right_wall

var just_stopped_attaching_to_floor: bool:
	get:
		return not is_attaching_to_floor and _get_bit(previous_bitmask, BIT_ATTACHING_TO_FLOOR)
var just_stopped_attaching_to_ceiling: bool:
	get:
		return not is_attaching_to_ceiling and _get_bit(previous_bitmask, BIT_ATTACHING_TO_CEILING)
var just_stopped_attaching_to_left_wall: bool:
	get:
		return (
			not is_attaching_to_left_wall and _get_bit(previous_bitmask, BIT_ATTACHING_TO_LEFT_WALL)
		)
var just_stopped_attaching_to_right_wall: bool:
	get:
		return (
			not is_attaching_to_right_wall
			and _get_bit(previous_bitmask, BIT_ATTACHING_TO_RIGHT_WALL)
		)
var just_stopped_attaching_to_surface: bool:
	get:
		return (
			just_stopped_attaching_to_floor
			or just_stopped_attaching_to_ceiling
			or just_stopped_attaching_to_left_wall
			or just_stopped_attaching_to_right_wall
		)
var just_stopped_attaching_to_wall: bool:
	get:
		return just_stopped_attaching_to_left_wall or just_stopped_attaching_to_right_wall

var is_facing_wall: bool:
	get:
		return (
			(is_touching_right_wall and horizontal_facing_sign > 0)
			or (is_touching_left_wall and horizontal_facing_sign < 0)
		)
var is_pressing_into_wall: bool:
	get:
		return (
			(is_touching_right_wall and character.actions.pressed_right)
			or (is_touching_left_wall and character.actions.pressed_left)
		)
var is_pressing_away_from_wall: bool:
	get:
		return (
			(is_touching_right_wall and character.actions.pressed_left)
			or (is_touching_left_wall and character.actions.pressed_right)
		)

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

var last_floor_frame_index := -1

var last_floor_position := Vector2.INF

# TODO(OLD): Add support for grabbing jump-through ceilings.
# - Not via a directional key.
# - Make this configurable for climb_adjacent_surfaces behavior.
#   - Add a property that indicates probability of climbing through instead of onto.
#   - Use the same probability for fall-through-floor.

# TODO: Create support for a ceiling_jump_up_action.gd?
# - Might need a new surface state property called
#   is_triggering_jump_up_through, which would be similar to
#   is_triggering_fall_through.
# - Also create support for transitioning from standing-on-fall-through-floor
#   to clinging-to-it-from-underneath and vice versa?
#   - This might require adding support for the concept of a multi-frame
#     action?
#   - And this might require adding new Edge sub-classes for either direction?

var is_ascending_through_ceilings: bool:
	get:
		return not character.movement_settings.can_attach_to_ceilings or not is_attaching_to_ceiling
var is_attaching_to_walk_through_walls: bool:
	get:
		return (
			character.movement_settings.can_attach_to_walls
			and (is_attaching_to_wall or character.actions.pressed_up)
		)

var surface_type: int:
	get:
		return _get_surface_type_from_mask(bitmask)
var previous_surface_type: int:
	get:
		return _get_surface_type_from_mask(previous_bitmask)
var just_left_surface_type: int:
	get:
		return previous_surface_type if surface_type != previous_surface_type else SurfaceType.OTHER

var _was_attaching_to_surface: bool:
	get:
		return (
			_get_bit(previous_bitmask, BIT_ATTACHING_TO_FLOOR)
			or _get_bit(previous_bitmask, BIT_ATTACHING_TO_CEILING)
			or _get_bit(previous_bitmask, BIT_ATTACHING_TO_LEFT_WALL)
			or _get_bit(previous_bitmask, BIT_ATTACHING_TO_RIGHT_WALL)
		)

var just_entered_air: bool:
	get:
		return not is_attaching_to_surface and _was_attaching_to_surface
var just_left_air: bool:
	get:
		return is_attaching_to_surface and not _was_attaching_to_surface

var attachment_side: int:
	get:
		if is_attaching_to_floor:
			return SurfaceSide.FLOOR
		elif is_attaching_to_ceiling:
			return SurfaceSide.CEILING
		elif is_attaching_to_left_wall:
			return SurfaceSide.LEFT_WALL
		elif is_attaching_to_right_wall:
			return SurfaceSide.RIGHT_WALL
		else:
			return SurfaceSide.NONE

var just_changed_attachment_side: bool:
	get:
		# Compare attachment bits (4-7) between current and previous bitmask
		const ATTACHMENT_MASK := 0xF << BIT_ATTACHING_TO_FLOOR
		return (bitmask & ATTACHMENT_MASK) != (previous_bitmask & ATTACHMENT_MASK)

var horizontal_facing_sign: int:
	set(value):
		_set_bit(BIT_FACING_LEFT, value <= 0)
	get:
		return -1 if _get_bit(bitmask, BIT_FACING_LEFT) else 1
var toward_wall_sign: int:
	get:
		return -1 if is_touching_left_wall else (1 if is_touching_right_wall else 0)
var is_facing_right: bool:
	set(value):
		_set_bit(BIT_FACING_LEFT, not value)
	get:
		return not _get_bit(bitmask, BIT_FACING_LEFT)

var horizontal_acceleration_sign: int:
	get:
		if is_attaching_to_wall:
			return 0
		elif character.actions.pressed_right:
			return 1
		elif character.actions.pressed_left:
			return -1
		else:
			return 0

var is_within_coyote_time: bool:
	get:
		if is_attaching_to_floor:
			return true
		if last_floor_frame_index < 0:
			return false
		var frames_since_floor := (
			Netcode.server_frame_index - last_floor_frame_index
		)
		var threshold_frames := int(
			character.movement_settings
				.late_jump_forgiveness_threshold_sec
			/ Netcode.time.get_time_step_sec()
		)
		return frames_since_floor <= threshold_frames

# TODO: Do something with this.
var surface_properties := SurfaceProperties.new()

var character: Character

# Validator for filtering invalid one-way floor collisions.
var _one_way_validator := OneWayCollisionValidator.new()


func _init(p_character: Character) -> void:
	self.character = p_character


## Helper function to check if a bit is set in a bitmask.
static func _get_bit(mask: int, bit: int) -> bool:
	return (mask >> bit) & 1 == 1


## Helper function to set or clear a bit in the bitmask.
func _set_bit(bit: int, value: bool) -> void:
	if value:
		bitmask |= 1 << bit
	else:
		bitmask &= ~(1 << bit)


## Helper function to compute surface type from a bitmask.
func _get_surface_type_from_mask(mask: int) -> int:
	if _get_bit(mask, BIT_ATTACHING_TO_FLOOR):
		return SurfaceType.FLOOR
	elif _get_bit(mask, BIT_ATTACHING_TO_LEFT_WALL) or _get_bit(mask, BIT_ATTACHING_TO_RIGHT_WALL):
		return SurfaceType.WALL
	elif _get_bit(mask, BIT_ATTACHING_TO_CEILING):
		return SurfaceType.CEILING
	else:
		return SurfaceType.AIR


func update_touches(
	pre_move_and_slide_position: Vector2 = Vector2.INF,
	pre_move_and_slide_velocity: Vector2 = Vector2.INF
) -> void:
	# Reset touch state before processing collisions.
	is_touching_floor = false
	is_touching_ceiling = character.is_on_ceiling()
	is_touching_left_wall = false
	is_touching_right_wall = false

	var should_correct := pre_move_and_slide_position != Vector2.INF

	# Process all slide collisions.
	for i in range(character.get_slide_collision_count()):
		var collision := character.get_slide_collision(i)
		var normal := collision.get_normal()

		# Floor-like collision (normal points up).
		if normal.y < -0.5:
			if _one_way_validator.validate_floor_collision(
				collision, character.velocity,
				character.collision_shape.shape,
				character.global_position
			):
				is_touching_floor = true
			elif should_correct:
				# Invalid one-way collision - correct position and velocity.
				_correct_invalid_collision(collision, pre_move_and_slide_position, pre_move_and_slide_velocity)
				should_correct = false # Only correct once per frame.
		# Wall collision (normal points horizontally).
		elif abs(normal.y) < 0.5:
			if normal.x > 0:
				is_touching_left_wall = true
			else:
				is_touching_right_wall = true


## Corrects position and velocity after an invalid one-way tile collision.
func _correct_invalid_collision(
	collision: KinematicCollision2D,
	_pre_move_and_slide_position: Vector2,
	pre_move_and_slide_velocity: Vector2
) -> void:
	# Use collision.get_remainder() to find where we should have gone.
	var remainder := collision.get_remainder()
	character.position += remainder
	character.velocity = pre_move_and_slide_velocity


# Updates surface-related state according to the character's recent movement
# and the environment of the current frame.
func update_actions() -> void:
	_update_horizontal_direction()
	_update_attachment_trigger_state()
	_update_attachment_state()

	assert(!is_attaching_to_surface or is_touching_surface)


func _update_horizontal_direction() -> void:
	# Flip the horizontal direction of the animation according to which way the
	# character is facing.
	if is_attaching_to_left_wall or is_attaching_to_right_wall:
		horizontal_facing_sign = toward_wall_sign
	elif character.actions.pressed_face_right:
		horizontal_facing_sign = 1
	elif character.actions.pressed_face_left:
		horizontal_facing_sign = -1
	elif character.actions.pressed_right:
		horizontal_facing_sign = 1
	elif character.actions.pressed_left:
		horizontal_facing_sign = -1


func _update_attachment_trigger_state() -> void:
	var is_touching_wall_and_pressing_up: bool = character.actions.pressed_up and is_touching_wall
	var is_touching_wall_and_pressing_attachment: bool = (
		character.actions.pressed_attach and is_touching_wall
	)

	var just_pressed_jump: bool = character.actions.just_triggered_jump
	var is_pressing_floor_attachment_input: bool = (
		character.actions.pressed_down and !just_pressed_jump
	)
	var is_pressing_ceiling_attachment_input: bool = (
		character.actions.pressed_up and !character.actions.pressed_down and !just_pressed_jump
	)
	var is_pressing_wall_attachment_input := (
		is_pressing_into_wall and !is_pressing_away_from_wall and !just_pressed_jump
	)
	var is_pressing_ceiling_release_input: bool = (
		character.actions.pressed_down
		and !character.actions.pressed_up
		and !character.actions.pressed_attach
		or just_pressed_jump
	)
	var is_pressing_wall_release_input := (
		is_pressing_away_from_wall and !is_pressing_into_wall or just_pressed_jump
	)
	var is_pressing_fall_through_input: bool = character.actions.pressed_down
	#var is_pressing_fall_through_input: bool = \
	#character.actions.pressed_down and \
	#character.actions.just_pressed_jump

	is_triggering_explicit_floor_attachment = (
		is_touching_floor
		and is_pressing_floor_attachment_input
		and character.movement_settings.can_attach_to_floors
		and !just_pressed_jump
	)
	is_triggering_explicit_ceiling_attachment = (
		is_touching_ceiling
		and is_pressing_ceiling_attachment_input
		and character.movement_settings.can_attach_to_ceilings
		and !just_pressed_jump
	)
	is_triggering_explicit_wall_attachment = (
		is_touching_wall
		and is_pressing_wall_attachment_input
		and character.movement_settings.can_attach_to_walls
		and !just_pressed_jump
	)

	is_triggering_implicit_floor_attachment = (
		is_touching_floor
		and character.movement_settings.can_attach_to_floors
		and !just_pressed_jump
	)
	is_triggering_implicit_ceiling_attachment = (
		is_touching_ceiling
		and character.actions.pressed_attach
		and character.movement_settings.can_attach_to_ceilings
		and !just_pressed_jump
	)
	is_triggering_implicit_wall_attachment = (
		(is_touching_wall_and_pressing_up or is_touching_wall_and_pressing_attachment)
		and character.movement_settings.can_attach_to_walls
		and !just_pressed_jump
	)

	is_triggering_ceiling_release = (
		is_attaching_to_ceiling
		and is_pressing_ceiling_release_input
		and !is_triggering_explicit_ceiling_attachment
		and !is_triggering_implicit_ceiling_attachment
	)
	is_triggering_wall_release = (
		is_attaching_to_wall
		and is_pressing_wall_release_input
		and !is_triggering_explicit_wall_attachment
		and !is_triggering_implicit_wall_attachment
	)
	is_triggering_fall_through = is_touching_floor and is_pressing_fall_through_input
	is_triggering_jump = just_pressed_jump and !is_triggering_fall_through


func _update_attachment_state() -> void:
	var standard_is_attaching_to_ceiling: bool = (
		is_touching_ceiling
		and (
			is_attaching_to_ceiling
			or is_triggering_explicit_ceiling_attachment
			or (
				is_triggering_implicit_ceiling_attachment
				and !is_attaching_to_floor
				and !is_attaching_to_wall
			)
		)
		and !is_triggering_ceiling_release
		and !is_triggering_jump
		and (is_triggering_explicit_ceiling_attachment or !is_triggering_explicit_wall_attachment)
	)

	var standard_is_attaching_to_wall: bool = (
		is_touching_wall
		and (
			is_attaching_to_wall
			or is_triggering_explicit_wall_attachment
			or (
				is_triggering_implicit_wall_attachment
				and !is_attaching_to_floor
				and !is_attaching_to_ceiling
			)
		)
		and !is_triggering_wall_release
		and !is_triggering_jump
		and !is_triggering_explicit_floor_attachment
		and !is_triggering_explicit_ceiling_attachment
	)

	# Check if floor attachment is blocked due to recent boost (kill/bump).
	var is_boost_cooldown_active: bool = character.is_in_boost_cooldown()

	var standard_is_attaching_to_floor: bool = (
		is_touching_floor
		and (
			is_attaching_to_floor
			or is_triggering_explicit_floor_attachment
			or (
				is_triggering_implicit_floor_attachment
				and !is_attaching_to_ceiling
				and !is_attaching_to_wall
			)
		)
		and !is_triggering_fall_through
		and !is_triggering_jump
		and !is_boost_cooldown_active
		and (is_triggering_explicit_floor_attachment or !is_triggering_explicit_wall_attachment)
	)

	var next_is_attaching_to_ceiling := (
		standard_is_attaching_to_ceiling and !is_triggering_ceiling_release
	)

	var next_is_attaching_to_floor := (
		standard_is_attaching_to_floor
		and !is_triggering_fall_through
		and !next_is_attaching_to_ceiling
	)

	var next_is_attaching_to_wall := (
		standard_is_attaching_to_wall
		and !is_triggering_wall_release
		and !is_triggering_fall_through
		and !next_is_attaching_to_floor
		and !next_is_attaching_to_ceiling
	)

	var next_is_attaching_to_left_wall: bool
	var next_is_attaching_to_right_wall: bool
	if next_is_attaching_to_wall:
		next_is_attaching_to_left_wall = is_touching_left_wall
		next_is_attaching_to_right_wall = is_touching_right_wall
	else:
		next_is_attaching_to_left_wall = false
		next_is_attaching_to_right_wall = false

	is_attaching_to_floor = next_is_attaching_to_floor
	is_attaching_to_ceiling = next_is_attaching_to_ceiling
	is_attaching_to_left_wall = next_is_attaching_to_left_wall
	is_attaching_to_right_wall = next_is_attaching_to_right_wall

	# Whether we should fall through fall-through floors.
	match surface_type:
		SurfaceType.FLOOR:
			is_descending_through_floors = is_triggering_fall_through
		SurfaceType.WALL:
			is_descending_through_floors = character.actions.pressed_down
		SurfaceType.CEILING:
			is_descending_through_floors = false
		SurfaceType.AIR, SurfaceType.OTHER:
			is_descending_through_floors = character.actions.pressed_down
		_:
			Netcode.fatal("CharacterSurfaceState._update_attachment_state")

	if is_attaching_to_floor:
		last_floor_frame_index = Netcode.server_frame_index
		last_floor_position = character.global_position


func clear_current_state() -> void:
	# Clear all bitmask-stored state (bits 0-8), default facing right
	bitmask = 0
	previous_bitmask = 0

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


func force_boost() -> void:
	var previous_horizontal_facing_sign := horizontal_facing_sign

	# Save current state as previous so just_* getters work correctly
	previous_bitmask = bitmask

	# Clear current state
	bitmask = 0
	horizontal_facing_sign = previous_horizontal_facing_sign


## Gets the collision for a specific surface side from the character's
## current slide collisions.
## Returns null if no collision matches the given side.
func get_collision_for_side(side: int) -> KinematicCollision2D:
	if character.get_slide_collision_count() == 0:
		return null

	for i in range(character.get_slide_collision_count()):
		var collision := character.get_slide_collision(i)
		var normal := collision.get_normal()

		match side:
			SurfaceSide.FLOOR:
				# Floor collision: normal points up (y < -0.5)
				if normal.y < -0.5:
					return collision
			SurfaceSide.CEILING:
				# Ceiling collision: normal points down (y > 0.5)
				if normal.y > 0.5:
					return collision
			SurfaceSide.LEFT_WALL:
				# Left wall collision: normal points right (x > 0.5)
				if abs(normal.y) < 0.5 and normal.x > 0.5:
					return collision
			SurfaceSide.RIGHT_WALL:
				# Right wall collision: normal points left (x < -0.5)
				if abs(normal.y) < 0.5 and normal.x < -0.5:
					return collision

	return null
