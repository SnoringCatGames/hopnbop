@tool
class_name NetworkedLevel
extends Level

## Networked multiplayer level with server-authoritative player spawning.

@export var player_spawner: MultiplayerSpawner:
	set(value):
		player_spawner = value
		update_configuration_warnings()

# Dictionary<int, Array[int]>
# Maps peer_id to array of player_ids for that peer.
var peer_to_player_ids := {}

var npcs: Array[NPC] = []


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return

	G.game_panel.on_level_added(self)

	if G.network.is_server:
		# Listen for player count declarations from clients.
		G.network.connector.peer_players_declared.connect(
			_server_on_peer_players_declared)


func _ready() -> void:
	var warnings := _get_configuration_warnings()
	if not warnings.is_empty():
		G.error("Level._ready: %s (%s)" % [warnings[0], get_scene_file_path()])
		return

	if Engine.is_editor_hint():
		return

	G.log.log_system_ready("Level")

	%PlayerSpawner.set_multiplayer_authority(NetworkConnector.SERVER_ID)

	for player_scene in G.settings.player_scenes:
		player_spawner.add_spawnable_scene(player_scene.resource_path)

	if G.network.is_client:
		%PlayerSpawner.spawned.connect(_client_on_player_spawned)
		%PlayerSpawner.despawned.connect(_client_on_player_despawned)

	if G.network.is_server:
		G.game_panel.is_level_fully_loaded = true


func _client_on_player_spawned(p_player: Node) -> void:
	G.ensure(p_player is Player)
	var player: Player = p_player
	G.print("Player spawned: %s" % player.get_string(), ScaffolderLog.CATEGORY_GAME_STATE)


func _client_on_player_despawned(p_player: Node) -> void:
	G.ensure(p_player is Player)
	var player: Player = p_player
	G.print("Player despawned: %s" % player.get_string(), ScaffolderLog.CATEGORY_GAME_STATE)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	if G.network.is_server:
		if is_instance_valid(G.game_panel):
			G.game_panel.is_level_fully_loaded = false
		G.network.connector.peer_players_declared.disconnect(
			_server_on_peer_players_declared)
	if is_instance_valid(G.game_panel):
		G.game_panel.on_level_removed(self)


func _server_on_peer_players_declared(
	peer_id: int,
	assigned_ids: Array[int]
) -> void:
	_server_register_players_for_peer(peer_id, assigned_ids)


func _server_register_players_for_peer(
		peer_id: int,
		assigned_ids: Array[int]) -> void:
	G.print(
		"Spawning %d player(s) for peer %d" % [assigned_ids.size(), peer_id],
		ScaffolderLog.CATEGORY_GAME_STATE,
	)

	for local_index in range(assigned_ids.size()):
		var player_id := assigned_ids[local_index]
		var player: Player = G.settings.default_player_scene.instantiate()
		player.player_id = player_id
		player.global_position = _get_player_spawn_position()
		player.name = "Player_%d" % player_id
		players_by_id[player_id] = player

		# Record peer to player_ids mapping.
		if not peer_to_player_ids.has(peer_id):
			peer_to_player_ids[peer_id] = []
		peer_to_player_ids[peer_id].append(player_id)

		players_node.add_child(player)


func _server_deregister_players_for_peer(peer_id: int) -> void:
	var player_ids_to_remove: Array = peer_to_player_ids.get(peer_id, [])

	G.print(
		"Removing %d player(s) for peer %d" %
		[player_ids_to_remove.size(), peer_id],
		ScaffolderLog.CATEGORY_GAME_STATE,
	)

	for player_id in player_ids_to_remove:
		if players_by_id.has(player_id):
			var player: Player = players_by_id[player_id]
			deregister_player(player)
			player.queue_free()
		else:
			G.warning(
				("Level._server_deregister_players_for_peer: " +
				"No player found for ID: %s") % player_id,
				ScaffolderLog.CATEGORY_CORE_SYSTEMS,
			)

	peer_to_player_ids.erase(peer_id)


func register_player(player: Player) -> void:
	super.register_player(player)

	if G.network.is_client:
		# Record peer to player_ids mapping on client side too.
		var peer_id := player.peer_id
		if not peer_to_player_ids.has(peer_id):
			peer_to_player_ids[peer_id] = []
		if not peer_to_player_ids[peer_id].has(player.player_id):
			peer_to_player_ids[peer_id].append(player.player_id)


func deregister_player(player: Player) -> void:
	super.deregister_player(player)

	if G.network.is_client:
		# Update peer to player_ids mapping.
		var peer_id := player.peer_id
		if peer_to_player_ids.has(peer_id):
			peer_to_player_ids[peer_id].erase(player.player_id)
			if peer_to_player_ids[peer_id].is_empty():
				peer_to_player_ids.erase(peer_id)


func register_npc(npc: NPC) -> void:
	if G.network.is_client:
		npcs.append(npc)


func deregister_npc(npc: NPC) -> void:
	if G.network.is_client:
		npcs.erase(npc)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = super._get_configuration_warnings()

	if not is_instance_valid(player_spawner):
		warnings.append("player_spawner must be set")

	return warnings
