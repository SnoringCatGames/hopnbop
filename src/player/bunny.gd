@tool
class_name Bunny
extends Player


var match_state: PlayerState:
	get:
		return G.get_player_match_state(player_id)

var _processed_collision_this_frame := false
var _last_collision_frame := -1
var _blink_accumulator := 0.0
var _is_blink_visible := true
# -------------------------------------
# FIXME: REMOVE
var _last_blink_toggle_frame := -1
# -------------------------------------
var _pending_bounce := Vector2.ZERO
var _last_processed_interaction_frame_index := -1

# Track intersections during invincibility.
# Dictionary<int, Array[String]> - player_id -> array of intersection types.
# Can contain both "foot" and "body" for the same player.
var _active_intersections := {}
var _was_invincible_last_frame := false


# -------------------------------------
# FIXME: REMOVE
# Bug detection: track visibility state for debugging.
var _visibility_diagnostic_enabled := true
var _last_expected_visible := true
var _frames_invisible_when_should_be_visible := 0
const _FRAMES_TO_TRIGGER_DIAGNOSTIC := 5
# -------------------------------------


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

	# Set up outline color when match state becomes available.
	if is_instance_valid(match_state):
		_apply_outline_color.call_deferred()
	else:
		G.match_state.player_joined.connect(_on_any_player_joined)

	# Update outline when colors are assigned/updated on the server.
	G.match_state.players_updated.connect(_on_players_updated)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	super._process(_delta)
	_update_invincibility_blink()


func _process_movement_and_actions() -> void:
	super._process_movement_and_actions()

	# Apply pending bounce after movement processing.
	if Netcode.is_server and _pending_bounce != Vector2.ZERO:
		velocity = _pending_bounce
		_pending_bounce = Vector2.ZERO

	# Reset collision flag each frame.
	if Netcode.is_server:
		var current_frame: int = Netcode.frame_driver.server_frame_index
		if _last_collision_frame != current_frame:
			_processed_collision_this_frame = false
			_last_collision_frame = current_frame

	# Update player-player collision based on invincibility state.
	# This runs every frame to handle invincibility expiring.
	_update_player_collision_for_invincibility()

	# Handle client-side interaction effects (sounds, particles).
	# Process the interaction if it's new (not yet processed).
	var should_process := (
		state_from_server.last_interaction_frame_index > _last_processed_interaction_frame_index and
		state_from_server.last_interaction_frame_index >= 0
	)

	if should_process:
		_handle_interaction_effects()
		_last_processed_interaction_frame_index = state_from_server.last_interaction_frame_index


	# -------------------------------------
	# FIXME: REMOVE
	# Diagnostic: detect if player should be visible but isn't.
	_check_visibility_bug_diagnostic()
	# -------------------------------------


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
		CharacterStateFromServer.ServerInteractionType.DIE:
			G.verbose(
				"F:%d Player %d DIE interaction detected on client" % [
					Netcode.server_frame_index,
					player_id,
				],
				NetworkLogger.CATEGORY_GAME_STATE,
			)
			play_sound("die")
		CharacterStateFromServer.ServerInteractionType.SPAWN:
			G.verbose(
				"F:%d Player %d SPAWN interaction detected on client" % [
					Netcode.server_frame_index,
					player_id,
				],
				NetworkLogger.CATEGORY_GAME_STATE,
			)
		_:
			G.fatal()


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
		_:
			G.fatal()
			return null


func _on_local_authority_added(
		_input_from_client: PlayerInputFromClient,
) -> void:
	_set_up_camera()


