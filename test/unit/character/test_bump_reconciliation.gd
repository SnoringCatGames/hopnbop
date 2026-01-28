extends GutTest
## Unit tests for bump event reconciliation in CharacterStateFromServer.


func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()


class TestInteractionFrameIndexConversion:
	extends GutTest

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_negative_time_converts_to_negative_frame():
		var state = CharacterStateFromServer.new()
		state.last_interaction_time_usec = -1

		assert_eq(
			state.last_interaction_frame_index,
			-1,
			"Negative time should convert to -1 frame"
		)

	func test_positive_frame_converts_to_time():
		var state = CharacterStateFromServer.new()
		state.last_interaction_frame_index = 100

		assert_gt(
			state.last_interaction_time_usec,
			0,
			"Positive frame should convert to positive time"
		)

	func test_frame_to_time_roundtrip():
		var state = CharacterStateFromServer.new()
		var original_frame = 500
		state.last_interaction_frame_index = original_frame

		var retrieved_frame = state.last_interaction_frame_index
		assert_eq(
			retrieved_frame,
			original_frame,
			"Frame index should survive roundtrip conversion"
		)

	func test_setting_negative_frame_clears_time():
		var state = CharacterStateFromServer.new()
		state.last_interaction_frame_index = 100
		state.last_interaction_frame_index = -1

		assert_eq(
			state.last_interaction_time_usec,
			-1,
			"Setting frame to -1 should clear time"
		)


class TestInteractionStateReplication:
	extends GutTest

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_interaction_properties_in_synced_dict():
		var state = CharacterStateFromServer.new()
		var props = state._synced_properties_and_rollback_diff_thresholds

		assert_true(
			props.has("last_interaction_type"),
			"last_interaction_type should be synced"
		)
		assert_true(
			props.has("last_interaction_time_usec"),
			"last_interaction_time_usec should be synced"
		)
		assert_true(
			props.has("last_interaction_position"),
			"last_interaction_position should be synced"
		)
		assert_true(
			props.has("last_interaction_direction"),
			"last_interaction_direction should be synced"
		)

	func test_interaction_properties_have_thresholds():
		var state = CharacterStateFromServer.new()
		var props = state._synced_properties_and_rollback_diff_thresholds

		assert_eq(
			props["last_interaction_type"],
			0,
			"Interaction type should have exact match threshold"
		)
		assert_eq(
			props["last_interaction_time_usec"],
			0,
			"Interaction time should have exact match threshold"
		)
		assert_almost_eq(
			props["last_interaction_position"],
			0.01,
			0.001,
			"Interaction position should have small tolerance"
		)
		assert_almost_eq(
			props["last_interaction_direction"],
			0.01,
			0.001,
			"Interaction direction should have small tolerance"
		)

	func test_interaction_properties_in_default_values():
		var state = CharacterStateFromServer.new()
		var defaults = state._get_default_values()

		# Verify array has correct number of elements.
		assert_eq(
			defaults.size(),
			7,
			"Default values should include all interaction properties"
		)


