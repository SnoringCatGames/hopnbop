class_name PlayerMatchState
extends RefCounted
## Match state associated with an individual player.
##
## - This should contain state that doesn't need to sync very often (every few
##   seconds at the most).
## - State that needs to sync every frame should instead be tracked in
##   CharacterStateFromServer (or a subclass of it).


const _BODY_TYPE_COUNT := 1
const _COSTUME_COUNT := 1

const _PROPERTY_NAMES := [
	"player_id",
	"peer_id",
	"local_player_index",
	"bunny_name",
	"adjective",
	"is_soft",
	"connect_time_usec",
	"disconnect_time_usec",
]

var player_id: int = 0
var peer_id: int = 0
var local_player_index: int = 0
var bunny_name := ""
var adjective := ""
var body_type_index := 0
var costume_index := 0
var outline_color := Color.WHITE
var is_soft := true
var connect_time_usec := 0
var disconnect_time_usec := 0

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

var is_connected_to_server: bool:
	get:
		return connect_time_usec >= disconnect_time_usec

var player: Player:
	get:
		if G.level.players_by_id.has(player_id):
			return G.level.players_by_id[player_id]
		return null


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
		p_is_soft: bool) -> void:
	player_id = p_player_id
	peer_id = p_peer_id
	local_player_index = p_local_index
	is_soft = p_is_soft

	bunny_name = BunnyWords.NAMES.pick_random()

	var adjectives := (
		BunnyWords.SOFT_ADJECTIVES if
		is_soft else
		BunnyWords.HARD_ADJECTIVES
	)
	adjective = adjectives.pick_random()

	# TODO: Add support for different body and costume types.
	body_type_index = 0
	costume_index = 0

	# FIXME: Add support for assigning colors on the server.
	outline_color = Color.WHITE


func get_string() -> String:
	return "Player %d (%s) [peer:%d, local:%d]" % [
		player_id,
		full_name,
		peer_id,
		local_player_index
	]
