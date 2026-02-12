class_name AirJumpAction
extends CharacterActionHandler

const NAME := "AirJumpAction"
const TYPE := SurfaceType.AIR
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 420

const AUTO_JUMP_FROM_HOLD_THROTTLE_PERIOD_SEC := 0.3

var last_jump_frame_index := -1


func _init() -> void:
	super (
		NAME,
		TYPE,
		USES_RUNTIME_PHYSICS,
		PRIORITY)


func process(character) -> bool:
	var current_frame := Netcode.server_frame_index
	var throttle_frames := int(
		AUTO_JUMP_FROM_HOLD_THROTTLE_PERIOD_SEC
		/ Netcode.time.get_time_step_sec()
	)
	var is_auto_jump_from_hold: bool = (
		character.actions.is_triggering_jump and
		(last_jump_frame_index < 0 or
			current_frame >
				last_jump_frame_index + throttle_frames) and
		not character.surfaces.is_attaching_to_surface
	)
	var is_jump_triggered: bool = (
		not character.surfaces.is_launched
		and (
			character.actions.just_triggered_jump
			or is_auto_jump_from_hold
		)
	)

	if is_jump_triggered and \
			(character.jump_sequence_count
				< character.movement_settings
					.max_jump_chain
			or character.surfaces
				.is_within_coyote_time):
		if character.surfaces.just_entered_air or \
				character.surfaces.is_within_coyote_time:
			# Coyote jump requires onset press, not held
			# auto-jump. This prevents jumping when
			# walking off a ledge while holding jump.
			if not character.actions.just_triggered_jump:
				return false
			character.jump_sequence_count = 1
		else:
			character.jump_sequence_count += 1
		var double_jump_multiplier := pow(
			character.movement_settings
				.double_jump_boost_multiplier,
			character.jump_sequence_count - 1)
		character.velocity.y = (
			character.movement_settings.jump_boost
			* double_jump_multiplier
		)
		last_jump_frame_index = current_frame

		return true
	else:
		return false
