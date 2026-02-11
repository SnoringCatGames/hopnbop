class_name FloorDefaultAction
extends CharacterActionHandler

const NAME := "FloorDefaultAction"
const TYPE := SurfaceType.FLOOR
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 210


func _init() -> void:
	super(NAME, TYPE, USES_RUNTIME_PHYSICS, PRIORITY)


func process(character) -> bool:
	# Only process when actually attached to floor. Skip when
	# dispatched via just_left_surface_type (departure frame)
	# to avoid zeroing jump velocity on the frame after onset.
	if character.surfaces.surface_type != SurfaceType.FLOOR:
		return false

	character.jump_sequence_count = 0

	character.velocity.y = 0.0

	return true
