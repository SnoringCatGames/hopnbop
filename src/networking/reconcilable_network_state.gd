@tool
class_name ReconcilableNetworkedState
extends MultiplayerSynchronizer
## Base class for all networked entities that require client-side prediction
## with server-mismatch reconciliation and rollback support.
##
## ReconcilableNetworkedState is the foundation of the networking system,
## providing automatic state replication, client prediction, mismatch detection,
## and rollback reconciliation for any game entity. Subclasses define which
## properties to sync and how to integrate with the scene hierarchy.
##
## Architecture:
## This class bridges three systems:
## 1. **Godot MultiplayerSynchronizer**: Handles low-level replication of
##	  packed_state across network
## 2. **RollbackBuffer**: Stores historical states for time-travel during
##	  rollback
## 3. **NetworkFrameDriver**: Coordinates frame-synchronous simulation and
##	  rollback
##
## Server-authoritative vs client-authoritative:
## - **Server-authoritative** (default): Server is source of truth for entity
##   state (position, health, etc.)
## - **Client-authoritative**: Client is source of truth (used for player input)
##
## Typically used as a pair: one client-authoritative node for input, one
## server-authoritative node for all other state.
##
## Frame processing cycle (called by NetworkFrameDriver):
## 1. **_pre_network_process()**: Restore state from rollback buffer (frame N-1)
##	  and sync to scene
## 2. **_network_process()**: Game logic executes (implemented by subclass)
## 3. **_post_network_process()**: Pack state from scene back to properties and
##	  buffer
##
## Subclass requirements:
## - Define `_synced_properties_and_rollback_diff_thresholds` dictionary mapping
##   property names to mismatch thresholds
## - Implement `_get_default_values()` to return initial state
## - Implement `_sync_to_scene_state(previous_state)` to update scene from
##   networked properties
## - Implement `_sync_from_scene_state()` to update networked properties from
##   scene
## - Must be marked with @tool annotation
##
## Rollback reconciliation:
## When the server's authoritative state differs from client prediction beyond
## the configured threshold, a rollback is triggered:
## 1. State is restored to the mismatched frame
## 2. All frames from mismatch to present are re-simulated
## 3. Visual state smoothly interpolates (future: rollback visual interpolation)
##
## Thresholds (in _synced_properties_and_rollback_diff_thresholds):
## - Position: typically 1.0 pixel
## - Velocity: typically 10.0 pixels/sec
## - Boolean/String: exact match required (threshold N/A)
## - Numeric: absolute difference threshold
## - Vector2: distance_squared threshold
##
## Usage example:
## ```gdscript
## @tool
## class_name CharacterStateFromServer
## extends ReconcilableNetworkedState
##
## var position := Vector2.ZERO
## var velocity := Vector2.ZERO
##
## var _synced_properties_and_rollback_diff_thresholds := {
##	   "position": 1.0,
##	   "velocity": 10.0,
## }
##
## func _get_default_values() -> Array:
##  	 return [Vector2.ZERO, Vector2.ZERO]
##
## func _sync_to_scene_state(_previous_state: Array) -> void:
##	   root.position = position
##	   root.velocity = velocity
##
## func _sync_from_scene_state() -> void:
##	   position = root.position
##	   velocity = root.velocity
## ```

enum FrameAuthority {
	UNKNOWN,
	AUTHORITATIVE,
	PREDICTED,
}

signal received_network_state
signal network_processed
signal player_id_changed(new_player_id: int)

const DEFAULT_POSITION_DIFF_ROLLBACK_THRESHOLD := 1.0
const DEFAULT_VELOCITY_DIFF_ROLLBACK_THRESHOLD := 10.0

## The estimated server frame, when this state occurred.
var timestamp_index := 0

## Unified interaction system properties.
## Interaction type is an integer enum value (child classes define specific enums).
var last_interaction_type := 0:
	set(value):
		# FIXME: REMOVE - debug when DIE interaction is set
		if value == 4 and G.network.is_client: # 4 = DIE in ServerInteractionType
			G.print(
				">> last_interaction_type set to DIE (4) on client for node %s" % name
			)
		last_interaction_type = value
var last_interaction_frame_index := -1
var last_interaction_position := Vector2.ZERO
var last_interaction_direction := Vector2.ZERO

var _last_reconciled_interaction_frame_index := -1

## This identifies whether this data originated from an authoritative source.
var frame_authority := FrameAuthority.UNKNOWN

## If true, the server is the authoritative source of data for this state.
##
## This likely should only be false for input from the client.
var is_server_authoritative: bool:
	get:
		return _get_is_server_authoritative()

var is_client_authoritative: bool:
	get:
		return not _get_is_server_authoritative()

## This should contain the values for all of the properties of this state
## instance, packed (somewhat) efficiently for syncing across the network.
var packed_state := []:
	set(value):
		packed_state = value

		if not _is_packing_state_locally:
			_handle_new_authoritative_state()

var _is_packing_state_locally := false

