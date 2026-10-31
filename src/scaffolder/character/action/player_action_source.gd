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

## H119 trace state (see InputDeviceManager.key_trace_note).
var _trace_ml_was := false
var _trace_still_since := -1


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
	var ml_pressed := false
	var poll_path := &"InputMap"
	if device_config != null:
		poll_path = device_config.name
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
		if action == &"move_left":
			ml_pressed = is_pressed

		if !Input.is_key_pressed(KEY_CTRL):
			CharacterActionSource.update_for_explicit_key_event(
				actions,
				input_key,
				is_pressed,
				time_scaled,
				is_additive,
			)
	_update_key_trace(ml_pressed, poll_path)


## H119: watches for leftward movement stopping during
## an A hold, and dumps the key trace when it happens
## (the action letting go with no key-up behind it, the
## action letting go while A is still held, or the body
## stalling with the input held). Once per hold;
## InputDeviceManager.dump_key_trace holds the guard.
func _update_key_trace(
		ml_pressed: bool,
		poll_path: StringName,
) -> void:
	var manager := G.input_device_manager
	var phys_a := Input.is_physical_key_pressed(KEY_A)
	if ml_pressed != _trace_ml_was:
		manager.key_trace_note(
			"ml=%s physA=%s vx=%.0f path=%s text_capture=%s"
			% [
				str(ml_pressed), str(phys_a),
				character.velocity.x,
				str(poll_path),
				str(manager.is_text_input_captured),
			])
	var reason := manager.get_move_left_release_reason(
		ml_pressed, _trace_ml_was)
	if (reason.is_empty() and phys_a
			and _trace_ml_was and not ml_pressed):
		reason = "move_left released while A held"
	if phys_a and ml_pressed:
		if (character.is_on_floor()
				and character.velocity.x > -10.0):
			if _trace_still_since < 0:
				_trace_still_since = Time.get_ticks_msec()
			elif (Time.get_ticks_msec()
					- _trace_still_since > 750):
				reason = "A held, move_left held, not moving"
		else:
			_trace_still_since = -1
	else:
		_trace_still_since = -1
	if not reason.is_empty():
		manager.dump_key_trace(reason)
	_trace_ml_was = ml_pressed


static func get_is_some_player_action_pressed() -> bool:
	for action in ACTIONS_TO_INPUT_KEYS:
		if Input.is_action_pressed(action):
			return true
	return false


static func validate_project_settings_input_actions() -> void:
	for action in ACTIONS_TO_INPUT_KEYS:
		if !InputMap.has_action(action):
			Netcode.fatal("PlayerActionSource: Missing input action '" + action + "' in project settings")
