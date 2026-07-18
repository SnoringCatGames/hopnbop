class_name CheatManager
extends Node
## Detects cheat code passwords typed during gameplay and manages
## cheat state. Networked cheats use RPCs; local cheats apply
## immediately.
##
## All cheat-enablement flags live on Settings so they can be
## toggled from the inspector.


signal cheat_toggled(cheat_name: String, is_active: bool)

## Rolling buffer of recently typed characters.
var _input_buffer := ""

## Maximum password length (computed from registry).
var _max_buffer_length := 0

## Registry of cheat codes. Each entry maps a password string to
## its configuration.
var _cheats := {}

## Set when a party match has forced the leader's gameplay cheats on
## this client, with the client's own are_cheats_enabled value at that
## moment. reset() (called on match cleanup) already zeroes the
## networked cheat flags; it also restores are_cheats_enabled from
## here, so forced cheats never leak into a later solo match.
var _forced_cheats_this_match := false
var _pre_force_cheats_enabled := false


func _ready() -> void:
	_cheats = {
		"flowerpower": {
			"is_networked": false,
			"settings_key":
				&"is_gore_enabled",
		},
		"jetpack": {
			"is_networked": true,
			"settings_key":
				&"is_jetpack_enabled",
		},
		"bloodisthickerthanwater": {
			"is_networked": false,
			"settings_key": (
				&"is_bloodisthickerthanwater"
				+ &"_enabled"),
		},
		"lordoftheflies": {
			"is_networked": true,
			"settings_key":
				&"is_lordoftheflies_enabled",
		},
		"pogostick": {
			"is_networked": true,
			"settings_key":
				&"is_pogostick_enabled",
		},
		"bunniesinspace": {
			"is_networked": true,
			"settings_key":
				&"is_bunniesinspace_enabled",
		},
		"moregore": {
			"is_networked": false,
			"settings_key":
				&"is_moregore_enabled",
		},
	}

	_max_buffer_length = 0
	for password in _cheats.keys():
		_max_buffer_length = max(
			_max_buffer_length,
			password.length(),
		)


func _unhandled_key_input(
	event: InputEvent,
) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var unicode: int = key_event.unicode
	if unicode == 0:
		return

	var c := char(unicode).to_lower()
	if c.length() != 1:
		return

	# Only accept a-z characters for cheat
	# passwords.
	if c < "a" or c > "z":
		return

	_input_buffer += c
	if _input_buffer.length() > _max_buffer_length:
		_input_buffer = _input_buffer.substr(
			_input_buffer.length()
			- _max_buffer_length)

	_check_for_cheats()


func _check_for_cheats() -> void:
	for password in _cheats.keys():
		if _input_buffer.ends_with(password):
			_activate_cheat(password)
			_input_buffer = ""
			break


func _activate_cheat(cheat_name: String) -> void:
	var cheat: Dictionary = _cheats[cheat_name]

	# Use Object.get() to avoid the cyclic-reference parser
	# failure on web/server exports. See CLAUDE.md "Web Build
	# Cyclic-Reference Parser Failures".
	var are_cheats_enabled: bool = (
		G.get("settings").get("are_cheats_enabled"))
	if not are_cheats_enabled:
		Netcode.print(
			"Cheat '%s' denied:"
			+ " cheats not enabled"
			% cheat_name,
		)
		return

	if cheat.is_networked:
		_request_toggle_networked_cheat.rpc_id(
			NetworkConnector.SERVER_ID,
			cheat_name,
		)
	else:
		_apply_local_cheat(cheat_name)


func _apply_local_cheat(
	cheat_name: String,
) -> void:
	var key: StringName = (
		_cheats[cheat_name].settings_key)
	var is_active: bool = not G.settings.get(key)

	# Persist via set_override BEFORE any direct
	# G.settings change. set_override compares
	# against the current value, so it must run
	# first. It also updates G.settings.
	if G.local_settings != null:
		G.local_settings.set_override(
			key, is_active)
		G.local_settings.save_settings()
	else:
		G.settings.set(key, is_active)

	Netcode.print(
		"Cheat '%s': %s" % [
			cheat_name,
			"ON" if is_active else "OFF",
		])
	cheat_toggled.emit(cheat_name, is_active)


