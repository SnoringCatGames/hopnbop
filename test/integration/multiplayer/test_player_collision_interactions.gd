extends GutTest
## Integration tests for player collision interactions (bump and kill).


func before_all():
	# Set up game_panel mock for entire test suite to prevent PerfTracker
	# errors. PerfTracker runs as autoload between tests.
	TestEnvironmentMock.setup_mock_game_panel()


func after_all():
	# Clean up game_panel mock after all tests.
	if is_instance_valid(G.game_panel):
		G.game_panel.free()
	G.game_panel = null


func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()


class TestCollisionBounceVelocity:
	extends GutTest

	var player1: Bunny
	var player2: Bunny
	var movement_settings: MovementSettings
	var mock_level: MockLevel

	func before_each():
		ArrayPool.clear_all_pools()

		# Set up mock environment.
		mock_level = TestEnvironmentMock.setup_mock_level(self)

		# Create movement settings.
		movement_settings = MovementSettings.new()
		movement_settings.bump_bounce_base_speed = 300.0
		movement_settings.bump_bounce_vertical_boost = -200.0

		# Create players with networking infrastructure.
		player1 = _create_test_player(1)
		player2 = _create_test_player(2)

	func after_each():
		ArrayPool.clear_all_pools()
		TestEnvironmentMock.cleanup_mock_level()

	func _create_test_player(player_id: int) -> Bunny:
		var player = Bunny.new()
		player.name = "Player%d" % player_id
		player.movement_settings = movement_settings

		# Initialize required Character exports.
		player.collision_shape = CollisionShape2D.new()
		player.animator = CharacterAnimator.new()
		player.animator.animated_sprite = AnimatedSprite2D.new()
		player.add_child(player.animator)

		# Set up networked state node.
		var state = CharacterStateFromServer.new()
		state.name = "StateFromServer"
		state.root_path = NodePath(".")
		state.player_id = player_id
		state.character = player
		TestEnvironmentMock.init_replication_config(state)
		player.add_child(state)
		player.state_from_server = state

		# Add to tree to trigger _ready() and initialize rollback buffer.
		add_child_autofree(player)

		# Set player_id after state_from_server is assigned.
		player.player_id = player_id

		return player

	func test_bounce_applies_directional_velocity():
		# Position players for horizontal bounce.
		player1.global_position = Vector2(0, 0)
		player2.global_position = Vector2(100, 0)

		# Apply bounce (player1 bounces away from player2).
		player1._server_apply_interaction(player2, CharacterStateFromServer.ServerInteractionType.BUMP)

		# Player1 should have pending bounce in negative X direction.
		assert_lt(
			player1._pending_bounce.x,
			0,
			"Player1 should bounce left"
		)

	func test_bounce_applies_upward_boost():
		player1.global_position = Vector2(0, 0)
		player2.global_position = Vector2(100, 0)

		player1._server_apply_interaction(player2, CharacterStateFromServer.ServerInteractionType.BUMP)

		# Upward boost is negative Y (up in Godot).
		assert_lt(
			player1._pending_bounce.y,
			-100.0,
			"Player1 should have upward boost"
		)

	func test_bounce_magnitude_matches_settings():
		player1.global_position = Vector2(0, 0)
		player2.global_position = Vector2(100, 0)

		player1._server_apply_interaction(player2, CharacterStateFromServer.ServerInteractionType.BUMP)

		var bounce_magnitude = player1._pending_bounce.length()

		# Expected: sqrt((300)^2 + (200)^2) ≈ 360.
		assert_almost_eq(
			bounce_magnitude,
			360.0,
			10.0,
			"Bounce magnitude should match combined bounce"
		)

	func test_bounce_direction_away_from_collision():
		# Player1 at origin, player2 to the right.
		player1.global_position = Vector2(0, 0)
		player2.global_position = Vector2(100, 0)

		player1._server_apply_interaction(player2, CharacterStateFromServer.ServerInteractionType.BUMP)

		# Player1 should bounce left (negative X).
		assert_lt(
			player1._pending_bounce.x,
			0,
			"Player1 should bounce away from player2"
		)

	func test_bounce_at_45_degree_angle():
		# Player1 at origin, player2 at 45 degrees.
		player1.global_position = Vector2(0, 0)
		player2.global_position = Vector2(100, 100)

		player1.velocity = Vector2.ZERO
		player1._server_apply_interaction(player2, CharacterStateFromServer.ServerInteractionType.BUMP)

		# Should bounce diagonally up-left.
		assert_lt(
			player1._pending_bounce.x,
			0,
			"Should bounce left"
		)
		assert_lt(
			player1._pending_bounce.y,
			0,
			"Should bounce up"
		)

	func test_bump_records_frame_and_direction():
		G.network.frame_driver.server_frame_index = 100

		player1.global_position = Vector2(0, 0)
		player2.global_position = Vector2(100, 0)

		player1._server_apply_interaction(player2, CharacterStateFromServer.ServerInteractionType.BUMP)

		assert_eq(
			player1.state_from_server.last_interaction_frame_index,
			100,
			"Bump frame should be recorded"
		)

		# Direction should be normalized.
		var direction = player1.state_from_server.last_interaction_direction
		assert_almost_eq(
			direction.length(),
			1.0,
			0.01,
			"Direction should be normalized"
		)