var _property_names_for_packing: Array[StringName] = []
# Dictionary<StringName, int>
var _property_name_to_pack_index := {}

## Server-assigned player ID (integer).
##
## - This uniquely identifies a player across the entire game session.
## - Assigned by the server when spawning new networked nodes.
## - Local-only lobby players use negative IDs (-1, -2, -3, etc.).
var player_id: int = 0:
	set(value):
		if value != player_id:
			player_id = value

			# Only update authority if we have a valid peer mapping.
			# For remote players on clients, this mapping won't exist yet
			# during initial replication - it will be set later in
			# _on_player_joined(), which will call update_authority()
			# explicitly.
			if G.network.get_peer_id_from_player_id(value) != 0:
				update_authority()

			# Assign player_id on sibling nodes.
			if is_server_authoritative:
				if is_instance_valid(input_from_client):
					input_from_client.player_id = player_id
				if is_instance_valid(forwarded_input_from_server):
					forwarded_input_from_server.player_id = player_id

			player_id_changed.emit(player_id)

## Peer ID that owns this entity.
var peer_id: int:
	get:
		return G.network.get_peer_id_from_player_id(player_id)

## Local player index within the peer (0, 1, 2...).
var local_player_index: int:
	get:
		return G.network.get_local_player_index_from_player_id(player_id)

var authority_id: int:
	get:
		if is_server_authoritative:
			return NetworkConnector.SERVER_ID
		return peer_id

## Sibling nodes in the 3-node architecture for players:
## - state_from_server: CharacterStateFromServer (server-authoritative physics/position)
## - input_from_client: PlayerInputFromClient (client-authoritative local input)
## - forwarded_input_from_server: ForwardedPlayerInputFromServer (server-authoritative remote input)
##
## For NPCs, only state_from_server is present.
## For 2-node players (legacy), only state_from_server and input_from_client are present.
var state_from_server: CharacterStateFromServer:
	set(value):
		state_from_server = value
		_get_configuration_warnings()
var input_from_client: PlayerInputFromClient:
	set(value):
		input_from_client = value
		_get_configuration_warnings()
var forwarded_input_from_server: ForwardedPlayerInputFromServer:
	set(value):
		forwarded_input_from_server = value
		_get_configuration_warnings()

var _partner_state_configuration_warning := ""

var root: Node:
	get:
		return get_node_or_null(root_path)

var _rollback_buffer: RollbackBuffer


func _init() -> void:
	if Engine.is_editor_hint():
		return

	G.ensure(
		Utils.check_whether_sub_classes_are_tools(self),
		"Subclasses of ReconcilableNetworkedState must be marked with @tool")


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	G.network.frame_driver.add_networked_state(self)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return

	G.network.frame_driver.remove_networked_state(self)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_update_replication_config()
	_update_partner_state()
	update_configuration_warnings()

	if Engine.is_editor_hint():
		return

	if _rollback_buffer == null:
		_set_up_rollback_buffer()

	_parse_property_names()
	update_authority()


func _parse_property_names() -> void:
	_property_names_for_packing.assign(
		get("_synced_properties_and_rollback_diff_thresholds").keys(),
	)
	for i in range(_property_names_for_packing.size()):
		var property_name := _property_names_for_packing[i]
		_property_name_to_pack_index[property_name] = i


func update_authority() -> void:
	var previous_authority_id := get_multiplayer_authority()
	set_multiplayer_authority(authority_id)
	if previous_authority_id != authority_id:
		G.print(
			(
				"%s authority changed: %d -> %d "
				+"(server_auth=%s, peer_id=%d, is_local_auth=%s)"
			) % [
				name,
				previous_authority_id,
				authority_id,
				is_server_authoritative,
				peer_id,
				is_multiplayer_authority(),
			],
			ScaffolderLog.CATEGORY_NETWORK_SYNC)


