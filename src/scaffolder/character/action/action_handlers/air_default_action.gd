class_name AirDefaultAction
extends CharacterActionHandler

const NAME := "AirDefaultAction"
const TYPE := SurfaceType.AIR
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 410

const BOUNCE_OFF_CEILING_VELOCITY := 15.0

const BUNNIESINSPACE_GRAVITY_MULTIPLIER := 0.4


func _init() -> void:
	super (NAME, TYPE, USES_RUNTIME_PHYSICS, PRIORITY)


func process(character) -> bool:
	# Water handlers manage gravity and horizontal
	# movement when in water.
	if character.surfaces.is_in_water:
		return false

	# If the character falls off a wall or ledge, then that's considered the
	# first jump.
	character.jump_sequence_count = max(character.jump_sequence_count, 1)

	var is_first_jump: bool = character.jump_sequence_count == 1

	# If we just fell off the bottom of a wall, cancel any velocity toward
	# that wall.
	if (
		character.surfaces.just_entered_air
		and (
			(
				character.surfaces.just_stopped_attaching_to_left_wall
				and character.velocity.x < 0.0
			)
			or (
				character.surfaces.just_stopped_attaching_to_right_wall
				and character.velocity.x > 0.0
			)
		)
	):
		character.velocity.x = 0.0

	character.velocity = update_velocity_in_air(
		character.velocity,
		Netcode.time.get_time_step_sec(),
		character.actions.is_triggering_jump,
		is_first_jump,
		character.surfaces.horizontal_acceleration_sign,
		character.movement_settings,
		character.surfaces.is_launched,
	)

	# Bouncing off ceiling.
	if (
		character.surfaces.is_touching_ceiling
		and !character.surfaces.is_attaching_to_ceiling
	):
		character.velocity.y = BOUNCE_OFF_CEILING_VELOCITY

		var ceiling_collision: KinematicCollision2D = (
			character.surfaces.get_collision_for_side(SurfaceSide.CEILING)
		)
		if ceiling_collision != null:
			var normal := ceiling_collision.get_normal()
			# Only cancel horizontal velocity if ceiling is sloped AND the
			# slope opposes movement direction (not for horizontal ceilings)
			var is_ceiling_sloped := absf(normal.x) > 0.1
			if is_ceiling_sloped:
				var is_sloped_against_movement: bool = (
					(normal.x < 0.0 and character.velocity.x < 0.0)
					or (normal.x > 0.0 and character.velocity.x > 0.0)
				)
				if is_sloped_against_movement:
					character.velocity.x = 0.0

	return true


static func update_velocity_in_air(
		velocity: Vector2,
		delta: float,
		is_pressing_jump: bool,
		is_first_jump: bool,
		horizontal_acceleration_sign: int,
		movement_settings: MovementSettings,
		is_launched: bool = false,
) -> Vector2:
	var is_rising_from_jump := velocity.y < 0 and is_pressing_jump

	# Make gravity stronger when falling. This creates a more satisfying jump.
	# Similarly, make gravity stronger for double jumps.
	var gravity := (
		movement_settings.gravity_fast_fall_acceleration
		if is_launched or !is_rising_from_jump
		else (
			movement_settings.gravity_slow_rise_acceleration
			if is_first_jump
			else movement_settings
				.gravity_double_jump_slow_rise_acceleration
		)
	)
	if CheatManager.is_bunniesinspace_cheat_active():
		gravity *= BUNNIESINSPACE_GRAVITY_MULTIPLIER

	# Vertical movement.
	velocity.y += delta * gravity

	# Horizontal movement.
	if horizontal_acceleration_sign != 0:
		velocity.x += (
			delta
			* movement_settings.in_air_horizontal_acceleration
			* horizontal_acceleration_sign
		)
	elif (
		movement_settings.fall_horizontal_friction > 0.0
		and not is_launched
	):
		# Apply friction to slow horizontal movement when not pressing
		# left/right.
		var friction_deceleration := (
			movement_settings.fall_horizontal_friction *
			movement_settings.gravity_fast_fall_acceleration *
			delta
		)
		if absf(velocity.x) <= friction_deceleration:
			velocity.x = 0.0
		else:
			velocity.x -= signf(velocity.x) * friction_deceleration

	return velocity
