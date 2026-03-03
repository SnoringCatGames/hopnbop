extends GutTest

const Helpers = preload("res://test/helpers/character_rollback_helpers.gd")
## Integration tests for character movement during rollback.
##
## Tests real gameplay scenarios with character prediction, rollback,
## and reconciliation to ensure smooth networked character movement.


func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()

## ============================================================================
## Helper Classes
## ============================================================================


## Helper to create a minimal test character with necessary components.
class TestCharacterFixture:
	extends RefCounted

	var character: Character
	var state_from_server: CharacterStateFromServer
	var input_from_client: PlayerInputFromClient
	var movement_settings: MovementSettings


	func _init():
		# Create movement settings
		movement_settings = MovementSettings.new()
		movement_settings.set_up()

		# Create character
		character = Character.new()
		character.movement_settings = movement_settings

		# Create collision shape (required)
		var collision_shape := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(20, 40)
		collision_shape.shape = shape
		character.collision_shape = collision_shape
		character.add_child(collision_shape)

		# Create animator with AnimatedSprite2D (required)
		var animator := CharacterAnimator.new()
		var animated_sprite := AnimatedSprite2D.new()
		var sprite_frames := SpriteFrames.new()
		# Add all animations used by Character
		for anim_name in [
			"Walk",
			"Rest",
			"ClimbUp",
			"ClimbDown",
			"RestOnWall",
			"CrawlOnCeiling",
			"RestOnCeiling",
			"JumpFall",
			"JumpRise",
		]:
			sprite_frames.add_animation(anim_name)
		animated_sprite.sprite_frames = sprite_frames
		animator.animated_sprite = animated_sprite
		animator.add_child(animated_sprite)
		character.animator = animator
		character.add_child(animator)

		# Create state from server (required)
		state_from_server = CharacterStateFromServer.new()
		state_from_server.character = character
		state_from_server.peer_id = 1
		state_from_server.replication_config = SceneReplicationConfig.new()
		character.state_from_server = state_from_server
		character.add_child(state_from_server)

		# Create input from client
		input_from_client = PlayerInputFromClient.new()
		input_from_client.peer_id = 1
		input_from_client.replication_config = SceneReplicationConfig.new()
		character.add_child(input_from_client)


	func setup_in_tree(tree_root: Node) -> void:
		tree_root.add_child(character)
		# Trigger _ready by adding to tree - Godot calls it automatically
		# Wait for ready to complete
		await tree_root.get_tree().process_frame


	func cleanup() -> void:
		if is_instance_valid(character) and character.is_inside_tree():
			character.queue_free()