func _handle_new_authoritative_state() -> void:
	if packed_state.is_empty():
		# Ignore any initial empty state.
		return

	var state_time_usec: int = _get_packed_timestamp_usec(packed_state)
	var state_frame_index := G.network.frame_driver.get_frame_index_from_time_usec(state_time_usec)

	# Extract the frame authority from the received state.
	var new_frame_authority: int = _get_packed_authority(packed_state)

	# FIXME: REMOVE - debug packed_state reception on clients
	if G.network.is_client and _property_names_for_packing.has(&"last_interaction_type"):
		var type_index := _property_names_for_packing.find(&"last_interaction_type")
		if type_index >= 0 and type_index < packed_state.size():
			var type_value = packed_state[type_index]
			if type_value != 0:
				G.print(
					">> _handle_new_authoritative_state: received packed_state with last_interaction_type=%d for frame %d, node=%s" % [
						type_value,
						state_frame_index,
						name,
					]
				)

	# PAUSE FILTERING: Reject states from after pause started.
	if G.network.frame_driver.is_paused:
		var pause_frame: int = G.network.frame_driver.pause_start_frame
		if state_frame_index > pause_frame:
			if G.is_verbose:
				G.verbose(
					"%s F:%d Rejecting state from frame %d (after pause at %d)" % [
						name,
						G.network.server_frame_index,
						state_frame_index,
						pause_frame,
					],
					ScaffolderLog.CATEGORY_NETWORK_SYNC)
			return

	if G.is_verbose:
		var authority_string: StringName = FrameAuthority.keys()[new_frame_authority]
		G.print("%s F:%d Received %s state for frame %d" %
			[
				name,
				G.network.server_frame_index,
				authority_string,
				state_frame_index,
			],
			ScaffolderLog.CATEGORY_NETWORK_SYNC)

	# Clients should ignore PREDICTED state from server-authoritative nodes entirely.
	# Only the server's AUTHORITATIVE state matters for reconciliation.
	# Exception: Some nodes (like ForwardedPlayerInputFromServer) need PREDICTED
	# states because they have no local prediction alternative.
	if (
		is_server_authoritative
		and G.network.is_client
		and new_frame_authority == FrameAuthority.PREDICTED
		and not _should_accept_predicted_states()
	):
		if G.is_verbose:
			G.print(
				"%s F:%d Ignoring PREDICTED server state for frame %d" %
				[
					name,
					G.network.server_frame_index,
					state_frame_index,
				],
				ScaffolderLog.CATEGORY_NETWORK_SYNC)
		return

	if G.network.frame_driver.is_frame_too_old_to_consider(state_frame_index):
		G.warning(
			(
				"Received networked state that is too old to reconcile - "
				+"DISCARDING: state frame: %d, state time: %d, local frame: %d, "
				+"local time: %d, oldest acceptable: %d"
			) % [
				state_frame_index,
				state_time_usec,
				G.network.server_frame_index,
				G.network.server_frame_time_usec,
				G.network.frame_driver.oldest_rollbackable_frame_index,
			],
			ScaffolderLog.CATEGORY_NETWORK_SYNC)
		return

	var should_trigger_fast_forward := (
		G.network.server_frame_index < state_frame_index - 1 and G.network.is_client
	)
	var is_more_than_one_frame_ahead := G.network.server_frame_index < state_frame_index - 2

	# Server rejects client states that are too far in the future (2+ frames ahead).
	# This likely indicates a bug or malicious client.
	if G.network.is_server and is_more_than_one_frame_ahead:
		G.warning(
			(
				"Rejecting too-distant-future state from client: "
				+"state frame %d, server frame %d"
			) % [state_frame_index, G.network.server_frame_index],
			ScaffolderLog.CATEGORY_NETWORK_SYNC)
		return

	# Unpack if state is for current frame, next frame, or past. State for the
	# next frame is valid when received between physics ticks.
	var should_unpack_state := state_frame_index >= G.network.server_frame_index
	var should_check_for_prediction_mismatch := (
		state_frame_index < G.network.server_frame_index
		and _rollback_buffer.has_at(state_frame_index)
		and new_frame_authority == FrameAuthority.AUTHORITATIVE
	)

	if should_check_for_prediction_mismatch:
		var mismatched_properties := _get_mismatched_properties(packed_state, state_frame_index)
		if not mismatched_properties.is_empty():
			var buffer_state: Array = _rollback_buffer.get_at(state_frame_index)
			var node_type := "state-from-server" if is_server_authoritative else "state-from-client"
			var mismatch_details := _get_mismatch_details_string(
				mismatched_properties,
				packed_state,
				buffer_state,
			)
			G.verbose(
				"Prediction state mismatch (%s): %s" %
				[node_type, mismatch_details],
				ScaffolderLog.CATEGORY_NETWORK_SYNC)

			G.network.frame_driver.queue_rollback(state_frame_index)

		# Release the array back to pool
		ArrayPool.release(mismatched_properties)

	# Record rollback buffer frame.
	_pack_buffer_state_from_network_state(packed_state)

	if should_unpack_state:
		# Record local class properties.
		_unpack_networked_state()
		frame_authority = new_frame_authority as FrameAuthority

	received_network_state.emit()

	# If we have skipped frames, we need to force the entire system to
	# fast-forward.
	if should_trigger_fast_forward:
		G.print(
			"Fast-forwarding due to future state from server",
			ScaffolderLog.CATEGORY_NETWORK_SYNC)

		# Adjust the time tracker's clock offset to account for the drift.
		# This prevents the NTP averaging from reverting the fast-forward by
		# also adjusting all NTP samples. The force_clock_offset method
		# updates both the current offset and all historical samples to
		# maintain consistency.
		var frames_behind := state_frame_index - 1 - G.network.server_frame_index
		var time_delta_usec := floori(
			frames_behind * G.network.frame_driver.TARGET_NETWORK_TIME_STEP_USEC,
		)
		G.network.time.force_clock_offset(time_delta_usec)

		G.network.frame_driver.fast_forward(state_frame_index - 1)


func _network_process() -> void:
	network_processed.emit()


