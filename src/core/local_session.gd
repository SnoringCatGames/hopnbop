class_name LocalSession
extends RefCounted

var is_game_active := false
var is_game_loading := false

var latest_match_state := MatchState.new()

## GameLift player session ID from matchmaking (used for connection validation).
var player_session_id := ""


func _init() -> void:
    clear()


func clear() -> void:
    is_game_active = false
    is_game_loading = false


func copy_match_state() -> void:
    latest_match_state = G.game_panel.match_state.duplicate()
