class_name CeilingDefaultAction
extends CharacterActionHandler

const NAME := "CeilingDefaultAction"
const TYPE := SurfaceType.CEILING
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 310


func _init() -> void:
	super(NAME, TYPE, USES_RUNTIME_PHYSICS, PRIORITY)


func process(character) -> bool:
	# Only process when actually attached to ceiling. Skip when
	# dispatched via just_left_surface_type (departure frame)
	# to avoid zeroing jump-down velocity on the frame after
	# onset.
	if character.surfaces.surface_type != SurfaceType.CEILING:
		return false

	character.jump_sequence_count = 0
	character.velocity.x = 0.0
	character.velocity.y = 0.0

	return true
