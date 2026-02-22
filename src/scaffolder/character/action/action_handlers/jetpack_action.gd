class_name JetpackAction
extends CharacterActionHandler
## Applies continuous upward thrust while the jump control is held,
## replacing discrete jumps when jetpack cheat is active.

const NAME := "JetpackAction"
const TYPE := SurfaceType.OTHER
const USES_RUNTIME_PHYSICS := true
## Runs after all default actions (including AirDefaultAction at
## 410) so that thrust is applied after gravity and
## FloorDefaultAction velocity zeroing.
const PRIORITY := 500


func _init() -> void:
	super(NAME, TYPE, USES_RUNTIME_PHYSICS, PRIORITY)


func process(character) -> bool:
	if not CheatManager.is_jetpack_cheat_active():
		return false

	if character.actions.is_triggering_jump:
		var delta := Netcode.time.get_time_step_sec()
		character.velocity.y -= (
			G.settings.jetpack_acceleration * delta
		)
		character.velocity.y = maxf(
			character.velocity.y,
			-G.settings.jetpack_max_upward_speed,
		)

	# Always return true when jetpack is active to block
	# discrete jump handlers via processed_action().
	return true
