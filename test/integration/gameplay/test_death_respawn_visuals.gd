extends GutTest
## Steps a real bunny scene frame by frame through a death and respawn
## and checks what would render on each frame.
##
## Physics interpolation is on, and entering the tree snapshots a
## canvas item's transform as its interpolation start. An effect sprite
## that enters at its default (0, 0) and is positioned afterwards
## renders sliding out of the level origin for one physics tick. So
## every canvas item spawned under the level is checked at tree entry,
## not only after it settles.
##
## The respawn teleport must also not spawn a water splash. That is
## checked on the peer that runs server logic (local mode), and on
## predicting and remote clients that receive the death and the
## respawn over the network with latency.


enum _Role {
	LOCAL_MODE,
	DEDICATED_SERVER,
	OWNING_CLIENT,
	REMOTE_CLIENT,
}

const _WATER_RECT := Rect2(40.0, 0.0, 200.0, 200.0)
## Deep enough that the bunny is still rising, well under water, while
## a client predicts it alive after it died on the server.
const _DEEP_WATER_POSITION := Vector2(120.0, 150.0)
const _ABOVE_WATER_POSITION := Vector2(120.0, -20.0)
const _SPAWN_POSITION := Vector2(-200.0, -60.0)
const _START_FRAME := 10
## Long enough that a remote client's latency-delayed splash for
## spawning into the water lands before the death.
const _ALIVE_FRAMES_BEFORE_DEATH := 12
const _FRAMES_AFTER_RESPAWN := 8
## Shortened so each death takes fewer real-time physics frames. Still
## much longer than the simulated network latency.
const _RESPAWN_COOLDOWN_SEC := 0.5
const _SETTLE_FRAMES := 3
const _MAX_FALL_FRAMES := 120
const _MAX_LAUNCH_FRAMES := 30
const _ORIGIN_CLEARANCE := 32.0
const _NETWORK_LATENCY_FRAMES := 4
## A peer that is neither this process nor the server.
const _OTHER_PEER_ID := 2


## Level stub with a rectangular water area and a fixed respawn
## position. Skips NetworkedLevel's scene setup.
class _TestLevel:
	extends NetworkedLevel

	var water_rect: Rect2
	var spawn_position: Vector2


	func _enter_tree() -> void:
		pass


	func _ready() -> void:
		pass


	func _exit_tree() -> void:
		pass


	func is_position_in_water(global_pos: Vector2) -> bool:
		return water_rect.has_point(global_pos)


	func get_water_surface_y(_global_pos: Vector2) -> float:
		return water_rect.position.y


	func _get_player_spawn_position() -> Vector2:
		return spawn_position


## Records splash requests instead of instancing splash scenes.
class _RecordingSplashManager:
	extends SplashManager

	var spawned: Array[Dictionary] = []


	func _ready() -> void:
		pass


	func spawn_splash(
		pos: Vector2,
		animation_name: StringName,
	) -> void:
		spawned.append({
			position = pos,
			animation = animation_name,
			frame = Netcode.server_frame_index,
		})


var _level: _TestLevel
var _splashes: _RecordingSplashManager
var _bunny: Bunny
var _death_position := Vector2.INF
var _death_frame := -1
## Canvas items added under the level, with their transform at tree
## entry (the physics interpolation start).
var _spawned_items: Array[Dictionary] = []
var _violations: Array[String] = []
var _timer_ids_before_test: Array = []
var _saved_is_server: bool
var _saved_is_local_mode: bool
var _saved_is_paused: bool
var _saved_match_state: MatchState
var _saved_respawn_cooldown_sec: float