## This is called before _network_process is called on any nodes.
func _pre_network_process() -> void:
	# Initialize rollback buffer on first frame processing if not already done.
	# This happens on clients after time synchronization is complete.
	if _rollback_buffer == null:
		_set_up_rollback_buffer()
		# If still null, time isn't initialized yet - skip this frame.
		if _rollback_buffer == null:
			return

	timestamp_index = G.network.server_frame_index
	frame_authority = FrameAuthority.UNKNOWN

	G.check(
		_rollback_buffer.get_latest_index() >= timestamp_index - 2,
		("Rollback buffer missing required frame: " +
		"current=%d, needs=%d, latest=%d") %
		[
			timestamp_index,
			timestamp_index - 2,
			_rollback_buffer.get_latest_index(),
		])

	# We're about to simulate frame N. Start by loading frame N-1's final state
	# as our starting point, and provide frame N-2 as "previous" for just_*
	# comparisons (e.g., just_pressed, just_touched).
	_unpack_buffer_state(timestamp_index - 1)

	var previous_frame_state = _rollback_buffer.get_at(timestamp_index - 2)
	if previous_frame_state == null:
		# For very early frames, use default values as "previous" state.
		previous_frame_state = _get_default_values()
	_sync_to_scene_state(previous_frame_state)


## This is called after _network_process has been called on all relevant nodes.
func _post_network_process() -> void:
	# Skip if rollback buffer isn't initialized yet (client before time sync).
	if _rollback_buffer == null:
		return

	_sync_from_scene_state()

	# Authority peers send their state over the network.
	if is_multiplayer_authority():
		_pack_networked_state()

	# All peers (authority and non-authority) pack local state into rollback
	# buffer to maintain buffer continuity. Non-authority peers will later
	# overwrite these frames with authoritative state when it arrives via
	# _pack_buffer_state_from_network_state().
	_pack_buffer_state_from_local_state()


func _get_is_server_authoritative() -> bool:
	G.fatal(
		"Abstract ReconcilableNetworkState._get_is_server_authoritative is not implemented")
	return true


## Virtual method: whether this node should accept PREDICTED states from the
## server. Defaults to false (only accept AUTHORITATIVE states).
## Override to return true for nodes that need server predictions (like
## ForwardedPlayerInputFromServer, which has no local prediction alternative).
func _should_accept_predicted_states() -> bool:
	return false


func _get_default_values() -> Array:
	G.fatal(
		"Abstract ReconcilableNetworkState._get_default_values is not implemented")
	return []


## This will update the surrounding scene state to match the networked state.
func _sync_to_scene_state(_previous_state: Array) -> void:
	G.fatal(
		"Abstract ReconcilableNetworkState._sync_to_scene_state is not implemented"
	)


## This will update the networked state to match the surrounding scene state.
func _sync_from_scene_state() -> void:
	G.fatal(
		"Abstract ReconcilableNetworkState._sync_from_scene_state is not implemented"
	)


func _update_replication_config() -> void:
	if Engine.is_editor_hint():
		return

	if not G.ensure(is_instance_valid(root)):
		return

	var packed_state_path := "%s:packed_state" % root.get_path_to(self)
	if not replication_config.has_property(packed_state_path):
		replication_config.add_property(packed_state_path)


func _set_up_rollback_buffer() -> void:
	# Don't initialize the rollback buffer until time is synchronized.
	# On clients, server_frame_index will be 0 until we receive the server's
	# time offset, which could cause the buffer to be initialized for the wrong
	# frame range.
	if not G.network.time.is_time_initialized:
		return

	var default_values := _get_default_values().duplicate()
	default_values.append(FrameAuthority.PREDICTED)

	_rollback_buffer = RollbackBuffer.new(
		G.network.frame_driver.rollback_buffer_size,
		G.network.frame_driver.server_frame_index,
		default_values,
	)


func _has_authoritative_state_for_current_frame() -> bool:
	if not _rollback_buffer.has_at(G.network.server_frame_index):
		return false
	var frame_data: Array = _rollback_buffer.get_at(G.network.server_frame_index)
	return frame_data[frame_data.size() - 1] == FrameAuthority.AUTHORITATIVE


func _pack_networked_state() -> void:
	var state := ArrayPool.acquire(_property_names_for_packing.size() + 2)

	var i := 0
	for property_name in _property_names_for_packing:
		state[i] = get(property_name)
		i += 1
	state[i] = frame_authority
	i += 1
	# We send time values across the network, but we store indices.
	state[i] = G.network.frame_driver.get_time_usec_from_frame_index(timestamp_index)
	_is_packing_state_locally = true

	# FIXME: REMOVE - debug interaction packing
	if G.network.is_server and last_interaction_type != 0:
		G.print(
			">> _pack_networked_state: last_interaction_type=%d, frame=%d, node=%s" % [
				last_interaction_type,
				last_interaction_frame_index,
				name,
			]
		)

	if G.is_verbose:
		var authority_string: StringName = FrameAuthority.keys()[frame_authority]
		if not is_server_authoritative:
				G.print(
					"%s F:%d Packed client-auth state (%s)" %
					[
						name,
						G.network.server_frame_index,
						authority_string,
					],
					ScaffolderLog.CATEGORY_NETWORK_SYNC)
		else:
			G.print(
				"%s F:%d Packed server-auth state (%s)" %
				[
					name,
					G.network.server_frame_index,
					authority_string,
				],
				ScaffolderLog.CATEGORY_NETWORK_SYNC)

	if not packed_state.is_empty():
		ArrayPool.release(packed_state)

	packed_state = state
	_is_packing_state_locally = false


