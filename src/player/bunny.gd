@tool
class_name Bunny
extends Player


var match_state: PlayerMatchState:
	get:
		return G.get_player_match_state(player_id)

# Dictionary<int, bool>
var _intersecting_head_player_ids := {}

var _processed_collision_this_frame := false
var _last_collision_frame := -1
var _blink_accumulator := 0.0
var _is_blink_visible := true


func _enter_tree() -> void:
	super._enter_tree()


func _exit_tree() -> void:
	super._exit_tree()


func _ready() -> void:
	super._ready()

	if Engine.is_editor_hint():
		return

	if G.network.is_client:
		G.network.local_authority_added.connect(
			_on_local_authority_added,
			CONNECT_ONE_SHOT,
		)
	_set_up_camera.call_deferred()

	# Set up outline color when match state becomes available.
	if is_instance_valid(match_state):
		_apply_outline_color()
	else:
		G.match_state.player_joined.connect(_on_any_player_joined)


func _process(_delta: float) -> void:
	super._process(_delta)
	_update_invincibility_blink()


func _process_movement_and_actions() -> void:
	super._process_movement_and_actions()

	# Reset collision flag each frame.
	if G.network.is_server:
		var current_frame: int = G.network.frame_driver.server_frame_index
		if _last_collision_frame != current_frame:
			_processed_collision_this_frame = false
			_last_collision_frame = current_frame


func play_sound(sound_name: StringName) -> void:
	if not G.network.is_primary_client:
		return

	var stream_player := _get_audio_stream_player(sound_name)
	if not stream_player.playing:
		stream_player.play()


# TODO: Make better sounds.
func _get_audio_stream_player(sound_name: StringName) -> AudioStreamPlayer2D:
	match sound_name:
		"jump":
			return %JumpAudioStreamPlayer
		"land":
			return %LandAudioStreamPlayer
		"walk":
			return %WalkAudioStreamPlayer
		"bump":
			return %BumpAudioStreamPlayer
		"die":
			if G.settings.is_gore_enabled:
				return %DieGoreAudioStreamPlayer
			else:
				return %DieFlowersAudioStreamPlayer
		_:
			G.fatal()
			return null


func _on_local_authority_added(
		_input_from_client: PlayerInputFromClient,
) -> void:
	_set_up_camera()


func _set_up_camera() -> void:
	var is_local_player := peer_id == G.network.local_peer_id

	G.print(
		"Setting up camera for player %s (peer=%d, local=%d, is_local=%s)" % [
			player_id,
			peer_id,
			G.network.local_peer_id,
			is_local_player,
		],
		ScaffolderLog.CATEGORY_CORE_SYSTEMS,
		ScaffolderLog.Verbosity.VERBOSE,
	)

	%CharacterCamera.enabled = is_local_player


func get_string() -> String:
	if is_instance_valid(match_state):
		return match_state.get_string()
	return "{Player}"


func _on_any_player_joined(player: PlayerMatchState) -> void:
	if player.player_id == player_id:
		_apply_outline_color()
		G.match_state.player_joined.disconnect(_on_any_player_joined)


func _apply_outline_color() -> void:
	if not G.ensure(is_instance_valid(match_state)):
		return

	var sprite := animator.animated_sprite as AnimatedSprite2D
	var shader_material := sprite.material as ShaderMaterial

	if G.ensure(is_instance_valid(shader_material)):
		shader_material.set_shader_parameter(
			"outline_color",
			match_state.outline_color
		)

		# Toggle outline based on whether we're in a networked match.
		shader_material.set_shader_parameter(
			"outline_enabled",
			G.is_networked_level_active)


func _on_body_area_body_entered(body: Node2D) -> void:
	# This should represent a collision with another player.
	if not G.network.is_server:
		return

	if not G.ensure(body is Player):
		return

	var other_player := body as Player
	var other_player_id := other_player.player_id

	# Prevent double-counting (this frame was already processed from the other
	# player).
	if _processed_collision_this_frame:
		return

	# Skip if either player is dead.
	if state_from_server.is_dead or other_player.state_from_server.is_dead:
		return

	# Skip if match has ended (all players are invincible during the end
	# sequence).
	if G.match_state.is_match_ended:
		return

	# Skip if either player is invincible.
	if (
		state_from_server.is_invincible or
		other_player.state_from_server.is_invincible
	):
		return

	# Mark this collision as processed.
	_processed_collision_this_frame = true
	other_player._processed_collision_this_frame = true

	# Determine interaction type and record.
	if not _intersecting_head_player_ids.has(other_player_id):
		# Bump - both players bounce away from each other.
		G.match_state.server_add_bump(player_id, other_player_id)
		_apply_collision_bounce(other_player)
		other_player._apply_collision_bounce(self)
	else:
		# Kill - only the killer bounces (killee is dying).
		G.match_state.server_add_kill(player_id, other_player_id)
		_apply_collision_bounce(other_player)


func _apply_collision_bounce(other_player: Player) -> void:
	G.check_is_server()

	# Calculate direction away from other player.
	var direction := (global_position - other_player.global_position).normalized()

	# Base bounce velocity in the direction away from collision.
	var base_bounce := direction * movement_settings.collision_bounce_base_speed

	# Additional upward boost.
	var upward_boost := Vector2(0, movement_settings.collision_bounce_vertical_boost)

	# Combine base bounce + upward boost.
	var total_bounce := base_bounce + upward_boost

	# Apply velocity delta (will be replicated via CharacterStateFromServer).
	velocity += total_bounce

	# Record bump event for network reconciliation and sound effects.
	state_from_server.last_bump_frame_index = G.network.server_frame_index
	state_from_server.last_bump_direction = direction


func _on_foot_area_area_entered(area: Area2D) -> void:
	if not G.network.is_server:
		return

	var other_parent: Node = area.get_parent()
	if not G.ensure(other_parent is Player):
		return
	var other_player := other_parent as Player

	_intersecting_head_player_ids[other_player.player_id] = true


func _on_foot_area_area_exited(area: Area2D) -> void:
	if not G.network.is_server:
		return

	var other_parent: Node = area.get_parent()
	if not G.ensure(other_parent is Player):
		return
	var other_player := other_parent as Player

	_intersecting_head_player_ids.erase(other_player.player_id)


func _update_invincibility_blink() -> void:
	if not state_from_server.is_invincible:
		# Ensure visible when not invincible.
		if not _is_blink_visible:
			animator.visible = true
			_is_blink_visible = true
		return

	# Don't blink during match-end invincibility.
	if G.match_state.is_match_ended:
		animator.visible = true
		_is_blink_visible = true
		return

	# Calculate blink period (seconds per toggle).
	var blink_period: float = 1.0 / \
		(G.settings.player_invincibility_blink_frequency_hz * 2.0)

	_blink_accumulator += get_process_delta_time()

	if _blink_accumulator >= blink_period:
		_blink_accumulator -= blink_period
		_is_blink_visible = not _is_blink_visible
		animator.visible = _is_blink_visible


func client_on_bumped(other_player: Player, is_first_of_pair: bool) -> void:
	# We don't need to play the bump sound at the same time for both players.
	if is_first_of_pair:
		play_sound("bump")


func client_on_killed(killee: Player) -> void:
	pass


func client_on_died(killer: Player) -> void:
	play_sound("die")
