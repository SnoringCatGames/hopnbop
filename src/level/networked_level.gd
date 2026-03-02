@tool
class_name NetworkedLevel
extends Level

## Networked multiplayer level with server-authoritative player spawning.

@export var player_spawner: MultiplayerSpawner:
	set(value):
		player_spawner = value
		update_configuration_warnings()

@export var blood_is_thicker_than_water_tiles: TileMapLayer

## Number of fly swarms to spawn (client-side).
@export var fly_swarm_count := 1

## Number of flies per swarm.
@export var flies_per_swarm := 12

## Number of snails to spawn.
@export var snail_count := 1

## Number of crickets to spawn (client-side).
@export var cricket_count := 1

## Number of fish to spawn in water
## (client-side).
@export var fish_count := 2

## Number of butterflies to spawn (client-side).
@export var butterfly_count := 4

## Fraction of the camera's vertical bounds where
## birds may spawn (0.0 to 1.0). A value of 0.5
## restricts birds to the middle 50% of the screen.
@export_range(0.0, 1.0) \
	var bird_flight_band_height := 0.5

## Shifts the bird flight band vertically as a
## fraction of the camera's height. Negative values
## shift upward, positive shift downward.
@export_range(-0.5, 0.5) \
	var bird_flight_band_offset := 0.0

## Rectangular bounds for wrap-around movement.
## Position is the top-left corner; size is the
## dimensions. If size is zero (default),
## wrap-around is disabled.
@export var wrap_bounds := Rect2():
	set(value):
		wrap_bounds = value
		if is_instance_valid(_wrap_overlay):
			_wrap_overlay.queue_redraw()
		elif is_inside_tree():
			_setup_wrap_bounds_overlay()

const _FISH_SCENE_PATH := (
	"res://src/objects/fish/fish.tscn")
const _BUTTERFLY_SCENE_PATH := (
	"res://src/objects/butterfly/butterfly.tscn")
const _BLOOD_TWEEN_DURATION := 0.3

# Dictionary<int, Array[int]>
# Maps peer_id to array of player_ids for that peer.
var peer_to_player_ids := {}

var npcs: Array[NPC] = []

var _extra_surface_cells := {}
var _snails: Array[Snail] = []
var _crickets: Array = []
var _critter_stat_tracker: CritterStatTracker
var _client_stat_reporter: ClientStatReporter
var _blood_tween: Tween
var _wrap_overlay: WrapBoundsOverlay


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return

	G.game_panel.on_level_added(self )

	if Netcode.is_server:
		# Listen for player count declarations from clients.
		Netcode.connector.peer_players_declared.connect(
			_server_on_peer_players_declared)


func _ready() -> void:
	# Create overlay before editor guard so
	# debug annotations render in-editor.
	_setup_wrap_bounds_overlay()

	var warnings := _get_configuration_warnings()
	if not warnings.is_empty():
		Netcode.error("Level._ready: %s (%s)" % [warnings[0], get_scene_file_path()])
		return

	if Engine.is_editor_hint():
		return

	super._ready()

	G.log.log_system_ready("Level")

	%PlayerSpawner.set_multiplayer_authority(NetworkConnector.SERVER_ID)

	for player_scene in G.settings.player_scenes:
		player_spawner.add_spawnable_scene(player_scene.resource_path)

	if Netcode.is_client:
		%PlayerSpawner.spawned.connect(_client_on_player_spawned)
		%PlayerSpawner.despawned.connect(_client_on_player_despawned)

	# Non-networked critters: each client
	# uses its own local preference.
	if (
		Netcode.is_client
		and G.settings.are_critters_enabled
	):
		# Stat tracker for critter disturbances
		# and fly proximity.
		_critter_stat_tracker = \
			CritterStatTracker.new()
		_critter_stat_tracker.name = \
			"CritterStatTracker"
		add_child(_critter_stat_tracker)

		# Reporter that periodically sends
		# accumulated stats to the server.
		_client_stat_reporter = \
			ClientStatReporter.new()
		_client_stat_reporter.name = \
			"ClientStatReporter"
		_client_stat_reporter.critter_tracker = \
			_critter_stat_tracker
		add_child(_client_stat_reporter)

		for i in cricket_count:
			var cricket := preload(
				"res://src/objects/cricket/"
				+"cricket.tscn"
			).instantiate()
			cricket.name = "Cricket_%d" % i
			%Objects.add_child(cricket)
			_crickets.append(cricket)
			_critter_stat_tracker \
				.register_cricket(cricket)

		_spawn_fly_swarms()
		_spawn_fish()
		_spawn_butterflies()
		_spawn_bird_flock()

	# Collect tile positions of scene-based
	# surfaces (e.g. springs) so snails can
	# crawl across them.
	_extra_surface_cells = (
		_collect_extra_surface_cells())

	# Create snail nodes on all peers so RPCs
	# have matching target nodes. Snails start
	# invisible until the server initializes them.
	_create_snail_nodes()

	if Netcode.is_server:
		# Snails are initialized later by GamePanel
		# after critter preference majority vote.
		G.game_panel.is_level_fully_loaded = true

	if blood_is_thicker_than_water_tiles != null:
		var is_active: bool = G.settings \
			.is_bloodisthickerthanwater_enabled
		blood_is_thicker_than_water_tiles \
			.modulate.a = (
				1.0 if is_active else 0.0)
		G.cheat_manager.cheat_toggled.connect(
			_on_cheat_toggled)


