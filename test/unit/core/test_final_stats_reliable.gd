extends GutTest
## H89: the final match stats rode the same unreliable RPC
## as the periodic sync, so a dropped packet left the
## game-over screen with stale numbers. The final snapshot
## has a reliable twin; the periodic one stays unreliable.


var _sync: MatchStateSynchronizer


func before_each() -> void:
	ArrayPool.clear_all_pools()
	_sync = MatchStateSynchronizer.new()


func after_each() -> void:
	if is_instance_valid(_sync):
		_sync.free()
	ArrayPool.clear_all_pools()


func test_final_stats_rpc_exists() -> void:
	# The reliable transfer mode is the @rpc annotation on
	# _rpc_client_update_stats_final in match_state_
	# synchronizer.gd; GDScript exposes no runtime read of
	# it, so this pins that the final path exists at all.
	assert_true(
		_sync.has_method("_rpc_client_update_stats_final"),
		"a final-stats RPC exists beside the periodic one",
	)


func test_final_stats_apply_to_state() -> void:
	var stats := PlayerMatchStats.new()
	var packed := [7]
	packed.append_array(stats.to_packed_array())

	_sync._rpc_client_update_stats_final(packed)

	assert_true(
		_sync.state._stats_by_player_id.has(7),
		"final stats are stored for the game-over screen",
	)
