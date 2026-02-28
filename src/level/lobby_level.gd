@tool
class_name LobbyLevel
extends Level
## Local player management lobby (no networking).
## Players spawn/despawn via keyboard partitions and gamepads.


const _SPAWN_SPEED_MIN := 150.0
const _SPAWN_SPEED_MAX := 270.0
const _SPAWN_TARGET_DIRECTION := Vector2(2, -1)
const _SPAWN_VELOCITY_ANGLE_MAX_OFFSET := PI / 16

## Array of device configs (null = slot empty).
var _pending_device_configs_by_index: Array[DeviceConfig] = []

# Dictionary<StringName, DeviceConfig>
var _pending_device_configs_by_name := {}

# Dictionary<StringName, int> - maps device name to
# player_id. Needed because _pending_device_configs_by_index
# shifts on removal, invalidating index-based ID lookups.
var _device_name_to_player_id := {}

# Monotonically increasing counter for unique lobby player
# IDs. Prevents ID collisions when players are removed and
# re-added (array indices shift, but this counter never
# decreases).
var _next_lobby_id_counter := 0


func _ready() -> void:
	super._ready()


func _physics_process(_delta: float) -> void:
	_check_keyboard_inputs()
	_check_gamepad_inputs()


func _check_keyboard_inputs() -> void:
	# Check each join/leave buttons for each keyboard partition.
	for i in range(
		InputDeviceManager.KEYBOARD_PARTITION_BINDINGS.size()
	):
		var bindings: Dictionary = \
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[i]
		# Skip device used by settings UI player.
		if _is_device_used_by_settings_ui(
				bindings["name"]):
			continue
		if Input.is_physical_key_pressed(bindings["move_up"]):
			_try_register_keyboard_player(bindings)
		elif Input.is_physical_key_pressed(
			bindings["move_down"]
		):
			_deregister_player(bindings["name"])


func _check_gamepad_inputs() -> void:
	for device_id in Input.get_connected_joypads():
		# Skip device used by settings UI player.
		var device_name := \
			DeviceConfig.get_controller_device_name(
				device_id)
		if _is_device_used_by_settings_ui(
				device_name):
			continue
		if Input.is_action_pressed("move_up", device_id):
			_try_register_gamepad_player(device_id)
		elif Input.is_action_pressed(
			"move_down", device_id
		):
			_try_deregister_gamepad_player(device_id)


func _try_register_keyboard_player(
	key_bindings: Dictionary,
) -> void:
	if (
		_pending_device_configs_by_index.size()
		>= G.settings.max_local_player_count
	):
		# No available slots.
		return

	var device_name: StringName = key_bindings["name"]
	if _pending_device_configs_by_name.has(device_name):
		# Already registered.
		return

	var device_config := DeviceConfig.new(
		DeviceConfig.DeviceType.KEYBOARD,
		DeviceConfig.KEYBOARD_DEVICE_ID,
		key_bindings)
	_register_player(device_config)


func _try_register_gamepad_player(device_id: int) -> void:
	if (
		_pending_device_configs_by_index.size()
		>= G.settings.max_local_player_count
	):
		# No available slots.
		return

	var device_name := \
		DeviceConfig.get_controller_device_name(device_id)
	if _pending_device_configs_by_name.has(device_name):
		# Already registered.
		return

	var device_config := DeviceConfig.new(
		DeviceConfig.DeviceType.GAMEPAD,
		device_id,
		{})
	_register_player(device_config)


func _try_deregister_gamepad_player(
	device_id: int,
) -> void:
	var device_name := \
		DeviceConfig.get_controller_device_name(device_id)
	_deregister_player(device_name)


