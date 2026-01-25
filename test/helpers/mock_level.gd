@tool
class_name MockLevel
extends Level
## Mock Level for testing.


# Override initialization to prevent full Level setup in tests
func _enter_tree() -> void:
	# Skip Level's _enter_tree which requires G.game_panel
	pass

func _ready() -> void:
	# Skip Level's _ready which requires player_spawner and G.settings
	pass

func _exit_tree() -> void:
	# Skip Level's _exit_tree which requires G.game_panel
	pass

# Override register_player to work in test context
func register_player(player: Player) -> void:
	# Check if state_from_server is set up (it might not be during test
	# setup)
	if player.state_from_server == null:
		return
	if player.player_id != 0:
		players_by_id[player.player_id] = player
		if not players.has(player):
			players.append(player)

# Override deregister_player to work in test context
func deregister_player(player: Player) -> void:
	players_by_id.erase(player.player_id)
	players.erase(player)