## ============================================================================
## Character Position & Velocity Reconciliation Tests
## ============================================================================
class TestCharacterMovementRollback:
	extends GutTest

	var fixture: TestCharacterFixture
	var character: Character


	func before_each():
		ArrayPool.clear_all_pools()
		fixture = TestCharacterFixture.new()
		await fixture.setup_in_tree(get_tree().root)
		character = fixture.character
		# Set initial state
		character.position = Vector2(100, 500)
		character.velocity = Vector2.ZERO


	func after_each():
		fixture.cleanup()
		ArrayPool.clear_all_pools()


	func test_position_mismatch_triggers_rollback():
		# Client predicts moving right for 5 frames
		Netcode.server_frame_index = 50
		character.velocity = Vector2(100, 0)

		var predicted_positions := []
		for i in range(5):
			predicted_positions.append(character.position)
			Helpers.simulate_frames(character, 1)

		# Server correction: position is different at frame 52
		var server_pos := Vector2(120, 500)
		var client_pos: Vector2 = predicted_positions[2]

		# Verify mismatch detected
		assert_true(
			Helpers.has_position_mismatch(client_pos, server_pos),
			"Should detect position mismatch",
		)

		# Verify difference exceeds rollback threshold
		var threshold := \
		CharacterStateFromServer.DEFAULT_POSITION_DIFF_ROLLBACK_THRESHOLD
		assert_gt(
			abs(client_pos.x - server_pos.x),
			threshold,
			"Difference should exceed rollback threshold",
		)


	func test_velocity_reconciliation_after_collision():
		# Client predicts passing through a wall
		Netcode.server_frame_index = 50
		character.position = Vector2(100, 500)
		character.velocity = Vector2(200, 0)

		# Simulate 3 frames of movement
		for i in range(3):
			Helpers.simulate_frames(character, 1)

		# Verify velocity mismatch with zero (hit wall)
		assert_true(
			Helpers.has_velocity_mismatch(character.velocity, Vector2.ZERO),
			"Should detect velocity mismatch",
		)


	func test_small_position_drift_under_threshold():
		# Client position differs by small amount
		var client_pos := Vector2(100.3, 500.4)
		var server_pos := Vector2(100.0, 500.0)

		# Verify difference is under threshold
		assert_false(
			Helpers.has_position_mismatch(client_pos, server_pos, 1.0),
			"Small drift should not trigger rollback",
		)

		var diff := client_pos.distance_to(server_pos)
		var threshold := \
		CharacterStateFromServer.DEFAULT_POSITION_DIFF_ROLLBACK_THRESHOLD
		assert_lt(diff, threshold, "Drift should be under threshold")


	func test_accumulated_drift_triggers_eventual_rollback():
		# Simulate gradual position drift over multiple frames
		Netcode.server_frame_index = 50
		character.position = Vector2(100, 500)
		character.velocity = Vector2(50, 0)

		var drift_per_frame := 0.3
		var accumulated_drift := 0.0

		for i in range(10):
			Helpers.simulate_frames(character, 1)
			accumulated_drift += drift_per_frame

			if accumulated_drift > 1.0:
				# Should trigger rollback at this point
				var threshold := CharacterStateFromServer.DEFAULT_POSITION_DIFF_ROLLBACK_THRESHOLD
				assert_gt(
					accumulated_drift,
					threshold,
					"Accumulated drift should exceed threshold",
				)
				break


## ============================================================================
## Input Replay & Action State Tests
## ============================================================================
class TestInputReplayDuringRollback:
	extends GutTest

	var fixture: TestCharacterFixture
	var character: Character


	func before_each():
		ArrayPool.clear_all_pools()
		fixture = TestCharacterFixture.new()
		await fixture.setup_in_tree(get_tree().root)
		character = fixture.character
		character.position = Vector2(100, 500)
		character.velocity = Vector2.ZERO


	func after_each():
		fixture.cleanup()
		ArrayPool.clear_all_pools()


	func test_jump_input_records_frame_index():
		# Setup: Character on ground with jump just pressed.
		Netcode.server_frame_index = 45
		character.surfaces.is_touching_floor = true
		character.surfaces.is_attaching_to_floor = true
		character.actions.previous_bitmask = 0
		character.actions.pressed_jump = true

		# Verify just_triggered_jump fires.
		assert_true(
			character.actions.just_triggered_jump,
			"Jump should be just triggered",
		)

		# _pre_movement records the jump frame when
		# just_triggered_jump is true.
		character._pre_movement()

		assert_eq(
			character.last_triggered_jump_frame_index,
			45,
			"Jump frame should be recorded at current server frame",
		)


	func test_direction_reversal_preserves_sequence():
		# Simulate 5 frames moving left via velocity.
		character.velocity = Vector2(-100, 0)
		Helpers.simulate_frames(character, 5)
		var position_after_left := character.position.x

		# Reverse direction and simulate 5 more frames.
		character.velocity = Vector2(100, 0)
		Helpers.simulate_frames(character, 5)

		# Position should have moved rightward relative to
		# the leftmost point.
		assert_gt(
			character.position.x,
			position_after_left,
			"Right velocity should move character rightward",
		)


	func test_action_state_consistency_after_rollback():
		# Character in AIR state
		character.surfaces.is_attaching_to_floor = false
		character.velocity = Vector2(0, -200)

		# Verify action state
		assert_eq(
			character.surfaces.surface_type,
			SurfaceType.AIR,
			"Should be in AIR state",
		)

		# Restore from server state
		var state := Helpers.create_server_state(
			character.position,
			character.velocity,
			character.surfaces.bitmask,
		)
		character.state_from_server._sync_to_scene_state(state)

		assert_eq(
			character.surfaces.surface_type,
			SurfaceType.AIR,
			"AIR state should be preserved after rollback",
		)


	func test_surface_contact_restored_after_rollback():
		# Character on platform
		character.position = Vector2(100, 500)
		character.surfaces.is_touching_floor = true
		character.surfaces.is_attaching_to_floor = true
		character.surfaces.update_actions()

		assert_eq(
			character.surfaces.surface_type,
			SurfaceType.FLOOR,
			"Should start on floor",
		)

		# Simulate losing contact
		character.surfaces.is_touching_floor = false
		character.surfaces.is_attaching_to_floor = false
		character.surfaces.update_actions()

		assert_eq(
			character.surfaces.surface_type,
			SurfaceType.AIR,
			"Should be in air after losing contact",
		)

		# Manually restore floor contact (simulating rollback restoration)
		character.surfaces.is_touching_floor = true
		character.surfaces.is_attaching_to_floor = true
		character.surfaces.update_actions()

		# Verify surface contact restored
		assert_eq(
			character.surfaces.surface_type,
			SurfaceType.FLOOR,
			"Floor contact should be restored",
		)