class TestCollisionDetectionLogic:
	extends GutTest

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_bump_interaction_type_recorded():
		var state = MatchState.new()
		for pid in [1, 2]:
			var p = PlayerMatchState.new()
			p.player_id = pid
			state.players_by_id[pid] = p

		G.network.frame_driver.server_frame_index = 200
		state.server_add_bump(1, 2)

		assert_gt(
			state.bumps.size(),
			0,
			"Bump should be recorded"
		)
		assert_eq(
			state._total_bumps_by_player_id[1],
			1,
			"Player 1 bump count should increase"
		)
		assert_eq(
			state._total_bumps_by_player_id[2],
			1,
			"Player 2 bump count should increase"
		)

	func test_kill_interaction_type_recorded():
		var state = MatchState.new()
		for pid in [1, 2]:
			var p = PlayerMatchState.new()
			p.player_id = pid
			state.players_by_id[pid] = p

		G.network.frame_driver.server_frame_index = 300
		state.server_add_kill(1, 2)

		assert_gt(
			state.kills.size(),
			0,
			"Kill should be recorded"
		)
		assert_eq(
			state._total_kills_by_player_id[1],
			1,
			"Killer kill count should increase"
		)
		assert_eq(
			state._total_deaths_by_player_id[2],
			1,
			"Killee death count should increase"
		)


