@tool
class_name Bunny
extends Player


var match_state: PlayerMatchState:
	get:
		return G.get_player_match_state(player_id)

var _processed_collision_this_frame := false
var _last_collision_frame := -1
var _blink_accumulator := 0.0
var _is_blink_visible := true
var _pending_bounce := Vector2.ZERO


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
		_apply_outline_color.call_deferred()
	else:
		G.match_state.player_joined.connect(_on_any_player_joined)

	# Update outline when colors are assigned/updated on the server.
	G.match_state.players_updated.connect(_on_players_updated)


func _process(_delta: float) -> void:
	super._process(_delta)
	_update_invincibility_blink()


func _process_movement_and_actions() -> void:
	super._process_movement_and_actions()

	# Apply pending bounce after movement processing.
	if G.network.is_server and _pending_bounce != Vector2.ZERO:
		velocity += _pending_bounce
		G.print(
			"F:%d Applied pending bounce to player %d: added %s, new vel=%s" % [
				G.network.server_frame_index,
				player_id,
				_pending_bounce,
				velocity,
			],
			ScaffolderLog.CATEGORY_GAME_STATE,
		)
		_pending_bounce = Vector2.ZERO

	# Reset collision flag each frame.
	if G.network.is_server:
		var current_frame: int = G.network.frame_driver.server_frame_index
		if _last_collision_frame != current_frame:
			_processed_collision_this_frame = false
			_last_collision_frame = current_frame

	# Handle client-side interaction effects (sounds, particles).
	if (
		state_from_server.last_interaction_frame_index ==
		G.network.server_frame_index
	):
		_handle_interaction_effects()


func _handle_interaction_effects() -> void:
	# Play sounds/visual effects based on interaction type.
	match state_from_server.last_interaction_type:
		CharacterStateFromServer.ServerInteractionType.NONE:
			pass
		CharacterStateFromServer.ServerInteractionType.BUMP:
			play_sound("bump")
		CharacterStateFromServer.ServerInteractionType.KILL:
			# Do nothing. The other player's DIE interaction will handle the
			# effects.
			pass
		CharacterStateFromServer.ServerInteractionType.DIE:
			# TODO: Add VFX.
			play_sound("die")
		CharacterStateFromServer.ServerInteractionType.SPAWN:
			# TODO: Add spawn sound and VFX.
			pass
		_:
			G.fatal()


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


func on_match_state_ready(_player_match_state: PlayerMatchState) -> void:
	super.on_match_state_ready(_player_match_state)
	_apply_outline_color()


func _on_any_player_joined(player: PlayerMatchState) -> void:
	if player.player_id == player_id:
		_apply_outline_color()
		G.match_state.player_joined.disconnect(_on_any_player_joined)


func _on_players_updated() -> void:
	# Reapply outline when player data is updated (e.g., color assignment).
	_apply_outline_color()


func _apply_outline_color() -> void:
	# Match state may not be ready yet when players_updated fires.
	if not is_instance_valid(match_state):
		return

	var sprite := animator.animated_sprite as AnimatedSprite2D
	if not sprite:
		G.warning("No sprite found on animator")
		return

	# Always duplicate material to make it unique to this instance.
	if sprite.material:
		sprite.material = sprite.material.duplicate()
	else:
		G.warning("No material found on sprite")
		return

	var shader_material := sprite.material as ShaderMaterial
	if not shader_material:
		G.warning("Material is not a ShaderMaterial")
		return

	# Set outline color.
	shader_material.set_shader_parameter(
		"outline_color",
		match_state.outline_color
	)

	# Set outline width (make it more visible).
	shader_material.set_shader_parameter("outline_width", 2.0)

	# Toggle outline based on whether we're in a networked match.
	var outline_enabled := G.is_networked_level_active
	shader_material.set_shader_parameter("outline_enabled", outline_enabled)

	G.print(
		"Applied outline for player %s: color=%s, enabled=%s, width=2.0" % [
			player_id,
			match_state.outline_color,
			outline_enabled,
		],
		ScaffolderLog.CATEGORY_GAME_STATE,
		ScaffolderLog.Verbosity.VERBOSE
	)


