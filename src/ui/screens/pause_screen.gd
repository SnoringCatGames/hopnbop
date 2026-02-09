class_name PauseScreen
extends Screen


var _can_local_peer_unpause := false


func _enter_tree() -> void:
	super._enter_tree()
	G.pause_screen = self


func on_open() -> void:
	super.on_open()
	_update_pause_info()
	%Button.grab_focus.call_deferred()


func _process(_delta: float) -> void:
	if visible:
		_update_countdown()


func _update_pause_info() -> void:
	var frame_driver := Netcode.frame_driver
	var initiator_peer_id := frame_driver._pause_initiator_peer_id
	var initiator_pauses_used := frame_driver._pause_initiator_pauses_used
	var max_pauses := G.settings.max_pauses_per_client

	# Update "Paused by" label.
	%PausedByLabel.text = "Paused by client %d" % initiator_peer_id

	# Update pauser's pauses remaining.
	var pauser_remaining := maxi(0, max_pauses - initiator_pauses_used)
	%PauserPausesRemainingLabel.text = "Pauses remaining for pauser: %d/%d" % [
		pauser_remaining,
		max_pauses,
	]

	# Update local peer's pauses remaining.
	var local_peer_id := multiplayer.get_unique_id()
	var local_pauses_used: int = 0
	if G.game_panel.match_state.pauses_used_by_peer.has(
		local_peer_id
	):
		local_pauses_used = G.game_panel.match_state \
			.pauses_used_by_peer[local_peer_id]

	var local_remaining := maxi(0, max_pauses - local_pauses_used)
	%LocalPausesRemainingLabel.text = "Your pauses remaining: %d/%d" % [
		local_remaining,
		max_pauses,
	]

	# Check if local peer can unpause.
	_can_local_peer_unpause = _check_if_local_peer_can_unpause(initiator_peer_id)
	%Button.disabled = not _can_local_peer_unpause

	if not _can_local_peer_unpause:
		%Button.text = "Unpause (locked)"
	else:
		%Button.text = "Unpause"


func _update_countdown() -> void:
	var frame_driver := Netcode.frame_driver
	var auto_unpause_time := frame_driver._pause_auto_unpause_time_usec

	if auto_unpause_time > 0:
		var remaining_usec := auto_unpause_time - Time.get_ticks_usec()
		var remaining_sec := maxi(0, ceili(remaining_usec / 1_000_000.0))
		%TimeRemainingLabel.text = "Auto-unpause in: %d seconds" % remaining_sec
	else:
		%TimeRemainingLabel.text = ""


func _check_if_local_peer_can_unpause(initiator_peer_id: int) -> bool:
	# Server can always unpause.
	if Netcode.is_server:
		return true

	# Check if local peer is the initiator.
	var local_peer_id := multiplayer.get_unique_id()
	return local_peer_id == initiator_peer_id


func _on_button_pressed() -> void:
	if not _can_local_peer_unpause:
		# Could play error sound here.
		return

	G.audio.play_sound("click")
	Netcode.frame_driver.client_request_unpause()
