class_name StateBundler
extends Node
## Bundles per-frame ReconcilableState into single
## packets to reduce SCTP packet count for WebRTC.
##
## Without bundling, each ReconcilableState node sends
## its own packet via MultiplayerSynchronizer. With 4
## players and 3 state types each, that is 12+ packets
## per tick. SCTP congestion control throttles at high
## packet rates regardless of individual packet size.
##
## StateBundler collects all per-frame state and sends
## one packet per peer per tick, reducing packet count
## from 12+ to 1.


## Cached node lookup by (entity_type, player_id) for
## fast dispatch on receive. Cleared when players
## join or leave.
var _node_lookup: Dictionary = {}


## Collect pending states from all nodes, serialize
## into bundles, and send to peers.
func _send_bundles() -> void:
	var nodes: Array[ReconcilableState] = (
		Netcode.frame_driver._networked_state_nodes
	)

	# Collect all pending states and pre-serialize.
	var entries: Array = []
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var states: Array = (
			node.consume_pending_bundle_states()
		)
		if states.is_empty():
			continue
		for state in states:
			var state_bytes := var_to_bytes(state)
			ArrayPool.release(state)
			entries.append({
				"type": node._get_type(),
				"player_id": node.player_id,
				"state_bytes": state_bytes,
				"peer_id": node.peer_id,
			})

	if entries.is_empty():
		return

	if Netcode.runs_server_logic:
		_send_server_bundles(entries)
	elif Netcode.is_client:
		_send_client_bundle(entries)


func _send_server_bundles(
	entries: Array,
) -> void:
	var peer_ids := multiplayer.get_peers()
	for target_peer_id in peer_ids:
		var bundle := _build_bundle_for_peer(
			entries, target_peer_id,
		)
		if bundle.is_empty():
			continue
		_client_rpc_receive_bundle.rpc_id(
			target_peer_id, bundle,
		)


func _send_client_bundle(
	entries: Array,
) -> void:
	var bundle := _build_bundle_all(entries)
	if bundle.is_empty():
		return
	_server_rpc_receive_input_bundle.rpc_id(
		NetworkConnector.SERVER_ID, bundle,
	)


## Build a bundle for a specific peer, filtering
## out ForwardedInput entries owned by that peer.
func _build_bundle_for_peer(
	entries: Array,
	target_peer_id: int,
) -> PackedByteArray:
	var filtered: Array = []
	for entry in entries:
		var is_forwarded: bool = (
			entry.type
			== ReconcilableState
				.ReconcilableStateType
				.FORWARDED_INPUT
		)
		if (
			is_forwarded
			and entry.peer_id == target_peer_id
		):
			continue
		filtered.append(entry)

	return _serialize_entries(filtered)


## Build a bundle from all entries (no filtering).
func _build_bundle_all(
	entries: Array,
) -> PackedByteArray:
	return _serialize_entries(entries)


## Serialize entries into a PackedByteArray bundle.
##
## Format:
##   [1 byte: entity_count]
##   For each entity:
##     [1 byte: entity_type]
##     [1 byte: player_id (unsigned)]
##     [2 bytes: data_length (little-endian)]
##     [data_length bytes: var_to_bytes data]
func _serialize_entries(
	entries: Array,
) -> PackedByteArray:
	if entries.is_empty():
		return PackedByteArray()

	var bundle := PackedByteArray()
	bundle.append(entries.size())
	for entry in entries:
		bundle.append(entry.type)
		bundle.append(entry.player_id & 0xFF)
		var state_bytes: PackedByteArray = (
			entry.state_bytes
		)
		var length := state_bytes.size()
		bundle.append(length & 0xFF)
		bundle.append((length >> 8) & 0xFF)
		bundle.append_array(state_bytes)

	return bundle


@rpc(
	"authority", "call_remote", "unreliable",
	NetworkConnector.RPC_CHANNEL_DEFAULT,
)
func _client_rpc_receive_bundle(
	bundle_data: PackedByteArray,
) -> void:
	_unpack_and_dispatch(bundle_data)


@rpc(
	"any_peer", "call_remote", "unreliable",
	NetworkConnector.RPC_CHANNEL_DEFAULT,
)
func _server_rpc_receive_input_bundle(
	bundle_data: PackedByteArray,
) -> void:
	_unpack_and_dispatch(bundle_data)


## Unpack a bundle and dispatch each entity's state
## to the corresponding ReconcilableState node.
func _unpack_and_dispatch(
	bundle_data: PackedByteArray,
) -> void:
	if bundle_data.size() < 1:
		return

	var offset := 0
	var entity_count: int = bundle_data[offset]
	offset += 1

	for _i in entity_count:
		# Need at least 4 bytes for header.
		if offset + 4 > bundle_data.size():
			Netcode.log.warning(
				"StateBundler: bundle truncated"
				+ " at entity header",
				NetworkLogger
					.CATEGORY_NETWORK_SYNC,
			)
			return

		var entity_type: int = (
			bundle_data[offset]
		)
		offset += 1

		var player_id_byte: int = (
			bundle_data[offset]
		)
		offset += 1
		# Convert unsigned byte to signed.
		var player_id: int = (
			player_id_byte
			if player_id_byte < 128
			else player_id_byte - 256
		)

		var data_length: int = (
			bundle_data[offset]
			| (bundle_data[offset + 1] << 8)
		)
		offset += 2

		if offset + data_length > bundle_data.size():
			Netcode.log.warning(
				"StateBundler: entity data"
				+ " truncated",
				NetworkLogger
					.CATEGORY_NETWORK_SYNC,
			)
			return

		var state_bytes := bundle_data.slice(
			offset, offset + data_length,
		)
		offset += data_length

		var state: Variant = (
			bytes_to_var(state_bytes)
		)
		if not (state is Array) or state.is_empty():
			continue

		var node := _find_node(
			entity_type, player_id,
		)
		if node == null:
			if Netcode.log.is_verbose:
				Netcode.log.verbose(
					"StateBundler: no node for"
					+ " type=%d player=%d"
					% [entity_type, player_id],
					NetworkLogger
						.CATEGORY_NETWORK_SYNC,
				)
			continue

		node._handle_new_state_from_network(state)


## Find the ReconcilableState node matching the given
## entity type and player ID. Uses a cached lookup
## table for fast dispatch.
func _find_node(
	entity_type: int,
	player_id: int,
) -> ReconcilableState:
	var key := entity_type * 1000 + player_id
	if _node_lookup.has(key):
		var cached: ReconcilableState = (
			_node_lookup[key]
		)
		if is_instance_valid(cached):
			return cached
		_node_lookup.erase(key)

	# Search in frame driver's registered nodes.
	var nodes: Array[ReconcilableState] = (
		Netcode.frame_driver._networked_state_nodes
	)
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if (
			node._get_type() == entity_type
			and node.player_id == player_id
		):
			_node_lookup[key] = node
			return node

	return null


## Clear the lookup cache. Call when players join
## or leave.
func clear_lookup() -> void:
	_node_lookup.clear()