func before_each() -> void:
	ArrayPool.clear_all_pools()
	_saved_is_server = Netcode.is_server
	_saved_is_local_mode = Netcode.is_local_mode
	_saved_is_paused = Netcode.frame_driver._is_paused
	_saved_match_state = G.match_state
	_saved_respawn_cooldown_sec = G.settings.player_respawn_cooldown_sec
	_timer_ids_before_test = Netcode.time._active_callbacks.keys()

	# Keep the frame driver from ticking on its own. Tests step it.
	Netcode.frame_driver._is_paused = true
	G.settings.player_respawn_cooldown_sec = _RESPAWN_COOLDOWN_SEC
	G.match_state = GameMatchState.new()

	_level = _TestLevel.new()
	_level.name = "TestLevel"
	_level.water_rect = _WATER_RECT
	_level.spawn_position = _SPAWN_POSITION
	add_child_autofree(_level)
	G.level = _level

	_splashes = _RecordingSplashManager.new()
	_splashes.name = "SplashManager"
	_level.add_child(_splashes)
	_level.splash_manager = _splashes

	_level.child_entered_tree.connect(_on_level_child_entered)

	_spawned_items.clear()
	_violations.clear()
	_death_position = Vector2.INF
	_death_frame = -1


func after_each() -> void:
	_cancel_scheduled_respawns()
	G.level = null
	G.match_state = _saved_match_state
	G.settings.player_respawn_cooldown_sec = _saved_respawn_cooldown_sec
	Netcode.is_server = _saved_is_server
	Netcode.is_local_mode = _saved_is_local_mode
	Netcode.frame_driver._is_paused = _saved_is_paused
	ArrayPool.clear_all_pools()


# --- Tests ---


func test_local_mode_death_renders_nothing_at_level_origin() -> void:
	_set_role(_Role.LOCAL_MODE)
	_spawn_bunny(_Role.LOCAL_MODE, _DEEP_WATER_POSITION)

	await _run_server_logic_death_and_respawn(1)

	_assert_no_render_violations()
	_assert_squish_sprite_entered_at_death_position()


func test_local_mode_water_death_respawn_spawns_no_splash(
	params = use_parameters([-1, 0, 1]),
) -> void:
	# The respawn timer is wall-clock based, so it can fire a frame
	# before, at, or after the frame where the frame-based death
	# cooldown expires.
	var respawn_delay_frames: int = params
	_set_role(_Role.LOCAL_MODE)
	_spawn_bunny(_Role.LOCAL_MODE, _DEEP_WATER_POSITION)

	await _run_server_logic_death_and_respawn(respawn_delay_frames)

	_assert_no_splashes_since_death(
		"Respawn after a water death should not splash"
		+ " (respawn delay %d)" % respawn_delay_frames)
	_assert_no_render_violations()


func test_owning_client_water_death_respawn_renders_correctly() -> void:
	var packets: Dictionary = await _record_dedicated_server_states(1)

	await _replay_on_client(_Role.OWNING_CLIENT, packets)

	_assert_no_splashes_since_death(
		"Predicting client should not splash on respawn")
	_assert_no_render_violations()
	_assert_squish_sprite_entered_at_death_position()


func test_remote_client_water_death_respawn_renders_correctly() -> void:
	var packets: Dictionary = await _record_dedicated_server_states(1)

	await _replay_on_client(_Role.REMOTE_CLIENT, packets)

	_assert_no_splashes_since_death(
		"Remote client should not splash on respawn")
	_assert_no_render_violations()
	_assert_squish_sprite_entered_at_death_position()


func test_water_entry_still_splashes_at_water_surface() -> void:
	_set_role(_Role.LOCAL_MODE)
	_spawn_bunny(_Role.LOCAL_MODE, _ABOVE_WATER_POSITION)

	for i in _MAX_FALL_FRAMES:
		await _step()
		if _bunny.surfaces.is_in_water:
			break
	await _step()

	assert_true(
		_bunny.surfaces.is_in_water,
		"Bunny should fall into the water",
	)
	var entry_splashes := _get_splashes_since(_START_FRAME).filter(
		func(splash: Dictionary) -> bool:
			return splash.animation == &"enter_water")
	assert_gt(
		entry_splashes.size(),
		0,
		"Falling into water should splash",
	)
	for splash in entry_splashes:
		assert_almost_eq(
			splash.position,
			Vector2(_bunny.global_position.x, _WATER_RECT.position.y),
			Vector2(1.0, 0.01),
			"Entry splash should be at the water surface",
		)


