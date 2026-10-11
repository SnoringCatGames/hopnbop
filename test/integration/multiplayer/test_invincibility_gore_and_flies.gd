extends GutTest
## Kickable gore and flies must still interact with invincible
## bunnies, without ending invincibility or re-enabling
## player-player collisions. Both used to detect bunnies on the
## player layer, which invincibility clears. Uses the real bunny,
## gore, and fly scenes and real physics.
##
## Same harness as test_spring_invincibility.gd: under a
## non-networked level, CharacterStateFromServer runs the bunny
## through _process_local_mode() every physics tick, and the
## SceneTree is unpaused so Area2D overlaps update.
##
## Each test lets the bunny settle first, so it is already off
## the player layer (when invincible) before the gore or fly
## first sees it.


const _BUNNY_SCENE := preload("res://src/player/bunny.tscn")
const _GORE_SCENE := preload("res://src/objects/gore/gore_kickable.tscn")
const _FLY_SCENE := preload("res://src/objects/flies/fly.tscn")

## Top surface of the floor everything rests on.
const _FLOOR_TOP_Y := 100.0
const _FLOOR_SIZE := Vector2(400.0, 20.0)
const _SPAWN_FRAME := 20
## Physics ticks for the bunny to land and apply its collision
## layers before the gore or fly appears.
const _SETTLE_FRAMES := 10
## Upper bound on physics ticks to wait for a kick. All waits stay
## well under the 2s invincibility window at 60 FPS.
const _MAX_KICK_WAIT_FRAMES := 30
## A kick pops gore up by tens of pixels. A resting piece only
## jitters by a fraction of a pixel.
const _KICK_RISE := 10.0
## Gore piece radius in gore_kickable.tscn.
const _GORE_RADIUS := 1.5
## The bunny body is a radius-5 circle centered 5px above its
## feet.
const _BUNNY_BODY_CENTER_OFFSET := Vector2(0.0, -5.0)
## The fly starts this far left of the bunny's body center.
const _FLY_START_OFFSET := Vector2(-12.0, 0.0)
const _FLY_SPEED := 120.0
## Enough ticks to carry an unblocked fly well past the bunny.
const _FLY_PUSH_FRAMES := 15

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
	G.input_device_manager.assign_device_to_player(
		0,
		DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD,
			DeviceConfig.KEYBOARD_DEVICE_ID,
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0],
		),
	)
	_add_floor()


func after_each() -> void:
	G.input_device_manager.unassign_device_from_player(0)
	TestEnvironmentMock.cleanup_mock_level()
	if is_instance_valid(_mock_level):
		_mock_level.free()
	get_tree().paused = _was_tree_paused
	ArrayPool.clear_all_pools()


func test_invincible_bunny_kicks_gore() -> void:
	var bunny := await _add_settled_bunny(true)

	var has_kicked := await _wait_for_gore_kick(_add_gore_at(bunny))

	assert_true(has_kicked, "An invincible bunny kicks gore")
	_assert_still_invincible_without_player_collision(bunny)


func test_vulnerable_bunny_kicks_gore() -> void:
	var bunny := await _add_settled_bunny(false)

	var has_kicked := await _wait_for_gore_kick(_add_gore_at(bunny))

	assert_true(has_kicked, "A vulnerable bunny kicks gore")


func test_invincible_bunny_bumps_fly() -> void:
	var bunny := await _add_settled_bunny(true)
	var fly := _add_fly_beside(bunny)

	var has_hit_bunny := await _push_fly_into(fly, bunny)

	assert_true(has_hit_bunny, "The fly collides with the bunny")
	assert_lt(
		fly.global_position.x,
		bunny.global_position.x,
		"The fly is stopped instead of passing through",
	)
	_assert_still_invincible_without_player_collision(bunny)


func test_vulnerable_bunny_bumps_fly() -> void:
	var bunny := await _add_settled_bunny(false)
	var fly := _add_fly_beside(bunny)

	var has_hit_bunny := await _push_fly_into(fly, bunny)

	assert_true(has_hit_bunny, "The fly collides with the bunny")
	assert_lt(fly.global_position.x, bunny.global_position.x)


