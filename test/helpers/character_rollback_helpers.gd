extends RefCounted

class_name CharacterRollbackHelpers
## Helper functions for character rollback integration tests.

## Simulate physics frames.
## Note: Uses state_from_server._network_process which internally calls
## the character's private methods in the correct order.
static func simulate_frames(
		character: Character,
		num_frames: int,
		set_input_callback: Callable = Callable(),
) -> void:
	for i in range(num_frames):
		if set_input_callback.is_valid():
			set_input_callback.call(i, character)

		# Use the public interface through state_from_server
		if is_instance_valid(character.state_from_server):
			character.state_from_server._network_process()
		G.network.server_frame_index += 1


## Create server state at a specific frame.
static func create_server_state(
		pos: Vector2,
		vel: Vector2,
		surfaces_bitmask: int = 0,
) -> Array:
	var state := ArrayPool.acquire(3)
	state[0] = pos
	state[1] = vel
	state[2] = surfaces_bitmask
	return state


## Set character input for testing.
static func set_character_input(
		character: Character,
		jump: bool = false,
		up: bool = false,
		down: bool = false,
		left: bool = false,
		right: bool = false,
) -> void:
	character.actions.pressed_jump = jump
	character.actions.pressed_up = up
	character.actions.pressed_down = down
	character.actions.pressed_left = left
	character.actions.pressed_right = right


## Check if position difference exceeds threshold.
static func has_position_mismatch(
		pos1: Vector2,
		pos2: Vector2,
		threshold: float = 1.0,
) -> bool:
	return pos1.distance_to(pos2) > threshold


## Check if velocity difference exceeds threshold.
static func has_velocity_mismatch(
		vel1: Vector2,
		vel2: Vector2,
		threshold: float = 0.5,
) -> bool:
	return vel1.distance_to(vel2) > threshold