class TestBumpReconciliation:
	extends GutTest

	var character: Character
	var state: CharacterStateFromServer
	var movement_settings: MovementSettings

	func before_each():
		ArrayPool.clear_all_pools()

		# Create minimal character setup.
		movement_settings = MovementSettings.new()
		movement_settings.bump_bounce_base_speed = 300.0
		movement_settings.bump_bounce_vertical_boost = -200.0

		character = Character.new()
		character.movement_settings = movement_settings

		state = CharacterStateFromServer.new()
		state.character = character
		character.state_from_server = state

		# Initialize property names (normally done in _ready()).
		state._parse_property_names()

		# Manually create rollback buffer (bypasses time initialization check).
		var default_values := state._get_default_values().duplicate()
		default_values.append(ReconcilableNetworkedState.FrameAuthority.PREDICTED)
		state._rollback_buffer = RollbackBuffer.new(
			90, # capacity (typical rollback buffer size)
			0, # current_frame_index
			default_values
		)

	func after_each():
		ArrayPool.clear_all_pools()
		if is_instance_valid(character):
			character.free()

	func test_reconciliation_skips_when_no_new_interaction():
		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.NONE
		state._last_reconciled_interaction_frame_index = 100

		# Call reconciliation (should do nothing).
		state._reconcile_server_interaction()

		# Verify no rollback was queued.
		assert_eq(
			state._last_reconciled_interaction_frame_index,
			100,
			"Reconciled frame should not change"
		)

	func test_reconciliation_skips_already_processed_bump():
		G.network.frame_driver.server_frame_index = 200
		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 100
		state._last_reconciled_interaction_frame_index = 100

		state._reconcile_server_interaction()

		# Should skip without changing reconciled frame.
		assert_eq(
			state._last_reconciled_interaction_frame_index,
			100,
			"Reconciled frame should not change when already processed"
		)

	func test_reconciliation_skips_stale_bump():
		# Set current frame far ahead.
		G.network.frame_driver.server_frame_index = 10000

		# Set bump at very old frame.
		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 10
		state.last_interaction_direction = Vector2(1, 0)

		state._reconcile_server_interaction()

		# Should skip due to staleness check.
		assert_eq(
			state._last_reconciled_interaction_frame_index,
			10,
			"Stale bump should be marked as reconciled"
		)

	func test_reconciliation_injects_velocity_into_buffer():
		# Set up rollback buffer with a frame.
		G.network.frame_driver.server_frame_index = 300

		# Manually create frame state array.
		# Format: [position, velocity, surfaces, last_interaction_type,
		# last_interaction_time_usec, last_interaction_position,
		# last_interaction_direction, frame_authority]
		var frame_state = ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO # position
		frame_state[1] = Vector2(100, 100) # velocity
		frame_state[2] = 0 # surfaces
		frame_state[3] = CharacterStateFromServer.ServerInteractionType.NONE
		frame_state[4] = -1 # last_interaction_time_usec
		frame_state[5] = Vector2.ZERO # last_interaction_position
		frame_state[6] = Vector2.ZERO # last_interaction_direction
		frame_state[7] = ReconcilableNetworkedState.FrameAuthority.AUTHORITATIVE

		state._rollback_buffer.set_at(300, frame_state)

		# Set bump event.
		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 300
		state.last_interaction_direction = Vector2(1, 0).normalized()

		# Reconcile.
		state._reconcile_server_interaction()

		# Verify velocity was modified.
		var modified_state: Array = state._rollback_buffer.get_at(300)
		var velocity: Vector2 = modified_state[1] # Index 1 is velocity

		# Should have original velocity + bump delta.
		var expected_bump = (
			Vector2(1, 0).normalized() * 300.0 + Vector2(0, -200.0)
		)
		var expected_velocity = Vector2(100, 100) + expected_bump

		assert_almost_eq(
			velocity.x,
			expected_velocity.x,
			1.0,
			"X velocity should include bump"
		)
		assert_almost_eq(
			velocity.y,
			expected_velocity.y,
			1.0,
			"Y velocity should include bump"
		)

	func test_reconciliation_marks_bump_as_processed():
		G.network.frame_driver.server_frame_index = 400

		# Manually create frame state array.
		var frame_state = ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO # position
		frame_state[1] = Vector2.ZERO # velocity
		frame_state[2] = 0 # surfaces
		frame_state[3] = CharacterStateFromServer.ServerInteractionType.NONE
		frame_state[4] = -1 # last_interaction_time_usec
		frame_state[5] = Vector2.ZERO # last_interaction_position
		frame_state[6] = Vector2.ZERO # last_interaction_direction
		frame_state[7] = ReconcilableNetworkedState.FrameAuthority.AUTHORITATIVE

		state._rollback_buffer.set_at(400, frame_state)

		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 400
		state.last_interaction_direction = Vector2(0, -1)

		state._reconcile_server_interaction()

		assert_eq(
			state._last_reconciled_interaction_frame_index,
			400,
			"Bump should be marked as reconciled"
		)

	func test_reconciliation_calculates_correct_bump_delta():
		G.network.frame_driver.server_frame_index = 500

		# Manually create frame state array.
		var frame_state = ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO # position
		frame_state[1] = Vector2.ZERO # velocity
		frame_state[2] = 0 # surfaces
		frame_state[3] = CharacterStateFromServer.ServerInteractionType.NONE
		frame_state[4] = -1 # last_interaction_time_usec
		frame_state[5] = Vector2.ZERO # last_interaction_position
		frame_state[6] = Vector2.ZERO # last_interaction_direction
		frame_state[7] = ReconcilableNetworkedState.FrameAuthority.AUTHORITATIVE

		state._rollback_buffer.set_at(500, frame_state)

		# Bump direction at 45 degrees.
		var direction = Vector2(1, -1).normalized()
		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 500
		state.last_interaction_direction = direction

		state._reconcile_server_interaction()

		var modified_state: Array = state._rollback_buffer.get_at(500)
		var velocity: Vector2 = modified_state[1] # Index 1 is velocity

		# Expected: direction * base_speed + upward_boost.
		var expected = direction * 300.0 + Vector2(0, -200.0)

		assert_almost_eq(
			velocity.x,
			expected.x,
			1.0,
			"X component should match expected"
		)
		assert_almost_eq(
			velocity.y,
			expected.y,
			1.0,
			"Y component should match expected"
		)


