class_name AwardPodium
extends AnimatedSprite2D
## Displays match results on a podium with player
## portrayals and name labels for the top 3 players.


const _PORTRAYAL_SCENE := preload(
	"res://src/player/player_portrayal.tscn")

## Offset to align PlayerPortrayal's animator origin
## (at viewport position 18, 25) with the position
## marker.
const _PORTRAYAL_OFFSET := Vector2(-18, -25)

## Label position above the portrayal.
const _LABEL_OFFSET_Y := -30.0

const _LABEL_FONT_SIZE := 6
const _LABEL_OUTLINE_SIZE := 1


func _ready() -> void:
	var latest := \
		G.client_session.latest_match_state \
			as GameMatchState
	if (latest != null and
			not latest.players_by_id.is_empty()):
		show_results(latest)
	else:
		hide_results()


## Shows match results on the podium. Populates up to 3
## positions with player portrayals and name labels.
func show_results(
	match_state: GameMatchState,
) -> void:
	_clear_positions()

	# Ensure scores and ranks are calculated.
	match_state.update_scores()

	# Collect and sort players by rank.
	var players: Array = \
		match_state.players_by_id.values()
	players.sort_custom(
		func(a, b): return a.rank < b.rank)

	var position_nodes: Array[Node2D] = [
		%FirstPlacePosition,
		%SecondPlacePosition,
		%ThirdPlacePosition,
	]

	var count := mini(players.size(), 3)
	for i in range(count):
		var player_state: GamePlayerState = players[i]
		var position_node: Node2D = position_nodes[i]

		# Create and configure player portrayal.
		var portrayal: PlayerPortrayal = \
			_PORTRAYAL_SCENE.instantiate()
		portrayal.position = _PORTRAYAL_OFFSET
		position_node.add_child(portrayal)
		portrayal.apply_player_state(player_state)

		# Show crown on 1st place.
		if i == 0:
			portrayal.set_crown_visible(true)

		# Create name label.
		var label := Label.new()
		label.text = player_state.bunny_name
		label.horizontal_alignment = \
			HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(
			"font_size", _LABEL_FONT_SIZE)
		label.add_theme_color_override(
			"font_color", player_state.label_color)
		label.add_theme_color_override(
			"font_outline_color", Color.BLACK)
		label.add_theme_constant_override(
			"outline_size", _LABEL_OUTLINE_SIZE)
		# Center the label horizontally above the
		# position marker.
		label.position = Vector2(
			0, _LABEL_OFFSET_Y)
		label.grow_horizontal = \
			Control.GROW_DIRECTION_BOTH
		position_node.add_child(label)

	visible = true


## Hides the podium and removes all dynamic children.
func hide_results() -> void:
	_clear_positions()
	visible = false


## Removes dynamically added children (PlayerPortrayal
## and Label instances) from all position nodes.
func _clear_positions() -> void:
	var position_nodes: Array[Node2D] = [
		%FirstPlacePosition,
		%SecondPlacePosition,
		%ThirdPlacePosition,
	]
	for position_node in position_nodes:
		for child in position_node.get_children():
			child.queue_free()