## Wraps a position to stay within wrap_bounds.
## Returns the position unchanged if wrap_bounds
## size is zero.
func wrap_position(pos: Vector2) -> Vector2:
	if wrap_bounds.size == Vector2.ZERO:
		return pos
	var origin := wrap_bounds.position
	pos.x = fposmod(
		pos.x - origin.x,
		wrap_bounds.size.x) + origin.x
	pos.y = fposmod(
		pos.y - origin.y,
		wrap_bounds.size.y) + origin.y
	return pos


## Wraps a node's global position to stay within
## wrap_bounds. Resets physics interpolation when
## the position wraps to prevent the renderer
## from lerping between the old and new positions.
func wrap_node(node: Node2D) -> void:
	if wrap_bounds.size == Vector2.ZERO:
		return
	var wrapped := wrap_position(
		node.global_position)
	if not wrapped.is_equal_approx(
		node.global_position
	):
		node.global_position = wrapped
		node.reset_physics_interpolation()


func _setup_wrap_bounds_overlay() -> void:
	if wrap_bounds.size == Vector2.ZERO:
		return
	if is_instance_valid(_wrap_overlay):
		return
	_wrap_overlay = WrapBoundsOverlay.new()
	_wrap_overlay.name = "WrapBoundsOverlay"
	add_child(_wrap_overlay)


func _client_on_player_spawned(p_player: Node) -> void:
	Netcode.ensure(p_player is Player)
	var player: Player = p_player
	if Netcode.log.is_verbose:
		Netcode.verbose(
			"Player spawned: %s (current player_id=%d)" %
				[player.get_string(), player.player_id],
			NetworkLogger.CATEGORY_CONNECTIONS,
		)


func _client_on_player_despawned(p_player: Node) -> void:
	Netcode.ensure(p_player is Player)
	var player: Player = p_player
	Netcode.print("Player despawned: %s" % player.get_string(), NetworkLogger.CATEGORY_GAME_STATE)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	if Netcode.is_server:
		if is_instance_valid(G.game_panel):
			G.game_panel.is_level_fully_loaded = false
		Netcode.connector.peer_players_declared.disconnect(
			_server_on_peer_players_declared)
	if (
		blood_is_thicker_than_water_tiles != null
		and G.cheat_manager.cheat_toggled
			.is_connected(_on_cheat_toggled)
	):
		G.cheat_manager.cheat_toggled.disconnect(
			_on_cheat_toggled)
	if is_instance_valid(G.game_panel):
		G.game_panel.on_level_removed(self )


func _on_cheat_toggled(
	cheat_name: String,
	is_active: bool,
) -> void:
	if cheat_name != "bloodisthickerthanwater":
		return
	if blood_is_thicker_than_water_tiles == null:
		return
	if _blood_tween != null:
		_blood_tween.kill()
	var target_alpha := (
		1.0 if is_active else 0.0)
	_blood_tween = create_tween()
	_blood_tween.tween_property(
		blood_is_thicker_than_water_tiles,
		"modulate:a",
		target_alpha,
		_BLOOD_TWEEN_DURATION,
	)


