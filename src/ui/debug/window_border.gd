class_name WindowBorder
extends Control
## Debug overlay that draws a colored border around the window frame in
## preview mode. The border color matches the local player's outline color to
## help distinguish between multiple client windows.

const BORDER_WIDTH := 3.0
const OPACITY := 0.3


func _ready() -> void:
	# Make this control cover the entire viewport.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Update border when player colors change.
	if G.match_state != null:
		G.match_state.players_updated.connect(_on_players_updated)

	# Initial draw.
	queue_redraw()


func _draw() -> void:
	# Only draw in preview mode.
	if not Netcode.is_preview or not G.settings.preview_run_multiple_clients:
		return

	# Get the local player's color.
	var color := _get_local_player_color()
	if color == Color.TRANSPARENT:
		return
	color.a = OPACITY

	# Draw border around the viewport.
	var viewport_size := get_viewport_rect().size

	# Draw 4 lines to form a border (top, right, bottom, left).
	var half_width := BORDER_WIDTH / 2.0

	# Top border.
	draw_line(
		Vector2(0, half_width),
		Vector2(viewport_size.x, half_width),
		color,
		BORDER_WIDTH
	)

	# Right border.
	draw_line(
		Vector2(viewport_size.x - half_width, 0),
		Vector2(viewport_size.x - half_width, viewport_size.y),
		color,
		BORDER_WIDTH
	)

	# Bottom border.
	draw_line(
		Vector2(0, viewport_size.y - half_width),
		Vector2(viewport_size.x, viewport_size.y - half_width),
		color,
		BORDER_WIDTH
	)

	# Left border.
	draw_line(
		Vector2(half_width, 0),
		Vector2(half_width, viewport_size.y),
		color,
		BORDER_WIDTH
	)


func _get_local_player_color() -> Color:
	if G.match_state == null:
		return Color.TRANSPARENT

	# Get the first local player's ID.
	if G.client_session.local_player_ids.is_empty():
		return Color.TRANSPARENT

	var local_player_id := G.client_session.local_player_ids[0]
	var player_state: PlayerMatchState = G.match_state.players_by_id.get(
		local_player_id
	)

	if player_state == null:
		return Color.TRANSPARENT

	return player_state.base_color


func _on_players_updated() -> void:
	queue_redraw()
