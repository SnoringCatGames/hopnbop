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
var _has_pending_bounce := false
var _pending_is_momentum_transfer := false
var _last_processed_interaction_start_time := -1
var _has_ever_died := false

const _SQUISH_DURATION_SEC := 0.09
const _SKID_VELOCITY_THRESHOLD := 20.0
const _LANDING_SKID_GRACE_SEC := 0.5
const _WALK_SOUND_INTERVAL_SEC := 0.133
const _AT_REST_VELOCITY_THRESHOLD := 50.0

@export var _sprite_outline_shader: Shader
@export var _bunny_animator_scene: PackedScene

var _was_floor_skid_condition := false
var _suppress_landing_skid := false
var _walk_sound_frame_counter := 0

# Track intersections during invincibility.
# Dictionary<int, Array[String]> - player_id -> array of intersection types.
# Can contain both "foot" and "body" for the same player.
var _active_intersections := {}
var _was_invincible_last_frame := false
var _had_crown := false
var _wrap_ghosts: Array[WrapGhost] = []


func _landing_skid_grace_frames() -> int:
	return int(
		_LANDING_SKID_GRACE_SEC
		/ Netcode.time.get_time_step_sec()
	)


func _walk_sound_interval_frames() -> int:
	return int(
		_WALK_SOUND_INTERVAL_SEC
		/ Netcode.time.get_time_step_sec()
	)


func _enter_tree() -> void:
	super._enter_tree()


func _exit_tree() -> void:
	super._exit_tree()


func _ready() -> void:
	super._ready()

	if Engine.is_editor_hint():
		return

	# Suppress landing skids for players spawned with
	# the level (not mid-game joins).
	if (
		is_instance_valid(G.level)
		and Netcode.server_frame_index
			-G.level.start_frame_index
			< _landing_skid_grace_frames()
	):
		_suppress_landing_skid = true

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

	# Connect eat-cycle signal for poop particle
	# spawning.
	var bunny_anim := animator as BunnyAnimator
	if is_instance_valid(bunny_anim):
		bunny_anim.eat_cycle_ended.connect(
			_on_eat_cycle_ended)

	# Create wrap ghosts for split-edge rendering
	# (client-only visual effect).
	if Netcode.is_client:
		_setup_wrap_ghosts.call_deferred()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	super._process(_delta)
	_update_invincibility_blink()


## Called by the Spring scene's Area2D when the
## player enters the spring trigger zone.
## Server forward-sim only.
func server_trigger_spring_bounce() -> void:
	if not Netcode.runs_server_logic:
		return
	if Netcode.frame_driver.is_resimulating:
		return
	if _has_pending_bounce:
		return
	var spring_velocity := Vector2(
		velocity.x,
		movement_settings.spring_bounce_vertical_boost
	)
	_pending_bounce = spring_velocity
	_has_pending_bounce = true
	state_from_server.record_interaction(
		CharacterStateFromServer
			.ServerInteractionType.SPRING,
		Netcode.server_frame_index,
		global_position,
		spring_velocity
	)
	# Record spring launch stat.
	(G.match_state
		.server_get_or_create_stats(player_id)
		.record_spring_launch())