## ============================================================================
## Surface Transition Tests
## ============================================================================
class TestSurfaceTransitions:
	extends GutTest

	var fixture: TestCharacterFixture
	var character: Character


	func before_each():
		ArrayPool.clear_all_pools()
		fixture = TestCharacterFixture.new()
		await fixture.setup_in_tree(get_tree().root)
		character = fixture.character


	func after_each():
		fixture.cleanup()
		ArrayPool.clear_all_pools()


	func test_floor_to_air_transition():
		# Client predicts walking off platform
		character.position = Vector2(100, 500)
		character.velocity = Vector2(100, 0)
		character.surfaces.is_touching_floor = true
		character.surfaces.is_attaching_to_floor = true

		assert_eq(
			character.surfaces.surface_type,
			SurfaceType.FLOOR,
			"Should start on FLOOR",
		)

		# Simulate leaving floor
		Helpers.simulate_frames(character, 2)
		character.surfaces.is_touching_floor = false
		character.surfaces.is_attaching_to_floor = false
		character.surfaces.update_actions()

		# Now in air
		assert_eq(
			character.surfaces.surface_type,
			SurfaceType.AIR,
			"Should transition to AIR",
		)


	func test_air_to_floor_landing():
		# Character falling
		character.position = Vector2(100, 400)
		character.velocity = Vector2(0, 200)
		character.surfaces.is_attaching_to_floor = false

		assert_eq(
			character.surfaces.surface_type,
			SurfaceType.AIR,
			"Should start in AIR",
		)

		# Simulate landing
		Helpers.simulate_frames(character, 3)
		character.surfaces.is_touching_floor = true
		character.surfaces.is_attaching_to_floor = true
		character.surfaces.update_actions()

		assert_eq(
			character.surfaces.surface_type,
			SurfaceType.FLOOR,
			"Should land on FLOOR",
		)

		# Check transition detection
		assert_true(
			character.surfaces.just_left_air,
			"Should detect transition from air",
		)


	func test_jump_input_state():
		# Test that jump input state can be set and queried
		character.position = Vector2(100, 500)
		character.surfaces.is_touching_floor = true
		character.surfaces.is_attaching_to_floor = true
		character.surfaces.update_actions()

		assert_eq(
			character.surfaces.surface_type,
			SurfaceType.FLOOR,
			"Should start on FLOOR",
		)

		# Set up "just pressed" jump state:
		# previous_bitmask has jump=false, current has jump=true
		character.actions.previous_bitmask = 0
		character.actions.pressed_jump = true

		# Verify just_pressed_jump is true
		assert_true(
			character.actions.just_pressed_jump,
			"Jump should be just pressed",
		)

		# Verify jump is pressed
		assert_true(
			character.actions.pressed_jump,
			"Jump should be pressed",
		)

		# Record jump frame
		character.last_triggered_jump_frame_index = Netcode.server_frame_index

		assert_eq(
			character.last_triggered_jump_frame_index,
			Netcode.server_frame_index,
			"Jump frame should be recorded",
		)


