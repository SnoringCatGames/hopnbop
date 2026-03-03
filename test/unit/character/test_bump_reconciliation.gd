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
		default_values.append(ReconcilableState.FrameAuthority.CLIENT_PREDICTED)
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
		# Buffer at server_frame has an old BUMP
		# interaction that's been superseded by a newer
		# one on the state.
		Netcode.frame_driver.server_frame_index = 50

		var frame_state := ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO
		frame_state[1] = Vector2.ZERO
		frame_state[2] = 0
		frame_state[3] = (
			CharacterStateFromServer
				.ServerInteractionType.BUMP)
		# Old interaction frame in the buffer.
		frame_state[4] = 40
		frame_state[5] = Vector2.ZERO
		frame_state[6] = Vector2(1, 0)
		frame_state[7] = (
			ReconcilableState
				.FrameAuthority.AUTHORITATIVE)

		state._rollback_buffer.set_at(
			50, frame_state)

		# State already has a newer interaction.
		state.last_interaction_frame_index = 45

		state._reconcile_server_interaction()

		# Stale check returns before updating
		# _last_reconciled_interaction_frame_index.
		assert_eq(
			state
				._last_reconciled_interaction_frame_index,
			-1,
			"Stale bump should not update reconciled"
			+ " frame",
		)

	func test_reconciliation_updates_state_from_buffer():
		# Buffer at server_frame has BUMP interaction
		# data. Reconciliation should update local state
		# properties from the buffer.
		Netcode.frame_driver.server_frame_index = 50

		var bounce_velocity := Vector2(300.0, -200.0)
		var frame_state := ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO
		frame_state[1] = Vector2.ZERO
		frame_state[2] = 0
		frame_state[3] = (
			CharacterStateFromServer
				.ServerInteractionType.BUMP)
		frame_state[4] = 50
		frame_state[5] = Vector2.ZERO
		frame_state[6] = bounce_velocity
		frame_state[7] = (
			ReconcilableState
				.FrameAuthority.AUTHORITATIVE)

		state._rollback_buffer.set_at(
			50, frame_state)

		state._reconcile_server_interaction()

		# State properties should be updated from
		# the buffer.
		assert_eq(
			state.last_interaction_type,
			(CharacterStateFromServer
				.ServerInteractionType.BUMP),
			"Interaction type updated from buffer",
		)
		assert_eq(
			state.last_interaction_frame_index,
			50,
			"Interaction frame updated from buffer",
		)
		assert_almost_eq(
			state.last_interaction_velocity.x,
			bounce_velocity.x,
			1.0,
			"Interaction velocity X updated from"
			+ " buffer",
		)
		assert_almost_eq(
			state.last_interaction_velocity.y,
			bounce_velocity.y,
			1.0,
			"Interaction velocity Y updated from"
			+ " buffer",
		)

	func test_reconciliation_marks_bump_as_processed():
		Netcode.frame_driver.server_frame_index = 50

		var frame_state := ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO
		frame_state[1] = Vector2.ZERO
		frame_state[2] = 0
		frame_state[3] = (
			CharacterStateFromServer
				.ServerInteractionType.BUMP)
		frame_state[4] = 50
		frame_state[5] = Vector2.ZERO
		frame_state[6] = Vector2(0, -1)
		frame_state[7] = (
			ReconcilableState
				.FrameAuthority.AUTHORITATIVE)

		state._rollback_buffer.set_at(
			50, frame_state)

		state._reconcile_server_interaction()

		assert_eq(
			state
				._last_reconciled_interaction_frame_index,
			50,
			"Bump should be marked as reconciled",
		)

	func test_reconciliation_preserves_stored_velocity():
		Netcode.frame_driver.server_frame_index = 50

		# Bump with pre-calculated velocity (as if
		# direction was at 45 degrees).
		var direction := Vector2(1, -1).normalized()
		var bounce_velocity := (
			direction * 300.0 + Vector2(0, -200.0))

		var frame_state := ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO
		frame_state[1] = Vector2.ZERO
		frame_state[2] = 0
		frame_state[3] = (
			CharacterStateFromServer
				.ServerInteractionType.BUMP)
		frame_state[4] = 50
		frame_state[5] = Vector2.ZERO
		frame_state[6] = bounce_velocity
		frame_state[7] = (
			ReconcilableState
				.FrameAuthority.AUTHORITATIVE)

		state._rollback_buffer.set_at(
			50, frame_state)

		state._reconcile_server_interaction()

		# State velocity should match the buffer's
		# interaction velocity.
		assert_almost_eq(
			state.last_interaction_velocity.x,
			bounce_velocity.x,
			1.0,
			"X component should match stored velocity",
		)
		assert_almost_eq(
			state.last_interaction_velocity.y,
			bounce_velocity.y,
			1.0,
			"Y component should match stored velocity",
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
		default_values.append(ReconcilableState.FrameAuthority.CLIENT_PREDICTED)
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
		Netcode.frame_driver.server_frame_index = 50

		var frame_state := ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO
		frame_state[1] = Vector2.ZERO
		frame_state[2] = 0
		frame_state[3] = (
			CharacterStateFromServer
				.ServerInteractionType.BUMP)
		frame_state[4] = 50
		frame_state[5] = Vector2.ZERO
		frame_state[6] = Vector2.ZERO
		frame_state[7] = (
			ReconcilableState
				.FrameAuthority.AUTHORITATIVE)

		state._rollback_buffer.set_at(
			50, frame_state)

		# Should not crash.
		state._reconcile_server_interaction()

		# Verify bump was marked as reconciled.
		assert_eq(
			state
				._last_reconciled_interaction_frame_index,
			50,
			"Bump should be reconciled even with"
			+ " zero velocity",
		)

	func test_reconciliation_skips_missing_frame():
		# Server frame points to frame not in buffer.
		Netcode.frame_driver.server_frame_index = 200

		state._reconcile_server_interaction()

		# Should skip without error. Reconciled frame
		# stays at default.
		assert_eq(
			state
				._last_reconciled_interaction_frame_index,
			-1,
			"Missing frame should not update"
			+ " reconciled index",
		)

	func test_reconciliation_with_downward_bump_velocity():
		Netcode.frame_driver.server_frame_index = 50

		# Pre-calculated velocity: downward direction
		# (0, 1) * 300 + vertical boost (0, -200) =
		# (0, 100).
		var bounce_velocity := Vector2(0, 100)

		var frame_state := ArrayPool.acquire(8)
		frame_state[0] = Vector2.ZERO
		frame_state[1] = Vector2.ZERO
		frame_state[2] = 0
		frame_state[3] = (
			CharacterStateFromServer
				.ServerInteractionType.BUMP)
		frame_state[4] = 50
		frame_state[5] = Vector2.ZERO
		frame_state[6] = bounce_velocity
		frame_state[7] = (
			ReconcilableState
				.FrameAuthority.AUTHORITATIVE)

		state._rollback_buffer.set_at(
			50, frame_state)

		state._reconcile_server_interaction()

		# State velocity should match the buffer's
		# interaction velocity.
		assert_almost_eq(
			state.last_interaction_velocity.y,
			bounce_velocity.y,
			1.0,
			"Velocity should match stored bounce"
			+ " velocity",
		)
