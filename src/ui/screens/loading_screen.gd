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


func _enter_tree() -> void:
	super._enter_tree()
	G.loading_screen = self


func _exit_tree() -> void:
	_disconnect_matchmaking_signal()


func _process(_delta: float) -> void:
	update_status_message()


func on_open() -> void:
	super.on_open()

	# Reset matchmaking state.
	_matchmaking_phase = ""
	_matchmaking_elapsed_sec = 0.0
	_matchmaking_estimated_sec = -1.0

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

	if Netcode.connector.is_connected_to_server:
		%Label.text = "Waiting for players..."
	elif not _matchmaking_phase.is_empty():
		%Label.text = _get_matchmaking_text()
	else:
		%Label.text = "Connecting to server..."


func _get_matchmaking_text() -> String:
	var phase_text: String
	match _matchmaking_phase:
		"queued":
			phase_text = "In queue"
		"searching":
			if _matchmaking_elapsed_sec >= (
					_EXPANSION_WAIT_SEC):
				phase_text = "Expanding search"
			else:
				phase_text = "Searching for match"
		"placing":
			phase_text = "Match found"
		_:
			phase_text = "Matchmaking"

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
				" ~%ds remaining"
				% ceili(remaining))

	return time_text + "..."


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