func _server_on_peer_players_declared(
	peer_id: int,
	assigned_ids: Array[int],
	_player_attributes: Array
) -> void:
	_server_register_players_for_peer(peer_id, assigned_ids)
	_server_send_snail_states_to_peer(peer_id)


func _server_register_players_for_peer(
		peer_id: int,
		assigned_ids: Array[int]) -> void:
	Netcode.print(
		"Spawning %d player(s) for peer %d" % [assigned_ids.size(), peer_id],
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	for local_index in range(assigned_ids.size()):
		var player_id := assigned_ids[local_index]
		var player: Player = G.settings.default_player_scene.instantiate()
		player.name = "Player_%d" % player_id
		players_by_id[player_id] = player

		# Record peer to player_ids mapping.
		if not peer_to_player_ids.has(peer_id):
			peer_to_player_ids[peer_id] = []
		peer_to_player_ids[peer_id].append(player_id)

		players_node.add_child(player)
		player.global_position = _get_player_spawn_position()

		# Initialize player_id and update authority after add_child.
		# This ensures all child nodes are ready and sibling references work.
		player.server_initialize_player_id(player_id)


func _server_deregister_players_for_peer(peer_id: int) -> void:
	var player_ids_to_remove: Array = peer_to_player_ids.get(peer_id, [])

	Netcode.print(
		"Removing %d player(s) for peer %d" %
		[player_ids_to_remove.size(), peer_id],
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	for player_id in player_ids_to_remove:
		if players_by_id.has(player_id):
			var player: Player = players_by_id[player_id]
			deregister_player(player)
			player.queue_free()
		else:
			Netcode.warning(
				("Level._server_deregister_players_for_peer: " +
				"No player found for ID: %s") % player_id,
				NetworkLogger.CATEGORY_CORE_SYSTEMS,
			)

	peer_to_player_ids.erase(peer_id)


func register_player(player: Player) -> void:
	super.register_player(player)

	if Netcode.is_client:
		# Record peer to player_ids mapping on client side too.
		var peer_id := player.peer_id
		if not peer_to_player_ids.has(peer_id):
			peer_to_player_ids[peer_id] = []
		if not peer_to_player_ids[peer_id].has(player.player_id):
			peer_to_player_ids[peer_id].append(player.player_id)


func deregister_player(player: Player) -> void:
	super.deregister_player(player)

	if Netcode.is_client:
		# Update peer to player_ids mapping.
		var peer_id := player.peer_id
		if peer_to_player_ids.has(peer_id):
			peer_to_player_ids[peer_id].erase(player.player_id)
			if peer_to_player_ids[peer_id].is_empty():
				peer_to_player_ids.erase(peer_id)


func register_npc(npc: NPC) -> void:
	if Netcode.is_client:
		npcs.append(npc)


func deregister_npc(npc: NPC) -> void:
	if Netcode.is_client:
		npcs.erase(npc)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = super._get_configuration_warnings()

	if not is_instance_valid(player_spawner):
		warnings.append("player_spawner must be set")

	return warnings


func _create_snail_nodes() -> void:
	for i in snail_count:
		var snail: Snail = preload(
			SnailSpawner.SNAIL_SCENE_PATH
		).instantiate()
		snail.name = "Snail_%d" % i
		snail.setup(
			collision_tiles, _extra_surface_cells)
		%Objects.add_child(snail)
		_snails.append(snail)


## Initializes snails on the server. Called by
## GamePanel after critter preference majority
## vote resolves in favor of critters.
func server_spawn_snails() -> void:
	if not _snails.is_empty():
		_server_init_snails()


func _server_init_snails() -> void:
	for snail in _snails:
		var surface := (
			SnailSpawner
				.find_random_interior_surface(
					collision_tiles,
					_extra_surface_cells))
		if surface.is_empty():
			Netcode.warning(
				"No interior surfaces for snail",
				NetworkLogger.CATEGORY_GAME_STATE,
			)
			continue
		var clockwise := randi() % 2 == 0
		snail.initialize(
			surface.tile,
			surface.face,
			clockwise,
		)
		snail._rpc_init.rpc(
			surface.tile.x,
			surface.tile.y,
			surface.face,
			1 if clockwise else 0,
			Netcode.server_frame_index,
		)


## Sends current snail states to a late-joining
## peer so their snails catch up.
func _server_send_snail_states_to_peer(
	peer_id: int,
) -> void:
	for snail in _snails:
		if snail == null:
			continue
		if not snail.is_alive:
			continue
		snail._rpc_init.rpc_id(
			peer_id,
			snail.current_tile.x,
			snail.current_tile.y,
			snail.current_face,
			1 if snail.is_clockwise else 0,
			Netcode.server_frame_index,
		)


## Scans collision_tiles children for scene
## collection tile instances (e.g. springs) that
## have the normal-surfaces collision layer bit.
## Returns a Dictionary mapping their tile
## coordinates to true.
func _collect_extra_surface_cells() -> Dictionary:
	var extra_cells := {}
	for child in collision_tiles.get_children():
		if not child is CollisionObject2D:
			continue
		if (child.collision_layer
				& Character._NORMAL_SURFACES_COLLISION_MASK_BIT == 0):
			continue
		var cell := (
			collision_tiles.local_to_map(
				child.position))
		extra_cells[cell] = true
	return extra_cells


func _spawn_fly_swarms() -> void:
	for i in fly_swarm_count:
		var swarm := FlySwarm.new()
		swarm.fly_count = flies_per_swarm
		swarm.name = "FlySwarm_%d" % i
		add_child(swarm)
		move_child(
			swarm, players_node.get_index())
		if _critter_stat_tracker:
			_critter_stat_tracker \
				.register_fly_swarm(swarm)


func _spawn_fish() -> void:
	# Collect all water cells.
	var water_cells: Array[Vector2i] = []
	for cell in (
		collision_tiles.get_used_cells()
	):
		var tile_data := (
			collision_tiles
				.get_cell_tile_data(cell))
		if tile_data == null:
			continue
		if (tile_data.get_terrain_set()
				== Level.TERRAIN_SET_WATER):
			water_cells.append(cell)
	if water_cells.is_empty():
		return

	var fish_scene: PackedScene = preload(
		_FISH_SCENE_PATH)
	for i in fish_count:
		var cell: Vector2i = (
			water_cells.pick_random())
		var fish: Fish = (
			fish_scene.instantiate())
		fish.name = "Fish_%d" % i
		fish.setup(collision_tiles)
		add_child(fish)
		move_child(
			fish, players_node.get_index())
		fish.initialize(cell)
		if _critter_stat_tracker:
			_critter_stat_tracker \
				.register_fish(fish)


func _spawn_butterflies() -> void:
	var interior_cells := (
		SnailSpawner
			.find_interior_empty_cells(
				collision_tiles,
				_extra_surface_cells))
	if interior_cells.is_empty():
		return

	var butterfly_scene: PackedScene = preload(
		_BUTTERFLY_SCENE_PATH)
	var used_positions: Array[Vector2] = []
	for i in butterfly_count:
		# Pick spawn cell far from existing
		# butterflies.
		var best_cell: Vector2i = (
			interior_cells.pick_random())
		var best_min_dist := 0.0
		for _attempt in 10:
			var candidate: Vector2i = (
				interior_cells.pick_random())
			var cand_local := (
				collision_tiles.map_to_local(
					candidate))
			var cand_global := (
				collision_tiles.to_global(
					cand_local))
			var min_dist := INF
			for pos in used_positions:
				var d := (
					cand_global
						.distance_to(pos))
				if d < min_dist:
					min_dist = d
			if min_dist > best_min_dist:
				best_min_dist = min_dist
				best_cell = candidate
		var butterfly: Butterfly = (
			butterfly_scene.instantiate())
		butterfly.name = "Butterfly_%d" % i
		butterfly.setup(
			collision_tiles, interior_cells)
		add_child(butterfly)
		move_child(
			butterfly,
			players_node.get_index())
		var local_pos := (
			collision_tiles.map_to_local(
				best_cell))
		butterfly.global_position = (
			collision_tiles.to_global(
				local_pos))
		used_positions.append(
			butterfly.global_position)
		if _critter_stat_tracker:
			_critter_stat_tracker \
				.register_butterfly(butterfly)


func _spawn_bird_flock() -> void:
	var flock := BirdFlock.new()
	flock.name = "BirdFlock"
	flock.flight_band_height = (
		bird_flight_band_height)
	flock.flight_band_vertical_offset = (
		bird_flight_band_offset)
	flock.setup(level_camera)
	add_child(flock)
	# Place before collision tiles so birds render
	# above background but behind terrain.
	move_child(
		flock, collision_tiles.get_index())