func test_water_exit_still_splashes_at_water_surface() -> void:
	_set_role(_Role.LOCAL_MODE)
	_spawn_bunny(_Role.LOCAL_MODE, _DEEP_WATER_POSITION, true)
	for i in _SETTLE_FRAMES:
		await _step()
	assert_true(
		_bunny.surfaces.is_in_water,
		"Bunny should start in the water",
	)
	var launch_frame := Netcode.server_frame_index

	_bunny.server_trigger_spring_bounce()
	for i in _MAX_LAUNCH_FRAMES:
		await _step()
		if not _bunny.surfaces.is_in_water:
			break
	await _step()

	assert_false(
		_bunny.surfaces.is_in_water,
		"Spring bounce should launch the bunny out of the water",
	)
	var exit_splashes := _get_splashes_since(launch_frame).filter(
		func(splash: Dictionary) -> bool:
			return splash.animation == &"exit_water")
	assert_gt(
		exit_splashes.size(),
		0,
		"Leaving the water should splash",
	)
	for splash in exit_splashes:
		assert_almost_eq(
			splash.position.y,
			_WATER_RECT.position.y,
			0.01,
			"Exit splash should be at the water surface",
		)


# --- Timelines ---


## Kills the bunny after some frames in the water, steps through the
## death, and respawns it. Runs the server-side death and respawn, so
## it is for roles that run server logic. respawn_delay_frames is when
## the respawn timer fires, relative to the frame where the frame-based
## death cooldown expires.
func _run_server_logic_death_and_respawn(
	respawn_delay_frames: int,
) -> void:
	for i in _ALIVE_FRAMES_BEFORE_DEATH:
		await _step()
	assert_true(
		_bunny.surfaces.is_in_water,
		"Precondition: bunny dies in the water",
	)
	assert_false(
		_level.is_position_in_water(_SPAWN_POSITION),
		"Precondition: respawn position is out of the water",
	)

	_kill_bunny()
	_check_render_state()

	var respawn_frame := (
		_death_frame
		+ _get_respawn_cooldown_frames()
		+ respawn_delay_frames
	)
	while Netcode.server_frame_index < respawn_frame:
		await _step()
	_bunny.server_execute_respawn()
	_check_render_state()
	assert_eq(
		_bunny.state_from_server.last_interaction_type,
		CharacterStateFromServer.ServerInteractionType.SPAWN,
		"Precondition: bunny respawned",
	)

	for i in _FRAMES_AFTER_RESPAWN:
		await _step()


## Runs the death and respawn on a dedicated server and returns the
## state the server confirms for each frame, as network packets keyed
## by frame index.
func _record_dedicated_server_states(
	respawn_delay_frames: int,
) -> Dictionary:
	_set_role(_Role.DEDICATED_SERVER)
	# Dedicated servers have no splash manager.
	_level.splash_manager = null
	_spawn_bunny(_Role.DEDICATED_SERVER, _DEEP_WATER_POSITION)

	var packets := {}
	for i in _ALIVE_FRAMES_BEFORE_DEATH:
		await _step_and_record(packets)
	assert_true(
		_bunny.surfaces.is_in_water,
		"Precondition: bunny dies in the water",
	)

	_kill_bunny()

	var respawn_frame := (
		_death_frame
		+ _get_respawn_cooldown_frames()
		+ respawn_delay_frames
	)
	while Netcode.server_frame_index < respawn_frame:
		await _step_and_record(packets)
	_bunny.server_execute_respawn()
	for i in _FRAMES_AFTER_RESPAWN:
		await _step_and_record(packets)

	_bunny.free()
	_bunny = null
	_spawned_items.clear()
	_violations.clear()
	_level.splash_manager = _splashes
	return packets