func _add_floor() -> void:
	var floor_body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = _FLOOR_SIZE
	shape.shape = rectangle
	floor_body.add_child(shape)
	floor_body.position = Vector2(
		0.0, _FLOOR_TOP_Y + _FLOOR_SIZE.y / 2.0)
	add_child_autofree(floor_body)


## Adds a bunny standing on the floor and lets it settle. An
## invincible bunny is respawned the way the server does it.
func _add_settled_bunny(is_invincible: bool) -> Bunny:
	var bunny: Bunny = _BUNNY_SCENE.instantiate()
	# Non-networked player ids are -1, -2, and so on.
	bunny.player_id = -1
	bunny.position = Vector2(0.0, _FLOOR_TOP_Y)
	add_child_autofree(bunny)
	if is_invincible:
		bunny.state_from_server.record_interaction(
			CharacterStateFromServer.ServerInteractionType.SPAWN,
			Netcode.server_frame_index,
			bunny.global_position,
			Vector2.ZERO,
		)
	await _step_physics(_SETTLE_FRAMES)

	assert_eq(
		bunny.state_from_server.is_invincible,
		is_invincible,
		"Precondition: invincibility",
	)
	assert_eq(
		bunny.get_collision_layer_value(
			Player._PLAYER_COLLISION_LAYER),
		not is_invincible,
		"Precondition: player layer is off only while invincible",
	)
	assert_true(
		bunny.get_collision_layer_value(
			Player._PLAYER_TRIGGER_COLLISION_LAYER),
		"Precondition: the bunny is on the player_trigger layer",
	)
	return bunny


## Adds a gore piece resting on the floor where it overlaps the
## bunny.
func _add_gore_at(bunny: Bunny) -> GoreKickable:
	var gore: GoreKickable = _GORE_SCENE.instantiate()
	gore.position = Vector2(
		bunny.global_position.x, _FLOOR_TOP_Y - _GORE_RADIUS)
	add_child_autofree(gore)
	return gore


## Adds a fly level with the bunny's body center, to its left.
func _add_fly_beside(bunny: Bunny) -> Fly:
	var fly: Fly = _FLY_SCENE.instantiate()
	fly.position = (
		bunny.global_position
		+ _BUNNY_BODY_CENTER_OFFSET
		+ _FLY_START_OFFSET
	)
	add_child_autofree(fly)
	return fly


func _wait_for_gore_kick(gore: GoreKickable) -> bool:
	var rest_y := gore.global_position.y
	for i in _MAX_KICK_WAIT_FRAMES:
		await _step_physics(1)
		if rest_y - gore.global_position.y > _KICK_RISE:
			return true
	return false


## Flies the fly right into the bunny, moving it the way FlySwarm
## does. Returns whether it collided with the bunny.
func _push_fly_into(fly: Fly, bunny: Bunny) -> bool:
	var has_hit_bunny := false
	for i in _FLY_PUSH_FRAMES:
		await _step_physics(1)
		fly.velocity = Vector2(_FLY_SPEED, 0.0)
		fly.move_and_slide()
		for collision_index in fly.get_slide_collision_count():
			var collision := fly.get_slide_collision(collision_index)
			if collision.get_collider() == bunny:
				has_hit_bunny = true
	return has_hit_bunny


func _assert_still_invincible_without_player_collision(
	bunny: Bunny,
) -> void:
	assert_true(
		bunny.state_from_server.is_invincible,
		"The interaction does not end invincibility",
	)
	assert_false(
		bunny.get_collision_layer_value(
			Player._PLAYER_COLLISION_LAYER),
		"Player-player collision layer stays off",
	)
	assert_false(
		bunny.get_collision_mask_value(
			Player._PLAYER_COLLISION_LAYER),
		"Player-player collision mask stays off",
	)


## Steps physics, advancing the network frame like the frame
## driver would.
func _step_physics(frame_count: int) -> void:
	for i in frame_count:
		await wait_physics_frames(1)
		Netcode.frame_driver.server_frame_index += 1
