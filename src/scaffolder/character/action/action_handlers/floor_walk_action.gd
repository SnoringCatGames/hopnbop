class_name FloorWalkAction
extends CharacterActionHandler


const NAME := "FloorWalkAction"
const TYPE := SurfaceType.FLOOR
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 240


func _init() -> void:
    super (
        NAME,
        TYPE,
        USES_RUNTIME_PHYSICS,
        PRIORITY)


func process(character) -> bool:
    if !character.processed_action(FloorJumpAction.NAME):
        # Horizontal movement.
        character.velocity.x += \
                character.current_walk_acceleration * \
                character.last_delta_scaled * \
                character.surfaces.horizontal_acceleration_sign

        return true
    else:
        return false
