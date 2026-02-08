class_name PlayerState
extends RefCounted
## Match state associated with an individual player.
##
## - This should contain state that doesn't need to sync very often (every few
##   seconds at the most).
## - State that needs to sync every frame should instead be tracked in
##   CharacterStateFromServer (or a subclass of it).


# TODO: Add support for configuring body-type and costume animator scenes in
#       Settings.
const _BODY_TYPE_COUNT := 1
const _COSTUME_COUNT := 1

const _OUTLINE_COLOR_OPACITY := 0.5
const _LABEL_COLOR_WHITENING_FACTOR := 0.7


const _PROPERTY_NAMES := [
	"player_id",
	"peer_id",
	"local_player_index",
	"bunny_name",
	"adjective",
	"is_soft",
	"body_type_index",
	"costume_index",
	"base_color",
	"connect_frame_index",
	"disconnect_frame_index",
]

var player_id: int = 0
var peer_id: int = 0
var local_player_index: int = 0

var connect_frame_index := 0
var disconnect_frame_index := 0

var is_connected_to_server: bool:
	get:
		return connect_frame_index >= disconnect_frame_index


func get_packed_state() -> Array:
	var packed_state := []
	packed_state.resize(_PROPERTY_NAMES.size())
	var i := 0
	for property_name in _PROPERTY_NAMES:
		packed_state[i] = get(property_name)
		i += 1
	return packed_state


func populate_from_packed_state(packed_state: Array) -> void:
	var i := 0
	for property_name in _PROPERTY_NAMES:
		set(property_name, packed_state[i])
		i += 1


static func get_player_id_from_packed_state(packed_state: Array) -> int:
	return packed_state[0]


func set_up(
		p_player_id: int,
		p_peer_id: int,
		p_local_index: int,
		p_attributes: Dictionary) -> void:
	player_id = p_player_id
	peer_id = p_peer_id
	local_player_index = p_local_index

	# Apply client-provided attributes.
	bunny_name = p_attributes.bunny_name
	adjective = p_attributes.adjective
	is_soft = p_attributes.is_soft
	body_type_index = p_attributes.body_type_index
	costume_index = p_attributes.costume_index

	# base_color is assigned later by MatchStateSynchronizer.
	base_color = Color.WHITE


func get_string() -> String:
	return "Player %d (%s) [peer:%d, local:%d]" % [
		player_id,
		full_name,
		peer_id,
		local_player_index
	]

# FIXME: Move these into a subclass.

var bunny_name := ""
var adjective := ""
var is_soft := true
var body_type_index := 0
var costume_index := 0
var base_color := Color.WHITE

# This is calculated locally, rather than networked.
var _score := 0
var score: int:
	get:
		return _score
	set(value):
		_score = value

# This is calculated locally, rather than networked.
var _rank := 1
var rank: int:
	get:
		return _rank
	set(value):
		_rank = value

var full_name: StringName:
	get:
		return "%s %s" % [adjective, bunny_name]

var outline_color: Color:
	get:
		return Color(base_color, _OUTLINE_COLOR_OPACITY)

var label_color: Color:
	get:
		return base_color.lightened(_LABEL_COLOR_WHITENING_FACTOR)