func _unpack_networked_state() -> void:
	# Empty packed_state is expected and normal during initial sync. When a
	# ReconcilableNetworkedState is first created, MultiplayerSynchronizer may
	# trigger a sync before we've packed any state.
	if packed_state.is_empty():
		return

	if not G.ensure(
			packed_state.size() == _property_names_for_packing.size() + 2):
		return

	# FIXME: REMOVE - debug interaction unpacking before setting
	if G.network.is_client and _property_names_for_packing.has(&"last_interaction_type"):
		var type_index := _property_names_for_packing.find(&"last_interaction_type")
		var type_value = packed_state[type_index]
		if type_value != 0:
			G.print(
				">> _unpack_networked_state BEFORE set: packed_state[%d]=%d (last_interaction_type), node=%s" % [
					type_index,
					type_value,
					name,
				]
			)

	var i := 0
	for property_name in _property_names_for_packing:
		set(property_name, packed_state[i])
		i += 1
	# Skip frame_authority (at index i) - we handle it separately in _handle_new_authoritative_state
	i += 1
	# We send time values across the network, but we store indices.
	var timestamp_usec: int = _get_packed_timestamp_usec(packed_state)
	timestamp_index = G.network.frame_driver.get_frame_index_from_time_usec(timestamp_usec)

	# FIXME: REMOVE - debug interaction unpacking after setting
	if G.network.is_client and last_interaction_type != 0:
		G.print(
			">> _unpack_networked_state AFTER set: last_interaction_type=%d, frame=%d, node=%s" % [
				last_interaction_type,
				last_interaction_frame_index,
				name,
			]
		)


func _pack_buffer_state_from_local_state() -> void:
	var state := ArrayPool.acquire(_property_names_for_packing.size() + 1)

	var i := 0
	for property_name in _property_names_for_packing:
		state[i] = get(property_name)
		i += 1
	state[i] = frame_authority

	# Note: state is now owned by the rollback buffer, don't release it here.
	_record_buffer_frame(timestamp_index, state)


## Records the current state in the rollback buffer at the current simulated
## frame index.
##
## This does _not_ record state in the packed_state array for syncing across the
## network.
func _pack_buffer_state_from_network_state(packed_network_state: Array) -> void:
	var state_time_usec: int = _get_packed_timestamp_usec(packed_network_state)
	var new_frame_authority: int = _get_packed_authority(packed_network_state)
	var frame_index := G.network.frame_driver.get_frame_index_from_time_usec(state_time_usec)

	# For the rollback buffer, we use the same state layout as the network state,
	# but we replace the timestamp with the frame_authority from the sender.
	var rollback_frame_state := ArrayPool.acquire(packed_network_state.size() - 1)

	for i in range(packed_network_state.size() - 2):
		rollback_frame_state[i] = packed_network_state[i]
	rollback_frame_state[rollback_frame_state.size() - 1] = new_frame_authority

	# Note: rollback_frame_state is now owned by the rollback buffer, don't
	#	   release it here.
	_record_buffer_frame(frame_index, rollback_frame_state)


func _record_buffer_frame(frame_index: int, frame_state: Array) -> void:
	# TODO: When updating frame buffer state later, reference the preexisting
	#	   frame array, rather than instantiating a new one.
	# Guard against null rollback buffer (For tests: can occur if time isn't
	# initialized yet when record_initial_state() is called during _ready()).
	if _rollback_buffer == null:
		# Release the frame_state array since we can't store it
		ArrayPool.release(frame_state)
		return

	_rollback_buffer.backfill_to_with_last_state(frame_index - 1)

	_rollback_buffer.set_at(frame_index, frame_state)


## Clean up rollback buffer state after pause started.
##
## Back-fills all frames after the pause frame with the pause frame's state
## marked as PREDICTED. This prevents mismatch detection from comparing
## pre-pause server state with invalid post-pause client predictions.
func _cleanup_buffer_after_pause(pause_frame: int) -> void:
	# Get pause frame state.
	if not _rollback_buffer.has_at(pause_frame):
		return

	var pause_state: Array = _rollback_buffer.get_at(pause_frame)

	# Create a copy marked as PREDICTED for resetting.
	var fill_state := ArrayPool.acquire(pause_state.size())
	for i in range(pause_state.size() - 1):
		fill_state[i] = pause_state[i]
	fill_state[fill_state.size() - 1] = FrameAuthority.PREDICTED

	# Reset from pause_frame+1 to current latest.
	var latest := _rollback_buffer.get_latest_index()
	for frame_index in range(pause_frame + 1, latest + 1):
		var frame_state := ArrayPool.acquire(fill_state.size())
		for i in range(fill_state.size()):
			frame_state[i] = fill_state[i]
		_rollback_buffer.set_at(frame_index, frame_state)

	ArrayPool.release(fill_state)


