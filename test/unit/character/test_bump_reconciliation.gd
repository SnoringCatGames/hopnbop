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

	func test_negative_frame_stays_negative():
		var state = CharacterStateFromServer.new()
		state.last_interaction_frame_index = -1

		assert_eq(
			state.last_interaction_frame_index,
			-1,
			"Negative frame should stay -1"
		)

	func test_positive_frame_can_be_set():
		var state = CharacterStateFromServer.new()
		state.last_interaction_frame_index = 100

		assert_eq(
			state.last_interaction_frame_index,
			100,
			"Positive frame should be stored correctly"
		)

	func test_frame_roundtrip():
		var state = CharacterStateFromServer.new()
		var original_frame = 500
		state.last_interaction_frame_index = original_frame

		var retrieved_frame = state.last_interaction_frame_index
		assert_eq(
			retrieved_frame,
			original_frame,
			"Frame index should roundtrip correctly"
		)

	func test_setting_negative_frame():
		var state = CharacterStateFromServer.new()
		state.last_interaction_frame_index = 100
		state.last_interaction_frame_index = -1

		assert_eq(
			state.last_interaction_frame_index,
			-1,
			"Setting frame to -1 should work"
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
			props.has("last_interaction_frame_index"),
			"last_interaction_frame_index should be synced"
		)
		assert_true(
			props.has("last_interaction_position"),
			"last_interaction_position should be synced"
		)
		assert_true(
			props.has("last_interaction_velocity"),
			"last_interaction_velocity should be synced"
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
			props["last_interaction_frame_index"],
			0,
			"Interaction frame index should have exact match threshold"
		)
		assert_almost_eq(
			props["last_interaction_position"],
			0.01,
			0.001,
			"Interaction position should have small tolerance"
		)
		assert_almost_eq(
			props["last_interaction_velocity"],
			10.0,
			0.1,
			"Interaction velocity should have reasonable tolerance"
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
		default_values.append(ReconcilableState.FrameAuthority.PREDICTED)
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
		Netcode.frame_driver.server_frame_index = 200
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
		Netcode.frame_driver.server_frame_index = 10000

		# Set bump at very old frame.
		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 10
		state.last_interaction_velocity = Vector2(1, 0)

		state._reconcile_server_interaction()

		# Should skip due to staleness check.
		assert_eq(
			state._last_reconciled_interaction_frame_index,
			10,
			"Stale bump should be marked as reconciled"
		)

	func test_reconciliation_injects_velocity_into_buffer():
		# Set up rollback buffer with a frame.
		Netcode.frame_driver.server_frame_index = 300

		# Manually create frame state array.
		# Format: [position, velocity, surfaces, last_interaction_type,
		# last_interaction_frame_index, last_interaction_position,
		# last_interaction_velocity, frame_authority]
		var frame_state = ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO # position
		frame_state[1] = Vector2(100, 100) # velocity (will be replaced)
		frame_state[2] = 0 # surfaces
		frame_state[3] = CharacterStateFromServer.ServerInteractionType.NONE
		frame_state[4] = -1 # last_interaction_frame_index
		frame_state[5] = Vector2.ZERO # last_interaction_position
		frame_state[6] = Vector2.ZERO # last_interaction_velocity
		frame_state[7] = ReconcilableState.FrameAuthority.AUTHORITATIVE

		state._rollback_buffer.set_at(300, frame_state)

		# Set bump event with the actual bounce velocity (already computed).
		var bounce_velocity = Vector2(300.0, -200.0)
		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 300
		state.last_interaction_velocity = bounce_velocity

		# Reconcile.
		state._reconcile_server_interaction()

		# Verify velocity was set to the bounce velocity.
		var modified_state: Array = state._rollback_buffer.get_at(300)
		var velocity: Vector2 = modified_state[1] # Index 1 is velocity

		# Should have the stored bounce velocity directly.
		assert_almost_eq(
			velocity.x,
			bounce_velocity.x,
			1.0,
			"X velocity should match stored bounce velocity"
		)
		assert_almost_eq(
			velocity.y,
			bounce_velocity.y,
			1.0,
			"Y velocity should match stored bounce velocity"
		)

	func test_reconciliation_marks_bump_as_processed():
		Netcode.frame_driver.server_frame_index = 400

		# Manually create frame state array.
		var frame_state = ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO # position
		frame_state[1] = Vector2.ZERO # velocity
		frame_state[2] = 0 # surfaces
		frame_state[3] = CharacterStateFromServer.ServerInteractionType.NONE
		frame_state[4] = -1 # last_interaction_frame_index
		frame_state[5] = Vector2.ZERO # last_interaction_position
		frame_state[6] = Vector2.ZERO # last_interaction_velocity
		frame_state[7] = ReconcilableState.FrameAuthority.AUTHORITATIVE

		state._rollback_buffer.set_at(400, frame_state)

		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 400
		state.last_interaction_velocity = Vector2(0, -1)

		state._reconcile_server_interaction()

		assert_eq(
			state._last_reconciled_interaction_frame_index,
			400,
			"Bump should be marked as reconciled"
		)

	func test_reconciliation_uses_stored_velocity_directly():
		Netcode.frame_driver.server_frame_index = 500

		# Manually create frame state array.
		var frame_state = ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO # position
		frame_state[1] = Vector2.ZERO # velocity
		frame_state[2] = 0 # surfaces
		frame_state[3] = CharacterStateFromServer.ServerInteractionType.NONE
		frame_state[4] = -1 # last_interaction_frame_index
		frame_state[5] = Vector2.ZERO # last_interaction_position
		frame_state[6] = Vector2.ZERO # last_interaction_velocity
		frame_state[7] = ReconcilableState.FrameAuthority.AUTHORITATIVE

		state._rollback_buffer.set_at(500, frame_state)

		# Bump with pre-calculated velocity (as if direction was at 45 degrees).
		var direction = Vector2(1, -1).normalized()
		var bounce_velocity = direction * 300.0 + Vector2(0, -200.0)
		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 500
		state.last_interaction_velocity = bounce_velocity

		state._reconcile_server_interaction()

		var modified_state: Array = state._rollback_buffer.get_at(500)
		var velocity: Vector2 = modified_state[1] # Index 1 is velocity

		# Velocity should match the stored bounce velocity directly.
		assert_almost_eq(
			velocity.x,
			bounce_velocity.x,
			1.0,
			"X component should match stored velocity"
		)
		assert_almost_eq(
			velocity.y,
			bounce_velocity.y,
			1.0,
			"Y component should match stored velocity"
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
		default_values.append(ReconcilableState.FrameAuthority.PREDICTED)
		state._rollback_buffer = RollbackBuffer.new(
			90, # capacity (typical rollback buffer size)
			0, # current_frame_index
			default_values
		)

	func after_each():
		ArrayPool.clear_all_pools()
		if is_instance_valid(character):
			character.free()

	func test_reconciliation_with_zero_velocity():
		Netcode.frame_driver.server_frame_index = 600

		# Manually create frame state array.
		var frame_state = ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO # position
		frame_state[1] = Vector2.ZERO # velocity
		frame_state[2] = 0 # surfaces
		frame_state[3] = CharacterStateFromServer.ServerInteractionType.NONE
		frame_state[4] = -1 # last_interaction_frame_index
		frame_state[5] = Vector2.ZERO # last_interaction_position
		frame_state[6] = Vector2.ZERO # last_interaction_velocity
		frame_state[7] = ReconcilableState.FrameAuthority.AUTHORITATIVE

		state._rollback_buffer.set_at(600, frame_state)

		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 600
		state.last_interaction_velocity = Vector2.ZERO

		# Should not crash.
		state._reconcile_server_interaction()

		# Verify bump was marked as reconciled.
		assert_eq(
			state._last_reconciled_interaction_frame_index,
			600,
			"Bump should be marked as reconciled even with zero velocity"
		)

	func test_reconciliation_skips_missing_frame():
		Netcode.frame_driver.server_frame_index = 10000

		# Set bump at frame that doesn't exist in buffer.
		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 9999
		state.last_interaction_velocity = Vector2(1, 0)

		state._reconcile_server_interaction()

		# Should skip without error.
		assert_eq(
			state._last_reconciled_interaction_frame_index,
			9999,
			"Missing frame should be marked as processed"
		)

	func test_reconciliation_with_downward_bump_velocity():
		Netcode.frame_driver.server_frame_index = 700

		# Manually create frame state array.
		var frame_state = ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO # position
		frame_state[1] = Vector2.ZERO # velocity
		frame_state[2] = 0 # surfaces
		frame_state[3] = CharacterStateFromServer.ServerInteractionType.NONE
		frame_state[4] = -1 # last_interaction_frame_index
		frame_state[5] = Vector2.ZERO # last_interaction_position
		frame_state[6] = Vector2.ZERO # last_interaction_velocity
		frame_state[7] = ReconcilableState.FrameAuthority.AUTHORITATIVE

		state._rollback_buffer.set_at(700, frame_state)

		# Pre-calculated velocity: downward direction (0, 1) * 300 + vertical
		# boost (0, -200) = (0, 100).
		var bounce_velocity = Vector2(0, 100)
		state.last_interaction_type = \
			CharacterStateFromServer.ServerInteractionType.BUMP
		state.last_interaction_frame_index = 700
		state.last_interaction_velocity = bounce_velocity

		state._reconcile_server_interaction()

		var modified_state: Array = state._rollback_buffer.get_at(700)
		var velocity: Vector2 = modified_state[1] # Index 1 is velocity

		# Velocity should match the stored bounce velocity.
		assert_almost_eq(
			velocity.y,
			bounce_velocity.y,
			1.0,
			"Velocity should match stored bounce velocity"
		)
