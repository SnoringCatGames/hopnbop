class_name CheatManager
extends Node
## Detects cheat code passwords typed during gameplay and manages
## cheat state. Networked cheats use RPCs; local cheats apply
## immediately.


signal cheat_toggled(cheat_name: String, is_active: bool)

## Active networked cheat states.
var is_jetpack_active := false

## Rolling buffer of recently typed characters.
var _input_buffer := ""

## Maximum password length (computed from registry).
var _max_buffer_length := 0

## Registry of cheat codes. Each entry maps a password string to
## its configuration.
var _cheats := {}


func _ready() -> void:
	_cheats = {
		"flowerpower": {
			"is_networked": false,
		},
		"jetpack": {
			"is_networked": true,
		},
	}

	_max_buffer_length = 0
	for password in _cheats.keys():
		_max_buffer_length = max(
			_max_buffer_length, password.length()
		)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var unicode: int = key_event.unicode
	if unicode == 0:
		return

	var c := char(unicode).to_lower()
	if c.length() != 1:
		return

	# Only accept a-z characters for cheat passwords.
	if c < "a" or c > "z":
		return

	_input_buffer += c
	if _input_buffer.length() > _max_buffer_length:
		_input_buffer = _input_buffer.substr(
			_input_buffer.length() - _max_buffer_length
		)

	_check_for_cheats()


func _check_for_cheats() -> void:
	for password in _cheats.keys():
		if _input_buffer.ends_with(password):
			_activate_cheat(password)
			_input_buffer = ""
			break


func _activate_cheat(cheat_name: String) -> void:
	var cheat: Dictionary = _cheats[cheat_name]

	if cheat.is_networked:
		if not G.settings.are_cheats_enabled:
			Netcode.print(
				"Cheat '%s' denied: cheats not enabled"
				% cheat_name
			)
			return
		_request_toggle_networked_cheat.rpc_id(
			NetworkConnector.SERVER_ID, cheat_name
		)
	else:
		# Local cheats always work.
		_apply_local_cheat(cheat_name)


func _apply_local_cheat(cheat_name: String) -> void:
	match cheat_name:
		"flowerpower":
			G.settings.is_gore_enabled = \
				not G.settings.is_gore_enabled
			Netcode.print(
				"Cheat 'flowerpower': gore %s" % (
					"ON" if G.settings.is_gore_enabled
					else "OFF"
				)
			)
	cheat_toggled.emit(cheat_name, true)


@rpc("any_peer", "reliable")
func _request_toggle_networked_cheat(
	cheat_name: String,
) -> void:
	if not Netcode.is_server:
		return
	if not G.settings.are_cheats_enabled:
		return
	if not _cheats.has(cheat_name):
		return
	if not _cheats[cheat_name].is_networked:
		return

	_apply_networked_cheat(cheat_name)

	# Broadcast to all clients.
	_client_on_networked_cheat_toggled.rpc(
		cheat_name, is_jetpack_active
	)


func _apply_networked_cheat(cheat_name: String) -> void:
	match cheat_name:
		"jetpack":
			is_jetpack_active = not is_jetpack_active
			Netcode.print(
				"Cheat 'jetpack': %s" % (
					"ON" if is_jetpack_active
					else "OFF"
				)
			)
	cheat_toggled.emit(cheat_name, is_jetpack_active)


@rpc("authority", "reliable")
func _client_on_networked_cheat_toggled(
	cheat_name: String,
	is_active: bool,
) -> void:
	match cheat_name:
		"jetpack":
			is_jetpack_active = is_active
			Netcode.print(
				"Cheat 'jetpack': %s" % (
					"ON" if is_jetpack_active
					else "OFF"
				)
			)
	cheat_toggled.emit(cheat_name, is_active)


## Returns true if the jetpack cheat is currently active.
## Safe to call even when CheatManager hasn't been created yet.
static func is_jetpack_cheat_active() -> bool:
	return (
		G.cheat_manager != null
		and G.cheat_manager.is_jetpack_active
	)


## Resets all cheat state between matches.
func reset() -> void:
	is_jetpack_active = false
	_input_buffer = ""