func _register_player(
	device_config: DeviceConfig,
	p_attributes: Dictionary = {},
) -> void:
	# Use monotonic counter for unique player identity.
	# Dense array index is only for array operations.
	var lobby_id := _next_lobby_id_counter
	_next_lobby_id_counter += 1

	# Register device config BEFORE creating/adding player,
	# so that Player._ready() can find the device when
	# setting up action sources.
	_pending_device_configs_by_index.append(device_config)
	_pending_device_configs_by_name[device_config.name] = \
		device_config

	# Use lobby_id as the device map key (matches what
	# Player._ready() derives from player_id).
	G.input_device_manager.assign_device_to_player(
		lobby_id,
		device_config
	)

	# Now create and add player to tree (triggers _ready()).
	var player: Player = \
		G.settings.default_player_scene.instantiate()
	player.player_id = get_local_player_id(lobby_id)
	player.name = "LobbyPlayer_%d" % lobby_id
	var spawn_position := _get_player_spawn_position()
	player.global_position = spawn_position
	players_node.add_child(player)
	player.global_position = spawn_position
	player.force_launch(_get_spawn_velocity())

	# Disable inter-player physics collision in lobby.
	# Only remove from mask (don't push other players),
	# keep layer so Area2Ds (RabbitHole) can still detect.
	player.set_collision_mask_value(
		Player._PLAYER_COLLISION_LAYER, false)

	register_player(player)

	# Play jump sound for the newly-spawned bunny.
	player.play_sound("jump")

	# Track device name to player_id mapping.
	_device_name_to_player_id[device_config.name] = \
		player.player_id

	# Generate or reuse player attributes.
	var attributes := p_attributes
	if attributes.is_empty():
		attributes = \
			PlayerAttributeGenerator \
				.generate_random_attributes()
	G.client_session.local_player_attributes.append(
		attributes)

	# Create lobby GamePlayerState for display purposes.
	var player_state := GamePlayerState.new()
	player_state.set_up(
		player.player_id,
		0,
		lobby_id,
		attributes)
	G.match_state.players_by_id[player.player_id] = \
		player_state

	# Hide the corresponding control display.
	%ControlDisplays.set_device_in_use(
		device_config.name, true)

	# Update lobby colors for all players.
	_update_lobby_colors()

	Netcode.print(
		"Spawned lobby player %d (id=%d)" % [
			lobby_id, player.player_id],
		NetworkLogger.CATEGORY_PLAYER_ACTIONS)

	if is_instance_valid(G.game_panel):
		G.game_panel.lobby_players_updated.emit()


func _get_player_spawn_position() -> Vector2:
	var available_spawn_points := _get_spawn_points()
	return available_spawn_points.pick_random() \
		.spawn_position


func _get_spawn_velocity() -> Vector2:
	var target_angle := _SPAWN_TARGET_DIRECTION.angle()
	var spawn_angle := (
		target_angle
		- _SPAWN_VELOCITY_ANGLE_MAX_OFFSET
		+ _SPAWN_VELOCITY_ANGLE_MAX_OFFSET * 2 * randf()
	)
	var speed := randf_range(
		_SPAWN_SPEED_MIN, _SPAWN_SPEED_MAX)
	return Vector2.from_angle(spawn_angle) * speed


func _deregister_player(
	device_name: StringName,
) -> void:
	if not _pending_device_configs_by_name.has(device_name):
		# Not registered.
		return

	var device_config: DeviceConfig = \
		_pending_device_configs_by_name[device_name]
	var dense_index := \
		_pending_device_configs_by_index.find(device_config)

	# Look up player_id from stable mapping (not from
	# array index, which shifts on removal).
	var player_id: int = \
		_device_name_to_player_id[device_name]
	if not Netcode.ensure(players_by_id.has(player_id)):
		return

	var player: Player = players_by_id[player_id]

	# Derive the stable lobby_id that was used as the
	# device map key (reverse of get_local_player_id).
	var lobby_id := - (player_id + 1)

	_pending_device_configs_by_index.remove_at(
		dense_index)
	_pending_device_configs_by_name.erase(device_name)
	_device_name_to_player_id.erase(device_name)
	G.input_device_manager.unassign_device_from_player(
		lobby_id)

	# Remove corresponding player attributes.
	G.client_session.local_player_attributes.remove_at(
		dense_index)

	# Remove lobby GamePlayerState.
	G.match_state.players_by_id.erase(player_id)
	G.match_state.players_updated.emit()

	deregister_player(player)

	G.audio.play_sound("kill")
	player.queue_free()

	# Show the corresponding control display.
	%ControlDisplays.set_device_in_use(
		device_name, false)

	# Update lobby colors for remaining players.
	_update_lobby_colors()

	Netcode.print(
		"Despawned lobby player %d (id=%d)" % [
			lobby_id, player_id],
		NetworkLogger.CATEGORY_PLAYER_ACTIONS)

	if is_instance_valid(G.game_panel):
		G.game_panel.lobby_players_updated.emit()


