class_name CeilingJumpDownAction
extends CharacterActionHandler

const NAME := "CeilingJumpDownAction"
const TYPE := SurfaceType.CEILING
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 320


func _init() -> void:
	super (NAME, TYPE, USES_RUNTIME_PHYSICS, PRIORITY)


func process(character) -> bool:
	if character.actions.just_triggered_jump:
		character.jump_sequence_count = 1

		character.velocity.y = - character.movement_settings.jump_boost

		return true
	else:
		return false
