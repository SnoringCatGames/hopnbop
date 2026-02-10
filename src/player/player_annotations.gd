class_name PlayerAnnotations
extends Node2D
## Centralized debug visualization for all player collision shapes and
## rollback buffer trails.
##
## Displays for each player:
## - Cyan outline matching the player's collision shape.
## - Colored dots for each frame in the rollback buffer.
## - Lines connecting adjacent frames.
## - Color coding by frame authority (green=authoritative,
##   teal=server-predicted, blue=client-predicted, gray=unknown).
##
## Toggle at runtime with F6 (respects G.settings.draw_annotations)
## and F1 (master HUD toggle via G.settings.show_hud). Both must be
## enabled to show.

# Configuration constants.
const COLLISION_OUTLINE_COLOR := Color(0.0, 1.0, 1.0, 0.569)
const COLLISION_OUTLINE_THICKNESS := 1.5
const COLLISION_OUTLINE_SECTOR_ARC_LENGTH := 2.0

const LINE_THICKNESS := 1.0

# Color coding by frame authority.
const COLOR_AUTHORITATIVE := Color(0.3, 0.9, 0.0, 0.6)
const COLOR_SERVER_PREDICTED := Color(0.0, 0.6, 0.5, 0.6)
const COLOR_CLIENT_PREDICTED := Color(0.1, 0.3, 1.0, 0.6)
const COLOR_UNKNOWN := Color(0.5, 0.5, 0.5, 0.6)

# Color coding for rollback/fast-forward events.
const COLOR_ROLLBACK := Color(1.0, 0.3, 0.3, 0.6)
const COLOR_FAST_FORWARD := Color(1.0, 0.8, 0.0, 0.3)

# Dot radius based on authoritative delay (bigger = slower/more
# delayed).
const DOT_RADIUS_MIN := 1.5
const DOT_RADIUS_MAX := 4.0

# Delay thresholds for dot radius interpolation.
const DELAY_MIN_THRESHOLD := 3
const DELAY_MAX_THRESHOLD := 10

var _player_ids: Array = []


func _enter_tree() -> void:
	G.player_annotations = self


func _ready() -> void:
	# Must run during countdown to track player positions.
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_up() -> void:
	G.match_state.players_updated.connect(_on_players_updated)
	_update_player_ids()


func _on_players_updated() -> void:
	_update_player_ids()


func _update_player_ids() -> void:
	if not is_instance_valid(G.match_state):
		_player_ids = []
		return
	_player_ids = G.match_state.players_by_id.keys()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if (
		Engine.is_editor_hint() or
		not G.settings.show_hud or
		not G.settings.draw_annotations
	):
		return

	for player_id in _player_ids:
		var player: Player = G.get_player(player_id)
		if not is_instance_valid(player):
			continue
		_draw_collision_shape(player)
		_draw_rollback_buffer_trail(player)


func _draw_collision_shape(player: Player) -> void:
	if not is_instance_valid(player.collision_shape):
		return

	var local_position := (
		player.collision_shape.global_position -
		global_position
	)

	DrawUtils.draw_shape_outline(
		self ,
		local_position,
		player.collision_shape.shape,
		COLLISION_OUTLINE_COLOR,
		COLLISION_OUTLINE_THICKNESS,
		COLLISION_OUTLINE_SECTOR_ARC_LENGTH,
	)


func _draw_rollback_buffer_trail(player: Player) -> void:
	if not is_instance_valid(player.state_from_server):
		return

	var buffer := player.state_from_server._rollback_buffer
	var debug_buffer := \
		player.state_from_server._debug_frame_buffer

	if buffer == null:
		return

	var oldest_index := buffer._get_oldest_accessible_index()
	var latest_index := buffer.get_latest_index()

	var prev_local_pos: Vector2
	var has_prev := false

	for frame_index in range(oldest_index, latest_index + 1):
		if not buffer.has_at(frame_index):
			has_prev = false
			continue

		var frame_state: Array = buffer.get_at(frame_index)

		if frame_state == null or frame_state.is_empty():
			has_prev = false
			continue

		var frame_position: Vector2 = frame_state[0]
		var frame_authority: int = \
			frame_state[frame_state.size() - 1]

		# Get debug info for this frame.
		var debug_entry: Array = []
		if (
			debug_buffer != null and
			debug_buffer.has_at(frame_index)
		):
			debug_entry = debug_buffer.get_at(frame_index)

		var local_pos := (
			frame_position -
			global_position +
			player.collision_shape.position
		)

		# Determine dot color based on debug info and
		# authority.
		var dot_color := _get_dot_color(
			frame_authority, debug_entry
		)

		# Determine dot radius based on authoritative delay
		# (bigger = slower).
		var dot_radius := _get_dot_radius(debug_entry)

		# Draw line to previous frame if exists.
		if has_prev:
			draw_line(
				prev_local_pos,
				local_pos,
				dot_color,
				LINE_THICKNESS,
			)

		# Draw dot for current frame.
		draw_circle(local_pos, dot_radius, dot_color)

		prev_local_pos = local_pos
		has_prev = true


func _get_color_for_authority(authority: int) -> Color:
	match authority:
		ReconcilableState.FrameAuthority.AUTHORITATIVE:
			return COLOR_AUTHORITATIVE
		ReconcilableState.FrameAuthority.SERVER_PREDICTED:
			return COLOR_SERVER_PREDICTED
		ReconcilableState.FrameAuthority.CLIENT_PREDICTED:
			return COLOR_CLIENT_PREDICTED
		_:
			return COLOR_UNKNOWN


func _get_dot_color(
	authority: int, debug_entry: Array
) -> Color:
	if not debug_entry.is_empty():
		if debug_entry[
			ReconcilableState._DEBUG_ROLLBACK_INDEX
		] > 0:
			return COLOR_ROLLBACK
		if debug_entry[
			ReconcilableState._DEBUG_FAST_FORWARD_INDEX
		] > 0:
			return COLOR_FAST_FORWARD
	return _get_color_for_authority(authority)


func _get_dot_radius(debug_entry: Array) -> float:
	if debug_entry.is_empty():
		return DOT_RADIUS_MIN

	var delay: int = debug_entry[
		ReconcilableState
			._DEBUG_AUTHORITATIVE_STATE_DELAY_INDEX
	]

	# Never received authoritative state - use max radius.
	if delay < 0:
		return DOT_RADIUS_MAX

	if delay <= DELAY_MIN_THRESHOLD:
		return DOT_RADIUS_MIN
	elif delay >= DELAY_MAX_THRESHOLD:
		return DOT_RADIUS_MAX
	else:
		var t := (
			float(delay - DELAY_MIN_THRESHOLD) /
			float(
				DELAY_MAX_THRESHOLD -
				DELAY_MIN_THRESHOLD
			)
		)
		return lerpf(DOT_RADIUS_MIN, DOT_RADIUS_MAX, t)
