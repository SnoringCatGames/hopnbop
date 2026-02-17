class_name AwardPodium
extends AnimatedSprite2D
## Displays match results on a podium with player
## portrayals and name labels for the top 3 places.
## Supports ties: tied players appear side-by-side
## at the same position marker.


const _PORTRAYAL_SCENE := preload(
	"res://src/player/player_portrayal.tscn")

## Offset to align PlayerPortrayal's animator origin
## (at viewport position 18, 25) with the position
## marker.
const _PORTRAYAL_OFFSET := Vector2(-18, -25)

## Horizontal spacing between tied players sharing
## a podium position.
const _TIE_X_SPACING := 20.0

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
## podium positions with player portrayals and name
## labels. Tied players share a position side-by-side.
func show_results(
	match_state: GameMatchState,
) -> void:
	_clear_positions()

	# Ensure scores and ranks are calculated.
	match_state.update_scores()

	# Determine crown holder.
	var crown_id := match_state.get_crown_player_id(
		G.settings.crown_kill_lead)

	# Collect and sort players by rank.
	var players: Array = \
		match_state.players_by_id.values()
	players.sort_custom(
		func(a, b): return a.rank < b.rank)

	# Group players into score tiers. Each tier maps
	# to one podium position.
	var tiers: Array[Array] = []
	for player_state in players:
		if (tiers.is_empty() or
				tiers.back().front().score !=
					player_state.score):
			tiers.append([player_state])
		else:
			tiers.back().append(player_state)

	var position_nodes: Array[Node2D] = [
		%FirstPlacePosition,
		%SecondPlacePosition,
		%ThirdPlacePosition,
	]

	var tier_count := mini(tiers.size(), 3)
	for tier_index in range(tier_count):
		var tier: Array = tiers[tier_index]
		var position_node: Node2D = \
			position_nodes[tier_index]

		for j in range(tier.size()):
			var player_state: GamePlayerState = \
				tier[j]
			var x_offset := _get_tie_x_offset(
				j, tier.size())
			_add_portrayal(
				position_node,
				player_state,
				crown_id,
				x_offset)

	visible = true


## Returns the x offset for a player within a tied
## group, centering them around the position marker.
func _get_tie_x_offset(
	index: int,
	count: int,
) -> float:
	if count <= 1:
		return 0.0
	# Center the group: offset from -(count-1)/2
	# to +(count-1)/2 in unit steps, scaled by
	# spacing.
	var center := (count - 1) / 2.0
	return (index - center) * _TIE_X_SPACING


## Adds a player portrayal and name label at the given
## position node with an optional x offset for ties.
func _add_portrayal(
	position_node: Node2D,
	player_state: GamePlayerState,
	crown_id: int,
	x_offset: float,
) -> void:
	# Create and configure player portrayal.
	var portrayal: PlayerPortrayal = \
		_PORTRAYAL_SCENE.instantiate()
	portrayal.position = \
		_PORTRAYAL_OFFSET + Vector2(x_offset, 0)
	position_node.add_child(portrayal)
	portrayal.apply_player_state(player_state)

	# Show crown if this player earned it.
	if player_state.player_id == crown_id:
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
	# portrayal.
	label.position = Vector2(
		x_offset, _LABEL_OFFSET_Y)
	label.grow_horizontal = \
		Control.GROW_DIRECTION_BOTH
	position_node.add_child(label)


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
