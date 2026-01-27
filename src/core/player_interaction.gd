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
