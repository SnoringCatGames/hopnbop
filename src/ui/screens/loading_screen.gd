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
var _has_recoverable_failure := false
var _failure_text_key := ""


func _enter_tree() -> void:
	super._enter_tree()
	G.loading_screen = self


func _exit_tree() -> void:
	_disconnect_matchmaking_signal()


func _process(delta: float) -> void:
	if (not _matchmaking_phase.is_empty()
			and not _has_recoverable_failure
			and not Netcode.connector
				.is_connected_to_server):
		_matchmaking_elapsed_sec += delta
	update_status_message()
	_update_action_buttons()


func on_open() -> void:
	super.on_open()

	# Reset matchmaking state.
	_matchmaking_phase = ""
	_matchmaking_elapsed_sec = 0.0
	_matchmaking_estimated_sec = -1.0
	_has_recoverable_failure = false
	_failure_text_key = ""

	if is_instance_valid(%RetryButton):
		%RetryButton.visible = false
	if is_instance_valid(%CancelButton):
		%CancelButton.visible = false

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
	_update_action_buttons()


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

	if _has_recoverable_failure:
		var key := (
			_failure_text_key
			if not _failure_text_key.is_empty()
			else "LOADING.NO_MATCH_FOUND"
		)
		%Label.text = tr(key)
		return

	if Netcode.connector.is_connected_to_server:
		%Label.text = tr(
			"LOADING.WAITING_FOR_PLAYERS")
		return

	# If the fleet has not reached ready yet, surface
	# the warming-up status. This covers the window
	# between app open and the first match, where
	# matchmaking would otherwise fail with "no match"
	# because no instance is available.
	if _is_fleet_warming_up():
		%Label.text = _get_warming_up_text()
		return

	if not _matchmaking_phase.is_empty():
		%Label.text = _get_matchmaking_text()
	else:
		%Label.text = tr("LOADING.CONNECTING")


func _is_fleet_warming_up() -> bool:
	if not is_instance_valid(G.backend_api_client):
		return false
	if G.settings.prefer_offline_mode:
		return false
	return G.backend_api_client.is_fleet_warming_up()


func _get_warming_up_text() -> String:
	var remaining: int = (
		G.backend_api_client
			.get_fleet_estimated_remaining_sec())
	var base := tr("LOADING.WARMING_UP_SERVER")
	if remaining <= 0:
		return base
	return base + " " + (
		tr("LOADING.REMAINING_MMSS")
		% _format_remaining_mmss(remaining))


static func _format_remaining_mmss(seconds: int) -> String:
	var minutes := seconds / 60
	var remainder := seconds % 60
	return "%d:%02d" % [minutes, remainder]


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
## Shows "no match found" + retry button.
func show_matchmaking_timeout() -> void:
	show_matchmaking_failure("LOADING.NO_MATCH_FOUND")


## Called by GamePanel for any recoverable matchmaking
## failure (timeout, allocation failure, socket drop).
## Pins the status text to failure_text_key and shows
## the retry button. The Cancel button is hidden — the
## flow is "retry on this screen, or hit Back on the
## controller to bail out."
func show_matchmaking_failure(failure_text_key: String) -> void:
	_has_recoverable_failure = true
	_failure_text_key = failure_text_key
	if is_instance_valid(%CancelButton):
		%CancelButton.visible = false
	if is_instance_valid(%RetryButton):
		%RetryButton.visible = true
		%RetryButton.grab_focus()
	update_status_message()


func _on_retry_pressed() -> void:
	G.audio.play_sound("click")
	_has_recoverable_failure = false
	_failure_text_key = ""
	if is_instance_valid(%RetryButton):
		%RetryButton.visible = false
	G.client_session.is_game_loading = true
	G.game_panel._client_client_request_session_ids()


func _on_cancel_pressed() -> void:
	G.audio.play_sound("click")
	if is_instance_valid(%CancelButton):
		%CancelButton.visible = false
	G.game_panel.client_cancel_matchmaking()


func _update_action_buttons() -> void:
	if not is_instance_valid(%CancelButton):
		return
	# Cancel is only meaningful while a matchmaker
	# ticket is live: we're past auth, not yet
	# connected to a game server, and no failure is
	# being retried. Hidden during fleet warmup (no
	# ticket exists yet).
	#
	# Stage 7.2: "placing" is now cancelable too —
	# the runtime tracks in-flight Edgegap allocations
	# and the cancel_matchmaking_allocation RPC tears
	# down the deploy + fans out match_failed to peers
	# so they see a recoverable "match cancelled by a
	# peer" prompt instead of waiting on the 120 s
	# client timeout.
	var phase_active := (
		_matchmaking_phase == "queued"
		or _matchmaking_phase == "searching"
		or _matchmaking_phase == "placing"
	)
	var should_show := (
		phase_active
		and not _has_recoverable_failure
		and not Netcode.connector
			.is_connected_to_server
	)
	%CancelButton.visible = should_show


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