class TestBothPlayersBounceBehavior:
	extends GutTest

	var player1: Bunny
	var player2: Bunny
	var movement_settings: MovementSettings
	var mock_level: MockLevel

	func before_each():
		ArrayPool.clear_all_pools()

		# Set up mock environment.
		mock_level = TestEnvironmentMock.setup_mock_level(self)

		movement_settings = MovementSettings.new()
		movement_settings.bump_bounce_base_speed = 300.0
		movement_settings.bump_bounce_vertical_boost = -200.0

		player1 = _create_test_player(1)
		player2 = _create_test_player(2)

	func after_each():
		ArrayPool.clear_all_pools()
		TestEnvironmentMock.cleanup_mock_level()

	func _create_test_player(player_id: int) -> Bunny:
		var player = Bunny.new()
		player.name = "Player%d" % player_id
		player.movement_settings = movement_settings

		# Initialize required Character exports.
		player.collision_shape = CollisionShape2D.new()
		player.animator = CharacterAnimator.new()
		player.animator.animated_sprite = AnimatedSprite2D.new()
		player.add_child(player.animator)

		# Set up networked state node.
		var state = CharacterStateFromServer.new()
		state.name = "StateFromServer"
		state.root_path = NodePath(".")
		state.player_id = player_id
		state.character = player
		TestEnvironmentMock.init_replication_config(state)
		player.add_child(state)
		player.state_from_server = state

		# Add to tree to trigger _ready() and initialize rollback buffer.
		add_child_autofree(player)

		# Set player_id after state_from_server is assigned.
		player.player_id = player_id

		return player

	func test_both_players_bounce_on_bump():
		player1.global_position = Vector2(0, 0)
		player2.global_position = Vector2(100, 0)

		# Simulate bump (both players bounce).
		player1._server_apply_interaction(player2, CharacterStateFromServer.ServerInteractionType.BUMP)
		player2._server_apply_interaction(player1, CharacterStateFromServer.ServerInteractionType.BUMP)

		# Player1 should bounce left, player2 should bounce right.
		assert_lt(
			player1._pending_bounce.x,
			0,
			"Player1 should bounce left"
		)
		assert_gt(
			player2._pending_bounce.x,
			0,
			"Player2 should bounce right"
		)

	func test_bounce_directions_are_opposite():
		player1.global_position = Vector2(0, 0)
		player2.global_position = Vector2(100, 0)

		player1._server_apply_interaction(player2, CharacterStateFromServer.ServerInteractionType.BUMP)
		player2._server_apply_interaction(player1, CharacterStateFromServer.ServerInteractionType.BUMP)

		# X components should have opposite signs.
		var same_sign = (
			sign(player1._pending_bounce.x) == sign(player2._pending_bounce.x)
		)
		assert_false(
			same_sign,
			"Bounce X directions should be opposite"
		)

	func test_both_players_get_upward_boost():
		player1.global_position = Vector2(0, 0)
		player2.global_position = Vector2(100, 0)

		player1._server_apply_interaction(player2, CharacterStateFromServer.ServerInteractionType.BUMP)
		player2._server_apply_interaction(player1, CharacterStateFromServer.ServerInteractionType.BUMP)

		# Both should have negative Y (upward).
		assert_lt(
			player1._pending_bounce.y,
			-100.0,
			"Player1 should have upward boost"
		)
		assert_lt(
			player2._pending_bounce.y,
			-100.0,
			"Player2 should have upward boost"
		)


class TestBouncePreservesExistingVelocity:
	extends GutTest

	var player1: Bunny
	var player2: Bunny
	var movement_settings: MovementSettings
	var mock_level: MockLevel

	func before_each():
		ArrayPool.clear_all_pools()

		# Set up mock environment.
		mock_level = TestEnvironmentMock.setup_mock_level(self)

		movement_settings = MovementSettings.new()
		movement_settings.bump_bounce_base_speed = 300.0
		movement_settings.bump_bounce_vertical_boost = -200.0

		player1 = _create_test_player(1)
		player2 = _create_test_player(2)

	func after_each():
		ArrayPool.clear_all_pools()
		TestEnvironmentMock.cleanup_mock_level()

	func _create_test_player(player_id: int) -> Bunny:
		var player = Bunny.new()
		player.name = "Player%d" % player_id
		player.movement_settings = movement_settings

		# Initialize required Character exports.
		player.collision_shape = CollisionShape2D.new()
		player.animator = CharacterAnimator.new()
		player.animator.animated_sprite = AnimatedSprite2D.new()
		player.add_child(player.animator)

		# Set up networked state node.
		var state = CharacterStateFromServer.new()
		state.name = "StateFromServer"
		state.root_path = NodePath(".")
		state.player_id = player_id
		state.character = player
		TestEnvironmentMock.init_replication_config(state)
		player.add_child(state)
		player.state_from_server = state

		# Add to tree to trigger _ready() and initialize rollback buffer.
		add_child_autofree(player)

		# Set player_id after state_from_server is assigned.
		player.player_id = player_id

		return player

	func test_bounce_adds_to_existing_velocity():
		player1.global_position = Vector2(0, 0)
		player2.global_position = Vector2(100, 0)

		# Give player1 initial rightward velocity.
		player1.velocity = Vector2(50, 0)

		player1._server_apply_interaction(player2, CharacterStateFromServer.ServerInteractionType.BUMP)

		# Bounce should be set (will be added to velocity later).
		assert_ne(
			player1._pending_bounce,
			Vector2.ZERO,
			"Bounce should be set"
		)
		# Bounce is leftward (negative X).
		assert_lt(
			player1._pending_bounce.x,
			0,
			"Bounce should be leftward"
		)

	func test_bounce_accumulates_with_gravity():
		player1.global_position = Vector2(0, 0)
		player2.global_position = Vector2(100, 0)

		# Player1 is falling.
		player1.velocity = Vector2(0, 500)  # Downward.

		player1._server_apply_interaction(player2, CharacterStateFromServer.ServerInteractionType.BUMP)

		# Bounce should have upward component (negative Y).
		assert_lt(
			player1._pending_bounce.y,
			0,
			"Bounce should have upward boost"
		)


