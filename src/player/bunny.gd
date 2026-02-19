@tool
class_name Bunny
extends Player


var match_state: GamePlayerState:
	get:
		return G.get_player_match_state(player_id)

var _processed_collision_this_frame := false
var _last_collision_frame := -1
var _blink_accumulator := 0.0
var _is_blink_visible := true
var _pending_bounce := Vector2.ZERO
var _last_processed_interaction_start_time := -1
var _has_ever_died := false

const _SQUISH_DURATION_SEC := 0.09

# Track intersections during invincibility.
# Dictionary<int, Array[String]> - player_id -> array of intersection types.
# Can contain both "foot" and "body" for the same player.
var _active_intersections := {}
var _was_invincible_last_frame := false


func _enter_tree() -> void:
	super._enter_tree()


func _exit_tree() -> void:
	super._exit_tree()


func _ready() -> void:
	super._ready()

	if Engine.is_editor_hint():
		return

	if Netcode.is_client:
		Netcode.local_authority_added.connect(
			_on_local_authority_added,
			CONNECT_ONE_SHOT,
		)
	_set_up_camera.call_deferred()

	# Set up appearance and outline when match state
	# becomes available.
	if is_instance_valid(match_state):
		_update_appearance.call_deferred()
		_update_outline_color.call_deferred()
	else:
		G.match_state.player_joined.connect(_on_any_player_joined)

	# Update outline when colors are assigned/updated on the server.
	G.match_state.players_updated.connect(_on_players_updated)

	# Update crown when kills change.
	G.match_state.kills_updated.connect(
		_on_kills_updated)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	super._process(_delta)
	_update_invincibility_blink()


func _process_movement_and_actions() -> void:
	super._process_movement_and_actions()

	# Apply pending bounce after movement processing.
	# This must happen AFTER action handlers run, because
	# action handlers add gravity which would reduce the
	# bounce effect.
	#
	# The buffer fallback path runs on BOTH server and
	# client. On the client, this is critical because
	# force_launch() sets initial_launch_velocity, which
	# current_air_max_horizontal_speed uses for speed
	# capping. Without this, the client would use the
	# stale default (Vector2.INF), resulting in
	# max_launch_horizontal_speed (300) instead of the
	# correct max_air_horizontal_speed (90).
	var applied_bounce := false
	var bounce_source := ""
	var bounce_vel := Vector2.ZERO

	if (
		Netcode.is_server
		and _pending_bounce != Vector2.ZERO
		and not Netcode.frame_driver.is_resimulating
	):
		# Server forward-sim only: apply pending bounce
		# from collision callback. force_launch() nudges
		# position up by 1 pixel and clears surface
		# attachments, preventing FloorDefaultAction from
		# zeroing velocity.
		bounce_vel = _pending_bounce
		force_launch(_pending_bounce)
		_pending_bounce = Vector2.ZERO
		applied_bounce = true
		bounce_source = "pending"
	else:
		# Buffer fallback (server re-sim AND client):
		# check buffer for bounce. This is the primary
		# path during rollback re-simulation (collision
		# callbacks don't re-fire). Also runs on the
		# client so force_launch() sets
		# initial_launch_velocity correctly.
		var buffer_bounce = (
			state_from_server
				.get_current_frame_bounce_velocity()
		)
		if buffer_bounce != null:
			bounce_vel = buffer_bounce
			force_launch(buffer_bounce)
			# Clear pending bounce when buffer handles
			# this frame's bounce. This prevents
			# redundant application after re-simulation
			# completes.
			_pending_bounce = Vector2.ZERO
			applied_bounce = true
			bounce_source = "buffer"

	if applied_bounce and Netcode.log.is_verbose:
		Netcode.verbose(
			"Player %d bounce applied (%s): vel=%s, pos=%s, surfaces=%d, boost_frame=%d" % [
				player_id,
				bounce_source,
				bounce_vel,
				global_position,
				surfaces.bitmask,
				_last_launch_frame_index,
			],
			NetworkLogger.CATEGORY_GAME_STATE,
		)

	# Reset collision flag each frame.
	if Netcode.is_server:
		var current_frame: int = Netcode.frame_driver.server_frame_index
		if _last_collision_frame != current_frame:
			_processed_collision_this_frame = false
			_last_collision_frame = current_frame

	# Update player-player collision based on invincibility state.
	# This runs every frame to handle invincibility expiring.
	_update_player_collision_for_invincibility()


