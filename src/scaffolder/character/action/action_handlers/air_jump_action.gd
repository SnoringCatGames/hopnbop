class_name AirJumpAction
extends CharacterActionHandler

const NAME := "AirJumpAction"
const TYPE := SurfaceType.AIR
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 420

const AUTO_JUMP_FROM_HOLD_THROTTLE_PERIOD_SEC := 0.3

var last_jump_time_sec := -INF


func _init() -> void:
	super (
		NAME,
		TYPE,
		USES_RUNTIME_PHYSICS,
		PRIORITY)


func process(character) -> bool:
	var current_time := Netcode.time.get_time()
	var is_auto_jump_from_hold: bool = (
		character.actions.pressed_jump and
		current_time >
			last_jump_time_sec + AUTO_JUMP_FROM_HOLD_THROTTLE_PERIOD_SEC and
		not character.surfaces.is_attaching_to_surface
	)
	var is_jump_triggered: bool = (
		character.actions.just_pressed_jump or
		is_auto_jump_from_hold
	)

	if is_jump_triggered and \
			(character.jump_sequence_count < character.movement_settings.max_jump_chain or
			character.surfaces.is_within_coyote_time):
		if character.surfaces.just_entered_air or \
				character.surfaces.is_within_coyote_time:
			character.jump_sequence_count = 1
		else:
			character.jump_sequence_count += 1
		var double_jump_multiplier := pow(
				character.movement_settings.double_jump_boost_multiplier,
				character.jump_sequence_count - 1)
		character.velocity.y = character.movement_settings.jump_boost * double_jump_multiplier
		last_jump_time_sec = current_time

		return true
	else:
		return false