class TestBumpReconciliationEdgeCases:
	extends GutTest

	var character: Character
	var state: CharacterStateFromServer
	var movement_settings: MovementSettings

	func before_each():
		ArrayPool.clear_all_pools()

		movement_settings = MovementSettings.new()
		movement_settings.bump_bounce_base_speed = 300.0
		movement_settings.bump_bounce_vertical_boost = -200.0

		character = Character.new()
		character.movement_settings = movement_settings

		state = CharacterStateFromServer.new()
		state.character = character
		character.state_from_server = state

		# Initialize property names (normally done in _ready()).
		state._parse_property_names()

		# Manually create rollback buffer (bypasses time initialization check).
		var default_values := state._get_default_values().duplicate()
		default_values.append(ReconcilableNetworkedState.FrameAuthority.PREDICTED)
		state._rollback_buffer = RollbackBuffer.new(
			90, # capacity (typical rollback buffer size)
			0, # current_frame_index
			default_values
		)

	func after_each():
		ArrayPool.clear_all_pools()
		if is_instance_valid(character):
			character.free()

	func test_reconciliation_with_zero_direction():
		G.network.frame_driver.server_frame_index = 600

		# Manually create frame state array.
		var frame_state = ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO # position
		frame_state[1] = Vector2.ZERO # velocity
		frame_state[2] = 0 # surfaces
		frame_state[3] = CharacterStateFromServer.ServerInteractionType.NONE
		frame_state[4] = -1 # last_interaction_time_usec
		frame_state[5] = Vector2.ZERO # last_interaction_position
		frame_state[6] = Vector2.ZERO # last_interaction_direction
		frame_state[7] = ReconcilableNetworkedState.FrameAuthority.AUTHORITATIVE

		state._rollback_buffer.set_at(600, frame_state)

		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 600
		state.last_interaction_direction = Vector2.ZERO

		# Should not crash.
		state._reconcile_server_interaction()

		# Verify bump was marked as reconciled.
		assert_eq(
			state._last_reconciled_interaction_frame_index,
			600,
			"Bump should be marked as reconciled even with zero direction"
		)

	func test_reconciliation_skips_missing_frame():
		# Set bump at frame that doesn't exist in buffer.
		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 9999
		state.last_interaction_direction = Vector2(1, 0)

		state._reconcile_server_interaction()

		# Should skip without error.
		assert_eq(
			state._last_reconciled_interaction_frame_index,
			9999,
			"Missing frame should be marked as processed"
		)

	func test_reconciliation_with_downward_bump_direction():
		G.network.frame_driver.server_frame_index = 700

		# Manually create frame state array.
		var frame_state = ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO # position
		frame_state[1] = Vector2.ZERO # velocity
		frame_state[2] = 0 # surfaces
		frame_state[3] = CharacterStateFromServer.ServerInteractionType.NONE
		frame_state[4] = -1 # last_interaction_time_usec
		frame_state[5] = Vector2.ZERO # last_interaction_position
		frame_state[6] = Vector2.ZERO # last_interaction_direction
		frame_state[7] = ReconcilableNetworkedState.FrameAuthority.AUTHORITATIVE

		state._rollback_buffer.set_at(700, frame_state)

		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 700
		state.last_interaction_direction = Vector2(0, 1) # Downward.

		state._reconcile_server_interaction()

		var modified_state: Array = state._rollback_buffer.get_at(700)
		var velocity: Vector2 = modified_state[1] # Index 1 is velocity

		# With downward direction (300) and upward boost (-200), net is 100
		# downward.
		assert_almost_eq(
			velocity.y,
			100.0,
			1.0,
			"Downward bump with upward boost should result in net downward velocity"
		)