## Called by the Snail scene when the player
## crushes it. Server forward-sim only.
func server_trigger_snail_crush_bounce() -> void:
	if not Netcode.runs_server_logic:
		return
	if Netcode.frame_driver.is_resimulating:
		return
	if _has_pending_bounce:
		return
	var crush_velocity := Vector2(
		velocity.x,
		movement_settings
			.snail_crush_bounce_vertical_boost
	)
	_pending_bounce = crush_velocity
	_has_pending_bounce = true
	state_from_server.record_interaction(
		CharacterStateFromServer
			.ServerInteractionType.SNAIL_CRUSH,
		Netcode.server_frame_index,
		global_position,
		crush_velocity
	)


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
		Netcode.runs_server_logic
		and _has_pending_bounce
		and not Netcode.frame_driver.is_resimulating
	):
		# Server forward-sim only: apply pending bounce
		# from collision callback.
		bounce_vel = _pending_bounce
		if _pending_is_momentum_transfer:
			# Momentum transfer: only adjust horizontal
			# velocity. Preserve vertical velocity so
			# jumps and gravity are unaffected.
			velocity.x = _pending_bounce.x
		else:
			# Bounce/kill: force_launch() nudges position
			# up by 1 pixel and clears surface
			# attachments, preventing FloorDefaultAction
			# from zeroing velocity.
			force_launch(_pending_bounce)
		_pending_bounce = Vector2.ZERO
		_has_pending_bounce = false
		_pending_is_momentum_transfer = false
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
			var is_mt_bump: bool = (
				G.settings.bump_mode
				== Settings.BumpMode.MOMENTUM_TRANSFER
				and state_from_server
					.get_current_frame_interaction_type()
				== CharacterStateFromServer
					.ServerInteractionType.BUMP
			)
			if is_mt_bump:
				velocity.x = buffer_bounce.x
			else:
				force_launch(buffer_bounce)
			# Clear pending bounce when buffer handles
			# this frame's bounce. This prevents
			# redundant application after re-simulation
			# completes.
			_pending_bounce = Vector2.ZERO
			_has_pending_bounce = false
			_pending_is_momentum_transfer = false
			applied_bounce = true
			bounce_source = "buffer"

	if applied_bounce and Netcode.log.is_verbose:
		Netcode.verbose(
			"Player %d bounce applied (%s): "
			+"vel=%s, pos=%s, surfaces=%d, "
			+"launch_frame=%d, resim=%s" % [
				player_id,
				bounce_source,
				bounce_vel,
				global_position,
				surfaces.bitmask,
				_last_launch_frame_index,
				Netcode.frame_driver.is_resimulating,
			],
			NetworkLogger.CATEGORY_GAME_STATE,
		)
	elif (
		not applied_bounce
		and Netcode.log.is_verbose
		and is_in_launch_cooldown()
	):
		# Log when no bounce was applied but the
		# launch cooldown is still active. Helps
		# diagnose cases where a bounce was applied
		# recently and we're verifying continuity.
		Netcode.verbose(
			"Player %d in launch cooldown "
			+"(no bounce this frame): "
			+"vel=%s, pos=%s, surfaces=%d, "
			+"launch_frame=%d, on_floor=%s, "
			+"attaching_floor=%s" % [
				player_id,
				velocity,
				global_position,
				surfaces.bitmask,
				_last_launch_frame_index,
				surfaces.is_touching_floor,
				surfaces.is_attaching_to_floor,
			],
			NetworkLogger.CATEGORY_GAME_STATE,
		)

	# Reset collision flag each frame.
	if Netcode.runs_server_logic:
		var current_frame: int = (
		Netcode.frame_driver.server_frame_index)
		if _last_collision_frame != current_frame:
			_processed_collision_this_frame = false
			_last_collision_frame = current_frame

	# Accumulate per-frame gameplay stats (server
	# forward-sim only, while alive and match active).
	if (
		Netcode.runs_server_logic
		and not Netcode.frame_driver.is_resimulating
		and not state_from_server.is_dead
		and not G.match_state.is_match_ended
	):
		var stats := (
			G.match_state
				.server_get_or_create_stats(
					player_id))
		var gms := (
			G.match_state as GameMatchState)
		var crown_holder_id := -1
		if is_instance_valid(gms):
			crown_holder_id = (
				gms.get_crown_player_id(
					G.settings.crown_kill_lead))
		stats.accumulate_frame(
			self ,
			Netcode.frame_driver
				.target_network_time_step_sec,
			crown_holder_id == player_id,
		)
		# Track jumps.
		if (
			last_triggered_jump_frame_index
				== Netcode.server_frame_index
		):
			stats.record_jump(
				surfaces.is_in_water)

	# Update player-player collision based on invincibility state.
	# This runs every frame to handle invincibility expiring.
	_update_player_collision_for_invincibility()


func _process_animation() -> void:
	# Force Rest during countdown to prevent
	# JumpFall from rollback re-simulation.
	if (Netcode.frame_driver
			.is_match_start_countdown_active):
		animator.play("Rest")
		return
	super._process_animation()
	_update_skids()
	_update_splashes()
	_update_walk_sounds()