func _process_client_effects() -> void:
	# Handle client-side interaction effects (sounds, particles).
	# Process the interaction if it's new (not yet processed).
	var interaction_start_time := (
		state_from_server.last_interaction_frame_index
	)
	var should_process := (
		interaction_start_time !=
			_last_processed_interaction_start_time
		and interaction_start_time >= 0
	)

	if should_process:
		_handle_interaction_effects()
		_last_processed_interaction_start_time = \
			interaction_start_time


func _handle_interaction_effects() -> void:
	# Play sounds based on interaction type.
	match state_from_server.last_interaction_type:
		CharacterStateFromServer.ServerInteractionType.NONE:
			pass
		CharacterStateFromServer.ServerInteractionType.BUMP:
			play_sound("bump")
		CharacterStateFromServer.ServerInteractionType.KILL:
			# Do nothing. The other player's DIE interaction will handle the
			# effects.
			pass
		CharacterStateFromServer \
				.ServerInteractionType.DIE:
			if Netcode.log.is_verbose:
				Netcode.verbose(
					("Player %d DIE interaction"
					+ " detected on client") % [
						player_id,
					],
					NetworkLogger
						.CATEGORY_GAME_STATE,
				)
			play_sound("die")
			_spawn_squish_sprite()
			_has_ever_died = true
		CharacterStateFromServer.ServerInteractionType.SPAWN:
			if Netcode.log.is_verbose:
				Netcode.verbose(
					"Player %d SPAWN interaction detected on client" % [
						player_id,
					],
					NetworkLogger.CATEGORY_GAME_STATE,
				)
			if not _has_ever_died:
				play_sound("respawn")
		_:
			Netcode.fatal()


func _spawn_gore_particles() -> void:
	if not Netcode.is_client:
		return
	if (not is_instance_valid(G.level) or
			not is_instance_valid(G.level.gore_manager)):
		return
	var death_pos := \
		state_from_server.last_interaction_position
	G.level.gore_manager.spawn_particles(death_pos)


## Spawns a detached Sprite2D showing the squish
## frame at the death position. After the duration,
## removes the sprite and spawns gore + camera
## shake. This is independent of the player's
## animator so it doesn't conflict with
## death visibility/position updates.
func _spawn_squish_sprite() -> void:
	if not Netcode.is_client:
		return
	if not is_instance_valid(G.level):
		return

	var anim_sprite := \
		animator.animated_sprite \
		as AnimatedSprite2D
	var squish_tex := \
		anim_sprite.sprite_frames \
		.get_frame_texture("Squish", 0)
	if squish_tex == null:
		_spawn_gore_particles()
		G.camera_shaker.shake()
		return

	var death_pos := \
		state_from_server \
		.last_interaction_position

	var sprite := Sprite2D.new()
	sprite.texture = squish_tex

	# Place at the death position (character
	# origin, i.e. the feet).
	sprite.global_position = death_pos
	sprite.flip_h = anim_sprite.flip_h

	# Create outline material for the standalone
	# sprite (uses the regular sprite_outline shader,
	# not the canvas_group_outline shader).
	if is_instance_valid(match_state):
		var shader := preload(
			"res://assets/shaders/"
			+ "sprite_outline.gdshader")
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter(
			"outline_color",
			match_state.outline_color)
		mat.set_shader_parameter(
			"outline_width", 1.0)
		mat.set_shader_parameter(
			"outline_enabled",
			G.is_networked_level_active and
			G.settings.show_player_outlines)
		sprite.material = mat

	G.level.add_child(sprite)

	# After the squish duration, remove the
	# sprite and spawn gore + camera shake.
	get_tree().create_timer(
		_SQUISH_DURATION_SEC
	).timeout.connect(
		func() -> void:
			if is_instance_valid(sprite):
				sprite.queue_free()
			_spawn_gore_particles()
			G.camera_shaker.shake()
	)


