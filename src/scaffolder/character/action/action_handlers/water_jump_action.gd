class_name WaterJumpAction
extends CharacterActionHandler
## Handles jumping while in water. Two types:
## - Surface jump: at or above the float line
##   with velocity near zero or upward.
## - Subsurface jump: below the float line; half
##   as strong as the surface jump.

const NAME := "WaterJumpAction"
const TYPE := SurfaceType.OTHER
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 225


func _init() -> void:
	super(NAME, TYPE, USES_RUNTIME_PHYSICS, PRIORITY)


func process(character) -> bool:
	if not character.surfaces.is_in_water:
		return false

	if not character.actions.just_triggered_jump:
		return false

	var ms: MovementSettings = (
		character.movement_settings
	)

	var float_line_y: float = (
		character.water_surface_y
		+ ms.water_sink_threshold
	)

	# Surface jump: near or above the float line
	# with velocity near zero or upward.
	var is_near_surface: bool = (
		character.global_position.y
		<= float_line_y
			+ ms.water_snap_threshold
	)
	var is_velocity_ok: bool = (
		character.velocity.y <= 0.0
	)

	if is_near_surface and is_velocity_ok:
		character.velocity.y = (
			ms.water_surface_jump_boost
		)
	else:
		character.velocity.y = (
			ms.water_subsurface_jump_boost
		)

	return true