## Replays recorded server states on a fresh client-side bunny. Each
## frame's state arrives _NETWORK_LATENCY_FRAMES after the client
## simulates that frame, like confirmed state from a real server.
func _replay_on_client(role: _Role, packets: Dictionary) -> void:
	_set_role(role)
	_spawn_bunny(role, _DEEP_WATER_POSITION)

	var last_packet_frame: int = packets.keys().max()
	var next_packet_frame := _START_FRAME
	while (
		Netcode.server_frame_index
		< last_packet_frame + _NETWORK_LATENCY_FRAMES
	):
		await _step()
		# Received network state is dropped while the frame driver
		# is paused.
		Netcode.frame_driver._is_paused = false
		while (
			next_packet_frame
			<= Netcode.server_frame_index - _NETWORK_LATENCY_FRAMES
		):
			if packets.has(next_packet_frame):
				var packet: Array = packets[next_packet_frame]
				(_bunny.state_from_server
					._handle_new_state_from_network(
						packet.duplicate()))
			next_packet_frame += 1
		Netcode.frame_driver._is_paused = true
	# Apply any rollback queued by the last states.
	await _step()

	assert_eq(
		_bunny.state_from_server.last_interaction_type,
		CharacterStateFromServer.ServerInteractionType.SPAWN,
		"Precondition: client applied the respawn",
	)


# --- Helpers ---


func _set_role(role: _Role) -> void:
	match role:
		_Role.LOCAL_MODE:
			Netcode.is_server = false
			Netcode.is_local_mode = true
		_Role.DEDICATED_SERVER:
			Netcode.is_server = true
			Netcode.is_local_mode = false
		_Role.OWNING_CLIENT, _Role.REMOTE_CLIENT:
			Netcode.is_server = false
			Netcode.is_local_mode = false


## Spawns the real player scene the way NetworkedLevel does. On a
## client, the SPAWN this records stands in for the replicated one.
## With is_floating, the bunny starts at rest on the water's float
## line instead of at spawn_position's depth.
func _spawn_bunny(
	role: _Role,
	spawn_position: Vector2,
	is_floating := false,
) -> void:
	Netcode.frame_driver.server_frame_index = _START_FRAME
	_bunny = G.settings.default_player_scene.instantiate()
	_bunny.name = "Player_1"
	_level.add_child(_bunny)
	if is_floating:
		spawn_position.y = (
			_WATER_RECT.position.y
			+ _bunny.movement_settings.water_sink_threshold)
	_bunny.global_position = spawn_position
	_bunny.server_initialize_player_id(1)

	if role == _Role.OWNING_CLIENT or role == _Role.REMOTE_CLIENT:
		# This process is peer 1, the server's ID. Hand server
		# authority to another peer so the bunny simulates as a
		# client.
		_bunny.state_from_server.set_multiplayer_authority(
			_OTHER_PEER_ID)
		_bunny.forwarded_input_from_server.set_multiplayer_authority(
			_OTHER_PEER_ID)
		_bunny.input_from_client.set_multiplayer_authority(
			1 if role == _Role.OWNING_CLIENT else _OTHER_PEER_ID)
		_bunny.state_from_server._has_received_valid_state = true


func _kill_bunny() -> void:
	_death_position = _bunny.global_position
	_death_frame = Netcode.server_frame_index
	_bunny.server_trigger_death()
	# Tests trigger the respawn themselves, on a chosen frame.
	_cancel_scheduled_respawns()


## Simulates one physics tick, then the idle step after it. Runs inside
## a physics frame so move_and_slide() uses the fixed physics delta.
func _step() -> void:
	await get_tree().physics_frame
	Netcode.frame_driver.server_frame_index += 1
	Netcode.frame_driver._run_network_process()
	# The invincibility blink updates visibility in _process.
	_bunny._update_invincibility_blink()
	_check_render_state()