func _update_splashes() -> void:
	if Netcode.frame_driver.is_resimulating:
		return

	if state_from_server.is_dead:
		return

	if (
		not is_instance_valid(G.level)
		or not is_instance_valid(
			G.level.splash_manager)
	):
		return

	# Entering water.
	if surfaces.just_entered_water:
		G.level.splash_manager.spawn_splash(
			Vector2(
				global_position.x,
				water_surface_y),
			&"enter_water",
		)
		play_sound("splash")

	# Exiting water (including jumping out).
	if surfaces.just_exited_water:
		G.level.splash_manager.spawn_splash(
			Vector2(
				global_position.x,
				water_surface_y),
			&"exit_water",
		)
		play_sound("splash")


func _update_walk_sounds() -> void:
	if Netcode.frame_driver.is_resimulating:
		return

	if state_from_server.is_dead:
		_walk_sound_frame_counter = 0
		return

	if (Netcode.frame_driver
			.is_match_start_countdown_active):
		_walk_sound_frame_counter = 0
		return

	var is_walking := (
		surfaces.is_attaching_to_floor
		and (
			actions.pressed_left
			or actions.pressed_right
		)
	)

	if is_walking:
		_walk_sound_frame_counter += 1
		if (
			_walk_sound_frame_counter
				>= _walk_sound_interval_frames()
		):
			if surfaces.surface_properties.is_ice:
				play_sound("ice")
			else:
				play_sound("walk")
			_walk_sound_frame_counter = 0
	else:
		_walk_sound_frame_counter = 0


func _update_skids() -> void:
	if Netcode.frame_driver.is_resimulating:
		return

	if state_from_server.is_dead:
		_was_floor_skid_condition = false
		return

	if (Netcode.frame_driver
			.is_match_start_countdown_active):
		_was_floor_skid_condition = false
		return

	if (
		not is_instance_valid(G.level)
		or not is_instance_valid(
			G.level.skid_manager)
	):
		return

	# Clear initial-spawn suppression after a grace
	# window past level start or countdown end.
	if _suppress_landing_skid:
		var grace_origin := (
			G.level.start_frame_index)
		var countdown_end := (
			Netcode.frame_driver
				.match_start_countdown_end_frame_index)
		if countdown_end > grace_origin:
			grace_origin = countdown_end
		if (
			Netcode.server_frame_index
				- grace_origin
				>= _landing_skid_grace_frames()
		):
			_suppress_landing_skid = false

	# Landing skid (bidirectional).
	if (
		surfaces.just_left_air
		and surfaces.is_attaching_to_floor
	):
		if not _suppress_landing_skid:
			G.level.skid_manager.spawn_skid(
				global_position,
				&"skid_both",
				not surfaces.is_facing_right,
			)
			play_sound("skid")
		_was_floor_skid_condition = false
		return

	# Jump skid.
	if (
		last_triggered_jump_frame_index
			== Netcode.server_frame_index
		and surfaces
			.just_stopped_attaching_to_floor
	):
		G.level.skid_manager.spawn_skid(
			surfaces.last_floor_position,
			&"jump",
			not surfaces.is_facing_right,
		)
		play_sound("skid")

	# Floor skids (one-direction).
	if surfaces.is_attaching_to_floor:
		var vel_x := velocity.x
		var accel_sign := (
			surfaces.horizontal_acceleration_sign
		)

		# Stopping: no input, still moving.
		var is_stopping := (
			accel_sign == 0
			and absf(vel_x)
				> _SKID_VELOCITY_THRESHOLD
		)
		# Changing direction: input opposes
		# velocity.
		var is_changing_direction := (
			accel_sign != 0
			and signf(vel_x) != 0.0
			and signf(vel_x) != accel_sign
			and absf(vel_x)
				> _SKID_VELOCITY_THRESHOLD
		)

		var is_floor_skid := (
			is_stopping or is_changing_direction
		)

		# Trigger on rising edge only.
		if (
			is_floor_skid
			and not _was_floor_skid_condition
		):
			G.level.skid_manager.spawn_skid(
				global_position,
				&"skid_right",
				vel_x < 0,
			)
			play_sound("skid")
		_was_floor_skid_condition = is_floor_skid
	else:
		_was_floor_skid_condition = false


