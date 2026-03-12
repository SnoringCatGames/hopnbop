class_name GameOverScreen
extends Screen


## Set of backend player IDs that have been
## friend-added this session (to avoid duplicates).
var _added_friend_ids: Dictionary = {}


func _enter_tree() -> void:
	super._enter_tree()
	G.game_over_screen = self


func on_open() -> void:
	super.on_open()
	_added_friend_ids.clear()

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
	%PlayAgainButton.grab_focus()


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

	# Ensure scores and ranks are calculated from
	# the replicated kills/bumps arrays.
	match_state.update_scores()

	# Build lookup of participants with backend IDs.
	var participants := (
		G.client_session
			.latest_match_participants)

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
		var backend_id := (
			_find_backend_id(
				ps.player_id, participants))
		_add_result_row(ps, stats, backend_id)


func _find_backend_id(
	player_id: int,
	participants: Array[Dictionary],
) -> String:
	for entry in participants:
		if entry.get("player_id", -1) == player_id:
			return entry.get(
				"backend_player_id", "")
	return ""


func _add_result_row(
	ps: GamePlayerState,
	stats: PlayerMatchStats,
	backend_player_id: String,
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(
		"separation", 16)
	row.alignment = (
		BoxContainer.ALIGNMENT_CENTER)
	%ResultsContainer.add_child(row)

	# Profile image.
	var profile_image := ProfileImageDisplay.new()
	profile_image.image_size = 48
	row.add_child(profile_image)
	profile_image.set_player(
		ps.player_id, ps.base_color)

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

	# Add Friend button for non-local, non-anonymous
	# players with a backend player ID.
	if (not backend_player_id.is_empty()
			and not G.auth_token_store.is_anonymous):
		var add_button := Button.new()
		add_button.text = tr("FRIENDS.ADD")
		add_button.pressed.connect(
			_on_add_friend_pressed.bind(
				backend_player_id, add_button))
		row.add_child(add_button)


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


func _on_add_friend_pressed(
	backend_player_id: String,
	button: Button,
) -> void:
	if backend_player_id in _added_friend_ids:
		return
	_added_friend_ids[backend_player_id] = true
	button.disabled = true
	button.text = "✓"

	G.friends_api_client.add_friend_by_player_id(
		backend_player_id, "recent_match")

	# Show toast on result.
	if not G.friends_api_client.friend_added\
			.is_connected(_on_friend_add_result):
		G.friends_api_client.friend_added.connect(
			_on_friend_add_result,
			CONNECT_ONE_SHOT)
		G.friends_api_client.request_failed\
			.connect(
				_on_friend_add_failed,
				CONNECT_ONE_SHOT)


func _on_friend_add_result(
	data: Dictionary,
) -> void:
	if G.friends_api_client.request_failed\
			.is_connected(_on_friend_add_failed):
		G.friends_api_client.request_failed\
			.disconnect(_on_friend_add_failed)
	var already: bool = data.get(
		"already_friends", false)
	if is_instance_valid(G.toast_overlay):
		if already:
			G.toast_overlay.show_toast(
				tr("FRIENDS.ALREADY_FRIENDS"))
		else:
			G.toast_overlay.show_toast(
				tr("FRIENDS.ADDED"))


func _on_friend_add_failed(error: String) -> void:
	if G.friends_api_client.friend_added\
			.is_connected(_on_friend_add_result):
		G.friends_api_client.friend_added\
			.disconnect(_on_friend_add_result)
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			error, G.toast_overlay.Type.ERROR)


func _on_play_again_pressed() -> void:
	G.audio.play_sound("click")
	G.game_panel.client_play_again()


func _on_return_to_lobby_pressed() -> void:
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