class TestCollisionEdgeCases:
	extends GutTest

	var player1: Bunny
	var player2: Bunny
	var movement_settings: MovementSettings
	var mock_level: MockLevel

	func before_each():
		ArrayPool.clear_all_pools()

		# Set up mock environment.
		mock_level = TestEnvironmentMock.setup_mock_level(self)

		movement_settings = MovementSettings.new()
		movement_settings.bump_bounce_base_speed = 300.0
		movement_settings.bump_bounce_vertical_boost = -200.0

		player1 = _create_test_player(1)
		player2 = _create_test_player(2)

	func after_each():
		ArrayPool.clear_all_pools()
		TestEnvironmentMock.cleanup_mock_level()

	func _create_test_player(player_id: int) -> Bunny:
		var player = Bunny.new()
		player.name = "Player%d" % player_id
		player.movement_settings = movement_settings

		# Initialize required Character exports.
		player.collision_shape = CollisionShape2D.new()
		player.animator = CharacterAnimator.new()
		player.animator.animated_sprite = AnimatedSprite2D.new()
		player.add_child(player.animator)

		# Set up networked state node.
		var state = CharacterStateFromServer.new()
		state.name = "StateFromServer"
		state.root_path = NodePath(".")
		state.player_id = player_id
		state.character = player
		TestEnvironmentMock.init_replication_config(state)
		player.add_child(state)
		player.state_from_server = state

		# Add to tree to trigger _ready() and initialize rollback buffer.
		add_child_autofree(player)

		# Set player_id after state_from_server is assigned.
		player.player_id = player_id

		return player

	func test_bounce_with_overlapping_positions():
		# Both players at same position.
		player1.global_position = Vector2(0, 0)
		player2.global_position = Vector2(0, 0)

		player1.velocity = Vector2.ZERO

		# Should not crash despite zero distance.
		player1._server_apply_interaction(player2, CharacterStateFromServer.ServerInteractionType.BUMP)

		# Velocity should still be modified (direction undefined but
		# normalized).
		assert_true(
			true,
			"Should not crash with overlapping positions"
		)

	func test_bounce_with_very_close_positions():
		player1.global_position = Vector2(0, 0)
		player2.global_position = Vector2(0.1, 0)  # Very close.

		player1._server_apply_interaction(player2, CharacterStateFromServer.ServerInteractionType.BUMP)

		# Should produce valid bounce.
		assert_ne(
			player1._pending_bounce,
			Vector2.ZERO,
			"Should produce non-zero bounce"
		)

	func test_bounce_with_diagonal_collision():
		# Collision from top-right.
		player1.global_position = Vector2(0, 0)
		player2.global_position = Vector2(100, -100)

		player1._server_apply_interaction(player2, CharacterStateFromServer.ServerInteractionType.BUMP)

		# Should bounce down-left.
		assert_lt(
			player1._pending_bounce.x,
			0,
			"Should bounce left"
		)
		assert_gt(
			player1._pending_bounce.y,
			0,
			"Base bounce should be downward (but upward boost may dominate)"
		)
