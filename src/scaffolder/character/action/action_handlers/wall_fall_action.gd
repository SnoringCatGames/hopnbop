class_name WallFallAction
extends CharacterActionHandler


const NAME := "WallFallAction"
const TYPE := SurfaceType.WALL
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 130


func _init() -> void:
    super (
        NAME,
        TYPE,
        USES_RUNTIME_PHYSICS,
        PRIORITY)


func process(character) -> bool:
    if !character.processed_action(WallJumpAction.NAME) and \
            character.surfaces.is_triggering_wall_release:
        # Cancel any velocity toward the wall.
        character.velocity.x = \
                - character.surfaces.toward_wall_sign * \
                character.movement_settings.wall_fall_horizontal_boost

        return true
    else:
        return false
