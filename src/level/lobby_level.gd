@tool
class_name LobbyLevel
extends Level
## Local player management lobby (no networking).
## Players spawn/despawn via keyboard partitions and gamepads.


const _SPAWN_SPEED_MIN := 2000.0
const _SPAWN_SPEED_MAX := 7000.0
const _SPAWN_TARGET_DIRECTION := Vector2(20, -1)
const _SPAWN_VELOCITY_ANGLE_MAX_OFFSET := PI / 128
const _CONTROL_DISPLAY_FRAME_COUNT := 8
const _CONTROL_DISPLAY_FPS := 2.0

## Array of device configs (null = slot empty).
var _pending_device_configs_by_index: Array[DeviceConfig] = []

# Dictionary<StringName, DeviceConfig>
var _pending_device_configs_by_name := {}


func _ready() -> void:
	super._ready()

	_set_up_control_displays()


func _physics_process(_delta: float) -> void:
	_check_keyboard_inputs()
	_check_gamepad_inputs()


func _check_keyboard_inputs() -> void:
	# Check each join/leave buttons for each keyboard partition.
	for i in range(InputDeviceManager.KEYBOARD_PARTITION_BINDINGS.size()):
		var bindings: Dictionary = InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[i]
		if Input.is_physical_key_pressed(bindings["move_up"]):
			_try_register_keyboard_player(bindings)
		elif Input.is_physical_key_pressed(bindings["move_down"]):
			_deregister_player(bindings["name"])


func _check_gamepad_inputs() -> void:
	for device_id in Input.get_connected_joypads():
		if Input.is_action_pressed("move_up", device_id):
			_try_register_gamepad_player(device_id)
		elif Input.is_action_pressed("move_down", device_id):
			_try_deregister_gamepad_player(device_id)


func _try_register_keyboard_player(key_bindings: Dictionary) -> void:
	if _pending_device_configs_by_index.size() >= G.settings.max_local_player_count:
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
	if _pending_device_configs_by_index.size() >= G.settings.max_local_player_count:
		# No available slots.
		return

	var device_name := DeviceConfig.get_controller_device_name(device_id)
	if _pending_device_configs_by_name.has(device_name):
		# Already registered.
		return

	var device_config := DeviceConfig.new(
		DeviceConfig.DeviceType.GAMEPAD,
		device_id,
		{})
	_register_player(device_config)


func _try_deregister_gamepad_player(device_id: int) -> void:
	var device_name := DeviceConfig.get_controller_device_name(device_id)
	_deregister_player(device_name)


func _register_player(device_config: DeviceConfig) -> void:
	var local_player_index := _pending_device_configs_by_index.size()

	# Register device config BEFORE creating/adding player, so that
	# Player._ready() can find the device when setting up action sources.
	_pending_device_configs_by_index.append(device_config)
	_pending_device_configs_by_name[device_config.name] = device_config

	G.input_device_manager.assign_device_to_player(
		local_player_index,
		device_config
	)

	# Now create and add player to tree (this triggers _ready()).
	var player: Player = G.settings.default_player_scene.instantiate()
	player.player_id = get_local_player_id(local_player_index)
	player.name = "LobbyPlayer_%d" % local_player_index
	var spawn_position := _get_player_spawn_position()
	player.global_position = spawn_position
	players_node.add_child(player)
	player.global_position = spawn_position
	player.force_boost(_get_spawn_velocity())

	register_player(player)

	# Generate player attributes when they join the lobby.
	var attributes := PlayerAttributeGenerator.generate_random_attributes()
	G.client_session.local_player_attributes.append(attributes)

	Netcode.print(
		"Spawned lobby player %d" % local_player_index,
		NetworkLogger.CATEGORY_PLAYER_ACTIONS)

	if is_instance_valid(G.game_panel):
		G.game_panel.lobby_players_updated.emit()


func _get_spawn_velocity() -> Vector2:
	var target_angle := _SPAWN_TARGET_DIRECTION.angle()
	var spawn_angle := (
		target_angle
		- _SPAWN_VELOCITY_ANGLE_MAX_OFFSET
		+ _SPAWN_VELOCITY_ANGLE_MAX_OFFSET * 2 * randf()
	)
	var speed := randf_range(_SPAWN_SPEED_MIN, _SPAWN_SPEED_MAX)
	return Vector2.from_angle(spawn_angle) * speed


func _deregister_player(device_name: StringName) -> void:
	if not _pending_device_configs_by_name.has(device_name):
		# Not registered.
		return

	var device_config: DeviceConfig = _pending_device_configs_by_name[device_name]
	var local_player_index := _pending_device_configs_by_index.find(device_config)

	var player_id := get_local_player_id(local_player_index)
	if not Netcode.ensure(players_by_id.has(player_id)):
		return

	var player: Player = players_by_id[player_id]

	_pending_device_configs_by_index.remove_at(local_player_index)
	_pending_device_configs_by_name.erase(device_name)
	G.input_device_manager.unassign_device_from_player(local_player_index)

	# Remove corresponding player attributes.
	G.client_session.local_player_attributes.remove_at(local_player_index)

	deregister_player(player)

	player.queue_free()

	Netcode.print(
		"Despawned lobby player %d" % local_player_index,
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

	G.client_session.local_device_configs = _pending_device_configs_by_index.duplicate()

	Netcode.print(
		"Starting match with %d player(s)" % G.client_session.local_player_count,
		NetworkLogger.CATEGORY_GAME_STATE
	)

	# Trigger GamePanel to despawn lobby and connect.
	G.game_panel.client_load_game()


static func get_local_player_id(local_player_index: int) -> int:
	# Lobby players use negative IDs: -1, -2, -3, etc.
	return - (local_player_index + 1)


func _on_rabbit_hole_body_entered(body: Node2D) -> void:
	if not Netcode.ensure(body is Player):
		return

	start_match()


func _set_up_control_displays() -> void:
	var displays: Array[AnimatedSprite2D] = [
		%WASDControls, %IJKLControls, %ArrowControls, %GamepadControls,
	]
	var delay_sec := _CONTROL_DISPLAY_FRAME_COUNT / _CONTROL_DISPLAY_FPS / displays.size()
	for display in displays:
		var frames := display.sprite_frames
		frames.set_animation_speed(display.animation, _CONTROL_DISPLAY_FPS)
		await get_tree().create_timer(delay_sec).timeout
		display.play(display.animation)
