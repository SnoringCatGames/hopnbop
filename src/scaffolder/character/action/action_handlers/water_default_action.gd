class_name WaterDefaultAction
extends CharacterActionHandler
## Handles buoyancy, gravity, and horizontal
## movement when the character is in water.

const NAME := "WaterDefaultAction"
const TYPE := SurfaceType.OTHER
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 405

## Frames after a jump during which float-line
## snapping and overshoot prevention are disabled,
## so the player can leave the water.
const _JUMP_GRACE_SEC := 0.167


func _init() -> void:
	super(NAME, TYPE, USES_RUNTIME_PHYSICS, PRIORITY)


func process(character) -> bool:
	if not character.surfaces.is_in_water:
		return false

	var delta: float = (
		Netcode.time.get_time_step_sec()
	)
	var ms: MovementSettings = (
		character.movement_settings
	)

	# Reduce downward speed on the first frame
	# of entering water.
	if (
		character.surfaces.just_entered_water
		and character.velocity.y > 0.0
	):
		character.velocity.y *= (
			ms.water_entry_speed_multiplier
		)

	# Float line = water surface + sink threshold.
	var float_line_y: float = (
		character.water_surface_y
		+ ms.water_sink_threshold
	)

	# Don't snap to the float line right after
	# a jump so the player can leave the water.
	var jump_grace_frames := int(
		_JUMP_GRACE_SEC
		/ Netcode.time.get_time_step_sec()
	)
	var recently_jumped: bool = (
		(Netcode.server_frame_index
			- character
				.last_triggered_jump_frame_index)
		< jump_grace_frames
	)

	# --- Vertical force ---
	# Snap when near the float line and velocity
	# is within buoyancy range (not a jump).
	# Uses water_max_upward_speed as the velocity
	# threshold to distinguish buoyancy from jumps.
	var at_float_line: bool = (
		not recently_jumped
		and character.velocity.y <= 0.0
		and absf(
			character.global_position.y
			- float_line_y
		) < ms.water_snap_threshold
		and absf(character.velocity.y)
			<= ms.water_max_upward_speed
	)

	if at_float_line:
		# Rest at float line. Only zero velocity;
		# avoid teleporting position because
		# move_and_slide may fight the snap and
		# cause oscillation. The overshoot
		# prevention lands the character within
		# fractions of a pixel, so a gentle
		# correction is enough.
		character.velocity.y = 0.0
		if absf(
			character.global_position.y
			- float_line_y
		) < 0.5:
			character.global_position.y = (
				float_line_y
			)
	elif character.global_position.y > float_line_y:
		# Below float line: upward buoyancy.
		character.velocity.y -= (
			ms.buoyancy_acceleration * delta
		)
		# Skip speed cap and overshoot prevention
		# after jumps/hops so the player can exit
		# the water.
		if not recently_jumped:
			# Cap upward speed in water.
			character.velocity.y = maxf(
				character.velocity.y,
				-ms.water_max_upward_speed,
			)
			# Prevent buoyancy from overshooting
			# the float line. Clamp velocity so
			# the next move_and_slide lands exactly
			# at (or just past) the float line.
			var dist: float = (
				character.global_position.y
				- float_line_y
			)
			var max_up := -dist / delta
			if character.velocity.y < max_up:
				character.velocity.y = max_up
	else:
		# Above float line from a jump or
		# falling back: normal gravity.
		character.velocity.y += (
			ms.gravity_fast_fall_acceleration
			* delta
		)

	# --- Horizontal movement ---
	var h_sign: int = (
		character.surfaces
			.horizontal_acceleration_sign
	)
	if h_sign != 0:
		character.velocity.x += (
			ms.water_horizontal_acceleration
			* h_sign
			* delta
		)
	elif ms.water_horizontal_friction > 0.0:
		# Decelerate when no horizontal input.
		var friction_decel := (
			ms.water_horizontal_friction
			* ms.gravity_fast_fall_acceleration
			* delta
		)
		if absf(character.velocity.x) <= (
			friction_decel
		):
			character.velocity.x = 0.0
		else:
			character.velocity.x -= (
				signf(character.velocity.x)
				* friction_decel
			)

	return true
