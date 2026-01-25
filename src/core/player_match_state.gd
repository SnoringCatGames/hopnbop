class_name PlayerMatchState
extends RefCounted
## Match state associated with an individual player.
##
## - This should contain state that doesn't need to sync very often (every few
##   seconds at the most).
## - State that needs to sync every frame should instead be tracked in
##   CharacterStateFromServer (or a subclass of it).

## Composite player ID in format "peer_id:local_index" (e.g., "1234:0").
var player_id: StringName = ""
var bunny_name := ""
var adjective := ""
var is_soft := true
var connect_time_usec := 0
var disconnect_time_usec := 0

const _PROPERTY_NAMES := [
	"player_id",
	"bunny_name",
	"adjective",
	"is_soft",
	"connect_time_usec",
	"disconnect_time_usec",
]

## Deprecated: Use peer_id instead. Kept for backward compatibility.
var multiplayer_id: int:
	get:
		return peer_id

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
		else:
			return null

var peer_id: int:
	get:
		return NetworkConnector.get_peer_id_from_player_id(player_id)

var local_index: int:
	get:
		return NetworkConnector.get_local_index_from_player_id(player_id)


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


static func get_player_id_from_packed_state(packed_state: Array) -> StringName:
	return packed_state[0]


func set_up(p_player_id: StringName, p_is_soft: bool) -> void:
	player_id = p_player_id

	is_soft = p_is_soft

	bunny_name = BunnyWords.NAMES.pick_random()

	var adjectives := (
		BunnyWords.SOFT_ADJECTIVES if
		is_soft else
		BunnyWords.HARD_ADJECTIVES
	)
	adjective = adjectives.pick_random()


func get_string() -> String:
	return "%s:%s" % [player_id, full_name]
