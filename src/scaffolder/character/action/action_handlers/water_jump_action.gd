class_name WaterJumpAction
extends CharacterActionHandler
## Handles jumping while in water. Three cases:
## - Water hop: precision-timed jump within a tight
##   window around the moment of water entry. Gives
##   a strong boost (same as a floor jump).
## - Surface jump: at or above the float line with
##   velocity near zero or upward.
## - No subsurface jump: the player must float to
##   the surface before jumping.

const NAME := "WaterJumpAction"
const TYPE := SurfaceType.OTHER
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 225


func _init() -> void:
	super(NAME, TYPE, USES_RUNTIME_PHYSICS, PRIORITY)


func process(character) -> bool:
	if not character.surfaces.is_in_water:
		return false

	var ms: MovementSettings = (
		character.movement_settings
	)
	var current_frame := Netcode.server_frame_index
	var hop_threshold_frames := int(
		ms.water_hop_window_sec
		/ Netcode.time.get_time_step_sec()
	)

	# --- Water hop: tight timing window around
	# water entry. ---

	# "After contact": player pressed jump shortly
	# after entering water.
	if character.actions.just_triggered_jump:
		var entry_frame: int = (
			character.surfaces
				.last_water_entry_frame_index
		)
		if (
			entry_frame >= 0
			and current_frame - entry_frame
				<= hop_threshold_frames
		):
			_apply_hop(character, ms, current_frame)
			return true

	# "Before contact": player entered water shortly
	# after pressing jump (input was "buffered").
	# Guard with velocity.y > 0 to ensure the player
	# was falling into the water. If a successful air
	# jump fired, velocity would be negative (upward)
	# and this branch correctly skips.
	if character.surfaces.just_entered_water:
		var jump_frame: int = (
			character.last_triggered_jump_frame_index
		)
		if (
			jump_frame >= 0
			and character.velocity.y > 0.0
			and current_frame - jump_frame
				<= hop_threshold_frames
		):
			_apply_hop(character, ms, current_frame)
			return true

	# --- Surface jump: at or above the float line
	# with velocity near zero or upward. ---

	if not character.actions.just_triggered_jump:
		return false

	var float_line_y: float = (
		character.water_surface_y
		+ ms.water_sink_threshold
	)

	var is_near_surface: bool = (
		character.global_position.y
		<= float_line_y
			+ ms.water_snap_threshold
	)
	var is_velocity_ok: bool = (
		character.velocity.y <= 0.0
	)

	if is_near_surface and is_velocity_ok:
		character.velocity.y = (
			ms.water_surface_jump_boost
		)
		return true

	return false


func _apply_hop(
	character,
	ms: MovementSettings,
	current_frame: int,
) -> void:
	character.velocity.y = ms.water_hop_boost
	character.jump_sequence_count = 1
	character.last_water_hop_frame_index = (
		current_frame
	)