## Get number of active players.
func get_player_count() -> int:
	return _pending_device_configs_by_index.size()


func can_start_match() -> bool:
	return get_player_count() > 0


## Called by GamePanel to start match with current players.
func start_match() -> void:
	if not Netcode.ensure(can_start_match()):
		return

	G.client_session.local_device_configs = \
		_pending_device_configs_by_index.duplicate()

	# Re-key device assignments from lobby_id-based keys
	# to dense match indices (0, 1, 2...) so the match
	# can look up devices by local_player_index.
	G.input_device_manager.clear_all_assignments()
	for i in range(
		G.client_session.local_device_configs.size()
	):
		G.input_device_manager.assign_device_to_player(
			i, G.client_session.local_device_configs[i])

	Netcode.print(
		"Starting match with %d player(s)" %
			G.client_session.local_player_count,
		NetworkLogger.CATEGORY_GAME_STATE
	)

	G.audio.play_sound("hole")

	# Trigger GamePanel to despawn lobby and connect.
	G.game_panel.client_load_game()


## Re-register players from a previous match, preserving
## their device configs and attributes (except color).
func restore_players_from_previous_match() -> void:
	var saved_configs := \
		G.client_session.latest_local_device_configs
	var saved_attributes := \
		G.client_session.latest_local_player_attributes

	if saved_configs.is_empty():
		return

	Netcode.verbose(
		"Restoring %d player(s) from previous match" %
			saved_configs.size(),
		NetworkLogger.CATEGORY_GAME_STATE)

	for i in range(saved_configs.size()):
		var device_config: DeviceConfig = saved_configs[i]
		var attributes: Dictionary = (
			saved_attributes[i]
			if i < saved_attributes.size()
			else {}
		)
		_register_player(device_config, attributes)

	_apply_lobby_crowns.call_deferred()


## Shows crown on the lobby bunny that ended the
## previous match with the crown. Called deferred so
## it runs after player appearance is applied.
func _apply_lobby_crowns() -> void:
	var latest := \
		G.client_session.latest_match_state \
			as GameMatchState
	if latest == null:
		return
	var crown_id := latest.get_crown_player_id(
		G.settings.crown_kill_lead)
	if crown_id < 0:
		return

	# Map match player_id back to lobby player.
	var saved_ids := \
		G.client_session.latest_local_player_ids
	for i in range(saved_ids.size()):
		if saved_ids[i] != crown_id:
			continue
		var lobby_id := get_local_player_id(i)
		if not players_by_id.has(lobby_id):
			continue
		var bunny: Bunny = players_by_id[lobby_id]
		var bunny_anim := \
			bunny.animator as BunnyAnimator
		if is_instance_valid(bunny_anim):
			bunny_anim.set_crown_visible(true)
		break


## Returns true if the given device name belongs
## to the player currently using the settings UI.
func _is_device_used_by_settings_ui(
	device_name: StringName,
) -> bool:
	if not G.is_settings_ui_shown:
		return false
	if not is_instance_valid(G.settings_ui_player):
		return false
	if not _device_name_to_player_id.has(
			device_name):
		return false
	return _device_name_to_player_id[device_name] \
		== G.settings_ui_player.player_id


static func get_local_player_id(
	local_player_index: int,
) -> int:
	# Lobby players use negative IDs: -1, -2, -3, etc.
	return - (local_player_index + 1)


func _on_rabbit_hole_body_entered(
	body: Node2D,
) -> void:
	if not Netcode.ensure(body is Player):
		return

	start_match()


## Assigns colors to all lobby players based on count.
func _update_lobby_colors() -> void:
	var player_ids: Array = \
		_device_name_to_player_id.values()
	if player_ids.is_empty():
		return

	var colors := \
		PlayerAttributeGenerator \
			.calculate_outline_colors(player_ids.size())
	for i in range(player_ids.size()):
		var player_id: int = player_ids[i]
		if G.match_state.players_by_id.has(player_id):
			G.match_state.players_by_id[player_id] \
				.base_color = colors[i]

	G.match_state.players_updated.emit()
