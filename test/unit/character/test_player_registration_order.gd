extends GutTest
## H24: the server spawns a player with add_child() and only
## then assigns its id (NetworkedLevel._server_register_players_
## for_peer). Player._enter_tree used to register at once, so
## the level kept a stale players_by_id[0] entry that nothing
## ever removed. The id must be set before registration.


var _level: Level
var _saved_level: Level
var _saved_is_server: bool


func before_each() -> void:
	ArrayPool.clear_all_pools()
	_saved_is_server = Netcode.is_server
	Netcode.is_server = true
	_saved_level = G.level
	_level = Level.new()
	G.level = _level


func after_each() -> void:
	G.level = _saved_level
	Netcode.is_server = _saved_is_server
	if is_instance_valid(_level):
		_level.free()
	ArrayPool.clear_all_pools()


func test_server_spawn_keeps_no_zero_id_entry() -> void:
	var spawned := TestEnvironmentMock.setup_player_with_networking(
		self, "Player_7")
	var player: Player = spawned["player"]
	player.server_initialize_player_id(7)

	assert_false(
		_level.players_by_id.has(0),
		"server must not keep a players_by_id[0] entry",
	)
	assert_eq(
		_level.players_by_id.get(7), player,
		"player registers under its assigned id",
	)
	assert_eq(
		_level.players.size(), 1,
		"player appears exactly once in players",
	)
	remove_child(player)
	player.free()
