class_name AirJumpAction
extends CharacterActionHandler


const NAME := "AirJumpAction"
const TYPE := SurfaceType.AIR
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 420


func _init() -> void:
    super(
        NAME,
        TYPE,
        USES_RUNTIME_PHYSICS,
        PRIORITY)


func process(character) -> bool:
    if character.actions.just_pressed_jump and \
            character.jump_count < character.movement_settings.max_jump_chain:
        if character.surface_state.just_entered_air:
            character.jump_count = 1
        else:
            character.jump_count += 1
        character.just_triggered_jump = true
        character.is_rising_from_jump = true
        character.velocity.y = character.movement_settings.jump_boost

        return true
    else:
        return false
