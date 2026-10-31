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
var _trace_dumped := false


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
	_update_key_trace(ml_pressed)


## H119: watches for leftward movement stopping while A
## is physically held, and dumps the key trace when it
## happens (the action letting go, or the body stalling
## with the input held). Once per hold.
func _update_key_trace(ml_pressed: bool) -> void:
	var phys_a := Input.is_physical_key_pressed(KEY_A)
	if ml_pressed != _trace_ml_was:
		G.input_device_manager.key_trace_note(
			"ml=%s physA=%s vx=%.0f" % [
				str(ml_pressed), str(phys_a),
				character.velocity.x,
			])
	if not phys_a:
		_trace_ml_was = ml_pressed
		_trace_still_since = -1
		_trace_dumped = false
		return
	if _trace_dumped:
		_trace_ml_was = ml_pressed
		return
	var reason := ""
	if _trace_ml_was and not ml_pressed:
		reason = "move_left released while A held"
	elif ml_pressed:
		if character.is_on_floor() \
				and character.velocity.x > -10.0:
			if _trace_still_since < 0:
				_trace_still_since = Time.get_ticks_msec()
			elif Time.get_ticks_msec() \
					- _trace_still_since > 750:
				reason = "A held, move_left held, not moving"
		else:
			_trace_still_since = -1
	if not reason.is_empty():
		_trace_dumped = true
		Netcode.print(
			"H119TRACE %s\n%s" % [
				reason,
				"\n".join(
					G.input_device_manager.get_key_trace()),
			],
			NetworkLogger.CATEGORY_PLAYER_ACTIONS,
		)
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
