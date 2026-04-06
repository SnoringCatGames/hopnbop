class_name LoadingScreen
extends Screen


## Expansion wait time from the FlexMatch
## ruleset. After this many seconds, the minimum
## player requirement relaxes.
const _EXPANSION_WAIT_SEC := 30.0

var _matchmaking_phase := ""
var _matchmaking_elapsed_sec := 0.0
var _matchmaking_estimated_sec := -1.0
var _is_matchmaking_connected := false
var _is_timed_out := false


func _enter_tree() -> void:
	super._enter_tree()
	G.loading_screen = self


func _exit_tree() -> void:
	_disconnect_matchmaking_signal()


func _process(delta: float) -> void:
	if (not _matchmaking_phase.is_empty()
			and not _is_timed_out
			and not Netcode.connector
				.is_connected_to_server):
		_matchmaking_elapsed_sec += delta
	update_status_message()


func on_open() -> void:
	super.on_open()

	# Reset matchmaking state.
	_matchmaking_phase = ""
	_matchmaking_elapsed_sec = 0.0
	_matchmaking_estimated_sec = -1.0
	_is_timed_out = false

	if is_instance_valid(%RetryButton):
		%RetryButton.visible = false

	# If game is no longer loading (disconnect
	# during transition), skip setup. The screen
	# system will immediately transition to
	# GAME_OVER.
	if not G.client_session.is_game_loading:
		Netcode.print(
			"LoadingScreen opened but game is no"
			+ " longer loading"
			+ " (disconnect during transition)",
			NetworkLogger.CATEGORY_GAME_STATE
		)
		return

	_connect_matchmaking_signal()

	# Set initial message.
	update_status_message()


func on_close() -> void:
	_disconnect_matchmaking_signal()


# Override the parent method, so we can force
# the hud theme.
func _set_default_styling() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	#theme = G.settings.default_theme
	add_theme_stylebox_override(
		"panel", G.settings.screen_style_box)


func update_status_message() -> void:
	if not is_instance_valid(%Label):
		return

	if _is_timed_out:
		%Label.text = tr("LOADING.NO_MATCH_FOUND")
		return

	if Netcode.connector.is_connected_to_server:
		%Label.text = tr(
			"LOADING.WAITING_FOR_PLAYERS")
	elif not _matchmaking_phase.is_empty():
		%Label.text = _get_matchmaking_text()
	else:
		%Label.text = tr("LOADING.CONNECTING")


func _get_matchmaking_text() -> String:
	var phase_text: String
	match _matchmaking_phase:
		"authenticating":
			phase_text = tr(
				"LOADING.AUTHENTICATING")
		"queued":
			phase_text = tr("LOADING.IN_QUEUE")
		"searching":
			if _matchmaking_elapsed_sec >= (
					_EXPANSION_WAIT_SEC):
				phase_text = tr(
					"LOADING.EXPANDING_SEARCH")
			else:
				phase_text = tr(
					"LOADING.SEARCHING")
		"placing":
			phase_text = tr("LOADING.MATCH_FOUND")
		_:
			phase_text = tr("LOADING.MATCHMAKING")

	# Authenticating phase does not show elapsed
	# time since it is typically very brief.
	if _matchmaking_phase == "authenticating":
		return phase_text

	# Show elapsed time.
	var elapsed := ceili(_matchmaking_elapsed_sec)
	var time_text := "%s (%ds)" % [
		phase_text, elapsed]

	# Show estimated remaining if available.
	if _matchmaking_estimated_sec > 0:
		var remaining := maxf(
			_matchmaking_estimated_sec
			- _matchmaking_elapsed_sec,
			0.0,
		)
		if remaining > 0:
			time_text += (
				" " + tr("LOADING.REMAINING")
				% ceili(remaining))

	return time_text + "..."


## Called by GamePanel when matchmaking times out.
## Shows the timeout message and retry button.
func show_matchmaking_timeout() -> void:
	_is_timed_out = true
	if is_instance_valid(%RetryButton):
		%RetryButton.visible = true
		%RetryButton.grab_focus()
	update_status_message()


func _on_retry_pressed() -> void:
	G.audio.play_sound("click")
	_is_timed_out = false
	if is_instance_valid(%RetryButton):
		%RetryButton.visible = false
	G.client_session.is_game_loading = true
	G.game_panel._client_client_request_session_ids()


func _connect_matchmaking_signal() -> void:
	if _is_matchmaking_connected:
		return
	if (
		is_instance_valid(G.game_panel)
		and G.game_panel.session_manager != null
	):
		(G.game_panel.session_manager
			.matchmaking_progress.connect(
				_on_matchmaking_progress))
		_is_matchmaking_connected = true


func _disconnect_matchmaking_signal() -> void:
	if not _is_matchmaking_connected:
		return
	if (
		is_instance_valid(G.game_panel)
		and G.game_panel.session_manager != null
	):
		(G.game_panel.session_manager
			.matchmaking_progress.disconnect(
				_on_matchmaking_progress))
	_is_matchmaking_connected = false


func _on_matchmaking_progress(
	phase: String,
	elapsed_sec: float,
	estimated_total_sec: float,
) -> void:
	_matchmaking_phase = phase
	_matchmaking_elapsed_sec = elapsed_sec
	_matchmaking_estimated_sec = (
		estimated_total_sec)
