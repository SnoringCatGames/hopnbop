@tool
class_name Level
extends Node2D
## Abstract base class for all level types (lobby, networked gameplay).


@export var level_camera: Camera2D

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


## Virtual method - override in subclasses to provide spawn position logic.
func _get_player_spawn_position() -> Vector2:
	return Vector2.ZERO


## Called when a player is added to this level.
## Maintains players array and players_by_id dictionary.
func register_player(player: Player) -> void:
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