@rpc("any_peer", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_DEBUG)
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
		cheat_name,
		_get_networked_cheat_state(cheat_name),
	)


func _apply_networked_cheat(
	cheat_name: String,
) -> void:
	_toggle_networked_cheat_setting(cheat_name)
	var is_active := (
		_get_networked_cheat_state(cheat_name))
	Netcode.print(
		"Cheat '%s': %s" % [
			cheat_name,
			"ON" if is_active else "OFF",
		])
	cheat_toggled.emit(cheat_name, is_active)


@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_DEBUG)
func _client_on_networked_cheat_toggled(
	cheat_name: String,
	is_active: bool,
) -> void:
	# Persist via set_override BEFORE updating
	# G.settings so the default comparison works.
	if (G.local_settings != null
			and _cheats.has(cheat_name)):
		var key: StringName = (
			_cheats[cheat_name].settings_key)
		G.local_settings.set_override(
			key, is_active)
		G.local_settings.save_settings()

	_set_networked_cheat_setting(
		cheat_name, is_active)
	Netcode.print(
		"Cheat '%s': %s" % [
			cheat_name,
			"ON" if is_active else "OFF",
		])
	cheat_toggled.emit(cheat_name, is_active)


## Toggles the Settings flag for a networked
## cheat.
func _toggle_networked_cheat_setting(
	cheat_name: String,
) -> void:
	match cheat_name:
		"jetpack":
			G.settings.is_jetpack_enabled = (
				not G.settings.is_jetpack_enabled)
		"lordoftheflies":
			G.settings.is_lordoftheflies_enabled = (
				not G.settings
					.is_lordoftheflies_enabled)
		"pogostick":
			G.settings.is_pogostick_enabled = (
				not G.settings
					.is_pogostick_enabled)
		"bunniesinspace":
			G.settings.is_bunniesinspace_enabled = (
				not G.settings
					.is_bunniesinspace_enabled)


## Sets the Settings flag for a networked cheat.
func _set_networked_cheat_setting(
	cheat_name: String,
	is_active: bool,
) -> void:
	match cheat_name:
		"jetpack":
			G.settings.is_jetpack_enabled = is_active
		"lordoftheflies":
			G.settings.is_lordoftheflies_enabled = (
				is_active)
		"pogostick":
			G.settings.is_pogostick_enabled = (
				is_active)
		"bunniesinspace":
			G.settings.is_bunniesinspace_enabled = (
				is_active)


## Returns the current state of a networked
## cheat.
func _get_networked_cheat_state(
	cheat_name: String,
) -> bool:
	match cheat_name:
		"jetpack":
			return G.settings.is_jetpack_enabled
		"lordoftheflies":
			return (
				G.settings
					.is_lordoftheflies_enabled)
		"pogostick":
			return (
				G.settings
					.is_pogostick_enabled)
		"bunniesinspace":
			return (
				G.settings
					.is_bunniesinspace_enabled)
	return false


# --------------------------------------------------------------
# Leader-authoritative match cheats (party matches)
# --------------------------------------------------------------


## Apply the party leader's gameplay-cheat prefs for this match,
## server-side. Reads MATCH_CHEAT_PREFS (set by the runtime on the
## Edgegap deploy env at allocation), enables the named networked
## (gameplay) cheats on the server, and broadcasts each to clients so
## it overrides their local settings for the match. Aesthetic (local)
## cheats are never forced. No-op for solo matches (env absent) or
## when cheats aren't enabled.
func server_apply_match_cheats() -> void:
	if not Netcode.runs_server_logic:
		return
	var raw := OS.get_environment("MATCH_CHEAT_PREFS")
	if raw.is_empty():
		return
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return
	if not bool(parsed.get("are_cheats_enabled", false)):
		return
	G.settings.are_cheats_enabled = true
	var names: Variant = parsed.get("networked_cheats", [])
	if not (names is Array):
		return
	for n in names:
		var cheat_name := str(n)
		if not _cheats.has(cheat_name):
			continue
		if not _cheats[cheat_name].is_networked:
			# Only gameplay (networked) cheats are leader-
			# authoritative; aesthetic ones stay per-client.
			continue
		_set_networked_cheat_setting(cheat_name, true)
		# call_remote broadcast (the server set its own state above).
		_client_apply_match_cheat.rpc(cheat_name, true)
		Netcode.print(
			"Forced leader match cheat '%s' ON" % cheat_name)


