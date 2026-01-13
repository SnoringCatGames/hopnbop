class_name PlayerMatchState
extends RefCounted
## Match state associated with an individual player.
##
## - This should contain state that doesn't need to sync very often (every few
##   seconds at the most).
## - State that needs to sync every frame should instead be tracked in
##   [FIXME: [Rollback]: Reference player networked state script].


var multiplayer_id := 0
var bunny_name := ""
var adjective := ""
var is_soft := true
var connect_time_usec := 0
var disconnect_time_usec := 0

var is_connected_to_server: bool:
    get: return disconnect_time_usec > connect_time_usec


func set_up(p_multiplayer_id: int, p_is_soft: bool) -> void:
    multiplayer_id = p_multiplayer_id

    is_soft = p_is_soft

    bunny_name = BunnyWords.NAMES.pick_random()

    var adjectives := \
        BunnyWords.SOFT_ADJECTIVES if is_soft else BunnyWords.HARD_ADJECTIVES
    adjective = adjectives.pick_random()