func _process_client_effects() -> void:
	# Handle client-side interaction effects (sounds, particles).
	# Process the interaction if it's new (not yet processed).
	var interaction_start_time := (
		state_from_server
			.last_interaction_frame_index)
	var should_process := (
		interaction_start_time
			!= _last_processed_interaction_start_time
		and interaction_start_time >= 0
	)

	if should_process:
		_handle_interaction_effects()
		_last_processed_interaction_start_time = (
		interaction_start_time)


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
		(CharacterStateFromServer
				.ServerInteractionType.DIE):
			if Netcode.log.is_verbose:
				Netcode.verbose(
					("Player %d DIE interaction"
					+" detected on client") % [
						player_id,
					],
					NetworkLogger
						.CATEGORY_GAME_STATE,
				)
			play_sound("die")
			_spawn_squish_sprite()
			_has_ever_died = true
			var bunny_anim := (
				animator as BunnyAnimator)
			if is_instance_valid(bunny_anim):
				bunny_anim.reset_eat_cycle()
		CharacterStateFromServer.ServerInteractionType.SPAWN:
			if Netcode.log.is_verbose:
				Netcode.verbose(
					"Player %d SPAWN interaction detected on client" % [
						player_id,
					],
					NetworkLogger.CATEGORY_GAME_STATE,
				)
			if _has_ever_died:
				play_sound("respawn")
			var bunny_anim := (
				animator as BunnyAnimator)
			if is_instance_valid(bunny_anim):
				bunny_anim.reset_eat_cycle()
		(CharacterStateFromServer
				.ServerInteractionType.SPRING):
			play_sound("spring")
		(CharacterStateFromServer
				.ServerInteractionType.SNAIL_CRUSH):
			pass
		_:
			Netcode.fatal()


func _spawn_gore_particles(
	death_pos: Vector2,
) -> void:
	if not Netcode.is_client:
		return
	if (
		not is_instance_valid(G.level)
		or not is_instance_valid(
			G.level.gore_manager)
	):
		return
	G.level.gore_manager.spawn_particles(death_pos)


func _on_eat_cycle_ended() -> void:
	if not Netcode.is_client:
		return
	if Netcode.frame_driver.is_resimulating:
		return
	if state_from_server.is_dead:
		return
	if (
		not is_instance_valid(G.level)
		or not is_instance_valid(
			G.level.gore_manager)
	):
		return

	# Poop travels opposite to horizontal motion,
	# or opposite facing direction if stationary.
	var backward_sign: float
	if velocity.x > 0.0:
		backward_sign = -1.0
	elif velocity.x < 0.0:
		backward_sign = 1.0
	elif surfaces.is_facing_right:
		backward_sign = -1.0
	else:
		backward_sign = 1.0

	var spawn_pos := (
		global_position
		+ Vector2(backward_sign * 2.0, -2.0))
	G.level.gore_manager.spawn_poop_particles(
		spawn_pos, backward_sign)

	# Record poop stat for adjective assignment.
	var reporter: ClientStatReporter = (
		G.level.get_node_or_null(
			"ClientStatReporter"))
	if reporter != null:
		reporter.record_poop(player_id)


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

	var death_pos := (
		state_from_server
			.last_interaction_position)

	var anim_sprite := (
		animator.animated_sprite
		as AnimatedSprite2D)
	var squish_tex := (
		anim_sprite.sprite_frames
			.get_frame_texture("Squish", 0))
	if squish_tex == null:
		_spawn_gore_particles(death_pos)
		G.camera_shaker.shake()
		return

	var sprite := Sprite2D.new()
	sprite.texture = squish_tex
	sprite.flip_h = anim_sprite.flip_h

	# Create outline material for the standalone
	# sprite (uses the regular sprite_outline shader,
	# not the canvas_group_outline shader).
	if is_instance_valid(match_state):
		var shader := _sprite_outline_shader
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter(
			"outline_color",
			match_state.outline_color)
		mat.set_shader_parameter(
			"outline_width", 1.0)
		mat.set_shader_parameter(
			"outline_enabled",
			G.is_networked_level_active
			and G.settings.show_player_outlines)
		sprite.material = mat

	G.level.add_child(sprite)
	# Set global position after add_child so the
	# parent transform is applied correctly.
	# Character origin is the feet.
	sprite.global_position = death_pos

	# After the squish duration, remove the
	# sprite and spawn gore + camera shake.
	get_tree().create_timer(
		_SQUISH_DURATION_SEC
	).timeout.connect(
		func() -> void:
			if is_instance_valid(sprite):
				sprite.queue_free()
			_spawn_gore_particles(death_pos)
			G.camera_shaker.shake()
	)


