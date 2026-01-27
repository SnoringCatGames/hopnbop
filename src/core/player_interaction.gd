class_name PlayerInteraction
extends RefCounted


enum Type {
	UNKNOWN,
	BUMP,
	KILL,
}


var player_1_id := 0
var player_2_id := 0
var type := Type.UNKNOWN
var frame_index := -1


func matches_players(p1_id: int, p2_id: int) -> bool:
	return (player_1_id == p1_id and player_2_id == p2_id) or \
		(player_1_id == p2_id and player_2_id == p1_id)
