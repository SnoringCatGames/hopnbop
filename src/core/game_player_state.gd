class_name GamePlayerState
extends PlayerState
## Hop 'n Bop specific player state with bunny attributes and scoring.


const _OUTLINE_COLOR_OPACITY := 0.25
const _LABEL_COLOR_WHITENING_FACTOR := 0.7


# Game-specific properties (moved from PlayerState).
var name_index := 0
var adj_list_id := 0
var adj_index := 0
var is_soft := true
var body_type_index := 0
var costume_index := 0
var base_color := Color.WHITE

# Computed properties that resolve locally via
# locale.
var bunny_name: String:
	get:
		return (
			DynamicAdjectiveConfig
				.get_localized_name(name_index))

var adjective: String:
	get:
		return (
			DynamicAdjectiveConfig
				.get_localized_adjective(
					adj_list_id, adj_index))

# Calculated locally, not networked.
var _score := 0
var score: int:
	get:
		return _score
	set(value):
		_score = value

var _rank := 1
var rank: int:
	get:
		return _rank
	set(value):
		_rank = value

# Computed properties.
var full_name: StringName:
	get:
		return "%s %s" % [adjective, bunny_name]

var outline_color: Color:
	get:
		return Color(base_color, _OUTLINE_COLOR_OPACITY)

var label_color: Color:
	get:
		return base_color.lightened(_LABEL_COLOR_WHITENING_FACTOR)


func _get_game_property_names() -> Array:
	return [
		"name_index",
		"adj_list_id",
		"adj_index",
		"is_soft",
		"body_type_index",
		"costume_index",
		"base_color",
	]


func get_packed_state() -> Array:
	var packed := super.get_packed_state()
	for property_name in _get_game_property_names():
		packed.append(get(property_name))
	return packed


func populate_from_packed_state(packed_state: Array) -> void:
	super.populate_from_packed_state(packed_state)
	var base_size := _get_base_property_names().size()
	var game_props := _get_game_property_names()
	for i in range(game_props.size()):
		set(game_props[i], packed_state[base_size + i])


func set_up(
		p_player_id: int,
		p_peer_id: int,
		p_local_index: int,
		p_attributes: Dictionary) -> void:
	super.set_up(p_player_id, p_peer_id, p_local_index, p_attributes)

	# Apply game-specific attributes.
	name_index = p_attributes.name_index
	adj_list_id = p_attributes.adj_list_id
	adj_index = p_attributes.adj_index
	is_soft = p_attributes.is_soft
	body_type_index = p_attributes.body_type_index
	costume_index = p_attributes.costume_index
	base_color = Color.WHITE # Assigned later by MatchStateSynchronizer.


func get_string() -> String:
	return "Player %d (%s) [peer:%d, local:%d]" % [
		player_id,
		full_name,
		peer_id,
		local_player_index
	]
