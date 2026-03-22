extends GutTest
## Unit tests for disconnect handling logic:
## - GameMatchState.server_demote_disconnected_players()
## - MatchState.is_match_active


class TestDemoteDisconnectedPlayers:
	extends GutTest

	var _original_use_simple_score: bool


	func before_each():
		_original_use_simple_score = (
			G.settings.use_simple_score
		)
		G.settings.use_simple_score = false


	func after_each():
		G.settings.use_simple_score = (
			_original_use_simple_score
		)


	func _make_state_with_players(
		player_ids: Array,
	) -> GameMatchState:
		var state := GameMatchState.new()
		for pid in player_ids:
			var p := GamePlayerState.new()
			p.player_id = pid
			p.connect_frame_index = 1
			state.players_by_id[pid] = p
		return state


	func _disconnect_player(
		state: GameMatchState,
		player_id: int,
	) -> void:
		var ps: PlayerState = (
			state.players_by_id[player_id])
		ps.disconnect_frame_index = 100
		state._connected_players.erase(player_id)


	func test_remaining_player_gets_rank_1():
		var state := _make_state_with_players(
			[1, 2, 3])
		# Player 2 had the most kills.
		state.kills.append_array(
			[2, 1, 2, 3, 2, 1])
		# Disconnect player 2 and 3.
		_disconnect_player(state, 2)
		_disconnect_player(state, 3)

		state.server_demote_disconnected_players()

		assert_eq(
			state.players_by_id[1].rank,
			1,
			"Remaining connected player is rank 1",
		)
		assert_gt(
			state.players_by_id[2].rank,
			1,
			"Disconnected player 2 is demoted",
		)
		assert_gt(
			state.players_by_id[3].rank,
			1,
			"Disconnected player 3 is demoted",
		)


	func test_disconnected_players_ranked_after_connected():
		var state := _make_state_with_players(
			[1, 2, 3, 4])
		# Players 1 and 2 have lower scores than
		# 3 and 4.
		state.kills.append_array(
			[3, 1, 4, 2, 3, 2, 4, 1])
		# Disconnect players 3 and 4 (the ones
		# who were winning).
		_disconnect_player(state, 3)
		_disconnect_player(state, 4)

		state.server_demote_disconnected_players()

		# Connected players (1, 2) must have
		# better ranks than disconnected (3, 4).
		assert_lt(
			state.players_by_id[1].rank,
			state.players_by_id[3].rank,
			"Connected player 1 outranks"
			+ " disconnected player 3",
		)
		assert_lt(
			state.players_by_id[2].rank,
			state.players_by_id[4].rank,
			"Connected player 2 outranks"
			+ " disconnected player 4",
		)


	func test_connected_players_keep_relative_order():
		var state := _make_state_with_players(
			[1, 2, 3])
		# Player 2 has more kills than player 1
		# among connected players.
		state.kills.append_array([2, 3, 2, 3])
		# Disconnect player 3.
		_disconnect_player(state, 3)

		state.server_demote_disconnected_players()

		assert_eq(
			state.players_by_id[2].rank,
			1,
			"Higher-scoring connected player is"
			+ " rank 1",
		)
		assert_eq(
			state.players_by_id[1].rank,
			2,
			"Lower-scoring connected player is"
			+ " rank 2",
		)
		assert_eq(
			state.players_by_id[3].rank,
			3,
			"Disconnected player is last",
		)


	func test_all_connected_no_change():
		var state := _make_state_with_players(
			[1, 2])
		state.kills.append_array([1, 2])

		state.server_demote_disconnected_players()

		# Normal ranking: player 1 has more kills.
		assert_eq(
			state.players_by_id[1].rank,
			1,
			"Player with more kills is rank 1",
		)
		assert_eq(
			state.players_by_id[2].rank,
			2,
			"Player with fewer kills is rank 2",
		)


	func test_all_disconnected():
		var state := _make_state_with_players(
			[1, 2])
		_disconnect_player(state, 1)
		_disconnect_player(state, 2)

		state.server_demote_disconnected_players()

		# Both disconnected. Ranked by score.
		var ranks := [
			state.players_by_id[1].rank,
			state.players_by_id[2].rank,
		]
		ranks.sort()
		assert_eq(
			ranks,
			[1, 2],
			"All disconnected players still get"
			+ " valid ranks",
		)


	func test_forfeit_flag_cleared_on_reset():
		var state := GameMatchState.new()
		state.is_forfeit_win = true
		state.clear()
		assert_false(
			state.is_forfeit_win,
			"is_forfeit_win resets on clear",
		)


class TestIsMatchActive:
	extends GutTest


	func test_inactive_when_not_started():
		var state := GameMatchState.new()
		assert_false(
			state.is_match_active,
			"Match is not active before start",
		)


	func test_active_after_start():
		var state := GameMatchState.new()
		state.match_start_frame_index = 100
		assert_true(
			state.is_match_active,
			"Match is active after timer starts",
		)


	func test_active_at_frame_zero():
		var state := GameMatchState.new()
		state.match_start_frame_index = 0
		assert_true(
			state.is_match_active,
			"Match is active when started at"
			+ " frame 0",
		)
