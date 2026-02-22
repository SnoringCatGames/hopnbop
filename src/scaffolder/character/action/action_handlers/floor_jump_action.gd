class_name FloorJumpAction
extends CharacterActionHandler

const NAME := "FloorJumpAction"
const TYPE := SurfaceType.FLOOR
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 230


func _init() -> void:
	super (NAME, TYPE, USES_RUNTIME_PHYSICS, PRIORITY)


func process(character) -> bool:
	if (
		!character.processed_action(
			FallThroughFloorAction.NAME)
		and not CheatManager.is_jetpack_cheat_active()
		and (character.actions.just_triggered_jump
			or CheatManager
				.is_pogostick_cheat_active())
		and not character.surfaces.is_launched
	):
		character.jump_sequence_count = 1
		character.velocity.y = character.movement_settings.jump_boost

		return true
	else:
		return false