func _step_and_record(packets: Dictionary) -> void:
	await _step()
	# Death and respawn are injected into already-processed frames,
	# so re-read the recent frames each time.
	var buffer := _bunny.state_from_server._rollback_buffer
	for frame in range(
		Netcode.server_frame_index - 2,
		Netcode.server_frame_index + 1,
	):
		if frame < _START_FRAME or not buffer.has_at(frame):
			continue
		var state: Array = buffer.get_at(frame)
		var packet := state.slice(0, state.size() - 1)
		packet.append(ReconcilableState.FrameAuthority.AUTHORITATIVE)
		packet.append(frame)
		packets[frame] = packet


## Records any frame that would render the bunny, or an effect spawned
## for it, at the level origin or sliding out of it.
func _check_render_state() -> void:
	var frame := Netcode.server_frame_index
	var animator := _bunny.animator
	if (
		_bunny.state_from_server.is_dead
		and animator.is_visible_in_tree()
	):
		_violations.append(
			"F:%d bunny visible while dead at %s"
			% [frame, animator.global_position])
	if (
		animator.is_visible_in_tree()
		and _is_near_origin(animator.global_position)
	):
		_violations.append(
			"F:%d bunny visible at %s"
			% [frame, animator.global_position])

	for item in _spawned_items:
		if item.is_checked:
			continue
		item.is_checked = true
		if _is_near_origin(item.entry_position):
			_violations.append(
				"F:%d %s entered the tree at %s"
				% [item.frame, item.name, item.entry_position])
		var node: Node2D = item.node
		if (
			is_instance_valid(node)
			and not node.global_position.is_equal_approx(
				item.entry_position)
		):
			# Interpolation starts from the entry transform.
			_violations.append(
				"F:%d %s entered at %s but sits at %s"
				% [
					item.frame,
					item.name,
					item.entry_position,
					node.global_position,
				])


func _on_level_child_entered(node: Node) -> void:
	if node == _bunny or node == _splashes:
		return
	if not node is Node2D:
		return
	_spawned_items.append({
		node = node,
		name = node.name,
		is_sprite = node is Sprite2D,
		entry_position = (node as Node2D).global_position,
		frame = Netcode.server_frame_index,
		is_checked = false,
	})


func _assert_no_render_violations() -> void:
	assert_true(
		_violations.is_empty(),
		"Nothing should render at the level origin:\n%s"
		% "\n".join(_violations),
	)


func _assert_no_splashes_since_death(message: String) -> void:
	var splashes := _get_splashes_since(_death_frame)
	assert_eq(splashes.size(), 0, "%s: %s" % [message, splashes])


func _assert_squish_sprite_entered_at_death_position() -> void:
	var sprites := _spawned_items.filter(
		func(item: Dictionary) -> bool:
			return item.is_sprite)
	assert_eq(sprites.size(), 1, "Death should spawn one squish sprite")
	if sprites.is_empty():
		return
	assert_almost_eq(
		sprites[0].entry_position,
		_death_position + _bunny.animator.position,
		Vector2(0.01, 0.01),
		"Squish sprite should enter the tree at the death position",
	)


func _get_splashes_since(frame: int) -> Array:
	return _splashes.spawned.filter(
		func(splash: Dictionary) -> bool:
			return splash.frame > frame)


func _get_respawn_cooldown_frames() -> int:
	return int(
		G.settings.player_respawn_cooldown_sec
		* Netcode.frame_driver.target_network_fps)


func _is_near_origin(global_pos: Vector2) -> bool:
	return global_pos.length() < _ORIGIN_CLEARANCE


## Drops respawn timers scheduled by server_trigger_death() so they
## never fire on a freed bunny. Tests trigger the respawn themselves.
func _cancel_scheduled_respawns() -> void:
	for id in Netcode.time._active_callbacks.keys():
		if not _timer_ids_before_test.has(id):
			Netcode.time.clear_timeout(id)