## Records the initial spawn state to the rollback buffer for the current
## frame and previous frames.
##
## This should be called (deferred) after _ready() completes to ensure the
## ReconcilableNetworkedState's _ready() has finished setting up the buffer.
## It prevents _pre_network_process from loading default zero values from the
## buffer on the first frame by pre-populating frames N-2, N-1, and N.
##
## All frames are marked as PREDICTED so authoritative state from the server
## can overwrite them.
##
## If include_partners is true (default), this will also record the initial
## state for the partner node if one exists (e.g., the client-authoritative
## input state paired with a server-authoritative character state).
func record_initial_state(include_partners := true) -> void:
	var current_frame := G.network.server_frame_index

	# Sync the current scene state to the networked properties
	_sync_from_scene_state()

	# Create the initial state array with current property values
	var initial_state := ArrayPool.acquire(
		_property_names_for_packing.size() + 1,
	)
	var i := 0
	for property_name in _property_names_for_packing:
		initial_state[i] = get(property_name)
		i += 1
	initial_state[i] = FrameAuthority.PREDICTED

	# Record for N-2, N-1, and N
	for frame_offset in range(-2, 1):
		var target_frame := current_frame + frame_offset
		var frame_state := ArrayPool.acquire(initial_state.size())
		for j in range(initial_state.size()):
			frame_state[j] = initial_state[j]
		_record_buffer_frame(target_frame, frame_state)

	ArrayPool.release(initial_state)

	# Also initialize the partner state if present
	if include_partners:
		# Record initial state for all sibling nodes.
		if is_instance_valid(state_from_server):
			state_from_server.record_initial_state(false)
		if is_instance_valid(input_from_client):
			input_from_client.record_initial_state(false)
		if is_instance_valid(forwarded_input_from_server):
			forwarded_input_from_server.record_initial_state(false)


func _unpack_buffer_state(frame_index: int) -> void:
	var frame_state = _rollback_buffer.get_at(frame_index)

	# If no state exists for this frame (early in simulation or during
	# fast-forward), return early. The current state will be used as-is.
	if frame_state == null:
		return

	var i := 0
	for property_name in _property_names_for_packing:
		set(property_name, frame_state[i])
		i += 1
	frame_authority = frame_state[i]


## Gets a property value from a frame state array by property name.
func _get_frame_property(frame_state: Array, property_name: StringName) -> Variant:
	var pack_index: int = _property_name_to_pack_index[property_name]
	return frame_state[pack_index]


## Sets a property value in a frame state array by property name.
func _set_frame_property(
	frame_state: Array,
	property_name: StringName,
	value: Variant
) -> void:
	var pack_index: int = _property_name_to_pack_index[property_name]
	frame_state[pack_index] = value


## Gets the frame authority from a frame state array (rollback buffer format).
func _get_frame_authority(frame_state: Array) -> FrameAuthority:
	var authority_idx := frame_state.size() - 1
	return frame_state[authority_idx] as FrameAuthority


## Sets the frame authority in a frame state array (rollback buffer format).
func _set_frame_authority(
	frame_state: Array,
	authority: FrameAuthority
) -> void:
	var authority_idx := frame_state.size() - 1
	frame_state[authority_idx] = authority


## Checks if a frame state has authoritative authority.
func _is_frame_authoritative(frame_state: Array) -> bool:
	return _get_frame_authority(frame_state) == FrameAuthority.AUTHORITATIVE


## Checks if a frame state has predicted authority.
func _is_frame_predicted(frame_state: Array) -> bool:
	return _get_frame_authority(frame_state) == FrameAuthority.PREDICTED


## Gets the timestamp from a packed_state array (network format).
func _get_packed_timestamp_usec(packed_network_state: Array) -> int:
	return packed_network_state[packed_network_state.size() - 1]


## Gets the frame authority from a packed_state array (network format).
func _get_packed_authority(packed_network_state: Array) -> FrameAuthority:
	var authority_idx := packed_network_state.size() - 2
	return packed_network_state[authority_idx] as FrameAuthority


