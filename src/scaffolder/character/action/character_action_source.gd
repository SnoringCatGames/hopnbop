class_name CharacterActionSource
extends RefCounted


const INPUT_KEY_TO_ACTION_NAME := {
    "j": "jump",
    "mu": "up",
    "md": "down",
    "ml": "left",
    "mr": "right",
    "g": "attach",
    "fl": "face_left",
    "fr": "face_right",
}

var source_type_prefix: String
var character: Character
var is_additive: bool


func _init(
        p_source_type_prefix: String,
        p_character,
        p_is_additive: bool) -> void:
    self.source_type_prefix = p_source_type_prefix
    self.character = p_character
    self.is_additive = p_is_additive


# Calculates actions for the current frame.
func update(
        _actions: CharacterActionState,
        _time_scaled: float) -> void:
    push_error("Abstract CharacterActionSource.update is not implemented")


static func update_for_explicit_key_event(
        actions: CharacterActionState,
        input_key: String,
        is_pressed: bool,
        _time_scaled: float,
        p_is_additive: bool) -> void:
    var action_name: String = INPUT_KEY_TO_ACTION_NAME[input_key]
    var pressed_action_key := "pressed_" + action_name

    var was_already_pressed_in_current_frame: bool = \
            actions.get(pressed_action_key)
    var is_pressed_in_current_frame := \
            is_pressed or \
            (p_is_additive and was_already_pressed_in_current_frame)

    actions.set(pressed_action_key, is_pressed_in_current_frame)
