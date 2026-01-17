class_name CeilingDefaultAction
extends CharacterActionHandler


const NAME := "CeilingDefaultAction"
const TYPE := SurfaceType.CEILING
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 310


func _init() -> void:
    super (
        NAME,
        TYPE,
        USES_RUNTIME_PHYSICS,
        PRIORITY)


func process(character) -> bool:
    character.jump_sequence_count = 0
    character.velocity.x = 0.0
    character.velocity.y = 0.0

    return true