func play_sound(sound_name: StringName) -> void:
	if not Netcode.is_primary_client:
		return
	if Netcode.frame_driver.is_resimulating:
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
		"ice":
			return %IceAudioStreamPlayer
		"skid":
			return %SkidAudioStreamPlayer
		"bump":
			return %BumpAudioStreamPlayer
		"die":
			if G.settings.is_gore_enabled:
				return %DieGoreAudioStreamPlayer
			else:
				return %DieFlowersAudioStreamPlayer
		"respawn":
			return %RespawnAudioStreamPlayer
		"spring":
			return %SpringAudioStreamPlayer
		"splash":
			return %SplashAudioStreamPlayer
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

	# Disconnect the fallback listener if it was connected
	# in _ready() (when player_id was still 0 and
	# match_state was unavailable).
	if G.match_state.player_joined.is_connected(
		_on_any_player_joined
	):
		G.match_state.player_joined.disconnect(
			_on_any_player_joined
		)


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
	var gms := G.match_state as GameMatchState
	if not is_instance_valid(gms):
		return
	var crown_id := gms.get_crown_player_id(
		G.settings.crown_kill_lead)
	var should_show := (crown_id == player_id)

	# Play crown cadence when this bunny newly gets
	# the crown.
	if should_show and not _had_crown:
		if is_instance_valid(G.audio):
			G.audio.play_sound("crown_cadence")
	_had_crown = should_show

	bunny_anim.set_crown_visible(should_show)


func _update_appearance() -> void:
	if not is_instance_valid(match_state):
		return

	var bunny_anim := animator as BunnyAnimator
	if not is_instance_valid(bunny_anim):
		return

	# Look up body type config.
	var body_type_index: int = (
		match_state.body_type_index)
	var body_type_config: BodyTypeConfig = null
	if (
		body_type_index >= 0
		and body_type_index
			< G.settings.body_types.size()
	):
		body_type_config = (
			G.settings.body_types[body_type_index])

	# Look up costume config.
	var costume_index: int = match_state.costume_index
	var costume_config: CostumeConfig = null
	if (
		costume_index >= 0
		and costume_index
			< G.settings.costumes.size()
	):
		costume_config = (
			G.settings.costumes[costume_index])

	# Apply body type and costume to animator.
	bunny_anim.apply_appearance(
		body_type_config, costume_config)

	# Store crown costume for later toggling.
	if is_instance_valid(G.settings.crown_costume):
		bunny_anim.set_crown_costume(
			G.settings.crown_costume)

	# Refresh wrap ghost appearance to match.
	for ghost in _wrap_ghosts:
		if is_instance_valid(ghost):
			ghost.refresh_appearance()