## Returns an array of property names that have mismatched values between
## networked state and local buffer state.
##
## Uses ArrayPool to reduce allocations since this is called frequently on the
## network hot path. Caller is responsible for releasing the array.
func _get_mismatched_properties(
	networked_state: Array,
	frame_index: int,
) -> Array:
	var buffer_data: Array = _rollback_buffer.get_at(frame_index)
	var thresholds: Dictionary = get("_synced_properties_and_rollback_diff_thresholds")

	# Pre-allocate for worst case (all properties mismatched)
	var mismatched := ArrayPool.acquire(thresholds.size())
	var mismatch_count := 0

	for property_name in thresholds:
		var threshold = thresholds[property_name]
		var pack_index: int = _property_name_to_pack_index[property_name]
		var networked_value = networked_state[pack_index]
		var buffer_value = buffer_data[pack_index]
		if _check_do_values_mismatch(buffer_value, networked_value, threshold):
			mismatched[mismatch_count] = property_name
			mismatch_count += 1

	# Trim to actual size
	mismatched.resize(mismatch_count)
	return mismatched


## Returns a formatted string showing only the mismatched properties and their
## values from both networked and local buffer state.
func _get_mismatch_details_string(
	mismatched_properties: Array,
	networked_state: Array,
	buffer_state: Array,
) -> String:
	var details: Array[String] = []
	for property_name in mismatched_properties:
		var pack_index: int = _property_name_to_pack_index[property_name]
		var networked_value = networked_state[pack_index]
		var buffer_value = buffer_state[pack_index]
		var networked_str := _get_string_for_value(networked_value)
		var buffer_str := _get_string_for_value(buffer_value)
		details.append(
			"{%s: remote=%s, local=%s}" %
			[property_name, networked_str, buffer_str],
		)

	return ", ".join(details)


func _check_do_values_mismatch(
	buffer_value: Variant,
	networked_value: Variant,
	threshold: Variant,
) -> bool:
	match typeof(buffer_value):
		TYPE_BOOL, TYPE_STRING:
			return buffer_value != networked_value
		TYPE_INT, TYPE_FLOAT:
			if threshold == 0:
				# Threshold of 0 means exact match required
				return buffer_value != networked_value
			else:
				return abs(buffer_value - networked_value) >= threshold
		TYPE_VECTOR2, TYPE_VECTOR2I:
			if threshold == 0:
				# Threshold of 0 means exact match required
				return buffer_value != networked_value
			else:
				return buffer_value.distance_squared_to(networked_value) >= threshold * threshold
		_:
			G.fatal(
				"Type not yet supported for client-prediction mismatch threshold calculations: %s" %
				type_string(buffer_value))
			return true


func _update_partner_state() -> void:
	if not is_node_ready():
		# Don't try parsing siblings until we're actually in the tree.
		return

	# Clear all sibling references.
	state_from_server = null
	input_from_client = null
	forwarded_input_from_server = null

	# Collect all sibling ReconcilableNetworkedState nodes and categorize them.
	var sibling_states: Array[ReconcilableNetworkedState] = []
	for child in get_parent().get_children():
		if child is ReconcilableNetworkedState and child != self:
			sibling_states.append(child)

			# Populate named properties based on node type.
			if child is CharacterStateFromServer:
				state_from_server = child as CharacterStateFromServer
			elif child is PlayerInputFromClient:
				input_from_client = child as PlayerInputFromClient
			elif child is ForwardedPlayerInputFromServer:
				forwarded_input_from_server = child as ForwardedPlayerInputFromServer

	# Validate the node configuration.
	# Only 1-node or 3-node (client-controlled player) are valid.
	if sibling_states.size() == 0:
		# Valid 1-node setup (NPC with only CharacterStateFromServer).
		if is_client_authoritative:
			_partner_state_configuration_warning = ("A client-authoritative ReconcilableNetworkedState node must be accompanied by a server-authoritative ReconcilableNetworkedState sibling node")
	elif sibling_states.size() == 1:
		# Invalid 2-node setup. Players now require the full 3-node setup.
		_partner_state_configuration_warning = (
			"Either CharacterStateFromServer must be by itself, or there "
			+"must be three nodes (for client-controlled players): "
			+"CharacterStateFromServer + PlayerInputFromClient + "
			+"ForwardedPlayerInputFromServer"
		)
	elif sibling_states.size() == 2:
		# 3-node configuration: 1 client-auth + 2 server-auth.
		var client_auth_count := 0
		var server_auth_count := 0

		# Count self.
		if is_client_authoritative:
			client_auth_count += 1
		else:
			server_auth_count += 1

		# Count siblings.
		for sibling in sibling_states:
			if sibling.is_client_authoritative:
				client_auth_count += 1
			else:
				server_auth_count += 1

		# Validate configuration: must be 1 client + 2 server (including self).
		if client_auth_count == 1 and server_auth_count == 2:
			# Valid 3-node setup.
			# Validate that we found the two expected sibling types.
			# (The third type is self, so it won't be in the sibling list.)
			if self is CharacterStateFromServer:
				# Self is CharacterStateFromServer, so we need the other two as siblings.
				if input_from_client == null or forwarded_input_from_server == null:
					_partner_state_configuration_warning = ("CharacterStateFromServer requires PlayerInputFromClient and ForwardedPlayerInputFromServer siblings")
			elif self is PlayerInputFromClient:
				# Self is PlayerInputFromClient, so we need the other two as siblings.
				if state_from_server == null or forwarded_input_from_server == null:
					_partner_state_configuration_warning = ("PlayerInputFromClient requires CharacterStateFromServer and ForwardedPlayerInputFromServer siblings")
			elif self is ForwardedPlayerInputFromServer:
				# Self is ForwardedPlayerInputFromServer, so we need the other two as siblings.
				if state_from_server == null or input_from_client == null:
					_partner_state_configuration_warning = ("ForwardedPlayerInputFromServer requires CharacterStateFromServer and PlayerInputFromClient siblings")
			else:
				_partner_state_configuration_warning = "" # Valid 3-node setup.
		else:
			_partner_state_configuration_warning = ("3-node configuration requires exactly 1 client-authoritative and 2 server-authoritative nodes")
	elif sibling_states.size() > 2:
		_partner_state_configuration_warning = ("There should be no more than 3 ReconcilableNetworkedState nodes (1 client-auth + 2 server-auth for Player, or 1 server-auth for NPC)")

	if not Engine.is_editor_hint() and not _partner_state_configuration_warning.is_empty():
		# Log and assert in game runtime environments.
		G.error(
			"ReconcilableNetworkedState is misconfigured: %s" %
			_partner_state_configuration_warning,
			ScaffolderLog.CATEGORY_CORE_SYSTEMS)

	# Also refresh sibling ReconcilableNetworkedState warnings.
	# Trigger configuration warning updates on all siblings.
	if is_instance_valid(state_from_server):
		state_from_server.update_configuration_warnings()
	if is_instance_valid(input_from_client):
		input_from_client.update_configuration_warnings()
	if is_instance_valid(forwarded_input_from_server):
		forwarded_input_from_server.update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []

	var thresholds = get("_synced_properties_and_rollback_diff_thresholds")

	if thresholds == null:
		warnings.append(
			"A _synced_properties_and_rollback_diff_thresholds property must be defined on subclasses of ReconcilableNetworkedState",
		)
	elif not thresholds is Dictionary:
		warnings.append(
			"The _synced_properties_and_rollback_diff_thresholds property must be a Dictionary",
		)
	else:
		# Check if _synced_properties_and_rollback_diff_thresholds matches the other properties.
		for property_name in thresholds.keys():
			if get(property_name) == null:
				warnings.append(
					("Key %s in _synced_properties_and_rollback_diff_thresholds " +
					"does not match any class property") % property_name,
				)

	if root_path.is_empty():
		warnings.append("root_path must be defined")
	elif not is_instance_valid(root):
		warnings.append("root_path does not point to a valid node")
	elif not _partner_state_configuration_warning.is_empty():
		warnings.append(_partner_state_configuration_warning)

	return warnings


