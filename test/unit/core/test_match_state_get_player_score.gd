extends GutTest
## Unit tests for GameMatchState.update_scores()


class TestMatchStateGetPlayerScore:
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
		var state = GameMatchState.new()
		for pid in player_ids:
			var p = GamePlayerState.new()
			p.player_id = pid
			state.players_by_id[pid] = p
		return state


	func _update_scores(state: GameMatchState) -> void:
		state.update_scores()


	func test_basic_kill():
		var state = _make_state_with_players([1, 2])
		# Player 1 kills player 2.
		state.kills.append_array([1, 2])
		_update_scores(state)
		# Player 1 (rank 0) kills player 2 (rank 1).
		# Killing worse player = no bonus.
		assert_eq(
			state.players_by_id[1].score,
			100,
			"Killer gets base kill score",
		)
		# Player 2 (rank 1) killed by player 1 (rank 0).
		# Dying to better player = no extra penalty.
		# _DEATH_PENALTY = 20.
		assert_eq(
			state.players_by_id[2].score,
			-20,
			"Killee gets base death penalty",
		)


	func test_bump_adds_score():
		var state = _make_state_with_players([1, 2])
		# 3 bumps involving both players.
		state.bumps.append_array([1, 2, 1, 2, 1, 2])
		_update_scores(state)
		# Each player gets 5 points per bump.
		assert_eq(
			state.players_by_id[1].score,
			15,
			"Bumps add to score",
		)
		assert_eq(
			state.players_by_id[2].score,
			15,
			"Both players get bump points",
		)


	func test_rank_bonus_for_kill():
		var state = _make_state_with_players([1, 2, 3])
		# Player 2 kills player 3 five times.
		state.kills.append_array(
			[2, 3, 2, 3, 2, 3, 2, 3, 2, 3]
		)
		# Player 1 kills player 2 (higher-ranked).
		state.kills.append_array([1, 2])
		_update_scores(state)
		var score = state.players_by_id[1].score
		# Player 1 (rank 1) kills player 2 (rank 0).
		# rank_diff = 1 - 0 = 1, bonus = 5.
		# Total: 100 + 5 = 105.
		assert_eq(
			score,
			105,
			"Killing higher-ranked player gives bonus",
		)


	func test_rank_penalty_for_death():
		var state = _make_state_with_players([1, 2, 3])
		# Player 1 kills player 3 five times.
		state.kills.append_array(
			[1, 3, 1, 3, 1, 3, 1, 3, 1, 3]
		)
		# Player 2 (rank 1) kills player 1 (rank 0).
		state.kills.append_array([2, 1])
		_update_scores(state)
		# Player 1: 5 kills (100 each) + 1 death.
		# Death penalty: _DEATH_PENALTY(20) + rank
		# penalty(5). killer_rank(1) - my_rank(0) = 1.
		# Total: 500 - 25 = 475.
		assert_eq(
			state.players_by_id[1].score,
			475,
			"Death to lower-ranked has rank penalty",
		)


	func test_self_kill_penalty():
		var state = _make_state_with_players([1])
		state.kills.append_array([1, 1])
		_update_scores(state)
		var score = state.players_by_id[1].score
		assert_eq(
			score,
			-45,
			"Self-kill penalty applied",
		)


	func test_negative_score_allowed():
		var state = _make_state_with_players([1, 2])
		# Player 2 kills player 1 three times.
		state.kills.append_array(
			[2, 1, 2, 1, 2, 1]
		)
		_update_scores(state)
		var score = state.players_by_id[1].score
		assert_true(
			score < 0,
			"Negative scores are allowed",
		)
