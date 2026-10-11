extends GutTest
## Post-respawn invincibility must survive a SPRING. The SPRING
## overwrites the SPAWN in the single last-interaction slot,
## which used to end invincibility (and re-enable player-player
## bumps and kills) the moment an invincible bunny hit a spring.
## Every other interaction, including SNAIL_CRUSH, still ends it.


const _SPAWN_FRAME := 20
const _BOUNCE_VELOCITY := Vector2(0.0, -360.0)

var _character: Character
var _state: CharacterStateFromServer


func before_each() -> void:
	ArrayPool.clear_all_pools()

	_character = Character.new()
	_character.movement_settings = MovementSettings.new()
	_state = CharacterStateFromServer.new()
	_state.character = _character
	_character.state_from_server = _state

	# Normally done in _ready(). Same standalone setup as
	# test_bump_reconciliation.gd.
	_state._parse_property_names()
	var default_values := _state._get_default_values().duplicate()
	default_values.append(
		ReconcilableState.FrameAuthority.CLIENT_PREDICTED)
	_state._rollback_buffer = RollbackBuffer.new(
		90,
		0,
		default_values,
	)


func after_each() -> void:
	ArrayPool.clear_all_pools()
	if is_instance_valid(_state):
		_state.free()
	if is_instance_valid(_character):
		_character.free()


func test_spawn_is_invincible_for_the_configured_duration() -> void:
	_record(_spawn_type(), _SPAWN_FRAME)

	assert_true(_is_invincible_at(_SPAWN_FRAME))
	assert_true(_is_invincible_at(_invincibility_end_frame() - 1))
	assert_false(_is_invincible_at(_invincibility_end_frame()))


func test_spring_bounce_keeps_invincibility() -> void:
	_record(_spawn_type(), _SPAWN_FRAME)
	_record(
		CharacterStateFromServer.ServerInteractionType.SPRING,
		_SPAWN_FRAME + 10,
	)

	assert_eq(
		_state.last_interaction_type,
		CharacterStateFromServer.ServerInteractionType.SPRING,
		"The spring replaces the spawn in the interaction slot",
	)
	assert_true(
		_is_invincible_at(_SPAWN_FRAME + 10),
		"Still invincible on the bounce frame",
	)
	assert_true(
		_is_invincible_at(_invincibility_end_frame() - 1),
		"Still invincible until the original window ends",
	)
	assert_false(
		_is_invincible_at(_invincibility_end_frame()),
		"The bounce does not extend the window",
	)


func test_snail_crush_still_ends_invincibility() -> void:
	# Unchanged behavior: unlike a spring, a snail crush during
	# invincibility ends it.
	_record(_spawn_type(), _SPAWN_FRAME)
	_record(
		CharacterStateFromServer.ServerInteractionType.SNAIL_CRUSH,
		_SPAWN_FRAME + 10,
	)

	assert_false(
		_is_invincible_at(_SPAWN_FRAME + 10),
		"A snail crush ends invincibility",
	)


func test_bump_after_spawn_is_not_invincible() -> void:
	# Bumps are deferred until invincibility ends, so a recorded
	# bump means the bunny is vulnerable. Only springs are exempt.
	_record(_spawn_type(), _SPAWN_FRAME)
	_record(
		CharacterStateFromServer.ServerInteractionType.BUMP,
		_SPAWN_FRAME + 10,
	)

	assert_false(_is_invincible_at(_SPAWN_FRAME + 10))


func test_death_after_spring_is_not_invincible() -> void:
	_record(_spawn_type(), _SPAWN_FRAME)
	_record(
		CharacterStateFromServer.ServerInteractionType.SPRING,
		_SPAWN_FRAME + 10,
	)
	Netcode.frame_driver.server_frame_index = _SPAWN_FRAME + 20
	_state.record_death_interaction(
		_SPAWN_FRAME + 20,
		Vector2.ZERO,
		Vector2.ZERO,
	)

	assert_false(_is_invincible_at(_SPAWN_FRAME + 20))


func test_spring_from_previous_life_is_not_invincible() -> void:
	# Rollback re-simulation can load a spring from before the
	# remembered spawn. It belongs to a previous life.
	_record(_spawn_type(), _SPAWN_FRAME)
	_state.last_interaction_type = (
		CharacterStateFromServer.ServerInteractionType.SPRING)
	_state.last_interaction_frame_index = _SPAWN_FRAME - 15

	assert_false(_is_invincible_at(_SPAWN_FRAME - 10))


func test_client_keeps_invincibility_through_reconciled_spring() -> void:
	# Clients never call record_interaction. They learn about the
	# spawn and the spring by reconciling them from the buffer.
	var spring_frame := _SPAWN_FRAME + 10
	_set_buffer_interaction(
		_SPAWN_FRAME,
		_spawn_type(),
		_SPAWN_FRAME,
	)
	Netcode.frame_driver.server_frame_index = _SPAWN_FRAME
	_state._reconcile_server_interaction()
	assert_true(_state.is_invincible, "Precondition: spawn seen")

	_set_buffer_interaction(
		spring_frame,
		CharacterStateFromServer.ServerInteractionType.SPRING,
		spring_frame,
	)
	Netcode.frame_driver.server_frame_index = spring_frame
	_state._reconcile_server_interaction()

	assert_eq(
		_state.last_interaction_type,
		CharacterStateFromServer.ServerInteractionType.SPRING,
	)
	assert_true(
		_state.is_invincible,
		"Client stays invincible after the spring",
	)
	assert_false(_is_invincible_at(_invincibility_end_frame()))


func _spawn_type() -> int:
	return CharacterStateFromServer.ServerInteractionType.SPAWN


func _invincibility_end_frame() -> int:
	return _SPAWN_FRAME + int(
		G.settings.player_invincibility_duration_sec
		* Netcode.frame_driver.target_network_fps
	)


## Records an interaction the way the server does.
func _record(interaction_type: int, frame_index: int) -> void:
	Netcode.frame_driver.server_frame_index = frame_index
	_state.record_interaction(
		interaction_type,
		frame_index,
		Vector2.ZERO,
		_BOUNCE_VELOCITY,
	)


func _is_invincible_at(frame_index: int) -> bool:
	Netcode.frame_driver.server_frame_index = frame_index
	return _state.is_invincible


## Writes an authoritative frame carrying the given interaction,
## as a client receives it from the server.
func _set_buffer_interaction(
	frame_index: int,
	interaction_type: int,
	interaction_frame_index: int,
) -> void:
	var frame_state := ArrayPool.acquire(8)
	frame_state[0] = Vector2.ZERO
	frame_state[1] = Vector2.ZERO
	frame_state[2] = 0
	frame_state[3] = interaction_type
	frame_state[4] = interaction_frame_index
	frame_state[5] = Vector2.ZERO
	frame_state[6] = Vector2.ZERO
	frame_state[7] = ReconcilableState.FrameAuthority.AUTHORITATIVE
	_state._rollback_buffer.set_at(frame_index, frame_state)