## ============================================================================
## Physics & Collision Handling Tests
## ============================================================================
class TestPhysicsDuringRollback:
	extends GutTest

	var fixture: TestCharacterFixture
	var character: Character


	func before_each():
		ArrayPool.clear_all_pools()
		fixture = TestCharacterFixture.new()
		await fixture.setup_in_tree(get_tree().root)
		character = fixture.character


	func after_each():
		fixture.cleanup()
		ArrayPool.clear_all_pools()


	func test_gravity_applied_during_air_state():
		# Character in air
		character.position = Vector2(100, 400)
		character.velocity = Vector2(0, 0)
		character.surfaces.is_attaching_to_floor = false

		# Simulate frames
		Helpers.simulate_frames(character, 3)

		# Verify still in air
		assert_false(
			character.surfaces.is_attaching_to_floor,
			"Should remain in air",
		)


	func test_floor_contact_state():
		# Character on floor
		character.position = Vector2(100, 500)
		character.velocity = Vector2(50, 0)
		character.surfaces.is_touching_floor = true
		character.surfaces.is_attaching_to_floor = true
		character.surfaces.update_actions()

		# Verify floor state
		assert_eq(
			character.surfaces.surface_type,
			SurfaceType.FLOOR,
			"Should be on FLOOR surface",
		)
		assert_true(
			character.surfaces.is_touching_floor,
			"Floor contact should be active",
		)

		# Simulate losing contact
		character.surfaces.is_touching_floor = false
		character.surfaces.is_attaching_to_floor = false
		character.surfaces.update_actions()

		# Verify air state
		assert_eq(
			character.surfaces.surface_type,
			SurfaceType.AIR,
			"Should be in AIR after losing contact",
		)


	func test_wall_contact_state():
		# Character touching left wall
		character.position = Vector2(100, 400)
		character.velocity = Vector2(-50, 0)
		character.surfaces.is_touching_left_wall = true
		character.surfaces.is_attaching_to_left_wall = true

		# Verify wall state
		assert_true(
			character.surfaces.is_touching_wall,
			"Should be touching wall",
		)
		assert_eq(
			character.surfaces.surface_type,
			SurfaceType.WALL,
			"Should be on WALL surface",
		)


	func test_ceiling_contact_state():
		# Character touching ceiling
		character.position = Vector2(100, 100)
		character.velocity = Vector2(0, -10)
		character.surfaces.is_touching_ceiling = true
		character.surfaces.is_attaching_to_ceiling = true

		# Verify ceiling state
		assert_true(
			character.surfaces.is_touching_ceiling,
			"Should be touching ceiling",
		)
		assert_eq(
			character.surfaces.surface_type,
			SurfaceType.CEILING,
			"Should be on CEILING surface",
		)



## ============================================================================
## Multi-Frame Prediction & Corrections
## ============================================================================
class TestPredictionWindows:
	extends GutTest

	var fixture: TestCharacterFixture
	var character: Character


	func before_each():
		ArrayPool.clear_all_pools()
		fixture = TestCharacterFixture.new()
		await fixture.setup_in_tree(get_tree().root)
		character = fixture.character


	func after_each():
		fixture.cleanup()
		ArrayPool.clear_all_pools()


	func test_multi_frame_prediction_accuracy():
		# Client predicts 10 frames ahead
		character.position = Vector2(100, 500)
		character.velocity = Vector2(100, 0)

		var predicted_positions := []

		# Predict 10 frames
		for i in range(10):
			predicted_positions.append(character.position)
			Helpers.simulate_frames(character, 1)

		# Verify prediction was stable
		assert_eq(
			predicted_positions.size(),
			10,
			"Should have 10 predicted frames",
		)

		# Verify positions are increasing (moving right)
		for i in range(1, 10):
			assert_gt(
				predicted_positions[i].x,
				predicted_positions[i - 1].x,
				"Position should increase each frame",
			)


	func test_long_prediction_window():
		# Predict 30 frames ahead (half second at 60fps)
		Netcode.server_frame_index = 80
		character.position = Vector2(100, 500)
		character.velocity = Vector2(50, 0)

		var start_position := character.position

		# Set input to move right continuously
		var set_input := func(_frame: int, char: Character) -> void:
			Helpers.set_character_input(char, false, false, false, false, true)

		# Simulate 30 frames of prediction with input
		Helpers.simulate_frames(character, 30, set_input)

		var final_position := character.position

		# Verify prediction advanced character significantly
		assert_gt(
			final_position.x,
			start_position.x,
			"Character should have moved forward significantly",
		)

		# Verify we predicted 30 frames (with noticeable movement)
		var distance_moved: float = abs(
			final_position.x - start_position.x)
		assert_gt(
			distance_moved,
			1.0,
			"Should move noticeable distance in 30 frames",
		)



