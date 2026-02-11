class_name WallDefaultAction
extends CharacterActionHandler

const NAME := "WallDefaultAction"
const TYPE := SurfaceType.WALL
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 110


func _init() -> void:
	super(NAME, TYPE, USES_RUNTIME_PHYSICS, PRIORITY)


func process(character) -> bool:
	# Only process when actually attached to wall. Skip when
	# dispatched via just_left_surface_type (departure frame)
	# to avoid zeroing wall-jump velocity on the frame after
	# onset.
	if character.surfaces.surface_type != SurfaceType.WALL:
		return false

	character.jump_sequence_count = 0
	character.velocity.x = 0.0
	character.velocity.y = 0.0

	return true
