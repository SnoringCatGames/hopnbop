class_name GamePlayerState
extends PlayerState
## Jump 'n Thump specific player state with bunny attributes and scoring.


const _OUTLINE_COLOR_OPACITY := 0.5
const _LABEL_COLOR_WHITENING_FACTOR := 0.7


# Game-specific properties (moved from PlayerState).
var bunny_name := ""
var adjective := ""
var is_soft := true
var body_type_index := 0
var costume_index := 0
var base_color := Color.WHITE

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
		"bunny_name",
		"adjective",
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
	bunny_name = p_attributes.bunny_name
	adjective = p_attributes.adjective
	is_soft = p_attributes.is_soft
	body_type_index = p_attributes.body_type_index
	costume_index = p_attributes.costume_index
	base_color = Color.WHITE  # Assigned later by MatchStateSynchronizer.


func get_string() -> String:
	return "Player %d (%s) [peer:%d, local:%d]" % [
		player_id,
		full_name,
		peer_id,
		local_player_index
	]
