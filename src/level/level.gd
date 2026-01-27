@tool
class_name Level
extends Node2D
## Abstract base class for all level types (lobby, networked gameplay).


const _SPAWN_POSITION_MIN_SPAWN_DISTANCE := 200.0
const _SPAWN_POSITION_COLLISION_CHECK_STEP := 4.0
const _SPAWN_POSITION_MAX_UPWARD_SHIFT := 200.0

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


func _ready() -> void:
	pass


func _get_player_spawn_position() -> Vector2:
	if not is_instance_valid(spawn_points):
		G.warning("spawn_points node not set in level: %s" %
			Utils.get_display_name(self))
		return Vector2.ZERO

	var available_spawn_points: Array[SpawnPoint] = []
	for child in spawn_points.get_children():
		if G.ensure(child is SpawnPoint):
			available_spawn_points.append(child)

	if not G.ensure(not available_spawn_points.is_empty()):
		G.warning("No spawn points available in level: %s" %
			Utils.get_display_name(self))
		return Vector2.ZERO

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
	var result := space_state.intersect_shape(query)

	if result.is_empty():
		# No collision at initial position.
		return initial_position

	# Try shifting upward.
	var shift := _SPAWN_POSITION_COLLISION_CHECK_STEP
	while shift <= _SPAWN_POSITION_MAX_UPWARD_SHIFT:
		var test_position := initial_position - Vector2(0, shift)
		query.transform = Transform2D(0.0, test_position)
		result = space_state.intersect_shape(query)

		if result.is_empty():
			# Found collision-free position.
			return test_position

		shift += _SPAWN_POSITION_COLLISION_CHECK_STEP

	# No collision-free position found.
	G.warning(
		"Could not find collision-free spawn position near %s" % \
			initial_position
	)
	return initial_position


## Called when a player is added to this level.
## Maintains players array and players_by_id dictionary.
func register_player(player: Player) -> void:
	if G.is_verbose:
		G.print(
			"Level.register_player: player_id=%d" % player.player_id,
			ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
			ScaffolderLog.Verbosity.VERBOSE,
		)
	players.append(player)
	players_by_id[player.player_id] = player


## Called when a player is removed from this level.
## Updates players array and players_by_id dictionary.
func deregister_player(player: Player) -> void:
	players.erase(player)
	players_by_id.erase(player.player_id)


## Returns a debug string identifying this level.
func get_string() -> String:
	return Utils.get_filename_from_path(scene_file_path)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []

	if not is_instance_valid(players_node):
		warnings.append("players_node not set")

	return warnings
