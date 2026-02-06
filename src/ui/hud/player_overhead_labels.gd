class_name PlayerOverheadLabels
extends Node2D
## Manages world-space labels above players with proximity-based fading.


## Hide labels when players closer than this.
const _PROXIMITY_THRESHOLD := 96.0
const _LABEL_OFFSET := Vector2(0, -40)
const _FADE_IN_DURATION_SEC := 0.3
const _FADE_OUT_DURATION_SEC := 0.05

@export var label_scene: PackedScene

# Dictionary<int, PlayerOverheadLabel>
var _labels_by_player_id := {}


func _enter_tree() -> void:
	G.player_overhead_labels = self


func _ready() -> void:
	# Throttle visibility updates for performance (we check distance to all
	# other players each time).
	Netcode.time.set_interval(
		_update_label_visibility,
		0.2
	)


func set_up() -> void:
	G.match_state.players_updated.connect(_on_players_updated)
	_update_labels()


func _process(_delta: float) -> void:
	_update_label_positions()


func _on_players_updated() -> void:
	_update_labels()
	_update_label_colors()


func _update_labels() -> void:
	if not is_instance_valid(G.match_state):
		return

	# Get current player IDs from match state.
	var current_player_ids: Array = G.match_state.players_by_id.keys()

	# Remove labels for players that no longer exist.
	var player_ids_to_remove: Array = []
	for player_id in _labels_by_player_id.keys():
		if not current_player_ids.has(player_id):
			player_ids_to_remove.append(player_id)

	for player_id in player_ids_to_remove:
		_remove_label(player_id)

	# Add labels for new players.
	for player_id in current_player_ids:
		if not _labels_by_player_id.has(player_id):
			_create_label(player_id)


func _create_label(player_id: int) -> void:
	var label: PlayerOverheadLabel = label_scene.instantiate()

	# Set text from player match state.
	var player_match_state := G.get_player_match_state(player_id)
	if player_match_state:
		label.text = player_match_state.bunny_name
		label.color = player_match_state.outline_color
	else:
		label.text = "Player"

	label.player_id = player_id
	label.shown = true

	_labels_by_player_id[player_id] = label
	add_child(label)


func _remove_label(player_id: int) -> void:
	if not _labels_by_player_id.has(player_id):
		return

	var label: PlayerOverheadLabel = _labels_by_player_id[player_id]
	_labels_by_player_id.erase(player_id)

	# Kill any active tween exists.
	if is_instance_valid(label.tween):
		label.tween.kill()

	label.queue_free()


func _update_label_positions() -> void:
	for player_id in _labels_by_player_id.keys():
		var player = G.get_player(player_id)
		if not is_instance_valid(player):
			continue

		var label: PlayerOverheadLabel = _labels_by_player_id[player_id]
		# Position is at bottom-center of label due to anchor settings.
		label.global_position = player.global_position + _LABEL_OFFSET


func _update_label_colors() -> void:
	# Update colors for all labels when player data is updated.
	for player_id in _labels_by_player_id.keys():
		var label: PlayerOverheadLabel = _labels_by_player_id[player_id]
		var player_match_state := G.get_player_match_state(player_id)
		if player_match_state:
			label.color = player_match_state.outline_color


func _update_label_visibility() -> void:
	for player_id in _labels_by_player_id.keys():
		var player = G.get_player(player_id)
		if not is_instance_valid(player):
			continue

		var should_show := _should_show_label(player_id)
		_fade_label(player_id, should_show)


func _should_show_label(player_id: int) -> bool:
	var player := G.get_player(player_id)
	if not is_instance_valid(player):
		return false

	# Check distance to all other players.
	for other_player_id in _labels_by_player_id.keys():
		if other_player_id == player_id:
			continue

		var other_player := G.get_player(other_player_id)
		if not is_instance_valid(other_player):
			continue

		var distance_squared := player.global_position.distance_squared_to(
			other_player.global_position
		)
		if distance_squared < _PROXIMITY_THRESHOLD * _PROXIMITY_THRESHOLD:
			# Too close, hide label.
			return false

	# No players nearby, show label.
	return true


func _fade_label(player_id: int, p_is_visible: bool) -> void:
	if not _labels_by_player_id.has(player_id):
		return

	var label: PlayerOverheadLabel = _labels_by_player_id[player_id]

	if label.shown == p_is_visible:
		# Already has the correct visibility.
		return

	label.shown = p_is_visible

	# Kill any preexisting tween.
	if is_instance_valid(label.tween):
		label.tween.kill()

	var target_alpha := 1.0 if p_is_visible else 0.0

	var duration := (
		_FADE_IN_DURATION_SEC if
		p_is_visible else
		_FADE_OUT_DURATION_SEC
	)

	label.tween = create_tween()
	label.tween.tween_property(
		label,
		"modulate:a",
		target_alpha,
		duration
	)