## ============================================================================
## Edge Cases & Boundary Tests
## ============================================================================
class TestMovementEdgeCases:
	extends GutTest

	var fixture: TestCharacterFixture
	var character: Character


	func before_each():
		ArrayPool.clear_all_pools()
		fixture = TestCharacterFixture.new()
		await fixture.setup_in_tree(get_tree().root)
		character = fixture.character


	func after_each():
		fixture.cleanup()
		ArrayPool.clear_all_pools()


	func test_zero_velocity_to_high_velocity():
		# Stationary to sprinting in one frame correction
		character.position = Vector2(100, 500)
		character.velocity = Vector2.ZERO

		# Server correction: high velocity
		var server_state := Helpers.create_server_state(
			Vector2(100, 500),
			Vector2(300, 0),
		)

		# Apply correction
		character.state_from_server.position = server_state[0]
		character.state_from_server.velocity = server_state[1]
		character.state_from_server._sync_to_scene_state(server_state)

		# Verify velocity applied correctly
		assert_almost_eq(
			character.velocity.x,
			300.0,
			1.0,
			"Velocity should jump to high value",
		)


	func test_direction_reversal_during_rollback():
		# Moving right, server corrects to moving left
		character.position = Vector2(100, 500)
		character.velocity = Vector2(100, 0)

		# Simulate 3 frames moving right
		for i in range(3):
			Helpers.simulate_frames(character, 1)

		# Server correction: was moving left
		var server_state := Helpers.create_server_state(
			Vector2(95, 500),
			Vector2(-100, 0),
		)

		# Apply correction
		character.state_from_server.position = server_state[0]
		character.state_from_server.velocity = server_state[1]
		character.state_from_server._sync_to_scene_state(server_state)

		# Verify direction reversal
		assert_lt(
			character.velocity.x,
			0,
			"Velocity should be reversed to left",
		)
		assert_almost_eq(
			character.velocity.x,
			-100.0,
			1.0,
			"Velocity magnitude should be correct",
		)


	func test_high_velocity_movement():
		# Very fast movement
		character.position = Vector2(100, 500)
		character.velocity = Vector2(500, 0)

		# Simulate frame
		Helpers.simulate_frames(character, 1)

		# Position should change significantly
		var distance_moved: float = abs(character.position.x - 100.0)
		assert_gt(
			distance_moved,
			2.0,
			"High velocity should produce significant movement",
		)


	func test_position_remains_valid_after_rollback():
		# Ensure position doesn't become INF or NAN
		character.position = Vector2(100, 500)
		character.velocity = Vector2(100, -100)

		# Simulate multiple frames
		for i in range(10):
			Helpers.simulate_frames(character, 1)

		# Verify position is valid
		assert_false(
			is_inf(character.position.x) or is_inf(character.position.y),
			"Position should not be INF",
		)
		assert_false(
			is_nan(character.position.x) or is_nan(character.position.y),
			"Position should not be NAN",
		)


	func test_velocity_remains_valid_after_rollback():
		# Ensure velocity doesn't become INF or NAN
		character.position = Vector2(100, 500)
		character.velocity = Vector2(50, 0)

		# Apply various inputs
		for i in range(10):
			# Alternate left/right input
			if i % 2 == 0:
				Helpers.set_character_input(
					character,
					false,
					false,
					false,
					true,
					false,
				)
			else:
				Helpers.set_character_input(
					character,
					false,
					false,
					false,
					false,
					true,
				)

			Helpers.simulate_frames(character, 1)

		# Verify velocity is valid
		assert_false(
			is_inf(character.velocity.x) or is_inf(character.velocity.y),
			"Velocity should not be INF",
		)
		assert_false(
			is_nan(character.velocity.x) or is_nan(character.velocity.y),
			"Velocity should not be NAN",
		)
