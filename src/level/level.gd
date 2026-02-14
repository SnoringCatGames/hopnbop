@tool
class_name Level
extends Node2D
## Abstract base class for all level types (lobby, networked gameplay).


const _SPAWN_POSITION_MIN_SPAWN_DISTANCE := 200.0
const _SPAWN_POSITION_COLLISION_CHECK_STEP := 4.0
const _SPAWN_POSITION_MAX_UPWARD_SHIFT := 200.0

@export var collision_tiles: TileMapLayer

@export var level_camera: Camera2D

@export var spawn_points: Node2D

## This is the location where all player nodes should be spawned.
@export var players_node: Node2D:
	set(value):
		players_node = value
		update_configuration_warnings()

var players: Array[Player] = []

# Dictionary<int, Player>
# Keys are player_id (int assigned by server, or negative for lobby).
var players_by_id := {}

var gore_manager: GoreManager


func _ready() -> void:
	Netcode.check(is_instance_valid(collision_tiles),
		"collision_tiles node not set in level: %s" %
		Utils.get_display_name(self ))
	Netcode.check(is_instance_valid(spawn_points),
		"spawn_points node not set in level: %s" %
		Utils.get_display_name(self ))

	if not Engine.is_editor_hint() and Netcode.is_client:
		gore_manager = GoreManager.new()
		gore_manager.name = "GoreManager"
		add_child(gore_manager)


func _get_spawn_points() -> Array[SpawnPoint]:
	var available_spawn_points: Array[SpawnPoint] = []
	for child in spawn_points.get_children():
		if Netcode.ensure(child is SpawnPoint):
			available_spawn_points.append(child)
	Netcode.check(not available_spawn_points.is_empty(),
		"No spawn points available in level: %s" %
		Utils.get_display_name(self ))
	return available_spawn_points


func _get_player_spawn_position() -> Vector2:
	var available_spawn_points := _get_spawn_points()

	# Find spawn point that's far enough from all players.
	var best_spawn_point: SpawnPoint = null
	var best_min_distance_squared := -INF
	var far_enough_spawn_points: Array[SpawnPoint] = []

	for spawn_point in available_spawn_points:
		var min_distance_squared := INF

		# Calculate minimum distance_squared to any existing player.
		for player in players:
			var distance_squared := spawn_point.spawn_position.distance_squared_to(
				player.global_position
			)
			min_distance_squared = min(min_distance_squared, distance_squared)

		# Track spawn points that are far enough.
		if (min_distance_squared >=
				_SPAWN_POSITION_MIN_SPAWN_DISTANCE *
				_SPAWN_POSITION_MIN_SPAWN_DISTANCE):
			far_enough_spawn_points.append(spawn_point)

		# Track spawn point with maximum minimum distance.
		if min_distance_squared > best_min_distance_squared:
			best_min_distance_squared = min_distance_squared
			best_spawn_point = spawn_point

	# Choose spawn point.
	var chosen_spawn_point: SpawnPoint
	if not far_enough_spawn_points.is_empty():
		# Randomly choose from spawn points that are far enough.
		chosen_spawn_point = far_enough_spawn_points.pick_random()
	else:
		# Use the spawn point with maximum minimum distance.
		chosen_spawn_point = best_spawn_point

	var spawn_position := chosen_spawn_point.spawn_position

	# Check for collision and adjust upward if needed.
	var final_position := _find_collision_free_position(spawn_position)

	return final_position


func _find_collision_free_position(initial_position: Vector2) -> Vector2:
	# Create a shape query to check for collisions.
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = G.settings.bunny_collision_shape.duplicate()
	query.collision_mask = 7 # Match player collision mask.

	# Test initial position.
	query.transform = Transform2D(0.0, initial_position)
	var space_state := get_world_2d().direct_space_state

	if _is_position_collision_free(space_state, query):
		return initial_position

	# Try shifting upward.
	var shift := _SPAWN_POSITION_COLLISION_CHECK_STEP
	while shift <= _SPAWN_POSITION_MAX_UPWARD_SHIFT:
		var test_position := initial_position - Vector2(0, shift)
		query.transform = Transform2D(0.0, test_position)

		if _is_position_collision_free(space_state, query):
			return test_position

		shift += _SPAWN_POSITION_COLLISION_CHECK_STEP

	# No collision-free position found.
	Netcode.warning(
		"Could not find collision-free spawn position near %s" % \
			initial_position
	)
	return initial_position


func _is_position_collision_free(
	space_state: PhysicsDirectSpaceState2D,
	query: PhysicsShapeQueryParameters2D,
) -> bool:
	var result := space_state.intersect_shape(query)
	for collision in result:
		if collision.collider != collision_tiles:
			return false
	return true


## Called when a player is added to this level.
## Maintains players array and players_by_id dictionary.
func register_player(player: Player) -> void:
	if Netcode.log.is_verbose:
		Netcode.verbose(
			"Level.register_player: player_id=%d" % player.player_id,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
	players.append(player)
	players_by_id[player.player_id] = player


## Called when a player is removed from this level.
## Updates players array and players_by_id dictionary.
func deregister_player(player: Player) -> void:
	players.erase(player)
	# Only erase from players_by_id if this is the same
	# instance. Prevents stale _exit_tree calls from
	# removing re-registered players with the same id.
	if players_by_id.get(player.player_id) == player:
		players_by_id.erase(player.player_id)


## Returns a debug string identifying this level.
func get_string() -> String:
	return Utils.get_filename_from_path(scene_file_path)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []

	if not is_instance_valid(players_node):
		warnings.append("players_node not set")

	return warnings
