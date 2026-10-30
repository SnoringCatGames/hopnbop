extends GutTest
## H8 (unverified): the server spawn path added the player
## and only then positioned it, so with physics interpolation
## the first tick could render it sliding out of the origin
## (the 7215b1d5 pattern). This records each player's global
## position at the moment it enters the tree, which is the
## transform the interpolation starts from.


const _LEVEL_SCENE := preload("res://src/level/level_1.tscn")

var _root: Node
var _level: NetworkedLevel
var _entry_positions: Array = []


func before_each() -> void:
	ArrayPool.clear_all_pools()
	if not Netcode.frame_driver._is_frame_tracking_initialized:
		Netcode.frame_driver._initialize_frame_tracking()
	_root = Node.new()
	add_child_autofree(_root)
	G.game_panel = MockGamePanel.new()
	G.match_state = GameMatchState.new()
	_level = _LEVEL_SCENE.instantiate()
	_root.add_child(_level)
	G.level = _level
	_level.players_node.child_entered_tree.connect(
		_on_player_entered)


func after_each() -> void:
	ArrayPool.clear_all_pools()
	G.level = null
	G.match_state = null
	if is_instance_valid(G.game_panel):
		G.game_panel.free()
	G.game_panel = null


func _on_player_entered(node: Node) -> void:
	if node is Player:
		_entry_positions.append((node as Player).global_position)


func test_spawned_players_enter_at_their_spawn_position() -> void:
	var assigned_ids: Array[int] = [10, 11]
	_level._server_register_players_for_peer(1234, assigned_ids)

	assert_eq(_entry_positions.size(), 2, "both players entered")
	for i in range(assigned_ids.size()):
		var player: Player = _level.players_by_id[assigned_ids[i]]
		assert_eq(
			_entry_positions[i], player.global_position,
			"player entered at its spawn position, not the origin",
		)
		assert_ne(
			_entry_positions[i], _level.players_node.global_position,
			"player did not enter at the players_node origin",
		)