func _setup_wrap_ghosts() -> void:
	if not is_instance_valid(G.level):
		return
	if not G.level is NetworkedLevel:
		return
	var net_level: NetworkedLevel = G.level
	if net_level.wrap_bounds.size == Vector2.ZERO:
		return

	for axis in [
		WrapGhost.OffsetAxis.HORIZONTAL,
		WrapGhost.OffsetAxis.VERTICAL,
		WrapGhost.OffsetAxis.DIAGONAL,
	]:
		var ghost := WrapGhost.new()
		ghost.name = "WrapGhost_%d" % axis
		ghost.animator_scene = (
			_bunny_animator_scene)
		add_child(ghost)
		ghost.setup(self, axis)
		_wrap_ghosts.append(ghost)


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
	var shader_material := (
		group.material as ShaderMaterial)
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
		G.is_networked_level_active
		and G.settings.show_player_outlines
	)

	var bunny_anim := animator as BunnyAnimator
	if not is_instance_valid(bunny_anim):
		return
	var group := bunny_anim.outline_group
	if not is_instance_valid(group):
		return
	var sm := (
		group.material as ShaderMaterial)
	if not is_instance_valid(sm):
		return
	sm.set_shader_parameter(
		"outline_enabled", outline_enabled)


func _on_body_area_body_entered(body: Node2D) -> void:
	# This should represent a collision with another player.
	if not Netcode.runs_server_logic:
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
		state_from_server.is_invincible
		or other_player.state_from_server
			.is_invincible
	):
		# Track this intersection for later.
		if not _active_intersections.has(
				other_player_id):
			_active_intersections[
				other_player_id] = []
		if not _active_intersections[
				other_player_id].has("body"):
			_active_intersections[
				other_player_id].append("body")
		return

	# Check if kill already happened this frame - kills take precedence.
	var current_frame := Netcode.server_frame_index
	if (
		_did_kill_happen_this_frame(current_frame)
		or other_player
			._did_kill_happen_this_frame(
				current_frame)
	):
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
	elif other_player._did_foot_pass_through_head_this_frame(self ):
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
				+"%d killed %d" % [
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

	# Record bump stat even when bumps are disabled,
	# so dynamic adjective tracking sees collisions.
	G.match_state.server_get_or_create_stats(
		player_id).record_bump()
	G.match_state.server_get_or_create_stats(
		other_player_id).record_bump()

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
			match G.settings.bump_mode:
				Settings.BumpMode.BOUNCE:
					var direction := (
						override_position
						- other_player.global_position
					).normalized()
					bounce_velocity = (
						direction
						* movement_settings
							.bump_bounce_base_speed
						+ Vector2(
							0,
							movement_settings
								.bump_bounce_vertical_boost,
						)
					)
				Settings.BumpMode.MOMENTUM_TRANSFER:
					bounce_velocity = (
						_calculate_momentum_transfer(
							other_player,
							override_position,
						)
					)
		CharacterStateFromServer.ServerInteractionType.KILL:
			var vertical_boost := movement_settings.kill_bounce_vertical_boost
			bounce_velocity = Vector2(velocity.x, vertical_boost)
		_:
			Netcode.fatal(
				"Invalid interaction type for bounce: %d" % interaction_type
			)
			return

	var is_mt_bump := (
		interaction_type
		== CharacterStateFromServer
			.ServerInteractionType.BUMP
		and G.settings.bump_mode
		== Settings.BumpMode.MOMENTUM_TRANSFER
	)

	_pending_bounce = bounce_velocity
	_has_pending_bounce = true
	_pending_is_momentum_transfer = is_mt_bump

	# Momentum transfer bumps skip record_interaction.
	# record_interaction injects bounce_velocity as
	# the character's buffer state velocity and queues
	# a rollback. For MT bumps this overwrites the
	# real velocity, disrupts floor contact during
	# resimulation, and causes cascading bumps with
	# upward drift. Instead, the server applies the
	# velocity change via _pending_bounce and clients
	# see it via normal state replication.
	if not is_mt_bump:
		state_from_server.record_interaction(
			interaction_type,
			Netcode.server_frame_index,
			override_position,
			bounce_velocity,
		)

	Netcode.verbose(
		(
			"Applied %s interaction to player %d:"
			+ " pos=%s, bounce=%s, vel=%s,"
			+ " recorded=%s"
		) % [
			CharacterStateFromServer
				.ServerInteractionType.keys()[
					interaction_type
				],
			player_id,
			override_position,
			_pending_bounce,
			bounce_velocity,
			not is_mt_bump,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)


## Calculates the post-collision velocity for this player
## using momentum transfer. The other player's approach
## velocity pushes this player, and this player's own
## approach velocity is reduced proportionally.
func _calculate_momentum_transfer(
	other_player: Player,
	override_position: Vector2,
) -> Vector2:
	# Use a horizontal-only axis. Players on the same
	# floor can have slight Y differences from physics
	# positioning. A non-horizontal axis would project
	# horizontal velocity into the vertical direction,
	# causing unintended upward movement.
	var raw_diff := (
		other_player.global_position
		- override_position
	)
	if raw_diff.x == 0.0:
		# Players at same X. Default to facing right.
		raw_diff.x = 1.0
	var axis := Vector2(signf(raw_diff.x), 0.0)

	# Project both velocities onto the collision axis.
	# Positive = moving toward other player.
	var v_self := pre_movement_velocity.dot(axis)
	var v_other := (
		other_player.pre_movement_velocity.dot(axis)
	)

	var closing_speed := v_self - v_other
	if closing_speed <= 0.0:
		# Players separating. No momentum to transfer.
		return Vector2.ZERO

	var transfer: float = (
		closing_speed
		* movement_settings
			.bump_momentum_transfer_factor
	)

	var v_self_new := v_self - transfer

	# Preserve horizontal velocity perpendicular to
	# collision axis (zero for a pure left/right axis).
	var perpendicular := (
		pre_movement_velocity - v_self * axis
	)

	var result := perpendicular + axis * v_self_new
	# Ensure no vertical component. Momentum transfer
	# keeps players grounded.
	result.y = 0.0
	return result


## Checks if a kill (or death) interaction happened this frame.
func _did_kill_happen_this_frame(frame_index: int) -> bool:
	if state_from_server.last_interaction_frame_index == frame_index:
		var type := state_from_server.last_interaction_type
		if (
		type == CharacterStateFromServer
			.ServerInteractionType.KILL
		or type == CharacterStateFromServer
			.ServerInteractionType.DIE
	):
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
		_is_foot_on_head(self , other_player)
		or _is_foot_on_head(other_player, self )
	)


## Returns true if the directional relationship between
## attacker and victim indicates a downward stomp.
## Uses relative velocity as the primary check. Falls
## back to a near-zero-velocity check for the case
## where Area2D overlap begins a frame after landing
## (both players at rest), which happens with round
## collision shapes and horizontal offset.
static func _is_downward_stomp(
	attacker: Player,
	victim: Player,
) -> bool:
	var relative_velocity := (
		attacker.pre_movement_velocity
		- victim.pre_movement_velocity)
	if relative_velocity.y > 0:
		return true
	# Fallback: if both players have near-zero vertical
	# velocity, the foot-on-head overlap alone is
	# sufficient. This catches the case where the
	# CharacterBody2D collision resolves one frame
	# before the Area2D overlap begins, by which time
	# move_and_slide() has zeroed both velocities.
	# A player jumping upward has significant velocity
	# and will not match this condition.
	return (
		absf(attacker.pre_movement_velocity.y)
			< _AT_REST_VELOCITY_THRESHOLD
		and absf(victim.pre_movement_velocity.y)
			< _AT_REST_VELOCITY_THRESHOLD
	)


## Checks if attacker's foot area overlaps victim's head
## area with a valid stomp direction.
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

	return _is_downward_stomp(attacker, victim)


## Checks if this player's foot passed through another player's head this
## frame using swept collision detection. This catches high-speed collisions
## that skip over collision areas between physics frames.
func _did_foot_pass_through_head_this_frame(other_player: Player) -> bool:
	# Early exit if no previous position data.
	# Note: previous_position is a property inherited from Character class.
	if (
		previous_position == Vector2.INF
		or other_player.previous_position
			== Vector2.INF
	):
		return false

	# Check relative velocity is downward. Use
	# pre-movement velocity since this is called from
	# callbacks that fire after move_and_slide().
	var relative_velocity := (
		pre_movement_velocity
		- other_player.pre_movement_velocity)
	if relative_velocity.y <= 0:
		return false

	# Get previous positions in global coordinates.
	# Note: previous_position is in local coords, convert to global.
	# Since Level parent is stationary, parent.global_position is constant.
	var my_prev_global: Vector2 = (
		get_parent().global_position + previous_position
	)
	var other_prev_global: Vector2 = (
		other_player.get_parent().global_position
		+ other_player.previous_position
	)

	# Calculate foot bottom and head top at t0
	# (previous frame).
	const FOOT_OFFSET_Y = -1.0
	const FOOT_HEIGHT = 2.0
	const HEAD_OFFSET_Y = -11.0
	const HEAD_HEIGHT = 2.0

	var foot_bottom_t0 = (
		my_prev_global.y
		+ FOOT_OFFSET_Y
		+ FOOT_HEIGHT / 2
	)
	var head_top_t0 = (
		other_prev_global.y
		+ HEAD_OFFSET_Y
		- HEAD_HEIGHT / 2
	)

	# Calculate foot bottom and head top at t1
	# (current frame).
	var foot_bottom_t1 = (
		global_position.y
		+ FOOT_OFFSET_Y
		+ FOOT_HEIGHT / 2
	)
	var head_top_t1 = (
		other_player.global_position.y
		+ HEAD_OFFSET_Y
		- HEAD_HEIGHT / 2
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
		(foot_left <= head_right)
		and (foot_right >= head_left)
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
		other_player.get_parent().global_position
		+ other_player.previous_position
	)

	# Calculate foot bottom and head top at t0 and t1.
	var foot_bottom_t0 = (
		my_prev_global.y
		+ FOOT_OFFSET_Y + FOOT_HEIGHT / 2)
	var head_top_t0 = (
		other_prev_global.y
		+ HEAD_OFFSET_Y - HEAD_HEIGHT / 2)
	var foot_bottom_t1 = (
		global_position.y
		+ FOOT_OFFSET_Y + FOOT_HEIGHT / 2)
	var head_top_t1 = (
		other_player.global_position.y
		+ HEAD_OFFSET_Y - HEAD_HEIGHT / 2)

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
	if not Netcode.runs_server_logic:
		return

	var other_parent: Node = area.get_parent()
	if not Netcode.ensure(other_parent is Player):
		return
	var other_player := other_parent as Player
	var other_player_id := other_player.player_id

	if other_player == self:
		return

	if not _is_downward_stomp(self, other_player):
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
		state_from_server.is_invincible
		or other_player.state_from_server
			.is_invincible
	):
		# Track this intersection for later.
		if not _active_intersections.has(
				other_player_id):
			_active_intersections[
				other_player_id] = []
		if not _active_intersections[
				other_player_id].has("foot"):
			_active_intersections[
				other_player_id].append("foot")
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
	if not Netcode.runs_server_logic:
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
	if not Netcode.runs_server_logic:
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
	var blink_period: float = (
		1.0
		/ (G.settings
			.player_invincibility_blink_frequency_hz
			* 2.0))

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
	if (
		is_instance_valid(G.match_state)
		and G.match_state.is_match_ended
	):
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
	set_collision_layer_value(
		_PLAYER_COLLISION_LAYER, not is_invincible,
	)
	set_collision_mask_value(
		_PLAYER_COLLISION_LAYER, not is_invincible,
	)

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
	if not Netcode.runs_server_logic:
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
		if (
			other_player.state_from_server.is_dead
			or other_player.state_from_server
				.is_invincible
		):
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
				if _is_downward_stomp(
					self, other_player):
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
				# Record bump stats for dynamic
				# adjective tracking.
				(G.match_state
					.server_get_or_create_stats(
						player_id)
					.record_bump())
				(G.match_state
					.server_get_or_create_stats(
						other_player_id)
					.record_bump())
				_processed_collision_this_frame = true
				other_player._processed_collision_this_frame = true
				G.match_state.server_add_bump(player_id, other_player_id)
				_server_apply_interaction(other_player, CharacterStateFromServer.ServerInteractionType.BUMP)
				other_player._server_apply_interaction(self , CharacterStateFromServer.ServerInteractionType.BUMP)

	# Clear all tracked intersections after processing.
	_active_intersections.clear()
