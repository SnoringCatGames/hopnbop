class_name PlayerActionSource
extends CharacterActionSource

const ACTIONS_TO_INPUT_KEYS := {
	"jump": "j",
	"move_up": "mu",
	"move_down": "md",
	"move_left": "ml",
	"move_right": "mr",
	"attach": "g",
	"face_left": "fl",
	"face_right": "fr",
}

## Device configuration for this player's input.
## Determines whether to use keyboard/gamepad and which device.
var device_config: DeviceConfig = null


func _init(
	p_character,
	p_is_additive: bool,
	p_device_config: DeviceConfig = null
) -> void:
	super ("PLAYER", p_character, p_is_additive)
	device_config = p_device_config


# Calculates actions for the current frame.
func update(actions: CharacterActionState, time_scaled: float) -> void:
	if not character.get_is_player_control_active():
		return

	# Use device-specific input polling if device_config is set.
	# Otherwise fall back to global input for backward compatibility.
	var any_pressed := false
	for action in ACTIONS_TO_INPUT_KEYS:
		var input_key: StringName = ACTIONS_TO_INPUT_KEYS[action]
		var is_pressed: bool
		if device_config != null:
			is_pressed = G.input_device_manager.get_is_action_pressed(
				action,
				device_config
			)
		else:
			is_pressed = Input.is_action_pressed(action)

		if is_pressed:
			any_pressed = true

		if !Input.is_key_pressed(KEY_CTRL):
			CharacterActionSource.update_for_explicit_key_event(
				actions,
				input_key,
				is_pressed,
				time_scaled,
				is_additive,
			)


static func get_is_some_player_action_pressed() -> bool:
	for action in ACTIONS_TO_INPUT_KEYS:
		if Input.is_action_pressed(action):
			return true
	return false


static func validate_project_settings_input_actions() -> void:
	for action in ACTIONS_TO_INPUT_KEYS:
		if !InputMap.has_action(action):
			G.fatal("PlayerActionSource: Missing input action '" + action + "' in project settings")