## Client receipt of a leader-forced match cheat. Unlike
## _client_on_networked_cheat_toggled this does NOT persist to local
## settings: the forced value is match-scoped and reverted on match
## cleanup via reset_networked_cheats_to_local. Snapshots the client's
## own state on the first force so it can be restored.
@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_DEBUG)
func _client_apply_match_cheat(
	cheat_name: String,
	is_active: bool,
) -> void:
	if not _cheats.has(cheat_name):
		return
	# Snapshot are_cheats_enabled on the first force so reset() can
	# restore it (the cheat flags themselves are zeroed by reset()).
	if not _forced_cheats_this_match:
		_forced_cheats_this_match = true
		_pre_force_cheats_enabled = G.settings.are_cheats_enabled
	# The effect check (is_*_cheat_active) also requires the master
	# flag, so force it on for the match.
	G.settings.are_cheats_enabled = true
	_set_networked_cheat_setting(cheat_name, is_active)
	Netcode.print(
		"Match cheat '%s': %s" % [
			cheat_name, "ON" if is_active else "OFF"])
	cheat_toggled.emit(cheat_name, is_active)


## Returns true if the jetpack cheat is currently
## active. Safe to call even when Settings hasn't
## been loaded yet.
static func is_jetpack_cheat_active() -> bool:
	return (
		G.settings != null
		and G.settings.are_cheats_enabled
		and G.settings.is_jetpack_enabled
	)


## Returns true if the pogostick cheat is
## currently active. Safe to call even when
## Settings hasn't been loaded yet.
static func is_pogostick_cheat_active() -> bool:
	return (
		G.settings != null
		and G.settings.are_cheats_enabled
		and G.settings.is_pogostick_enabled
	)


## Returns true if the bunniesinspace cheat is
## currently active. Safe to call even when
## Settings hasn't been loaded yet.
static func is_bunniesinspace_cheat_active() -> bool:
	return (
		G.settings != null
		and G.settings.are_cheats_enabled
		and G.settings.is_bunniesinspace_enabled
	)


## Returns true if the lordoftheflies cheat is
## currently active. Safe to call even when
## Settings hasn't been loaded yet.
static func is_lordoftheflies_cheat_active() -> bool:
	return (
		G.settings != null
		and G.settings.are_cheats_enabled
		and G.settings.is_lordoftheflies_enabled
	)


## Returns true if the bloodisthickerthanwater
## cheat is currently active. Safe to call even
## when Settings hasn't been loaded yet.
static func is_bloodisthickerthanwater_cheat_active(
) -> bool:
	return (
		G.settings != null
		and G.settings.are_cheats_enabled
		and G.settings
			.is_bloodisthickerthanwater_enabled
	)


## Returns true if the moregore cheat is
## currently active. Safe to call even when
## Settings hasn't been loaded yet.
static func is_moregore_cheat_active() -> bool:
	return (
		G.settings != null
		and G.settings.are_cheats_enabled
		and G.settings.is_moregore_enabled
	)


## Resets all networked cheat state between
## matches.
func reset() -> void:
	G.settings.is_jetpack_enabled = false
	G.settings.is_lordoftheflies_enabled = false
	G.settings.is_pogostick_enabled = false
	G.settings.is_bunniesinspace_enabled = false
	# If a party match forced the leader's cheats on this client,
	# restore the client's own are_cheats_enabled (the forced value
	# was applied in-memory only, never persisted).
	if _forced_cheats_this_match:
		G.settings.are_cheats_enabled = _pre_force_cheats_enabled
		_forced_cheats_this_match = false
	_input_buffer = ""
