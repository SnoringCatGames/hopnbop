extends GutTest
## H3: "Dead" and the respawn share one frame boundary. The
## respawn used to run on a wall-clock timer while is_dead
## ended on a frame count, so the bunny reappeared 1-2 frames
## before its respawn (visible, collision still off). The
## frame Player schedules is now exactly the frame is_dead
## ends: get_respawn_frame_index().


const _DEATH_FRAME := 100

var _character: Character
var _state: CharacterStateFromServer
var _saved_cooldown: float


func before_each() -> void:
	ArrayPool.clear_all_pools()
	_saved_cooldown = G.settings.player_respawn_cooldown_sec
	G.settings.player_respawn_cooldown_sec = 2.0

	_character = Character.new()
	_character.movement_settings = MovementSettings.new()
	_state = CharacterStateFromServer.new()
	_state.character = _character
	_character.state_from_server = _state
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
	G.settings.player_respawn_cooldown_sec = _saved_cooldown
	ArrayPool.clear_all_pools()
	if is_instance_valid(_state):
		_state.free()
	if is_instance_valid(_character):
		_character.free()


func test_respawn_frame_is_death_plus_cooldown_frames() -> void:
	_state.record_death_interaction(
		_DEATH_FRAME, Vector2.ZERO, Vector2.ZERO)
	var expected := _DEATH_FRAME + int(
		2.0 * Netcode.frame_driver.target_network_fps)
	assert_eq(
		_state.get_respawn_frame_index(), expected,
		"respawn lands cooldown*fps frames after the death frame",
	)


func test_is_dead_ends_exactly_on_the_respawn_frame() -> void:
	_state.record_death_interaction(
		_DEATH_FRAME, Vector2.ZERO, Vector2.ZERO)
	var respawn_frame := _state.get_respawn_frame_index()

	Netcode.frame_driver.server_frame_index = respawn_frame - 1
	assert_true(_state.is_dead, "still dead one frame before respawn")

	Netcode.frame_driver.server_frame_index = respawn_frame
	assert_false(
		_state.is_dead,
		"dead ends on the respawn frame: no early reappearance",
	)