func play_sound(sound_name: StringName) -> void:
	if not Netcode.is_primary_client:
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
		"respawn":
			return %RespawnAudioStreamPlayer
		_:
			Netcode.fatal()
			return null


func _on_local_authority_added(
		_input_from_client: PlayerInputFromClient,
) -> void:
	_set_up_camera()


func _set_up_camera() -> void:
	var is_local_player := peer_id == Netcode.local_peer_id

	Netcode.verbose(
		"Setting up camera for player %s (peer=%d, local=%d, is_local=%s)" % [
			player_id,
			peer_id,
			Netcode.local_peer_id,
			is_local_player,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	%CharacterCamera.enabled = is_local_player


func get_string() -> String:
	if is_instance_valid(match_state):
		return match_state.get_string()
	return "{Player}"


func on_match_state_ready(_player_match_state: PlayerState) -> void:
	super.on_match_state_ready(_player_match_state)
	_update_appearance()
	_update_outline_color()


func _on_any_player_joined(player: PlayerState) -> void:
	if player.player_id == player_id:
		_update_appearance()
		_update_outline_color()
		G.match_state.player_joined.disconnect(_on_any_player_joined)


func _on_players_updated() -> void:
	# Reapply appearance and outline when player data
	# is updated (e.g., color assignment).
	_update_appearance()
	_update_outline_color()


func _on_kills_updated() -> void:
	_update_crown_visibility()


func _update_crown_visibility() -> void:
	var bunny_anim := animator as BunnyAnimator
	if not is_instance_valid(bunny_anim):
		return
	var game_state := G.match_state as GameMatchState
	if not is_instance_valid(game_state):
		return
	var crown_id := game_state.get_crown_player_id(
		G.settings.crown_kill_lead)
	var should_show := (crown_id == player_id)
	bunny_anim.set_crown_visible(should_show)


func _update_appearance() -> void:
	if not is_instance_valid(match_state):
		return

	var bunny_anim := animator as BunnyAnimator
	if not is_instance_valid(bunny_anim):
		return

	# Look up body type config.
	var body_type_index: int = \
		match_state.body_type_index
	var body_type_config: BodyTypeConfig = null
	if (body_type_index >= 0 and
			body_type_index < \
				G.settings.body_types.size()):
		body_type_config = \
			G.settings.body_types[body_type_index]

	# Look up costume config.
	var costume_index: int = match_state.costume_index
	var costume_config: CostumeConfig = null
	if (costume_index >= 0 and
			costume_index < \
				G.settings.costumes.size()):
		costume_config = \
			G.settings.costumes[costume_index]

	# Apply body type and costume to animator.
	bunny_anim.apply_appearance(
		body_type_config, costume_config)

	# Store crown costume for later toggling.
	if is_instance_valid(G.settings.crown_costume):
		bunny_anim.set_crown_costume(
			G.settings.crown_costume)


func _get_shader_material() -> ShaderMaterial:
	var bunny_anim := animator as BunnyAnimator
	if not is_instance_valid(bunny_anim):
		return null
	var group := bunny_anim.outline_group
	if not group or not group.material:
		return null
	return group.material as ShaderMaterial


func _update_outline_color() -> void:
	# Match state may not be ready yet when
	# players_updated fires.
	if not is_instance_valid(match_state):
		return

	var bunny_anim := animator as BunnyAnimator
	if not is_instance_valid(bunny_anim):
		return
	var group := bunny_anim.outline_group
	if not is_instance_valid(group):
		return
	if not is_instance_valid(group.material):
		return

	# Apply outline to the CanvasGroup so the shader
	# sees the combined silhouette of all layers.
	group.material = group.material.duplicate()
	var shader_material := \
		group.material as ShaderMaterial
	if not is_instance_valid(shader_material):
		return

	shader_material.set_shader_parameter(
		"outline_color", match_state.outline_color)
	shader_material.set_shader_parameter(
		"outline_width", 1.0)

	# Set outline enabled state.
	update_outline()

	Netcode.verbose(
		"Applied outline for player %s: color=%s" % [
			player_id,
			match_state.base_color,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)


func update_outline() -> void:
	var outline_enabled := (
		G.is_networked_level_active and
		G.settings.show_player_outlines
	)

	var bunny_anim := animator as BunnyAnimator
	if not is_instance_valid(bunny_anim):
		return
	var group := bunny_anim.outline_group
	if not is_instance_valid(group):
		return
	var shader_material := \
		group.material as ShaderMaterial
	if not is_instance_valid(shader_material):
		return
	shader_material.set_shader_parameter(
		"outline_enabled", outline_enabled)


func _on_body_area_body_entered(body: Node2D) -> void:
	# This should represent a collision with another player.
	if not Netcode.is_server:
		return

	if not Netcode.ensure(body is Player):
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

	# Track intersection for deferred processing after invincibility.
	if (
		state_from_server.is_invincible or
		other_player.state_from_server.is_invincible
	):
		# Track this intersection for later.
		if not _active_intersections.has(other_player_id):
			_active_intersections[other_player_id] = []
		if not _active_intersections[other_player_id].has("body"):
			_active_intersections[other_player_id].append("body")
		return

	# Check if kill already happened this frame - kills take precedence.
	var current_frame := Netcode.server_frame_index
	if _did_kill_happen_this_frame(current_frame) or \
		other_player._did_kill_happen_this_frame(current_frame):
		Netcode.verbose(
			"Skipping bump - kill already processed this frame (players %d and %d)" % [
				player_id,
				other_player_id,
			],
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return

	# Check if a foot-head collision happened this frame via
	# swept detection in EITHER direction. This catches
	# high-speed collisions that skip over collision areas.
	# Check both directions because this callback may fire on
	# either player first.
	var swept_killer: Player = null
	var swept_victim: Player = null
	if _did_foot_pass_through_head_this_frame(other_player):
		swept_killer = self
		swept_victim = other_player
	elif other_player._did_foot_pass_through_head_this_frame(self):
		swept_killer = other_player
		swept_victim = self

	if swept_killer != null:
		# Prevent double-counting (this frame was already
		# processed from the other player).
		if _processed_collision_this_frame:
			return

		# Mark this collision as processed.
		_processed_collision_this_frame = true
		other_player._processed_collision_this_frame = true

		if Netcode.log.is_verbose:
			Netcode.verbose(
				"Player kill detected (swept): "
				+ "%d killed %d" % [
					swept_killer.player_id,
					swept_victim.player_id,
				],
				NetworkLogger.CATEGORY_GAME_STATE,
			)

		# Calculate lag-compensated position.
		var lag_compensated_position: Vector2 = (
			swept_killer
				._calculate_lag_compensated_kill_position(
					swept_victim
				)
		)

		# Process as kill with lag-compensated position.
		G.match_state.server_add_kill(
			swept_killer.player_id,
			swept_victim.player_id,
		)
		swept_killer._server_apply_interaction_with_position(
			swept_killer,
			CharacterStateFromServer
				.ServerInteractionType.KILL,
			lag_compensated_position,
		)
		return

	# Check if a kill collision is currently happening - kills take precedence.
	# This prevents the bump from blocking the kill when bump fires first.
	if _is_kill_collision_happening(other_player):
		Netcode.verbose(
			"Skipping bump - kill collision is happening (players %d and %d)" % [
				player_id,
				other_player_id,
			],
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return

	# Prevent double-counting (this frame was already processed from the other
	# player).
	if _processed_collision_this_frame:
		return

	if not G.settings.are_bumps_enabled:
		return

	# Mark this collision as processed.
	_processed_collision_this_frame = true
	other_player._processed_collision_this_frame = true

	# Bump - both players bounce away from each other.
	Netcode.verbose(
		"Players bump detected: %d bumped %d" %
			[player_id, other_player_id],
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	G.match_state.server_add_bump(player_id, other_player_id)
	_server_apply_interaction(
		other_player,
		CharacterStateFromServer.ServerInteractionType.BUMP
	)
	other_player._server_apply_interaction(
		self ,
		CharacterStateFromServer.ServerInteractionType.BUMP
	)


## Applies an interaction to this player (bounce velocity + state recording).
func _server_apply_interaction(
	other_player: Player,
	interaction_type: CharacterStateFromServer.ServerInteractionType
) -> void:
	# Delegate to position-override variant with current position.
	_server_apply_interaction_with_position(
		other_player,
		interaction_type,
		global_position
	)


## Applies an interaction with explicit position override.
## This variant injects the specified position into the rollback buffer
## before recording the interaction (used for lag compensation).
func _server_apply_interaction_with_position(
	other_player: Player,
	interaction_type: CharacterStateFromServer.ServerInteractionType,
	override_position: Vector2
) -> void:
	Netcode.check_is_server()

	var bounce_velocity: Vector2

	match interaction_type:
		CharacterStateFromServer.ServerInteractionType.BUMP:
			var direction := (
				override_position - other_player.global_position
			).normalized()
			var base_speed := movement_settings.bump_bounce_base_speed
			var vertical_boost := movement_settings.bump_bounce_vertical_boost
			bounce_velocity = direction * base_speed + Vector2(0, vertical_boost)
		CharacterStateFromServer.ServerInteractionType.KILL:
			var vertical_boost := movement_settings.kill_bounce_vertical_boost
			bounce_velocity = Vector2(velocity.x, vertical_boost)
		_:
			Netcode.fatal(
				"Invalid interaction type for bounce: %d" % interaction_type
			)
			return

	_pending_bounce = bounce_velocity

	# Record interaction with lag-compensated position (automatically injects
	# into buffer).
	state_from_server.record_interaction(
		interaction_type,
		Netcode.server_frame_index,
		override_position,
		bounce_velocity
	)

	Netcode.verbose(
		(
			"Applied %s interaction to player %d: pos=%s " +
			"(lag compensated), bounce=%s, vel=%s"
		) % [
			CharacterStateFromServer.ServerInteractionType.keys()[
				interaction_type
			],
			player_id,
			override_position,
			_pending_bounce,
			bounce_velocity,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)


## Checks if a kill (or death) interaction happened this frame.
func _did_kill_happen_this_frame(frame_index: int) -> bool:
	if state_from_server.last_interaction_frame_index == frame_index:
		var type := state_from_server.last_interaction_type
		if (type == CharacterStateFromServer.ServerInteractionType.KILL or
			type == CharacterStateFromServer.ServerInteractionType.DIE):
			return true
	return false


## Checks if a kill collision is currently happening between
## this player and another player, in EITHER direction.
## Returns true if either player's foot overlaps the other's
## head with downward relative velocity.
func _is_kill_collision_happening(other_player: Player) -> bool:
	# Check both directions: self killing other, and
	# other killing self.
	return (
		_is_foot_on_head(self, other_player) or
		_is_foot_on_head(other_player, self)
	)


## Checks if attacker's foot area overlaps victim's head
## area with downward relative velocity.
static func _is_foot_on_head(
	attacker: Player,
	victim: Player,
) -> bool:
	var foot_area: Area2D = attacker.get_node(
		"%FootArea"
	)
	var head_area: Area2D = victim.get_node(
		"%HeadArea"
	)

	if not foot_area.overlaps_area(head_area):
		return false

	var relative_velocity := (
		attacker.velocity - victim.velocity
	)
	return relative_velocity.y > 0


## Checks if this player's foot passed through another player's head this
## frame using swept collision detection. This catches high-speed collisions
## that skip over collision areas between physics frames.
func _did_foot_pass_through_head_this_frame(other_player: Player) -> bool:
	# Early exit if no previous position data.
	# Note: previous_position is a property inherited from Character class.
	if (previous_position == Vector2.INF or
		other_player.previous_position == Vector2.INF):
		return false

	# Check relative velocity is downward.
	var relative_velocity := velocity - other_player.velocity
	if relative_velocity.y <= 0:
		return false

	# Get previous positions in global coordinates.
	# Note: previous_position is in local coords, convert to global.
	# Since Level parent is stationary, parent.global_position is constant.
	var my_prev_global: Vector2 = (
		get_parent().global_position + previous_position
	)
	var other_prev_global: Vector2 = (
		other_player.get_parent().global_position +
		other_player.previous_position
	)

	# Calculate foot bottom and head top at t0 (previous frame).
	const FOOT_OFFSET_Y = -1.0
	const FOOT_HEIGHT = 2.0
	const HEAD_OFFSET_Y = -11.0
	const HEAD_HEIGHT = 2.0

	var foot_bottom_t0 = (
		my_prev_global.y +
		FOOT_OFFSET_Y +
		FOOT_HEIGHT / 2
	)
	var head_top_t0 = (
		other_prev_global.y +
		HEAD_OFFSET_Y -
		HEAD_HEIGHT / 2
	)

	# Calculate foot bottom and head top at t1 (current frame).
	var foot_bottom_t1 = (
		global_position.y +
		FOOT_OFFSET_Y +
		FOOT_HEIGHT / 2
	)
	var head_top_t1 = (
		other_player.global_position.y +
		HEAD_OFFSET_Y -
		HEAD_HEIGHT / 2
	)

	# Check if foot passed through head vertically.
	var foot_was_above = foot_bottom_t0 < head_top_t0
	var foot_is_below = foot_bottom_t1 > head_top_t1

	if not (foot_was_above and foot_is_below):
		return false

	# Check horizontal overlap (at current frame for simplicity).
	const FOOT_WIDTH = 10.0
	const HEAD_WIDTH = 6.0
	var foot_left = global_position.x + 0.5 - FOOT_WIDTH / 2
	var foot_right = global_position.x + 0.5 + FOOT_WIDTH / 2
	var head_left = other_player.global_position.x - HEAD_WIDTH / 2
	var head_right = other_player.global_position.x + HEAD_WIDTH / 2

	var has_horizontal_overlap = (
		(foot_left <= head_right) and
		(foot_right >= head_left)
	)

	if has_horizontal_overlap:
		Netcode.verbose(
			(
				"Swept collision detected: %d foot passed through %d " +
				"head (t0: foot_y=%.1f, head_y=%.1f; t1: foot_y=%.1f, " +
				"head_y=%.1f)"
			) % [
				player_id,
				other_player.player_id,
				foot_bottom_t0,
				head_top_t0,
				foot_bottom_t1,
				head_top_t1
			],
			NetworkLogger.CATEGORY_GAME_STATE,
		)

	return has_horizontal_overlap


## Calculates the killer's position at the moment of first contact with victim.
## Returns the interpolated position based on swept collision intersection.
func _calculate_lag_compensated_kill_position(
	other_player: Player
) -> Vector2:
	# Constants matching swept detection.
	const FOOT_OFFSET_Y = -1.0
	const FOOT_HEIGHT = 2.0
	const HEAD_OFFSET_Y = -11.0
	const HEAD_HEIGHT = 2.0

	# Get previous positions in global coordinates.
	var my_prev_global: Vector2 = (
		get_parent().global_position + previous_position
	)
	var other_prev_global: Vector2 = (
		other_player.get_parent().global_position +
		other_player.previous_position
	)

	# Calculate foot bottom and head top at t0 and t1.
	var foot_bottom_t0 = my_prev_global.y + FOOT_OFFSET_Y + FOOT_HEIGHT / 2
	var head_top_t0 = other_prev_global.y + HEAD_OFFSET_Y - HEAD_HEIGHT / 2
	var foot_bottom_t1 = global_position.y + FOOT_OFFSET_Y + FOOT_HEIGHT / 2
	var head_top_t1 = (
		other_player.global_position.y + HEAD_OFFSET_Y - HEAD_HEIGHT / 2
	)

	# Calculate interpolation factor t where foot contacts head.
	var foot_delta = foot_bottom_t1 - foot_bottom_t0
	var head_delta = head_top_t1 - head_top_t0
	var relative_delta = foot_delta - head_delta

	var t: float
	if abs(relative_delta) < 0.01:
		t = 0.5 # Parallel movement - use midpoint.
	else:
		t = (head_top_t0 - foot_bottom_t0) / relative_delta
		t = clamp(t, 0.0, 1.0)

	# Interpolate killer's position at contact moment.
	var lag_compensated_position = my_prev_global.lerp(global_position, t)

	if Netcode.log.is_verbose:
		Netcode.verbose(
			(
				"Lag compensation: player %d contact at t=%.3f, " +
				"prev=%s, curr=%s, compensated=%s"
			) % [
				player_id,
				t,
				my_prev_global,
				global_position,
				lag_compensated_position,
			],
			NetworkLogger.CATEGORY_GAME_STATE,
		)

	return lag_compensated_position


func _on_foot_area_area_entered(area: Area2D) -> void:
	if not Netcode.is_server:
		return

	var other_parent: Node = area.get_parent()
	if not Netcode.ensure(other_parent is Player):
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

	# Track intersection for deferred processing after invincibility.
	if (
		state_from_server.is_invincible or
		other_player.state_from_server.is_invincible
	):
		# Track this intersection for later.
		if not _active_intersections.has(other_player_id):
			_active_intersections[other_player_id] = []
		if not _active_intersections[other_player_id].has("foot"):
			_active_intersections[other_player_id].append("foot")
		return

	Netcode.verbose(
		"Player kill detected: %d killed %d" %
			[player_id, other_player_id],
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	_processed_collision_this_frame = true
	other_player._processed_collision_this_frame = true

	# Kill - killer bounces with kill_bounce velocity, victim dies.
	G.match_state.server_add_kill(player_id, other_player_id)

	# For direct collision, use current position (collision areas overlap).
	_server_apply_interaction_with_position(
		self ,
		CharacterStateFromServer.ServerInteractionType.KILL,
		global_position
	)


func _on_body_area_body_exited(body: Node2D) -> void:
	if not Netcode.is_server:
		return

	if not body is Player:
		return

	var other_player := body as Player
	var other_player_id := other_player.player_id

	# Remove "body" from tracked intersections when players separate.
	if _active_intersections.has(other_player_id):
		var types: Array = _active_intersections[other_player_id]
		types.erase("body")
		if types.is_empty():
			_active_intersections.erase(other_player_id)


func _on_foot_area_area_exited(area: Area2D) -> void:
	if not Netcode.is_server:
		return

	var other_parent: Node = area.get_parent()
	if not other_parent is Player:
		return

	var other_player := other_parent as Player
	var other_player_id := other_player.player_id

	# Remove "foot" from tracked intersections when players separate.
	if _active_intersections.has(other_player_id):
		var types: Array = _active_intersections[other_player_id]
		types.erase("foot")
		if types.is_empty():
			_active_intersections.erase(other_player_id)


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


func set_is_collidable(is_collidable: bool) -> void:
	super.set_is_collidable(is_collidable)

	# Also update blink visibility state.
	if is_collidable:
		# Alive - ensure blink state is visible.
		_is_blink_visible = true

		# When alive, update player-player collision for invincibility.
		_update_player_collision_for_invincibility()
	else:
		# Dead - ensure blink state is hidden.
		_is_blink_visible = false


## Updates player-player collision based on invincibility state.
## Called when collidability changes and every frame during movement.
func _update_player_collision_for_invincibility() -> void:
	# Skip in lobby (collision is disabled by LobbyLevel).
	if G.is_lobby_active:
		return

	# Keep collision disabled after match ends.
	if is_instance_valid(G.match_state) and \
			G.match_state.is_match_ended:
		set_collision_mask_value(
			_PLAYER_COLLISION_LAYER, false)
		return

	# Skip if not alive (dead players have all collision disabled).
	if state_from_server.is_dead:
		_was_invincible_last_frame = false
		return

	var is_invincible := state_from_server.is_invincible

	# Check if invincibility just ended.
	if _was_invincible_last_frame and not is_invincible:
		_process_deferred_collisions()

	_was_invincible_last_frame = is_invincible

	# Disable player-player collision when invincible.
	# Layer bit 4 = this player can be hit by others.
	# Mask bit 4 = this player can hit others.
	set_collision_layer_value(_PLAYER_COLLISION_LAYER, not is_invincible)
	set_collision_mask_value(_PLAYER_COLLISION_LAYER, not is_invincible)

	# Also update Area2D children (BodyArea, FootArea, HeadArea).
	for area_name in ["%BodyArea", "%FootArea", "%HeadArea"]:
		var area := get_node_or_null(area_name)
		if is_instance_valid(area) and area is Area2D:
			# Players use layer 4 for player-player collision.
			area.set_collision_layer_value(_PLAYER_COLLISION_LAYER, not is_invincible)
			area.set_collision_mask_value(_PLAYER_COLLISION_LAYER, not is_invincible)


## Processes collisions that were deferred during invincibility.
## Called when invincibility ends.
func _process_deferred_collisions() -> void:
	if not Netcode.is_server:
		return

	if _active_intersections.is_empty():
		return

	Netcode.verbose(
		"Processing %d deferred collision(s) for player %d" % [
			_active_intersections.size(),
			player_id,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	# Process each tracked intersection.
	for other_player_id in _active_intersections.keys():
		var intersection_types: Array = _active_intersections[other_player_id]
		var other_player := G.get_player(other_player_id)

		if not is_instance_valid(other_player):
			continue

		# Skip if other player is now dead or invincible.
		if other_player.state_from_server.is_dead or \
			other_player.state_from_server.is_invincible:
			continue

		# Check foot first (kill takes precedence over bump).
		if intersection_types.has("foot"):
			# Verify foot intersection is still active.
			var foot_area: Area2D = %FootArea
			var other_head_area: Area2D = other_player.get_node_or_null("%HeadArea")
			var is_still_intersecting := false
			if is_instance_valid(other_head_area):
				is_still_intersecting = foot_area.overlaps_area(other_head_area)

			if is_still_intersecting:
				# Check downward velocity requirement for kills.
				var relative_velocity := velocity - other_player.velocity
				if relative_velocity.y > 0:
					Netcode.verbose(
						"Deferred kill: %d killed %d" % [player_id, other_player_id],
						NetworkLogger.CATEGORY_GAME_STATE,
					)
					_processed_collision_this_frame = true
					other_player._processed_collision_this_frame = true
					G.match_state.server_add_kill(player_id, other_player_id)
					_server_apply_interaction_with_position(
						self ,
						CharacterStateFromServer.ServerInteractionType.KILL,
						global_position
					)
					continue # Skip body check since kill was processed.

		# Check body (bump) if no kill was processed.
		if intersection_types.has("body"):
			# Verify body intersection is still active.
			var body_area: Area2D = %BodyArea
			var is_still_intersecting := body_area.overlaps_body(other_player)

			if is_still_intersecting:
				Netcode.verbose(
					"Deferred bump: %d bumped %d" % [player_id, other_player_id],
					NetworkLogger.CATEGORY_GAME_STATE,
				)
				_processed_collision_this_frame = true
				other_player._processed_collision_this_frame = true
				G.match_state.server_add_bump(player_id, other_player_id)
				_server_apply_interaction(other_player, CharacterStateFromServer.ServerInteractionType.BUMP)
				other_player._server_apply_interaction(self , CharacterStateFromServer.ServerInteractionType.BUMP)

	# Clear all tracked intersections after processing.
	_active_intersections.clear()
