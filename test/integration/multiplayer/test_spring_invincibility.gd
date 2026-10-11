extends GutTest
## Springs must bounce invincible bunnies, and the bounce must
## not end invincibility or re-enable player-player collisions.
## Uses the real bunny and spring scenes and real physics, so it
## covers the collision layers as well as the gameplay code.
##
## Under a non-networked level, CharacterStateFromServer runs
## the bunny through _process_local_mode() every physics tick:
## gravity, the per-frame invincibility collision toggle, and
## the server-side spring bounce (Netcode.runs_server_logic is
## true outside a session).
##
## The test environment starts with the SceneTree paused, which
## also deactivates PhysicsServer2D. move_and_slide() still works
## then, but Area2D overlaps never update, so these tests unpause
## the tree while they run.


const _BUNNY_SCENE := preload("res://src/player/bunny.tscn")
const _SPRING_SCENE := preload("res://src/objects/spring/spring.tscn")

## Spring center. Its top surface and trigger strip are 8px up.
const _SPRING_POSITION := Vector2(0.0, 100.0)
## The bunny drops onto the spring from this far above its top.
const _DROP_HEIGHT := 30.0
const _SPAWN_FRAME := 20
## Upper bound on physics ticks for the bunny to land and bounce.
## Well under the 2s invincibility window at 60 FPS.
const _MAX_WAIT_FRAMES := 60
const _LOCAL_PLAYER_COUNT := 2

var _spring: Spring
var _mock_level: MockLevel
var _was_tree_paused := false


func before_each() -> void:
	ArrayPool.clear_all_pools()
	_was_tree_paused = get_tree().paused
	get_tree().paused = false
	if not Netcode.frame_driver._is_frame_tracking_initialized:
		Netcode.frame_driver._initialize_frame_tracking()
	Netcode.frame_driver.server_frame_index = _SPAWN_FRAME
	_mock_level = TestEnvironmentMock.setup_mock_level(self)

	# Outside a networked level, bunnies set up local input
	# sources in _ready(), which need a device per local index.
	for i in _LOCAL_PLAYER_COUNT:
		G.input_device_manager.assign_device_to_player(
			i,
			DeviceConfig.new(
				DeviceConfig.DeviceType.KEYBOARD,
				DeviceConfig.KEYBOARD_DEVICE_ID,
				InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[i],
			),
		)

	_spring = _SPRING_SCENE.instantiate()
	_spring.position = _SPRING_POSITION
	add_child_autofree(_spring)


func after_each() -> void:
	for i in _LOCAL_PLAYER_COUNT:
		G.input_device_manager.unassign_device_from_player(i)
	TestEnvironmentMock.cleanup_mock_level()
	if is_instance_valid(_mock_level):
		_mock_level.free()
	get_tree().paused = _was_tree_paused
	ArrayPool.clear_all_pools()


func test_invincible_bunny_bounces_on_spring() -> void:
	var bunny := _add_bunny(
		0,
		_SPRING_POSITION + Vector2(0.0, -8.0 - _DROP_HEIGHT),
	)
	_respawn(bunny)
	assert_true(
		bunny.state_from_server.is_invincible,
		"Precondition: a freshly respawned bunny is invincible",
	)

	var has_bounced := await _wait_for_upward_velocity(bunny)

	assert_true(
		has_bounced,
		"The spring should launch the invincible bunny upward",
	)
	assert_eq(
		bunny.state_from_server.last_interaction_type,
		CharacterStateFromServer.ServerInteractionType.SPRING,
		"The server recorded a spring interaction",
	)
	assert_true(
		bunny.state_from_server.is_invincible,
		"The bounce must not end invincibility",
	)
	assert_false(
		bunny.get_collision_layer_value(
			Player._PLAYER_COLLISION_LAYER),
		"Player-player collision layer stays off after the bounce",
	)
	assert_false(
		bunny.get_collision_mask_value(
			Player._PLAYER_COLLISION_LAYER),
		"Player-player collision mask stays off after the bounce",
	)

	# Invincibility still ends on schedule.
	Netcode.frame_driver.server_frame_index = _invincibility_end_frame()
	await wait_physics_frames(2)
	assert_false(bunny.state_from_server.is_invincible)
	assert_true(
		bunny.get_collision_layer_value(
			Player._PLAYER_COLLISION_LAYER),
		"Player-player collision comes back when invincibility ends",
	)


func test_vulnerable_bunny_still_bounces_on_spring() -> void:
	var bunny := _add_bunny(
		0,
		_SPRING_POSITION + Vector2(0.0, -8.0 - _DROP_HEIGHT),
	)

	var has_bounced := await _wait_for_upward_velocity(bunny)

	assert_false(bunny.state_from_server.is_invincible)
	assert_true(has_bounced, "Springs still work without invincibility")


func test_invincible_bunny_does_not_touch_other_players() -> void:
	# Overlap an invincible bunny with a vulnerable one, in mid-air
	# away from the spring. Neither body area may see the other, so
	# no bump or kill can happen.
	var invincible_bunny := _add_bunny(0, Vector2(200.0, 0.0))
	_respawn(invincible_bunny)
	var vulnerable_bunny := _add_bunny(1, Vector2(200.0, 0.0))

	await wait_physics_frames(3)

	assert_true(invincible_bunny.state_from_server.is_invincible)
	assert_false(vulnerable_bunny.state_from_server.is_invincible)
	var invincible_area: Area2D = (
		invincible_bunny.get_node("%BodyArea"))
	var vulnerable_area: Area2D = (
		vulnerable_bunny.get_node("%BodyArea"))
	assert_false(
		vulnerable_area.overlaps_body(invincible_bunny),
		"A vulnerable bunny must not detect an invincible one",
	)
	assert_false(
		invincible_area.overlaps_body(vulnerable_bunny),
		"An invincible bunny must not detect other bunnies",
	)
	var match_state := G.match_state as GameMatchState
	assert_eq(match_state.bumps.size(), 0, "No bump recorded")
	assert_eq(match_state.kills.size(), 0, "No kill recorded")


func _add_bunny(local_index: int, position: Vector2) -> Bunny:
	var bunny: Bunny = _BUNNY_SCENE.instantiate()
	# Non-networked player ids are -1, -2, and so on.
	bunny.player_id = -(local_index + 1)
	bunny.position = position
	add_child_autofree(bunny)
	return bunny


## Records a SPAWN the way the server does on respawn, which
## starts the invincibility window.
func _respawn(bunny: Bunny) -> void:
	bunny.state_from_server.record_interaction(
		CharacterStateFromServer.ServerInteractionType.SPAWN,
		Netcode.server_frame_index,
		bunny.global_position,
		Vector2.ZERO,
	)


## Steps physics, advancing the network frame like the frame
## driver would, until the bunny moves upward.
func _wait_for_upward_velocity(bunny: Bunny) -> bool:
	for i in _MAX_WAIT_FRAMES:
		await wait_physics_frames(1)
		if bunny.velocity.y < 0.0:
			return true
		Netcode.frame_driver.server_frame_index += 1
	return false


func _invincibility_end_frame() -> int:
	return _SPAWN_FRAME + int(
		G.settings.player_invincibility_duration_sec
		* Netcode.frame_driver.target_network_fps
	)
