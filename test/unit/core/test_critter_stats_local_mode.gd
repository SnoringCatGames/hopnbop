extends GutTest
## H106: in local mode the client stat reporter RPC'd the
## server peer, which is this process, so Godot refused the
## call and (since H86) queued a crash report per offline
## run. The critter deltas feed the match-end stats, which
## local play shows, so the handler applies them in place
## instead. Networked validation is unchanged.


var _sync: MatchStateSynchronizer
var _level: NetworkedLevel
var _was_local_mode := false
var _original_level: Level


func before_each() -> void:
	ArrayPool.clear_all_pools()
	_was_local_mode = Netcode.is_local_mode
	_original_level = G.level
	_level = NetworkedLevel.new()
	_level.peer_to_player_ids = {1: [7]}
	G.level = _level
	_sync = MatchStateSynchronizer.new()
	add_child_autofree(_sync)


func after_each() -> void:
	Netcode.is_local_mode = _was_local_mode
	G.level = _original_level
	if is_instance_valid(_level):
		_level.free()
	ArrayPool.clear_all_pools()


func test_local_mode_applies_critter_deltas() -> void:
	Netcode.is_local_mode = true

	_sync._rpc_server_update_critter_stats(
		[7, 2, 1, 0, 0.5, 3])

	var stats := _sync.state.get_player_stats(7)
	assert_not_null(stats, "stats recorded for the player")
	if stats != null:
		assert_eq(stats.cricket_disturb_count, 2)
		assert_eq(stats.fish_disturb_count, 1)
		assert_almost_eq(stats.fly_proximity_time_sec, 0.5, 0.001)
		assert_eq(stats.poop_count, 3)


func test_local_mode_still_validates_the_player() -> void:
	Netcode.is_local_mode = true

	_sync._rpc_server_update_critter_stats(
		[99, 2, 0, 0, 0.0, 0])

	assert_null(
		_sync.state.get_player_stats(99),
		"a player this peer does not own is skipped",
	)
