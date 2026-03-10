class_name GameOverScreen
extends Screen




func _enter_tree() -> void:
	super._enter_tree()
	G.game_over_screen = self


func on_open() -> void:
	super.on_open()

	# Display server message if present.
	if not (G.client_session
			.latest_server_message.is_empty()):
		%MessageLabel.text = (
			G.client_session
				.latest_server_message)
		%MessageLabel.visible = true
	else:
		%MessageLabel.visible = false

	_populate_results()

	# Wait a frame for the button to be fully
	# ready, then grab focus.
	await get_tree().process_frame
	%Button.grab_focus()


func _populate_results() -> void:
	# Clear previous results.
	for child in %ResultsContainer.get_children():
		child.queue_free()

	var match_state: GameMatchState = (
		G.client_session.latest_match_state
		as GameMatchState)
	if match_state == null:
		return
	if match_state.players_by_id.is_empty():
		return

	# Sort players by rank.
	var sorted_players: Array = (
		match_state.players_by_id.values())
	sorted_players.sort_custom(
		func(a: GamePlayerState,
			b: GamePlayerState) -> bool:
			return a.rank < b.rank)

	for ps: GamePlayerState in sorted_players:
		var stats: PlayerMatchStats = (
			match_state.get_player_stats(
				ps.player_id))
		_add_result_row(ps, stats)


func _add_result_row(
	ps: GamePlayerState,
	stats: PlayerMatchStats,
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(
		"separation", 16)
	%ResultsContainer.add_child(row)

	# Rank label.
	var rank_label := Label.new()
	rank_label.text = _ordinal(ps.rank)
	rank_label.custom_minimum_size.x = 40
	row.add_child(rank_label)

	# Player name (colored).
	var name_label := Label.new()
	name_label.text = String(ps.full_name)
	name_label.modulate = ps.label_color
	name_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	row.add_child(name_label)

	# Score.
	var score_label := Label.new()
	score_label.text = str(ps.score)
	score_label.custom_minimum_size.x = 50
	score_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(score_label)

	# K/D.
	if stats != null:
		var kd_label := Label.new()
		kd_label.text = "%d/%d" % [
			stats.kill_count,
			stats.death_count,
		]
		kd_label.custom_minimum_size.x = 50
		kd_label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_RIGHT)
		row.add_child(kd_label)


func _ordinal(n: int) -> String:
	match n:
		1:
			return tr("ORDINAL.1ST")
		2:
			return tr("ORDINAL.2ND")
		3:
			return tr("ORDINAL.3RD")
		_:
			return tr("ORDINAL.NTH") % n


func _on_button_pressed() -> void:
	G.audio.play_sound("click")
	G.screens.client_open_screen(
		ScreensMain.ScreenType.LOBBY)


func _on_leaderboard_pressed() -> void:
	G.audio.play_sound("click")
	var panel: LeaderboardPanel = preload(
		"res://src/ui/leaderboard_panel/"
		+ "leaderboard_panel.tscn"
	).instantiate()
	get_tree().root.add_child(panel)