func _set_up_camera() -> void:
	var is_local_player := peer_id == Netcode.local_peer_id

	G.verbose(
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
	_apply_outline_color()


func _on_any_player_joined(player: PlayerState) -> void:
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
	shader_material.set_shader_parameter("outline_width", 1.0)

	# Toggle outline based on whether we're in a networked match.
	var outline_enabled := G.is_networked_level_active
	shader_material.set_shader_parameter("outline_enabled", outline_enabled)

	G.verbose(
		"Applied outline for player %s: color=%s, enabled=%s, width=2.0" % [
			player_id,
			match_state.base_color,
			outline_enabled,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)


func _on_body_area_body_entered(body: Node2D) -> void:
	# This should represent a collision with another player.
	if not Netcode.is_server:
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
		G.verbose(
			"Skipping bump - kill already processed this frame (players %d and %d)" % [
				player_id,
				other_player_id,
			],
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return

	# Check if a foot-head collision happened this frame via swept detection.
	# This catches high-speed collisions that skip over collision areas.
	if _did_foot_pass_through_head_this_frame(other_player):
		# Prevent double-counting (this frame was already processed from the
		# other player).
		if _processed_collision_this_frame:
			return

		# Mark this collision as processed.
		_processed_collision_this_frame = true
		other_player._processed_collision_this_frame = true

		G.verbose(
			"Player kill detected (swept): %d killed %d" %
				[player_id, other_player.player_id],
			NetworkLogger.CATEGORY_GAME_STATE,
		)

		# Calculate lag-compensated position.
		var lag_compensated_position := (
			_calculate_lag_compensated_kill_position(other_player)
		)

		# Process as kill with lag-compensated position.
		G.match_state.server_add_kill(player_id, other_player.player_id)
		_server_apply_interaction_with_position(
			self ,
			CharacterStateFromServer.ServerInteractionType.KILL,
			lag_compensated_position
		)
		return

	# Check if a kill collision is currently happening - kills take precedence.
	# This prevents the bump from blocking the kill when bump fires first.
	if _is_kill_collision_happening(other_player):
		G.verbose(
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

	# Mark this collision as processed.
	_processed_collision_this_frame = true
	other_player._processed_collision_this_frame = true

	# Bump - both players bounce away from each other.
	G.verbose(
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
			G.fatal(
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

	G.verbose(
		(
			"F:%d Applied %s interaction to player %d: pos=%s " +
			"(lag compensated), bounce=%s, vel=%s"
		) % [
			Netcode.server_frame_index,
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


## Checks if a kill collision is currently happening with another player.
func _is_kill_collision_happening(other_player: Player) -> bool:
	# Check if foot area overlaps with other player's head area.
	var foot_area: Area2D = %FootArea
	var other_head_area: Area2D = other_player.get_node("%HeadArea")

	if not foot_area.overlaps_area(other_head_area):
		return false

	# Check if relative velocity is downward (required for kill).
	var relative_velocity := velocity - other_player.velocity
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
		G.verbose(
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
		G.verbose(
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

	G.verbose(
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
		_last_blink_toggle_frame = Netcode.server_frame_index


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

	G.verbose(
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
					G.verbose(
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
					continue  # Skip body check since kill was processed.

		# Check body (bump) if no kill was processed.
		if intersection_types.has("body"):
			# Verify body intersection is still active.
			var body_area: Area2D = %BodyArea
			var is_still_intersecting := body_area.overlaps_body(other_player)

			if is_still_intersecting:
				G.verbose(
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


# -------------------------------------
# FIXME: REMOVE
## Diagnostic check to detect visibility bug after respawn.
## Only logs when bug is detected (player should be visible but isn't).
func _check_visibility_bug_diagnostic() -> void:
	if not _visibility_diagnostic_enabled:
		return

	# Determine if player should be visible based on interaction state.
	var should_be_visible := (
		state_from_server.last_interaction_type != CharacterStateFromServer.ServerInteractionType.DIE
	)

	# Check if there's a mismatch.
	var is_actually_visible := animator.visible
	var has_mismatch := should_be_visible and not is_actually_visible

	if has_mismatch:
		_frames_invisible_when_should_be_visible += 1

		# Trigger diagnostic after N consecutive frames of mismatch.
		if _frames_invisible_when_should_be_visible >= _FRAMES_TO_TRIGGER_DIAGNOSTIC:
			_log_visibility_diagnostic()
			# Disable further diagnostics to avoid log spam.
			_visibility_diagnostic_enabled = false
	else:
		# Reset counter when state is correct.
		_frames_invisible_when_should_be_visible = 0


## Logs detailed diagnostic information when visibility bug is detected.
func _log_visibility_diagnostic() -> void:
	G.print(
		"===== VISIBILITY BUG DETECTED: Player %d =====" % player_id,
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	G.print(
		"  Current frame: %d" % Netcode.server_frame_index,
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	G.print(
		"  Last interaction: type=%s, frame=%d" % [
			CharacterStateFromServer.ServerInteractionType.keys()[state_from_server.last_interaction_type],
			state_from_server.last_interaction_frame_index,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	G.print(
		"  State: is_dead=%s, is_invincible=%s" % [
			state_from_server.is_dead,
			state_from_server.is_invincible,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	G.print(
		"  Visibility: animator.visible=%s, _is_blink_visible=%s" % [
			animator.visible,
			_is_blink_visible,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	G.print(
		"  Collision: layer=%d (original=%d), mask=%d (original=%d)" % [
			collision_layer,
			_original_collision_layer,
			collision_mask,
			_original_collision_mask,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	G.print(
		"  Position: global_position=%s, velocity=%s" % [
			global_position,
			velocity,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	G.print(
		"  Blink state: _blink_accumulator=%.3f, last_toggle_frame=%d, period=%.3f" % [
			_blink_accumulator,
			_last_blink_toggle_frame,
			(1.0 / (G.settings.player_invincibility_blink_frequency_hz * 2.0)),
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	G.print(
		"  Authority: is_authority_for_state=%s, is_authority_for_input=%s" % [
			state_from_server.is_authority_for_state_from_server,
			state_from_server.is_authority_for_input_from_client,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	G.print(
		"  Collidability tracking: last_applied_frame=%d, last_value=%s, apply_count=%d" % [
			state_from_server._last_applied_collidability_frame,
			state_from_server._last_applied_collidability_value,
			state_from_server._collidability_apply_count,
		],
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	G.print(
		"  _last_processed_interaction_frame_index=%d" % _last_processed_interaction_frame_index,
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	G.print(
		"========================================",
		NetworkLogger.CATEGORY_GAME_STATE,
	)
# -------------------------------------