func get_string_for_packed_state(state: Array) -> String:
	var tokens: Array[String] = []
	tokens.resize(state.size())
	var i := 0
	for value in state:
		tokens[i] = _get_string_for_value(value, i == state.size() - 1)
		i += 1

	return "[%s]" % ",".join(tokens)


func _get_string_for_value(value, is_final_value := false) -> String:
	match typeof(value):
		TYPE_BOOL, TYPE_STRING:
			return str(value)
		TYPE_INT:
			# By default, we display int values as bitmasks.
			if is_final_value:
				return str(value)
			return _get_string_for_bitmask(value)
		TYPE_FLOAT:
			return "%.1f" % value
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return Utils.get_vector_string(value, 1)
		_:
			G.fatal(
				"Type not yet supported for rollback buffer: %s" %
				type_string(value))
			return ""


func _get_string_for_bitmask(value: int) -> String:
	return String.num_int64(value, 2).lpad(8, "0")


## Converts a timestamp in microseconds to a frame index.
## Returns -1 if the timestamp is invalid (< 0).
func _get_interaction_frame_from_time(time_usec: int) -> int:
	if time_usec < 0:
		return -1
	return G.network.frame_driver.get_frame_index_from_time_usec(time_usec)


## Records an interaction by setting all interaction properties at once.
## This is a convenience method to avoid repetitive property assignments.
func record_interaction(
	interaction_type: int,
	frame_index: int,
	position: Vector2,
	direction: Vector2
) -> void:
	last_interaction_type = interaction_type
	last_interaction_frame_index = (
		frame_index if frame_index >= 0 else G.network.server_frame_index
	)
	last_interaction_position = position
	last_interaction_direction = direction


## Validates whether an interaction should be reconciled.
## Checks: frame not already processed, not too old, exists in buffer (in the
## future).
func _should_reconcile_interaction(
	interaction_frame: int,
	last_reconciled_frame: int
) -> bool:
	if interaction_frame <= last_reconciled_frame:
		return false
	if G.network.frame_driver.is_frame_too_old_to_consider(interaction_frame):
		G.warning(
			"Interaction too old to reconcile: frame %d" % interaction_frame,
			ScaffolderLog.CATEGORY_NETWORK_SYNC,
		)
		return false
	if not _rollback_buffer.has_at(interaction_frame):
		return false
	return true
