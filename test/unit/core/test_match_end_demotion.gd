extends GutTest
## H42 (G2.1): on a normal match end, a disconnected player
## must not keep the win. GamePanel._server_initiate_match_end
## demotes whenever server_has_disconnected_players() is true;
## these tests pin the row assembly it relies on.


var _original_use_simple_score: bool


func before_each():
	_original_use_simple_score = G.settings.use_simple_score
	G.settings.use_simple_score = false


func after_each():
	G.settings.use_simple_score = _original_use_simple_score


func _make_player(pid: int, disconnected: bool) -> GamePlayerState:
	var p = GamePlayerState.new()
	p.player_id = pid
	p.connect_frame_index = 10
	p.disconnect_frame_index = 20 if disconnected else 10
	return p


func _make_state() -> GameMatchState:
	var state = GameMatchState.new()
	# Player 1: connected, one kill. Player 2: disconnected
	# leader with five kills. Player 3: connected, no kills.
	state.players_by_id[1] = _make_player(1, false)
	state.players_by_id[2] = _make_player(2, true)
	state.players_by_id[3] = _make_player(3, false)
	state.kills.append_array([1, 3])
	state.kills.append_array([2, 3, 2, 3, 2, 3, 2, 3, 2, 3])
	return state


func test_disconnected_leader_detected() -> void:
	var state = _make_state()
	assert_true(
		state.server_has_disconnected_players(),
		"a disconnected player is present",
	)


func test_all_connected_reports_none_disconnected() -> void:
	var state = GameMatchState.new()
	state.players_by_id[1] = _make_player(1, false)
	state.players_by_id[2] = _make_player(2, false)
	assert_false(
		state.server_has_disconnected_players(),
		"nobody disconnected",
	)


func test_demotion_strips_disconnected_leader_win() -> void:
	var state = _make_state()
	state.update_scores()
	assert_eq(
		state.players_by_id[2].rank, 1,
		"before demotion the disconnected leader leads (the bug)",
	)
	# The match-end sequence GamePanel runs.
	if state.server_has_disconnected_players():
		state.server_demote_disconnected_players()
	assert_eq(
		state.players_by_id[1].rank, 1,
		"connected player takes rank 1",
	)
	assert_eq(
		state.players_by_id[2].rank, 3,
		"disconnected leader drops below every connected player",
	)
	assert_eq(
		state.players_by_id[3].rank, 2,
		"connected players keep score order",
	)
