class_name PlayerOverheadLabels
extends Node2D

## Manages world-space labels above players with proximity-based fading.

const PROXIMITY_THRESHOLD := 100.0 ## Hide labels when players closer than this.
const FADE_DURATION := 0.3 ## Tween animation duration in seconds.
const LABEL_OFFSET := Vector2(0, -40) ## Above player head.

# Dictionary<StringName, Label>
var _labels_by_player_id := {}

# Dictionary<StringName, Tween>
var _active_tweens_by_player_id := {}


func _enter_tree() -> void:
	G.player_overhead_labels = self


func set_up() -> void:
	G.match_state.players_updated.connect(_refresh_labels)
	_refresh_labels()


func _process(_delta: float) -> void:
	_update_label_positions()
	_update_label_visibility()


func _refresh_labels() -> void:
	if not is_instance_valid(G.match_state):
		return

	# Get current player IDs from match state.
	var current_player_ids: Array = G.match_state.players.keys()

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


func _create_label(player_id: StringName) -> void:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Set text from player match state.
	var player_match_state := G.get_player_match_state(player_id)
	if player_match_state:
		label.text = player_match_state.bunny_name
	else:
		label.text = "Player"

	_labels_by_player_id[player_id] = label
	add_child(label)


func _remove_label(player_id: StringName) -> void:
	if not _labels_by_player_id.has(player_id):
		return

	var label: Label = _labels_by_player_id[player_id]
	_labels_by_player_id.erase(player_id)

	# Kill active tween if exists.
	if _active_tweens_by_player_id.has(player_id):
		var tween: Tween = _active_tweens_by_player_id[player_id]
		if is_instance_valid(tween):
			tween.kill()
		_active_tweens_by_player_id.erase(player_id)

	label.queue_free()


func _update_label_positions() -> void:
	for player_id in _labels_by_player_id.keys():
		var player = G.get_player(player_id)
		if not is_instance_valid(player):
			continue

		var label: Label = _labels_by_player_id[player_id]
		label.global_position = player.global_position + LABEL_OFFSET


func _update_label_visibility() -> void:
	for player_id in _labels_by_player_id.keys():
		var player = G.get_player(player_id)
		if not is_instance_valid(player):
			continue

		var should_show := _should_show_label(player_id)
		_fade_label(player_id, should_show)


func _should_show_label(player_id: StringName) -> bool:
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

		var distance := player.global_position.distance_to(
			other_player.global_position
		)
		if distance < PROXIMITY_THRESHOLD:
			return false # Too close, hide label.

	return true # No players nearby, show label.


func _fade_label(player_id: StringName, should_show: bool) -> void:
	if not _labels_by_player_id.has(player_id):
		return

	var label: Label = _labels_by_player_id[player_id]
	var target_alpha := 1.0 if should_show else 0.0

	# Check if already at target alpha.
	if is_equal_approx(label.modulate.a, target_alpha):
		return

	# Kill existing tween if active.
	if _active_tweens_by_player_id.has(player_id):
		var old_tween: Tween = _active_tweens_by_player_id[player_id]
		if is_instance_valid(old_tween):
			old_tween.kill()

	# Create new tween.
	var tween := create_tween()
	_active_tweens_by_player_id[player_id] = tween

	tween.tween_property(
		label,
		"modulate:a",
		target_alpha,
		FADE_DURATION
	)

	# Cleanup tween reference after completion.
	tween.finished.connect(
		func() -> void:
			if _active_tweens_by_player_id.get(player_id) == tween:
				_active_tweens_by_player_id.erase(player_id)
	)
