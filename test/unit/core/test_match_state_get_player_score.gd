extends GutTest
## Unit tests for GameMatchState.update_scores()


class TestMatchStateGetPlayerScore:
	extends GutTest


	func _make_state_with_players(player_ids: Array) -> GameMatchState:
		var state = GameMatchState.new()
		for pid in player_ids:
			var p = PlayerMatchState.new()
			p.player_id = pid
			state.players_by_id[pid] = p
		return state


	func _update_scores(state: GameMatchState) -> void:
		state.update_scores()


	func test_basic_kill_and_death():
		var state = _make_state_with_players([1, 2])
		state.kills.append_array([1, 2])
		state._total_kills_by_player_id[1] = 1
		state._total_deaths_by_player_id[2] = 1
		_update_scores(state)
		assert_eq(state.players_by_id[1].score, 105, "Killer gets kill score + rank bonus")
		assert_eq(state.players_by_id[2].score, -95, "Killee gets death penalty + rank penalty")


	func test_bump_adds_score():
		var state = _make_state_with_players([1, 2])
		state._total_bumps_by_player_id[1] = 3
		_update_scores(state)
		assert_eq(state.players_by_id[1].score, 15, "Bumps add to score")


	func test_rank_bonus_for_kill():
		var state = _make_state_with_players([1, 2, 3])
		state._total_kills_by_player_id[2] = 5
		state._total_kills_by_player_id[1] = 1
		state.kills.append_array([1, 2])
		state._total_deaths_by_player_id[2] = 1
		state._total_kills_by_player_id[1] += 1
		_update_scores(state)
		var score = state.players_by_id[1].score
		assert_true(score > 100, "Killing higher-ranked player gives bonus")


	func test_rank_penalty_for_death():
		var state = _make_state_with_players([1, 2, 3])
		state._total_kills_by_player_id[1] = 5
		state._total_kills_by_player_id[2] = 1
		state.kills.append_array([2, 1])
		state._total_deaths_by_player_id[1] = 1
		state._total_kills_by_player_id[2] += 1
		_update_scores(state)
		var score = state.players_by_id[1].score
		assert_eq(score, -90, "Death to lower-ranked player is only penalized by DEATH_PENALTY")


	func test_self_kill_penalty():
		var state = _make_state_with_players([1])
		state.kills.append_array([1, 1])
		_update_scores(state)
		var score = state.players_by_id[1].score
		assert_eq(score, -45, "Self-kill penalty applied")


	func test_negative_score_allowed():
		var state = _make_state_with_players([1, 2])
		state.kills.append_array([2, 1])
		state._total_deaths_by_player_id[1] = 10
		_update_scores(state)
		var score = state.players_by_id[1].score
		assert_true(score < 0, "Negative scores are allowed")