func _on_body_area_body_entered(body: Node2D) -> void:
	# This should represent a collision with another player.
	if not G.network.is_server:
		return

	if not G.ensure(body is Player):
		return

	var other_player := body as Player
	var other_player_id := other_player.player_id

	if other_player == self:
		return

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

	# Check if kill already happened this frame - kills take precedence.
	var current_frame := G.network.server_frame_index
	if _did_kill_happen_this_frame(current_frame) or \
		other_player._did_kill_happen_this_frame(current_frame):
		G.print(
			"Skipping bump - kill already processed this frame (players %d and %d)" % [
				player_id,
				other_player_id,
			],
			ScaffolderLog.CATEGORY_GAME_STATE,
			ScaffolderLog.Verbosity.VERBOSE,
		)
		return

	# Mark this collision as processed.
	_processed_collision_this_frame = true
	other_player._processed_collision_this_frame = true

	# Bump - both players bounce away from each other.
	G.print(
		"Players bump detected: %d bumped %d" %
			[player_id, other_player_id],
		ScaffolderLog.CATEGORY_GAME_STATE,
		ScaffolderLog.Verbosity.VERBOSE,
		true,
	)

	G.match_state.server_add_bump(player_id, other_player_id)
	_server_apply_interaction(
		other_player,
		CharacterStateFromServer.ServerInteractionType.BUMP
	)
	other_player._server_apply_interaction(
		self,
		CharacterStateFromServer.ServerInteractionType.BUMP
	)


## Applies an interaction to this player (bounce velocity + state recording).
func _server_apply_interaction(
	other_player: Player,
	interaction_type: CharacterStateFromServer.ServerInteractionType
) -> void:
	G.check_is_server()

	var direction := (global_position - other_player.global_position).normalized()

	# Select bounce settings based on interaction type.
	var base_speed: float
	var vertical_boost: float

	match interaction_type:
		CharacterStateFromServer.ServerInteractionType.BUMP:
			base_speed = movement_settings.bump_bounce_base_speed
			vertical_boost = movement_settings.bump_bounce_vertical_boost
		CharacterStateFromServer.ServerInteractionType.KILL:
			base_speed = movement_settings.kill_bounce_base_speed
			vertical_boost = movement_settings.kill_bounce_vertical_boost
		_:
			G.fatal("Invalid interaction type for bounce: %d" % interaction_type)
			return

	var bounce_velocity := direction * base_speed + Vector2(0, vertical_boost)
	_pending_bounce = bounce_velocity

	# Record interaction for network reconciliation.
	state_from_server.record_interaction(
		interaction_type,
		G.network.server_frame_index,
		global_position,
		direction
	)

	G.print(
		"F:%d Applied %s interaction to player %d: bounce=%s, dir=%s" % [
			G.network.server_frame_index,
			CharacterStateFromServer.ServerInteractionType.keys()[interaction_type],
			player_id,
			bounce_velocity,
			direction,
		],
		ScaffolderLog.CATEGORY_GAME_STATE,
		ScaffolderLog.Verbosity.VERBOSE,
	)


## Checks if a kill (or death) interaction happened this frame.
func _did_kill_happen_this_frame(frame_index: int) -> bool:
	if state_from_server.last_interaction_frame_index == frame_index:
		var type := state_from_server.last_interaction_type
		if (type == CharacterStateFromServer.ServerInteractionType.KILL or
			type == CharacterStateFromServer.ServerInteractionType.DIE):
			return true
	return false


func _on_foot_area_area_entered(area: Area2D) -> void:
	if not G.network.is_server:
		return

	var other_parent: Node = area.get_parent()
	if not G.ensure(other_parent is Player):
		return
	var other_player := other_parent as Player
	var other_player_id := other_player.player_id

	var relative_velocity := velocity - other_player.velocity
	var is_relative_velocity_downward := relative_velocity.y > 0

	if other_player == self:
		return

	if not is_relative_velocity_downward:
		return

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

	G.print(
		"Player kill detected: %d killed %d" %
			[player_id, other_player_id],
		ScaffolderLog.CATEGORY_GAME_STATE,
		ScaffolderLog.Verbosity.VERBOSE,
		true,
	)

	_processed_collision_this_frame = true
	other_player._processed_collision_this_frame = true

	# Kill - killer bounces with kill_bounce velocity, victim dies.
	G.match_state.server_add_kill(player_id, other_player_id)

	# Apply KILL interaction to killer (bounce up).
	_server_apply_interaction(
		other_player,
		CharacterStateFromServer.ServerInteractionType.KILL
	)

	# Trigger death on victim.
	other_player.server_trigger_death()


func _update_invincibility_blink() -> void:
	# Don't blink if dead (sprite should stay hidden).
	if state_from_server.is_dead:
		if _is_blink_visible:
			animator.visible = false
			_is_blink_visible = false
		return

	if not state_from_server.is_invincible:
		# Ensure visible when not invincible and not dead.
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
