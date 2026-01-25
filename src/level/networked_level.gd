@tool
class_name NetworkedLevel
extends Level

## Networked multiplayer level with server-authoritative player spawning.

@export var player_spawner: MultiplayerSpawner:
	set(value):
		player_spawner = value
		update_configuration_warnings()

# Dictionary<int, Array<StringName>>
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
		G.game_panel.is_level_fully_loaded = false
		G.network.connector.peer_players_declared.disconnect(
			_server_on_peer_players_declared)
	G.game_panel.on_level_removed(self)


func _server_on_peer_players_declared(
	peer_id: int,
	session_ids: Array
) -> void:
	_server_register_players_for_peer(peer_id, session_ids.size())


func _server_register_players_for_peer(peer_id: int, count: int) -> void:
	G.print(
		"Spawning %d player(s) for peer %d" % [count, peer_id],
		ScaffolderLog.CATEGORY_GAME_STATE,
	)

	for i in range(count):
		var player_id := NetworkConnector.get_player_id(peer_id, i)
		var player: Player = G.settings.default_player_scene.instantiate()
		player.player_id = player_id
		player.global_position = _get_player_spawn_position()
		player.name = "Player_%s" % player_id.replace(":", "_")
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
			players.erase(player)
			players_by_id.erase(player_id)
			player.queue_free()
		else:
			G.warning(
				("Level._server_deregister_players_for_peer: " +
				"No player found for ID: %s") % player_id,
				ScaffolderLog.CATEGORY_CORE_SYSTEMS,
			)

	peer_to_player_ids.erase(peer_id)


func register_player(player: Player) -> void:
	if G.network.is_client:
		super.register_player(player)

		# Record peer to player_ids mapping on client side too.
		# Extract peer_id from player_id string.
		var peer_id := G.network.get_peer_id_from_player_id(player.player_id)
		if not peer_to_player_ids.has(peer_id):
			peer_to_player_ids[peer_id] = []
		if not peer_to_player_ids[peer_id].has(player.player_id):
			peer_to_player_ids[peer_id].append(player.player_id)


func deregister_player(player: Player) -> void:
	if G.network.is_client:
		super.deregister_player(player)

		# Update peer to player_ids mapping.
		# Extract peer_id from player_id string.
		var peer_id := G.network.get_peer_id_from_player_id(player.player_id)
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


func _get_player_spawn_position() -> Vector2:
	# FIXME: Calculate player spawn position.
	return Vector2.ZERO


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = super._get_configuration_warnings()

	if not is_instance_valid(player_spawner):
		warnings.append("player_spawner must be set")

	return warnings
